# ============================================================
#  Diagnostic ciblé - Java, .NET Runtime, démarrage
#  Génère : $Home\Downloads\Diag2_Cible.txt
# ============================================================

$OutputFile = "$Home\Downloads\Diag2_Cible.txt"
$Separator  = "`n" + ("=" * 60) + "`n"

Clear-Host
Write-Host "  Diagnostic ciblé - lancement..." -ForegroundColor Cyan

"DIAGNOSTIC CIBLÉ - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" | Out-File $OutputFile -Encoding UTF8
("=" * 60) | Out-File $OutputFile -Append -Encoding UTF8


# ── 1. IDENTIFIER LE PROCESSUS JAVA ─────────────────────────
"$Separator=== 1. IDENTIFICATION DU PROCESSUS JAVA ===" | Out-File $OutputFile -Append -Encoding UTF8

$javaProcs = Get-Process -Name "java" -ErrorAction SilentlyContinue
if ($javaProcs) {
    foreach ($p in $javaProcs) {
        "`n--- java PID $($p.Id) ---" | Out-File $OutputFile -Append -Encoding UTF8

        # Chemin de l'exécutable
        try {
            $exe = (Get-Process -Id $p.Id).MainModule.FileName
            "Chemin EXE    : $exe" | Out-File $OutputFile -Append -Encoding UTF8
        } catch {
            "Chemin EXE    : (accès refusé - relancer en admin)" | Out-File $OutputFile -Append -Encoding UTF8
        }

        # Ligne de commande complète (révèle l'application parente)
        $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue
        "Ligne commande: $($wmi.CommandLine)" | Out-File $OutputFile -Append -Encoding UTF8
        "Processus parent PID: $($wmi.ParentProcessId)" | Out-File $OutputFile -Append -Encoding UTF8

        # Qui est le parent ?
        $parent = Get-Process -Id $wmi.ParentProcessId -ErrorAction SilentlyContinue
        if ($parent) {
            "Parent nom    : $($parent.Name)" | Out-File $OutputFile -Append -Encoding UTF8
            $parentWmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($wmi.ParentProcessId)" -ErrorAction SilentlyContinue
            "Parent chemin : $($parentWmi.ExecutablePath)" | Out-File $OutputFile -Append -Encoding UTF8
        }

        # Variables d'environnement clés du processus
        "RAM (MB)      : $([math]::Round($p.WorkingSet/1MB,1))" | Out-File $OutputFile -Append -Encoding UTF8
        "Threads       : $($p.Threads.Count)" | Out-File $OutputFile -Append -Encoding UTF8
    }
} else {
    "Aucun processus java en cours d'exécution au moment du diagnostic." | Out-File $OutputFile -Append -Encoding UTF8
    "`nRecherche d'installations Java sur le système..." | Out-File $OutputFile -Append -Encoding UTF8

    # Recherche dans les emplacements standards
    $javaPaths = @(
        "C:\Program Files\Java",
        "C:\Program Files\Eclipse Adoptium",
        "C:\Program Files\Microsoft",
        "C:\Program Files\Android",
        "$env:LOCALAPPDATA\Programs",
        "$env:APPDATA\Local"
    )
    foreach ($path in $javaPaths) {
        if (Test-Path $path) {
            $found = Get-ChildItem $path -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 5
            foreach ($f in $found) {
                "  Trouvé : $($f.FullName)" | Out-File $OutputFile -Append -Encoding UTF8
            }
        }
    }

    # Registre : JRE/JDK installés
    "`nJava dans le registre :" | Out-File $OutputFile -Append -Encoding UTF8
    $regJava = @(
        "HKLM:\SOFTWARE\JavaSoft",
        "HKLM:\SOFTWARE\WOW6432Node\JavaSoft",
        "HKLM:\SOFTWARE\Eclipse Adoptium",
        "HKLM:\SOFTWARE\Microsoft\JDK"
    )
    foreach ($r in $regJava) {
        if (Test-Path $r) {
            Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
                "  Registre : $($_.Name)" | Out-File $OutputFile -Append -Encoding UTF8
            }
        }
    }

    # Applications installées contenant Java
    "`nApplications installées liées à Java :" | Out-File $OutputFile -Append -Encoding UTF8
    Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                     "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "java|jdk|jre|corretto|temurin|zulu|liberica|android" } |
        Select-Object DisplayName, Publisher, InstallLocation, DisplayVersion |
        Format-List | Out-File $OutputFile -Append -Encoding UTF8
}


# ── 2. ERREURS .NET RUNTIME - ANALYSE DÉTAILLÉE ──────────────
"$Separator=== 2. ERREURS .NET RUNTIME - ANALYSE DÉTAILLÉE ===" | Out-File $OutputFile -Append -Encoding UTF8

$cutoff = (Get-Date).AddDays(-3)

# Erreurs .NET du journal Application
"`n--- Événements .NET Runtime (3 derniers jours) ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime'; StartTime=$cutoff} `
    -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName,
        @{N='Message'; E={$_.Message -replace '\r?\n',' '}} |
    Format-List | Out-File $OutputFile -Append -Encoding UTF8

# Chercher aussi les erreurs Application Framework
"`n--- Événements .NET Runtime Optimization (ngen) ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime Optimization Service'; StartTime=$cutoff} `
    -ErrorAction SilentlyContinue | Select-Object -First 5 TimeCreated, Message |
    Format-List | Out-File $OutputFile -Append -Encoding UTF8

# Erreurs Application Hang (plantages liés)
"`n--- Plantages d'applications (3 derniers jours) ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Hang','Application Error'; StartTime=$cutoff} `
    -ErrorAction SilentlyContinue | Select-Object -First 10 TimeCreated, ProviderName,
        @{N='Message'; E={$_.Message -replace '\r?\n',' '}} |
    Format-List | Out-File $OutputFile -Append -Encoding UTF8

# Versions .NET installées
"`n--- Versions .NET installées ---" | Out-File $OutputFile -Append -Encoding UTF8
try {
    & dotnet --list-runtimes 2>$null | Out-File $OutputFile -Append -Encoding UTF8
} catch {}
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP" -Recurse -ErrorAction SilentlyContinue |
    Get-ItemProperty -Name Version, Release -ErrorAction SilentlyContinue |
    Where-Object { $_.Version } |
    Select-Object PSChildName, Version, Release |
    Format-Table | Out-File $OutputFile -Append -Encoding UTF8


# ── 3. DÉSACTIVER LES APPS AU DÉMARRAGE ──────────────────────
"$Separator=== 3. DÉSACTIVATION AU DÉMARRAGE ===" | Out-File $OutputFile -Append -Encoding UTF8

$toDisable = @("Steam", "Discord", "Docker Desktop", "Figma Agent")

"`n--- Désactivation dans le registre StartupApproved ---" | Out-File $OutputFile -Append -Encoding UTF8
$approvedPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"

foreach ($appName in $toDisable) {
    if (Test-Path $approvedPath) {
        $prop = Get-ItemProperty -Path $approvedPath -Name $appName -ErrorAction SilentlyContinue
        if ($prop) {
            # Octet 0 = 03 = désactivé (Task Manager), 02 aussi utilisé
            $val = $prop.$appName
            if ($val[0] -ne 3) {
                $val[0] = 3
                Set-ItemProperty -Path $approvedPath -Name $appName -Value $val -ErrorAction SilentlyContinue
                "  [DÉSACTIVÉ] $appName" | Out-File $OutputFile -Append -Encoding UTF8
                Write-Host "  Désactivé : $appName" -ForegroundColor Green
            } else {
                "  [DÉJÀ DÉSACTIVÉ] $appName" | Out-File $OutputFile -Append -Encoding UTF8
            }
        } else {
            "  [NON TROUVÉ dans StartupApproved] $appName - vérification registre Run..." | Out-File $OutputFile -Append -Encoding UTF8
        }
    }
}

# Vérification état final
"`n--- État final des apps de démarrage ---" | Out-File $OutputFile -Append -Encoding UTF8
if (Test-Path $approvedPath) {
    $items = Get-ItemProperty -Path $approvedPath -ErrorAction SilentlyContinue
    $items.PSObject.Properties | Where-Object {$_.Name -notlike 'PS*'} | ForEach-Object {
        $firstByte = $_.Value[0]
        $status = if ($firstByte -eq 3 -or $firstByte -eq 2) { "DÉSACTIVÉ" } else { "ACTIVÉ" }
        "  [$status] $($_.Name)" | Out-File $OutputFile -Append -Encoding UTF8
    }
}


# ── 4. ANALYSE EXPRESSVPN ────────────────────────────────────
"$Separator=== 4. ANALYSE EXPRESSVPN ===" | Out-File $OutputFile -Append -Encoding UTF8

"`n--- Installation ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "expressvpn" } |
    Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, InstallLocation, UninstallString |
    Format-List | Out-File $OutputFile -Append -Encoding UTF8

"`n--- Services ExpressVPN actifs ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-Service | Where-Object { $_.DisplayName -match "express" -or $_.Name -match "express" } |
    Select-Object Name, DisplayName, Status, StartType | Format-Table | Out-File $OutputFile -Append -Encoding UTF8

"`n--- Pilotes réseau ExpressVPN ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "express|tap|tun" } |
    Select-Object Name, InterfaceDescription, Status, DriverFileName | Format-Table | Out-File $OutputFile -Append -Encoding UTF8

"`n--- Processus ExpressVPN ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-Process | Where-Object { $_.Name -match "express" } |
    Select-Object Name, Id, @{N='RAM (MB)'; E={[math]::Round($_.WorkingSet/1MB,1)}} |
    Format-Table | Out-File $OutputFile -Append -Encoding UTF8

"`n--- Tâches planifiées ExpressVPN ---" | Out-File $OutputFile -Append -Encoding UTF8
Get-ScheduledTask | Where-Object { $_.TaskName -match "express" -or $_.TaskPath -match "express" } |
    Select-Object TaskName, TaskPath, State | Format-Table | Out-File $OutputFile -Append -Encoding UTF8


# ── FIN ──────────────────────────────────────────────────────
$Separator | Out-File $OutputFile -Append -Encoding UTF8
"Diagnostic terminé le $(Get-Date -Format 'dd/MM/yyyy à HH:mm:ss')" | Out-File $OutputFile -Append -Encoding UTF8

Write-Host ""
Write-Host "  Terminé ! Fichier : $OutputFile" -ForegroundColor Green
Write-Host ""