# Fonction pour sélectionner un dossier via une boîte de dialogue
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

# Sélectionner la jonction (source)
$junctionPath = Select-Folder "Sélectionnez la jonction à supprimer"
if (-not (Test-Path $junctionPath)) {
    Write-Host "Le chemin de jonction n'existe pas."
    exit
}

# Vérifier si le chemin est une jonction
$attributes = (Get-Item $junctionPath).Attributes
if (-not ($attributes -match "ReparsePoint")) {
    Write-Host "Le dossier sélectionné n'est pas une jonction."
    exit
}

# Sélectionner l'emplacement actuel du dossier réel (destination)
$realFolderLocation = Select-Folder "Sélectionnez l'emplacement actuel du dossier déplacé"
if (-not (Test-Path $realFolderLocation)) {
    Write-Host "Le dossier déplacé n'existe pas."
    exit
}

# Construire le chemin original
$originalFolder = Join-Path (Split-Path $junctionPath -Parent) (Split-Path $junctionPath -Leaf)

# Supprimer la jonction
try {
    Remove-Item $junctionPath -Recurse -Force -ErrorAction Stop
    Write-Host "La jonction a été supprimée avec succès."
}
catch {
    Write-Host "Erreur lors de la suppression de la jonction : $($_.Exception.Message)"
    exit
}

# Vérifier si un dossier existe déjà à l'emplacement d'origine
if (Test-Path $originalFolder) {
    Write-Host "Un dossier existe déjà à l'emplacement d'origine ($originalFolder)."
    exit
}

# Déplacer le dossier réel vers son emplacement d'origine
try {
    Move-Item -Path $realFolderLocation -Destination $originalFolder -ErrorAction Stop
    Write-Host "Le dossier a été déplacé de '$realFolderLocation' vers '$originalFolder'."
}
catch {
    Write-Host "Erreur lors du déplacement du dossier : $($_.Exception.Message)"
    exit
}

pause
