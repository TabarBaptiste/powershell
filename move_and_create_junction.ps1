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

# --- Sélection des dossiers ---

# Dossier source
$sourceFolder = Select-Folder "Sélectionnez le dossier à déplacer"
if (-not (Test-Path $sourceFolder)) {
    Write-Host "Le dossier source n'existe pas."
    exit
}
Write-Host "Source choisie : $sourceFolder"

# Dossier de destination « racine »
$destinationRoot = Select-Folder "Sélectionnez le dossier de destination"
if (-not (Test-Path $destinationRoot)) {
    Write-Host "Le dossier de destination n'existe pas."
    exit
}
Write-Host "Destination choisie : $destinationRoot"

# --- Préparation du déplacement ---

# Empêcher source = destination
if ($sourceFolder -eq $destinationRoot) {
    Write-Host "Le dossier source et le dossier de destination ne peuvent pas être identiques."
    exit
}

# Créer la destination finale (inclut le nom du dossier source)
$destinationFolder = Join-Path $destinationRoot (Split-Path $sourceFolder -Leaf)
if (-not (Test-Path $destinationFolder)) {
    try {
        New-Item -Path $destinationFolder -ItemType Directory -Force -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Erreur lors de la création du dossier de destination : $($_.Exception.Message)"
        exit
    }
}

# --- Déplacement avec indicateur de progression ---

# Récupération de tous les éléments (fichiers et sous-dossiers)
$items = Get-ChildItem -LiteralPath $sourceFolder -Force
$total = $items.Count
$i = 0

foreach ($item in $items) {
    $i++

    # Construction du chemin cible pour chaque élément
    $target = Join-Path $destinationFolder $item.Name

    # Déplacement
    try {
        Move-Item -LiteralPath $item.FullName -Destination $target -ErrorAction Stop
        # Mise à jour de la barre de progression
        Write-Progress `
            -Activity "Déplacement des éléments" `
            -Status "$i / $total éléments déplacés" `
    } catch {
        Write-Host -ForegroundColor Red "Erreur au déplacement de '$($item.Name)' : $($_.Exception.Message)"
        exit
    }

}

# --- Création de la jonction ---

# Chemins pour la jonction
$parentFolder = Split-Path $sourceFolder -Parent
$junctionName = Split-Path $sourceFolder -Leaf
$junctionPath = Join-Path $parentFolder $junctionName

# Suppression de l’ancienne jonction / dossier s’il existe
if (Test-Path $junctionPath) {
    try {
        Remove-Item $junctionPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Erreur lors de la suppression de l'ancien dossier : $($_.Exception.Message)"
        exit
    }
}

# Exécution de mklink pour créer la jonction symbole
try {
    $mklinkCommand = "mklink /J `"$junctionPath`" `"$destinationFolder`""
    cmd /c $mklinkCommand | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "La jonction a été créée avec succès entre '$junctionPath' et '$destinationFolder'."
    }
    else {
        Write-Host -ForegroundColor Red "Erreur lors de la création de la jonction (code $LASTEXITCODE)."
        exit
    }
}
catch {
    Write-Host -ForegroundColor Red "Erreur lors de l'exécution de mklink : $($_.Exception.Message)"
    exit
}

# Pause finale pour laisser le temps de lire les messages
pause
