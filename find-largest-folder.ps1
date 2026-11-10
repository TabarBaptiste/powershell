# ============================================================
#  Liste les sous-dossiers les plus lourds d'un dossier.
#
#    .\find-largest-folder.ps1                 -> boite de dialogue
#    .\find-largest-folder.ps1 -Path C:\Users\bapti -Top 15
#
#  - Compte aussi les fichiers caches / systeme.
#  - Ne suit pas les jonctions : un dossier deplace via
#    move_and_create_junction.ps1 est affiche avec sa cible mais
#    compte 0 (il n'occupe plus de place sur ce disque).
#  - Ignore les fichiers OneDrive "en ligne uniquement" (pas sur le disque).
# ============================================================

param(
    [string]$Path,
    [int]$Top = 10
)

if (-not $Path) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Selectionnez le dossier a analyser"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host "Operation annulee."; exit }
    $Path = $dlg.SelectedPath
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Le chemin '$Path' n'existe pas ou n'est pas accessible."
    exit 1
}

$Reparse = [IO.FileAttributes]::ReparsePoint
$Cloud   = 0x1000 -bor 0x400000 -bor 0x40000   # Offline | RecallOnDataAccess | RecallOnOpen

function Get-FolderStats([IO.DirectoryInfo]$root) {
    $count = 0L; $size = 0L; $denied = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count) {
        $d = $stack.Pop()
        try { $entries = $d.GetFileSystemInfos() } catch { $denied++; continue }
        foreach ($e in $entries) {
            if ($e.Attributes -band $Reparse) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e); continue }
            if ([int]$e.Attributes -band $Cloud) { continue }
            $count++; $size += $e.Length
        }
    }
    [PSCustomObject]@{ Count = $count; Size = $size; Denied = $denied }
}

function Format-Size([long]$b) {
    if ($b -ge 1GB) { "{0,8:N2} Go" -f ($b / 1GB) } else { "{0,8:N0} Mo" -f ($b / 1MB) }
}

$folders = @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue)
$results = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $folders) {
    $i++
    Write-Progress -Activity "Analyse de $Path" -Status "$i / $($folders.Count) : $($f.Name)" -PercentComplete ($i * 100 / [math]::Max(1, $folders.Count))
    if ($f.Attributes -band $Reparse) {
        $results.Add([PSCustomObject]@{ Name = $f.FullName; Size = 0L; Count = 0L; Note = "[jonction -> $(@($f.Target)[0])]" })
        continue
    }
    $s = Get-FolderStats $f
    $note = if ($s.Denied) { "($($s.Denied) dossier(s) inaccessible(s), relancer en admin)" } else { "" }
    $results.Add([PSCustomObject]@{ Name = $f.FullName; Size = $s.Size; Count = $s.Count; Note = $note })
}
Write-Progress -Activity "Analyse terminee" -Completed

# Fichiers poses directement dans le dossier
$loose = @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue | Where-Object { -not ([int]$_.Attributes -band $Cloud) })
if ($loose.Count) {
    $results.Add([PSCustomObject]@{ Name = "$Path (fichiers a la racine)"; Size = [long]($loose | Measure-Object Length -Sum).Sum; Count = [long]$loose.Count; Note = "" })
}

$total = ($results | Measure-Object Size -Sum).Sum
Write-Host ("`nTotal : {0}   ({1} sous-dossiers)`n" -f (Format-Size $total).Trim(), $folders.Count) -ForegroundColor Cyan
$results | Sort-Object Size -Descending | Select-Object -First $Top | ForEach-Object {
    "{0}  {1,9:N0} fichiers  {2} {3}" -f (Format-Size $_.Size), $_.Count, $_.Name, $_.Note
}
