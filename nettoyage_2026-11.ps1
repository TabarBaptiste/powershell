# ============================================================
#  Nettoyage PC - partie administrateur (10/11/2026)
#  A lancer en ADMINISTRATEUR.
#    Simulation (ne supprime rien) : .\nettoyage_2026-11.ps1 -Simulation
#    Execution reelle             : .\nettoyage_2026-11.ps1
#  Journal : $Home\Downloads\Nettoyage_PC_2026-11.txt
#
#  1. Desinstalle .NET Desktop Runtime 6.0.10 et 7.0.0 (plus maintenus ;
#     .NET 8 reste installe)
#  2. Supprime les restes de VMware (logiciel deja desinstalle)
#  3. Retire l'entree "GRIS" restee dans Programmes et fonctionnalites
#     (le jeu a ete supprime de Steam)
# ============================================================

param([switch]$Simulation)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Simulation) { Write-Host "Relance ce script en tant qu'administrateur." -ForegroundColor Red; exit 1 }

Start-Transcript -Path "$Home\Downloads\Nettoyage_PC_2026-11.txt" -Force | Out-Null
$freeBefore = (Get-PSDrive C).Free
if ($Simulation) { Write-Host "`n*** MODE SIMULATION : rien ne sera modifie ***" -ForegroundColor Yellow }
function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# ------------------------------------------------------------
Section "1. .NET Desktop Runtime 6.0.10 et 7.0.0"
# Le desinstalleur "bundle" n'existe plus dans Package Cache : on desinstalle
# directement les paquets MSI qui le composent (.NET 8 n'est pas concerne).
$msi = [ordered]@{
    'Windows Desktop Runtime 7.0.0' = '{192E20E1-D873-40DC-9D0B-0E46E651C583}'
    '.NET Runtime 7.0.0'            = '{A17DDA5A-F944-4E22-B578-FB860C604D21}'
    '.NET Host FX Resolver 7.0.0'   = '{F8BC94FF-FF0C-4226-AE0A-811960F93DF7}'
    '.NET Host 7.0.0'               = '{BE6438FD-8DCE-46CF-9678-825A064DAAAA}'
    'Windows Desktop Runtime 6.0.10'= '{3EC7701F-54F2-491D-AFD1-0395F465BC5A}'
    '.NET Runtime 6.0.10'           = '{A2A39CB9-677D-4299-8537-C00B99F3D4A4}'
    '.NET Host FX Resolver 6.0.10'  = '{A93C4E12-1BAB-4CFB-ADBC-9CE0B93176FF}'
    '.NET Host 6.0.10'              = '{0222FFF1-57A3-48A6-9AD2-0D6B5D0172B3}'
}
$allOk = $true
foreach ($name in $msi.Keys) {
    if ($Simulation) { Write-Host "  [desinstalle] $name  (msiexec /x $($msi[$name]))"; continue }
    $r = Start-Process msiexec.exe -ArgumentList "/x $($msi[$name]) /qn /norestart" -Wait -PassThru
    $ok = $r.ExitCode -in 0, 1605, 3010   # 1605 = deja absent, 3010 = redemarrage requis
    if (-not $ok) { $allOk = $false }
    Write-Host ("  [{0}] {1} (code {2})" -f $(if ($ok) {'desinstalle'} else {'ERREUR'}), $name, $r.ExitCode) -ForegroundColor $(if ($ok) {'Green'} else {'Red'})
}
# Entrees "bundle" orphelines dans Programmes et fonctionnalites
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
Get-ChildItem $uninst -EA SilentlyContinue | Where-Object {
    $p = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    $p.DisplayName -match '^Microsoft Windows Desktop Runtime - (6\.0\.10|7\.0\.0) ' -and $p.BundleProviderKey
} | ForEach-Object {
    if ($Simulation) { Write-Host "  [supprime]  entree orpheline $($_.PSChildName)" }
    elseif ($allOk) { Remove-Item $_.PSPath -Recurse -Force; Write-Host "  [supprime]  entree orpheline $($_.PSChildName)" -ForegroundColor Green }
}
if (-not $Simulation) { Write-Host "  Runtimes restants :"; & dotnet --list-runtimes 2>$null | ForEach-Object { "    $_" } }

# ------------------------------------------------------------
Section "2. Restes de VMware"
if (Get-Service -Name 'VMAuthdService','VMUSBArbService','VMnetDHCP' -EA SilentlyContinue) {
    Write-Host "  Des services VMware existent encore : on ne touche a rien." -ForegroundColor Yellow
} else {
    foreach ($p in 'C:\Program Files (x86)\Common Files\VMware', 'C:\ProgramData\VMware') {
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "  [absent]    $p" -ForegroundColor DarkGray; continue }
        if ($Simulation) { Write-Host "  [supprime]  $p"; continue }
        Remove-Item -LiteralPath $p -Recurse -Force -EA SilentlyContinue
        if (Test-Path -LiteralPath $p) { Write-Host "  [ERREUR]    $p" -ForegroundColor Red } else { Write-Host "  [supprime]  $p" -ForegroundColor Green }
    }
}

# ------------------------------------------------------------
Section "3. Entree fantome GRIS"
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 683320'
if (-not (Test-Path $key)) { Write-Host "  [absent]    $key" -ForegroundColor DarkGray }
elseif (Test-Path 'C:\Program Files (x86)\Steam\steamapps\appmanifest_683320.acf') { Write-Host "  GRIS est de nouveau installe : on garde l'entree." -ForegroundColor Yellow }
elseif ($Simulation) { Write-Host "  [supprime]  $key" }
else { Remove-Item $key -Recurse -Force; Write-Host "  [supprime]  $key" -ForegroundColor Green }

# ------------------------------------------------------------
Section "Bilan"
if ($Simulation) { Write-Host "Simulation terminee. Relance sans -Simulation (en admin) pour executer." -ForegroundColor Yellow }
else { Write-Host ("Espace libere : {0:N2} Go" -f (((Get-PSDrive C).Free - $freeBefore) / 1GB)) -ForegroundColor Green }
Stop-Transcript | Out-Null
