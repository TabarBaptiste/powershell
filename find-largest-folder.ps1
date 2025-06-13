Add-Type -AssemblyName System.Windows.Forms

# Boîte de dialogue pour sélectionner le dossier
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Sélectionnez le dossier à trier"
$folderBrowser.ShowNewFolderButton = $false

if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $directoryPath = $folderBrowser.SelectedPath
} else {
    Write-Host "Opération annulée par l'utilisateur."
    exit
}

# Vérifier l'existence du chemin
if (-Not (Test-Path $directoryPath)) {
    Write-Error "Le chemin spécifié n'existe pas ou n'est pas accessible."
    exit
}

# Récupérer tous les dossiers enfants
$allFolders = Get-ChildItem -Directory -Path $directoryPath -ErrorAction SilentlyContinue
$total = $allFolders.Count
$index = 0
$results = @()

# Parcourir chaque dossier et calculer sa taille
foreach ($folder in $allFolders) {
    $index++

    Write-Progress `
        -Activity "Analyse des dossiers" `
        -Status "$index / $total analysés" `
        # -PercentComplete (($index / $total) * 100)

    try {
        $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    }
    catch {
        Write-Warning "Impossible d'accéder à $($folder.FullName) : $($_.Exception.Message)"
        continue
    }

    # Vérifier si le dossier est une jonction
    $isJunction = (Get-Item $folder.FullName -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint"
    $junctionIndicator = if ($isJunction) { " [OK]" } else { "" }

    $results += [PSCustomObject]@{
        Name = $folder.FullName + $junctionIndicator
        Size = [math]::Round($folderSize / 1MB, 2)
    }
}

# Afficher les 10 plus gros dossiers
$results |
    Sort-Object Size -Descending |
    Select-Object -First 10 |
    ForEach-Object {
        Write-Output ("Dossier : {0} - Taille : {1} Mo" -f $_.Name, $_.Size)
    }

# Nettoyer la barre de progression
Write-Progress -Activity "Analyse terminée" -Completed
