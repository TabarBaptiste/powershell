# 📁 Scripts PowerShell pour gestion avancée des dossiers

J’ai créé ces scripts dans le but de **simplifier la gestion manuelle des dossiers volumineux** sur Windows, notamment lorsque l’on veut libérer de l’espace tout en maintenant la compatibilité avec les chemins originaux grâce aux **jonctions NTFS**.

Ces scripts sont destinés à :

* Identifier les dossiers les plus lourds
* Déplacer certains dossiers tout en créant une jonction à leur ancien emplacement
* Restaurer les dossiers déplacés à leur emplacement d’origine

---

## 🔍 `find-largest-folder.ps1` — Identifier les plus gros dossiers

Ce script :

* Ouvre une boîte de dialogue pour que l'utilisateur sélectionne un dossier parent.
* Analyse tous les dossiers enfants (non récursivement).
* Calcule la **taille réelle occupée sur disque** de chaque sous-dossier.
* Affiche les **10 plus volumineux** dans la console.
* Indique si un dossier est une **jonction** via un indicateur `[OK]`.

💡 Très utile pour détecter rapidement les dossiers à déplacer ou archiver.

---

## 📦 `move_and_create_junction.ps1` — Déplacer un dossier et créer une jonction

Ce script :

* Permet à l’utilisateur de sélectionner un **dossier source à déplacer** et une **destination**.
* Déplace le dossier sélectionné à la nouvelle destination.
* Crée ensuite une **jonction symbolique (NTFS)** à l’emplacement d’origine, pointant vers la nouvelle destination.

✅ Cela permet de **libérer de l’espace sur un disque tout en conservant la compatibilité** avec d’anciens chemins utilisés par des applications.

---

## ↩️ `origin.ps1` — Restaurer un dossier déplacé

Ce script inverse l’opération précédente :

* L’utilisateur sélectionne la **jonction existante** et l’emplacement actuel du dossier déplacé.
* Le script supprime la jonction.
* Puis il **replace le dossier** à son emplacement d’origine.

📌 Très pratique pour **réorganiser** ou **désactiver une jonction** sans casser les liens de dépendance.

---

## 🩺 `diag.ps1` — Diagnostic système complet

Ce script :

* Lance une série de contrôles système (12 sections) et génère un rapport complet.
* Génère : `$Home\Downloads\Diagnostic_PC.txt`.
* Sections couvertes : Système, RAM, CPU, Disques, Réseau, Démarrage, Services, Énergie, GPU, Journaux (24h), Mises à jour, Sécurité.
* Conçu pour être robuste : chaque section s’exécute en job avec un timeout par défaut de 30s (modifiable en tête de script).
* Utilise `Get-CimInstance`, `Get-NetAdapter`, `Get-WinEvent`, `Get-MpComputerStatus`, entre autres.
* Exécution : ouvrez PowerShell et lancez `.\diag.ps1` (privilèges administrateur recommandés pour collecter toutes les informations).

---

## 🧠 Remarques générales

* Tous les scripts utilisent des **interfaces graphiques Windows.Forms** pour faciliter l’usage sans avoir à taper de chemins manuellement.
* Des vérifications d’erreurs sont présentes pour éviter les actions critiques (écrasement, mauvais dossiers, etc.).
* Une version avec élévation des privilèges est prévue mais commentée dans `move_and_create_junction.ps1`.

<!-- ---

## 📂 Arborescence typique :

```
test/ps/
│
├── find-largest-folder.ps1            # Lister les dossiers les plus volumineux
├── move_and_create_junction.ps1       # Déplacer un dossier + créer une jonction
├── origin.ps1                          # Supprimer une jonction et restaurer le dossier
``` -->
