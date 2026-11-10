# ============================================================
#  Annule move_and_create_junction.ps1 : supprime la jonction et
#  rapatrie le dossier a son emplacement d'origine.
#
#    .\origin.ps1                      -> boite de dialogue
#    .\origin.ps1 -Jonction C:\X
#
#  La cible de la jonction est lue automatiquement. Copie avec robocopy,
#  verification, puis suppression de la copie distante. En cas d'echec,
#  la jonction est recreee : rien n'est perdu.
# ============================================================

param(
    [string]$Jonction,
    [switch]$Force   # ne pas demander confirmation avant de supprimer la copie distante
)

$ErrorActionPreference = 'Stop'

function Stop-WithError($msg) { Write-Host $msg -ForegroundColor Red; pause; exit 1 }

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

if (-not $Jonction) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Selectionnez la jonction a supprimer (le dossier a son emplacement d'origine)"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host "Aucun dossier selectionne."; exit 1 }
    $Jonction = $dlg.SelectedPath
}
$Jonction = [IO.Path]::GetFullPath($Jonction.TrimEnd('\'))

# --- Verifications
$item = Get-Item -LiteralPath $Jonction -Force -ErrorAction SilentlyContinue
if (-not $item) { Stop-WithError "'$Jonction' n'existe pas." }
if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Stop-WithError "'$Jonction' n'est pas une jonction." }
$cible = @($item.Target)[0]
if (-not $cible) { Stop-WithError "Impossible de lire la cible de la jonction." }
$cible = $cible -replace '^\\\?\?\\', ''
if (-not (Test-Path -LiteralPath $cible -PathType Container)) { Stop-WithError "La cible '$cible' n'existe plus." }

Write-Host "Jonction : $Jonction"
Write-Host "Cible    : $cible"
$stats = Get-FolderStats $cible
Write-Host ("  {0} fichiers, {1:N2} Go a rapatrier" -f $stats.Count, ($stats.Size / 1GB))

$drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Jonction))
if ($drive.AvailableFreeSpace -lt $stats.Size * 1.05) { Stop-WithError ("Pas assez de place sur {0} ({1:N2} Go libres)." -f $drive.Name, ($drive.AvailableFreeSpace / 1GB)) }

Write-Host "Fermez les applications qui utilisent ce dossier avant de continuer." -ForegroundColor Yellow

# --- Suppression de la jonction seule (Directory.Delete non recursif = ne touche pas a la cible)
[IO.Directory]::Delete($Jonction)

# --- Copie + verification
robocopy $cible $Jonction /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:8 /NFL /NDL /NJH /NP
$ok = $LASTEXITCODE -lt 8
if ($ok) {
    $after = Get-FolderStats $Jonction
    $ok = ($after.Count -eq $stats.Count -and $after.Size -eq $stats.Size)
}
if (-not $ok) {
    # Retour a l'etat initial
    if (Test-Path -LiteralPath $Jonction) { cmd /c rd /s /q "\\?\$Jonction" }
    cmd /c mklink /J "`"$Jonction`"" "`"$cible`"" | Out-Null
    Stop-WithError "La copie a echoue ou est incomplete : la jonction a ete recreee, rien n'est perdu."
}
Write-Host "Dossier rapatrie dans '$Jonction'." -ForegroundColor Green

if (-not $Force) {
    $r = Read-Host "Supprimer definitivement l'ancienne copie '$cible' ? (o/N)"
    if ($r -notmatch '^[oOyY]') { Write-Host "Ancienne copie conservee dans '$cible'."; pause; exit 0 }
}
cmd /c rd /s /q "\\?\$cible"
Write-Host "Termine." -ForegroundColor Green
pause
