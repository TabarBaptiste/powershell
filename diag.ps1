# ============================================================
#  Script de diagnostic global Windows - Version robuste
#  Chaque section a un timeout de 30s et gere les erreurs
#  Genere : $Home\Downloads\Diagnostic_PC.txt
# ============================================================

$OutputFile = "$Home\Downloads\Diagnostic_PC.txt"
$Separator  = "`n" + ("=" * 60) + "`n"
$TimeoutSec = 30

Clear-Host
Write-Host ""
Write-Host "  Diagnostic PC - Lancement..." -ForegroundColor Cyan
Write-Host ""

"DIAGNOSTIC PC - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" | Out-File $OutputFile -Encoding UTF8
("=" * 60) | Out-File $OutputFile -Append -Encoding UTF8

function Invoke-Section {
    param([string]$Label, [scriptblock]$Block, [int]$Timeout = $TimeoutSec)
    Write-Host "  $Label" -ForegroundColor Yellow -NoNewline
    $job = Start-Job -ScriptBlock $Block -ArgumentList $OutputFile, $Separator
    $done = Wait-Job $job -Timeout $Timeout
    if ($done) {
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Write-Host " OK" -ForegroundColor Green
    } else {
        Stop-Job $job
        "`n[TIMEOUT $Timeout s] $Label ignoree." | Out-File $OutputFile -Append -Encoding UTF8
        Write-Host " TIMEOUT ($Timeout s)" -ForegroundColor Red
    }
    Remove-Job $job -Force
}

# 1 - SYSTEME
Invoke-Section "[1/12] Informations systeme..." {
    param($out, $sep)
    try {
        $os   = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15
        $cs   = Get-CimInstance Win32_ComputerSystem  -OperationTimeoutSec 15
        $cpu  = Get-CimInstance Win32_Processor       -OperationTimeoutSec 15 | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS            -OperationTimeoutSec 15
        "$sep=== 1. INFORMATIONS SYSTEME ===" | Out-File $out -Append -Encoding UTF8
        [PSCustomObject]@{
            "OS"             = "$($os.Caption) ($($os.OSArchitecture))"
            "Build"          = $os.Version
            "Installation"   = $os.InstallDate
            "Uptime"         = "$(([datetime]::Now - $os.LastBootUpTime).ToString('dd\j\ hh\h\ mm\m'))"
            "Modele"         = $cs.Model
            "Fabricant"      = $cs.Manufacturer
            "RAM (GB)"       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            "CPU"            = $cpu.Name
            "Coeurs/Threads" = "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
            "BIOS"           = $bios.SMBIOSBIOSVersion
        } | Format-List | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 2 - RAM
Run-Section "[2/12] Utilisation RAM..." {
    param($out, $sep)
    try {
        $os  = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15
        $cs  = Get-CimInstance Win32_ComputerSystem  -OperationTimeoutSec 15
        "$sep=== 2. MEMOIRE (RAM) ===" | Out-File $out -Append -Encoding UTF8
        $tot  = [math]::Round($cs.TotalPhysicalMemory / 1MB, 0)
        $free = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
        $used = $tot - $free
        $pct  = [math]::Round(($used / $tot) * 100, 1)
        "RAM totale   : $([math]::Round($tot/1024,2)) GB"    | Out-File $out -Append -Encoding UTF8
        "RAM utilisee : $([math]::Round($used/1024,2)) GB ($pct %)" | Out-File $out -Append -Encoding UTF8
        "RAM libre    : $([math]::Round($free/1024,2)) GB"   | Out-File $out -Append -Encoding UTF8
        "`n--- Top 15 processus (RAM) ---" | Out-File $out -Append -Encoding UTF8
        Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 15 `
            Name, Id,
            @{N='RAM (MB)'; E={[math]::Round($_.WorkingSet/1MB,1)}},
            @{N='Privee (MB)'; E={[math]::Round($_.PrivateMemorySize64/1MB,1)}} |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 3 - CPU
Run-Section "[3/12] Utilisation CPU..." {
    param($out, $sep)
    try {
        "$sep=== 3. CPU ===" | Out-File $out -Append -Encoding UTF8
        $load = (Get-CimInstance Win32_Processor -OperationTimeoutSec 15 | Measure-Object -Property LoadPercentage -Average).Average
        "Charge globale : $load %" | Out-File $out -Append -Encoding UTF8
        "`n--- Top 15 processus (CPU cumule) ---" | Out-File $out -Append -Encoding UTF8
        Get-Process | Where-Object {$_.CPU -ne $null} | Sort-Object CPU -Descending | Select-Object -First 15 `
            Name, Id,
            @{N='CPU (s)';  E={[math]::Round($_.CPU,1)}},
            @{N='Threads'; E={$_.Threads.Count}} |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 4 - DISQUES
Run-Section "[4/12] Etat des disques..." {
    param($out, $sep)
    try {
        "$sep=== 4. DISQUES ===" | Out-File $out -Append -Encoding UTF8
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -OperationTimeoutSec 15 | Select-Object `
            DeviceID,
            @{N='Taille (GB)'; E={[math]::Round($_.Size/1GB,2)}},
            @{N='Libre (GB)';  E={[math]::Round($_.FreeSpace/1GB,2)}},
            @{N='Utilise (%)'; E={[math]::Round((($_.Size-$_.FreeSpace)/$_.Size)*100,1)}} |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
        "`n--- SMART ---" | Out-File $out -Append -Encoding UTF8
        Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk -OperationTimeoutSec 15 |
            Select-Object FriendlyName, MediaType, OperationalStatus, HealthStatus |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 5 - RESEAU
Run-Section "[5/12] Activite reseau..." {
    param($out, $sep)
    try {
        "$sep=== 5. RESEAU ===" | Out-File $out -Append -Encoding UTF8
        "`n--- Interfaces ---" | Out-File $out -Append -Encoding UTF8
        Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed | Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
        "`n--- Stats (MB depuis demarrage) ---" | Out-File $out -Append -Encoding UTF8
        Get-NetAdapterStatistics | Select-Object Name,
            @{N='Recu (MB)';  E={[math]::Round($_.ReceivedBytes/1MB,2)}},
            @{N='Envoye (MB)';E={[math]::Round($_.SentBytes/1MB,2)}} |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
        "`n--- Connexions TCP etablies ---" | Out-File $out -Append -Encoding UTF8
        Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 20 |
            ForEach-Object {
                $n = try { (Get-Process -Id $_.Name -EA Stop).Name } catch { "PID $($_.Name)" }
                "  $n : $($_.Count) connexion(s)" | Out-File $out -Append -Encoding UTF8
            }
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 6 - DEMARRAGE
Run-Section "[6/12] Applications au demarrage..." {
    param($out, $sep)
    try {
        "$sep=== 6. DEMARRAGE ===" | Out-File $out -Append -Encoding UTF8
        "`n--- Registre Run ---" | Out-File $out -Append -Encoding UTF8
        @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
          "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run") | ForEach-Object {
            if (Test-Path $_) {
                (Get-ItemProperty $_ -EA SilentlyContinue).PSObject.Properties |
                Where-Object {$_.Name -notlike 'PS*'} | ForEach-Object {
                    "  [REGISTRE] $($_.Name) -- $($_.Value)" | Out-File $out -Append -Encoding UTF8
                }
            }
        }
        "`n--- Task Manager (active / desactive) ---" | Out-File $out -Append -Encoding UTF8
        @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
          "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32",
          "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder") |
        ForEach-Object {
            if (Test-Path $_) {
                (Get-ItemProperty $_ -EA SilentlyContinue).PSObject.Properties |
                Where-Object {$_.Name -notlike 'PS*'} | ForEach-Object {
                    $s = if ($_.Value[0] -eq 2 -or $_.Value[0] -eq 3) {"DESACTIVE"} else {"ACTIVE"}
                    "  [$s] $($_.Name)" | Out-File $out -Append -Encoding UTF8
                }
            }
        }
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 7 - SERVICES
Run-Section "[7/12] Services..." -Timeout 90 {
    param($out, $sep)
    try {
        "$sep=== 7. SERVICES ===" | Out-File $out -Append -Encoding UTF8
        "`n--- Services tiers en cours ---" | Out-File $out -Append -Encoding UTF8
        Get-Service | Where-Object {$_.Status -eq 'Running'} | ForEach-Object {
            $w = Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'" -OperationTimeoutSec 5 -EA SilentlyContinue
            [PSCustomObject]@{Nom=$_.Name; Affichage=$_.DisplayName; Mode=$w.StartMode; Path=$w.PathName}
        } | Where-Object {$_.Path -notmatch 'system32|SysWOW64|Microsoft' -or !$_.Path} |
            Format-Table -AutoSize -Wrap | Out-File $out -Append -Encoding UTF8
        "`n--- Total par etat ---" | Out-File $out -Append -Encoding UTF8
        Get-Service | Group-Object Status | Select-Object Name, Count | Format-Table | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 8 - ENERGIE
Run-Section "[8/12] Energie & alimentation..." {
    param($out, $sep)
    try {
        "$sep=== 8. ENERGIE ===" | Out-File $out -Append -Encoding UTF8
        (powercfg /getactivescheme 2>$null) | Out-File $out -Append -Encoding UTF8
        $bat = Get-CimInstance Win32_Battery -OperationTimeoutSec 10 -EA SilentlyContinue
        if ($bat) {
            $bat | Select-Object Name, EstimatedChargeRemaining, BatteryStatus | Format-List | Out-File $out -Append -Encoding UTF8
        } else { "Pas de batterie." | Out-File $out -Append -Encoding UTF8 }
        "`n--- Processus energivores (RAM > 200MB ou CPU > 60s) ---" | Out-File $out -Append -Encoding UTF8
        Get-Process | Where-Object {($_.WorkingSet -gt 200MB) -or ($_.CPU -gt 60)} |
            Sort-Object WorkingSet -Descending | Select-Object Name, Id,
                @{N='RAM (MB)';E={[math]::Round($_.WorkingSet/1MB,1)}},
                @{N='CPU (s)'; E={[math]::Round($_.CPU,1)}} |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 9 - GPU
Run-Section "[9/12] Carte graphique..." {
    param($out, $sep)
    try {
        "$sep=== 9. GPU ===" | Out-File $out -Append -Encoding UTF8
        Get-CimInstance Win32_VideoController -OperationTimeoutSec 15 | Select-Object `
            Name, AdapterRAM, DriverVersion, CurrentHorizontalResolution,
            CurrentVerticalResolution, CurrentRefreshRate, Status |
            Format-List | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# 10 - ERREURS
Run-Section "[10/12] Journaux erreurs..." {
    param($out, $sep)
    "$sep=== 10. ERREURS (24h) ===" | Out-File $out -Append -Encoding UTF8
    $cutoff = (Get-Date).AddHours(-24)
    foreach ($log in @('System','Application')) {
        "`n--- $log ---" | Out-File $out -Append -Encoding UTF8
        try {
            Get-WinEvent -FilterHashtable @{LogName=$log; Level=1,2; StartTime=$cutoff} -EA SilentlyContinue |
                Select-Object -First 10 TimeCreated, LevelDisplayName, ProviderName,
                    @{N='Message';E={($_.Message -split "`n")[0] -replace '\r',''}} |
                Format-List | Out-File $out -Append -Encoding UTF8
        } catch { "[ERREUR journal $log] $_" | Out-File $out -Append -Encoding UTF8 }
    }
}

# 11 - MISES A JOUR (Get-HotFix remplace par WMI direct - moins sujet au blocage)
Run-Section "[11/12] Mises a jour..." {
    param($out, $sep)
    "$sep=== 11. MISES A JOUR ===" | Out-File $out -Append -Encoding UTF8
    try {
        Get-CimInstance -ClassName Win32_QuickFixEngineering -OperationTimeoutSec 20 |
            Sort-Object InstalledOn -Descending | Select-Object -First 10 Description, HotFixID, InstalledOn |
            Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "[ERREUR] WMI QuickFixEngineering a echoue : $_" | Out-File $out -Append -Encoding UTF8 }
}

# 12 - SECURITE
Run-Section "[12/12] Securite..." {
    param($out, $sep)
    try {
        "$sep=== 12. SECURITE ===" | Out-File $out -Append -Encoding UTF8
        $def = Get-MpComputerStatus -EA SilentlyContinue
        if ($def) {
            [PSCustomObject]@{
                "Protection temps reel" = $def.RealTimeProtectionEnabled
                "Antivirus"             = $def.AntivirusEnabled
                "Pare-feu"              = $def.FirewallEnabled
                "Derniere analyse"      = $def.LastFullScanEndTime
                "Signatures"            = $def.AntispywareSignatureLastUpdated
            } | Format-List | Out-File $out -Append -Encoding UTF8
        }
        Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table | Out-File $out -Append -Encoding UTF8
        Get-LocalUser | Select-Object Name, Enabled, LastLogon | Format-Table -AutoSize | Out-File $out -Append -Encoding UTF8
    } catch { "`n[ERREUR] $_" | Out-File $out -Append -Encoding UTF8 }
}

# FIN
$Separator | Out-File $OutputFile -Append -Encoding UTF8
"Diagnostic termine le $(Get-Date -Format 'dd/MM/yyyy a HH:mm:ss')" | Out-File $OutputFile -Append -Encoding UTF8
Write-Host ""
Write-Host "  Termine ! Fichier : $OutputFile" -ForegroundColor Green
Write-Host ""
