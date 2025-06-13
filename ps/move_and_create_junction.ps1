# Fonction pour sélectionner un dossier via une boîte de dialogue
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Write-Host "Le script a démarré"

function Select-Folder($prompt) {
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = $prompt
    $folderBrowser.ShowNewFolderButton = $true
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    }
    else {
        Write-Host "Aucun dossier sélectionné."
        exit
    }
}
#! Test
# Vérifie si le script est exécuté en tant qu'administrateur
# if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
#     [Security.Principal.WindowsBuiltInRole]::Administrator)) {

#     Write-Host "Redémarrage du script avec les droits administrateur..."
    
#     # Relance le script avec les privilèges administrateur
#     $psi = New-Object System.Diagnostics.ProcessStartInfo
#     $psi.FileName = "powershell.exe"
#     $psi.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
#     $psi.Verb = "runas"
#     try {
#         [System.Diagnostics.Process]::Start($psi) | Out-Null
#     } catch {
#         Write-Host -ForegroundColor Red "Le script a besoin des droits administrateur pour fonctionner."
#     }
#     exit
# }
#! Fin Test

# Sélectionner le dossier à déplacer (source)
$sourceFolder = Select-Folder "Sélectionnez le dossier à déplacer"
if (-not (Test-Path $sourceFolder)) {
    Write-Host "Le dossier source n'existe pas."
    exit
}
Write-Host "Source choisie : $sourceFolder"

# Sélectionner l'emplacement futur (destination)
$destinationFolder = Select-Folder "Sélectionnez le dossier de destination"
if (-not (Test-Path $destinationFolder)) {
    Write-Host "Le dossier de destination n'existe pas."
    exit
}
Write-Host "Destination choisie : $destinationRoot"

# Write-Host "Dossier source : $sourceFolder"
# Write-Host "Dossier de destination : $destinationFolder"
# $confirmation = Read-Host "Confirmez-vous ces choix ? (O/N)"
# if ($confirmation -notlike "O") {
#     Write-Host "Opération annulée."
#     exit
# }

# Créer le dossier destination s'il n'existe pas
if (-not (Test-Path $destinationFolder)) {
    try {
        New-Item -Path $destinationFolder -ItemType Directory -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Erreur lors de la création du dossier de destination : $($_.Exception.Message)"
        exit
    }
}

# Vérifier si le dossier source et destination ne sont pas les mêmes
if ($sourceFolder -eq $destinationFolder) {
    Write-Host "Le dossier source et le dossier de destination ne peuvent pas être identiques."
    exit
}

# Déplacer le dossier source vers la destination
$destinationFolder = Join-Path $destinationFolder (Split-Path $sourceFolder -Leaf)
try {
    Move-Item -Path $sourceFolder -Destination $destinationFolder -ErrorAction Stop
}
catch {
    Write-Host -ForegroundColor Red "Erreur lors du déplacement du dossier : $($_.Exception.Message)"
    exit
}

# Créer la jonction
$parentFolder = Split-Path $sourceFolder -Parent
$junctionName = Split-Path $sourceFolder -Leaf
$junctionPath = Join-Path $parentFolder $junctionName

# Supprimer le dossier original s'il existe encore après le déplacement
if (Test-Path $junctionPath) {
    try {
        Remove-Item $junctionPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Erreur lors de la suppression de l'ancien dossier : $($_.Exception.Message)"
        exit
    }
}

# Créer la jonction de manière sécurisée
try {
    $mklinkCommand = "mklink /J `"$junctionPath`" `"$destinationFolder`""
    cmd /c $mklinkCommand
    if ($LASTEXITCODE -eq 0) {
        Write-Host "La jonction a été créée avec succès entre '$junctionPath' et '$destinationFolder'."
    } else {
        Write-Host "Une erreur est survenue lors de la création de la jonction."
        exit
    }
}
catch {
    Write-Host -ForegroundColor Red "Erreur lors de l'exécution de la commande mklink : $($_.Exception.Message)"
    exit
}

pause
