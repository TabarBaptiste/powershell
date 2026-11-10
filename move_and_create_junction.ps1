# ============================================================
#  Deplace un dossier vers un autre disque et laisse une jonction
#  NTFS a l'ancien emplacement (les applications continuent de
#  trouver le dossier a son chemin d'origine).
#
#    .\move_and_create_junction.ps1                       -> boites de dialogue
#    .\move_and_create_junction.ps1 -Source C:\X -Destination E:\Archives
#
#  Securite : copie avec robocopy, verification (nombre de fichiers +
#  taille), puis seulement suppression de l'original. En cas de
#  probleme, l'original n'est jamais supprime.
# ============================================================

param(
    [string]$Source,
    [string]$Destination,
    [switch]$Force   # ne pas demander confirmation avant de supprimer l'original
)

$ErrorActionPreference = 'Stop'

function Select-Folder($prompt, $newFolder = $true) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $prompt
    $dlg.ShowNewFolderButton = $newFolder
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    Write-Host "Aucun dossier selectionne."; exit 1
}

function Stop-WithError($msg) { Write-Host $msg -ForegroundColor Red; pause; exit 1 }

# Compte les fichiers et additionne leur taille, sans suivre les jonctions
function Get-FolderStats($path) {
    $count = 0L; $size = 0L
    $stack = New-Object System.Collections.Stack
    $stack.Push([IO.DirectoryInfo]$path)
    while ($stack.Count) {
        $d = $stack.Pop()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) } else { $count++; $size += $e.Length }
        }
    }
    [PSCustomObject]@{ Count = $count; Size = $size }
}

# --- Selection
if (-not $Source)      { $Source      = Select-Folder "Selectionnez le dossier a deplacer" $false }
if (-not $Destination) { $Destination = Select-Folder "Selectionnez le dossier de destination (sur un autre disque)" }
$Source      = [IO.Path]::GetFullPath($Source.TrimEnd('\'))
$Destination = [IO.Path]::GetFullPath($Destination.TrimEnd('\'))
$target      = Join-Path $Destination (Split-Path $Source -Leaf)

Write-Host "Source      : $Source"
Write-Host "Destination : $target"

# --- Verifications
if (-not (Test-Path -LiteralPath $Source -PathType Container)) { Stop-WithError "Le dossier source n'existe pas." }
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { Stop-WithError "Le dossier de destination n'existe pas." }
$srcItem = Get-Item -LiteralPath $Source -Force
if ($srcItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-WithError "La source est deja une jonction / un lien." }
if ($Source -eq [IO.Path]::GetPathRoot($Source).TrimEnd('\')) { Stop-WithError "Impossible de deplacer la racine d'un disque." }
if (($Destination + '\').StartsWith($Source + '\', 'OrdinalIgnoreCase')) { Stop-WithError "La destination est a l'interieur de la source." }
if (Test-Path -LiteralPath $target) { Stop-WithError "'$target' existe deja : rien n'est fait pour ne rien ecraser." }

$srcRoot = [IO.Path]::GetPathRoot($Source); $dstRoot = [IO.Path]::GetPathRoot($Destination)
if ($srcRoot -eq $dstRoot) { Write-Host "Attention : source et destination sont sur le meme disque, aucun espace ne sera libere." -ForegroundColor Yellow }
$dstDrive = New-Object IO.DriveInfo $dstRoot
if ($dstDrive.DriveType -ne 'Fixed' -and $dstDrive.DriveType -ne 'Removable') {
    Stop-WithError "Une jonction NTFS ne peut pointer que vers un disque local (pas un lecteur reseau)."
}
if ($dstDrive.DriveFormat -ne 'NTFS') {
    Write-Host "Attention : le disque de destination est en $($dstDrive.DriveFormat). Les jonctions fonctionnent mieux vers du NTFS." -ForegroundColor Yellow
}

Write-Host "Calcul de la taille de la source..."
$before = Get-FolderStats $Source
Write-Host ("  {0} fichiers, {1:N2} Go" -f $before.Count, ($before.Size / 1GB))
if ($dstDrive.AvailableFreeSpace -lt $before.Size * 1.05) { Stop-WithError ("Pas assez de place sur {0} ({1:N2} Go libres)." -f $dstRoot, ($dstDrive.AvailableFreeSpace / 1GB)) }

Write-Host "Fermez les applications qui utilisent ce dossier avant de continuer." -ForegroundColor Yellow

# --- Copie
Write-Host "`nCopie en cours (robocopy)..." -ForegroundColor Cyan
robocopy $Source $target /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:8 /NFL /NDL /NJH /NP
if ($LASTEXITCODE -ge 8) { Stop-WithError "Robocopy a signale des erreurs (code $LASTEXITCODE). L'original est intact ; supprimez '$target' a la main." }

# --- Verification
$after = Get-FolderStats $target
Write-Host ("Copie : {0} fichiers, {1:N2} Go" -f $after.Count, ($after.Size / 1GB))
if ($after.Count -ne $before.Count -or $after.Size -ne $before.Size) {
    Stop-WithError "La copie ne correspond pas a l'original (fichiers verrouilles ?). L'original est intact ; supprimez '$target' a la main."
}

# --- Bascule : l'original est renomme (instantane), la jonction est creee, puis l'original est supprime
$backup = "$Source.__ancien_$(Get-Date -Format yyyyMMddHHmmss)"
try { Rename-Item -LiteralPath $Source -NewName (Split-Path $backup -Leaf) }
catch { Stop-WithError "Impossible de renommer l'original (un fichier est ouvert ?) : $($_.Exception.Message). La copie reste dans '$target'." }

cmd /c mklink /J "`"$Source`"" "`"$target`"" | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Source)) {
    Rename-Item -LiteralPath $backup -NewName (Split-Path $Source -Leaf)
    Stop-WithError "Echec de la creation de la jonction : l'original a ete remis en place."
}
Write-Host "Jonction creee : $Source -> $target" -ForegroundColor Green

if (-not $Force) {
    $r = Read-Host "Supprimer definitivement l'original renomme '$backup' ? (o/N)"
    if ($r -notmatch '^[oOyY]') { Write-Host "Original conserve dans '$backup'. Supprimez-le quand vous aurez verifie que tout fonctionne."; pause; exit 0 }
}
cmd /c rd /s /q "\\?\$backup"
if (Test-Path -LiteralPath $backup) { Write-Host "Certains fichiers de '$backup' n'ont pas pu etre supprimes." -ForegroundColor Yellow }
else { Write-Host ("Termine. {0:N2} Go liberes sur {1}" -f ($before.Size / 1GB), $srcRoot) -ForegroundColor Green }
pause
