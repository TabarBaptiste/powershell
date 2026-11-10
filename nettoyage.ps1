# ============================================================
#  Script de nettoyage PC - genere le 11/10/2026
#  A lancer en ADMINISTRATEUR.
#    Simulation (ne supprime rien) : .\nettoyage.ps1 -Simulation
#    Execution reelle             : .\nettoyage.ps1
#  Journal : $Home\Downloads\Nettoyage_PC.txt
#
#  - Donnees non regenerables -> CORBEILLE (rollback possible)
#  - node_modules / .next / caches / temporaires -> suppression definitive
# ============================================================

param([switch]$Simulation)

$U   = 'C:\Users\bapti'
$Dev = 'C:\developpement'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Simulation) { Write-Host "Relance ce script en tant qu'administrateur." -ForegroundColor Red; exit 1 }

Add-Type -AssemblyName Microsoft.VisualBasic
Start-Transcript -Path "$U\Downloads\Nettoyage_PC.txt" -Force | Out-Null
$freeBefore = (Get-PSDrive C).Free

function Get-SizeGB($p) {
    if (Test-Path -LiteralPath $p -PathType Leaf) { return [math]::Round((Get-Item -LiteralPath $p -Force).Length / 1GB, 2) }
    [math]::Round(((Get-ChildItem -LiteralPath $p -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2)
}

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# Envoie a la corbeille (si trop gros pour la corbeille, Windows peut demander confirmation)
function Remove-ToRecycleBin($p) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "  [absent]    $p" -ForegroundColor DarkGray; return }
    if ($Simulation) { Write-Host ("  [corbeille] {0} ({1} Go)" -f $p, (Get-SizeGB $p)); return }
    try {
        if (Test-Path -LiteralPath $p -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        Write-Host "  [corbeille] $p" -ForegroundColor Green
    } catch { Write-Host "  [ERREUR]    $p : $($_.Exception.Message)" -ForegroundColor Red }
}

# Suppression definitive (pour ce qui se regenere)
function Remove-Hard($p) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "  [absent]    $p" -ForegroundColor DarkGray; return }
    if ($Simulation) { Write-Host ("  [supprime]  {0} ({1} Go)" -f $p, (Get-SizeGB $p)); return }
    if (Test-Path -LiteralPath $p -PathType Container) {
        cmd /c rd /s /q "\\?\$p" 2>$null      # \\?\ = gere les chemins tres longs de node_modules
    } else {
        Remove-Item -LiteralPath $p -Force -EA SilentlyContinue
    }
    if (Test-Path -LiteralPath $p) { Write-Host "  [ERREUR]    $p (fichier verrouille ?)" -ForegroundColor Red }
    else { Write-Host "  [supprime]  $p" -ForegroundColor Green }
}

# Recherche node_modules / .next sans descendre dedans, en sautant bambouno et portfolio
function Find-DepDirs($dir) {
    try { $subs = [IO.Directory]::GetDirectories($dir) } catch { return }
    foreach ($s in $subs) {
        $name = [IO.Path]::GetFileName($s)
        if ((Get-Item -LiteralPath $s -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($s -match '\\perso\\(bambouno|portfolio)$') { continue }
        if ($name -eq 'node_modules' -or $name -eq '.next') { $s }
        elseif ($name -ne '.git') { Find-DepDirs $s }
    }
}

if ($Simulation) { Write-Host "`n*** MODE SIMULATION : rien ne sera supprime ***" -ForegroundColor Yellow }

# ------------------------------------------------------------
Section "1. Docker (images, conteneurs, volumes)"
$dockerDisk = "$U\AppData\Local\Docker\wsl\disk\docker_data.vhdx"
if (-not $Simulation) {
    Get-Process 'Docker Desktop', 'com.docker.backend', 'com.docker.build', 'com.docker.service' -EA SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3
    wsl --shutdown
    Start-Sleep -Seconds 3
}
Remove-Hard $dockerDisk   # Docker Desktop recree un disque vide au prochain lancement

# ------------------------------------------------------------
Section "2. WSL Ubuntu"
if ($Simulation) { Write-Host "  [supprime]  distribution WSL 'Ubuntu' (13,9 Go)" }
else { wsl --unregister Ubuntu }

# ------------------------------------------------------------
Section "3. node_modules / .next (sauf bambouno et portfolio)"
Find-DepDirs $Dev | ForEach-Object { Remove-Hard $_ }
Remove-ToRecycleBin "$U\node_modules"
Remove-ToRecycleBin "$U\package.json"
Remove-ToRecycleBin "$U\package-lock.json"

# ------------------------------------------------------------
Section "4. Caches (se retelechargent si besoin) - AMD et Rust conserves"
Remove-Hard "$U\AppData\Local\npm-cache"
Remove-Hard "$U\AppData\Local\Yarn"
Remove-Hard "$U\AppData\Local\pip\Cache"
Remove-Hard "$U\AppData\Local\ms-playwright"
Remove-Hard "$U\AppData\Local\Cypress\Cache"
Remove-Hard "$U\AppData\Local\.dartServer"
Remove-Hard "$U\AppData\Local\Pub\Cache"
Remove-Hard "$U\.gradle\caches"        # on garde gradle.properties eventuel
Remove-Hard "$U\.gradle\wrapper\dists"
Remove-Hard "$U\.gradle\daemon"
Remove-Hard "$U\.m2\repository"        # on garde settings.xml eventuel

# ------------------------------------------------------------
Section "5. Desinstallation : Silverlight, Teams Machine-Wide, Ruby, Scrivener, Laragon"
$uninstKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'

$msi = @{ 'Microsoft Silverlight' = '{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}'
          'Teams Machine-Wide Installer' = '{731F6BAA-A986-45A4-8936-7C3AAAAA760B}' }
foreach ($n in $msi.Keys) {
    Write-Host "  $n"
    if (-not $Simulation) {
        $r = Start-Process msiexec.exe -ArgumentList "/x $($msi[$n]) /qn /norestart" -Wait -PassThru
        Write-Host "    code retour : $($r.ExitCode) (0 ou 1605 = OK/deja absent)"
    }
}

Write-Host "  Ruby 3.2"
if (-not $Simulation -and (Test-Path 'C:\Ruby32-x64\unins000.exe')) {
    Start-Process 'C:\Ruby32-x64\unins000.exe' -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
}

Write-Host "  Scrivener"
$scriv = "$U\AppData\Local\Scrivener3\uninstall.exe"
if (-not $Simulation -and (Test-Path $scriv)) {
    $r = Start-Process $scriv -ArgumentList '--mode unattended' -Wait -PassThru
    if ($r.ExitCode -ne 0) { Start-Process $scriv -Wait }   # sinon desinstalleur classique (cliquer Suivant)
}

Write-Host "  Laragon (dossier deja absent, on retire juste l'entree fantome)"
Get-ItemProperty $uninstKeys -EA SilentlyContinue | Where-Object { $_.DisplayName -like 'Laragon*' } | ForEach-Object {
    if ($Simulation) { Write-Host "    [supprime]  entree registre $($_.PSChildName)" }
    else { Remove-Item $_.PSPath -Recurse -Force; Write-Host "    [supprime]  entree registre $($_.PSChildName)" -ForegroundColor Green }
}

# Retire les entrees PATH mortes (Ruby, wamp64 qui n'existe plus)
foreach ($scope in 'Machine', 'User') {
    $path = [Environment]::GetEnvironmentVariable('Path', $scope)
    if (-not $path) { continue }
    $parts = $path -split ';' | Where-Object { $_ }
    $dead  = $parts | Where-Object { $_ -match '\\Ruby32-x64\\|^C:\\wamp64\\' }
    if ($dead) {
        $dead | ForEach-Object { Write-Host "  [PATH $scope] retire : $_" }
        if (-not $Simulation) { [Environment]::SetEnvironmentVariable('Path', (($parts | Where-Object { $_ -notin $dead }) -join ';'), $scope) }
    }
}

# ------------------------------------------------------------
Section "6. Restes 2023 / projets archives -> corbeille"
Remove-ToRecycleBin "$U\wamp_www_backup"
Remove-ToRecycleBin "$U\.jdks"
Remove-ToRecycleBin 'C:\Mono'
Remove-ToRecycleBin 'C:\mono.msi'
Remove-ToRecycleBin 'C:\Ruby32-x64'     # au cas ou le desinstalleur laisse des restes
Remove-ToRecycleBin "$U\AppData\Local\Scrivener3"

# ------------------------------------------------------------
Section "7. Assistants IA abandonnes -> corbeille"
if (-not $Simulation) {
    $code = Get-Command code -EA SilentlyContinue
    if ($code) { & code --uninstall-extension codeium.codeium 2>$null }   # sinon l'extension recree .codeium
} else { Write-Host "  [desinstalle] extension VS Code codeium.codeium" }
Remove-ToRecycleBin "$U\.codeium"
Remove-ToRecycleBin "$U\.windsurf"
Remove-ToRecycleBin "$U\.codegpt"
Remove-ToRecycleBin "$U\AppData\Roaming\TabNine"
Remove-ToRecycleBin "$U\AppData\Local\TabNine"

# ------------------------------------------------------------
Section "8. Divers racine C:\ et profil"
Remove-ToRecycleBin 'C:\logiciel - virtualisation - vmware workstation 16 pro 1.2-17966106 sans cle (1)'
Remove-ToRecycleBin 'C:\adobeTemp'
Remove-Hard 'C:\temp'
Remove-Hard 'C:\DumpStack.log'
Remove-Hard 'C:\WRP187A.tmp'
Get-ChildItem $U -Force -File -EA SilentlyContinue |
    Where-Object { $_.Name -match '^\.claude\.json\.backup\.\d+$|^java\d\.log$|^ganttproject\.log(\.\d)?$|^composer-setup\.php$|^AMDRM_Install\.log$' } |
    ForEach-Object { Remove-ToRecycleBin $_.FullName }

# ------------------------------------------------------------
Section "Bilan"
$gain = [math]::Round(((Get-PSDrive C).Free - $freeBefore) / 1GB, 1)
if ($Simulation) { Write-Host "Simulation terminee. Relance sans -Simulation pour executer." -ForegroundColor Yellow }
else {
    Write-Host "Espace libere immediatement : $gain Go" -ForegroundColor Green
    Write-Host "Les elements envoyes a la corbeille occupent encore de la place tant qu'elle n'est pas videe." -ForegroundColor Yellow
}
Stop-Transcript | Out-Null
