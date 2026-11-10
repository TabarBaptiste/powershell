# 📁 Scripts PowerShell pour gérer, diagnostiquer et nettoyer Windows

J’ai créé ces scripts pour **simplifier la gestion des dossiers volumineux**, **diagnostiquer le PC** et **libérer de l’espace** sur Windows, notamment grâce aux **jonctions NTFS** qui gardent les chemins d’origine valides.

| Script | Rôle |
|---|---|
| `find-largest-folder.ps1` | Trouver les dossiers les plus lourds |
| `move_and_create_junction.ps1` | Déplacer un dossier (même vers un autre disque) et laisser une jonction |
| `origin.ps1` | Annuler le déplacement : supprimer la jonction et rapatrier le dossier |
| `diag.ps1` | Diagnostic système complet |
| `diag2_cible.ps1` | Diagnostic ciblé (Java, .NET, démarrage, ExpressVPN) |
| `nettoyage.ps1` | Nettoyage du PC du 11/10/2026 |
| `nettoyage_2026-11.ps1` | Nettoyage du PC, partie administrateur, du 10/11/2026 |
| `lbp_parser.py` | Extracteur de relevés de compte La Banque Postale (JSON) |

> Les scripts qui supportent des paramètres ouvrent une **boîte de dialogue Windows.Forms** quand on ne les fournit pas : on n’a rien à taper.

---

## 🔍 `find-largest-folder.ps1` — Identifier les plus gros dossiers

```powershell
.\find-largest-folder.ps1                          # boîte de dialogue
.\find-largest-folder.ps1 -Path C:\Users\moi -Top 15
```

* Analyse les sous-dossiers directs du dossier choisi et affiche les `-Top` plus volumineux (10 par défaut), avec leur **nombre de fichiers**.
* Compte les **fichiers cachés et système**.
* Ne suit pas les **jonctions** : elles sont affichées avec leur cible et comptent 0, puisqu’elles n’occupent plus de place sur ce disque.
* Ignore les fichiers OneDrive « en ligne uniquement » (absents du disque).
* Signale les dossiers inaccessibles (relancer en administrateur).

---

## 📦 `move_and_create_junction.ps1` — Déplacer un dossier et créer une jonction

```powershell
.\move_and_create_junction.ps1                                   # boîtes de dialogue
.\move_and_create_junction.ps1 -Source C:\Jeux\X -Destination E:\Archives
.\move_and_create_junction.ps1 -Source C:\Jeux\X -Destination E:\Archives -Force   # sans confirmation
```

Libère de l’espace tout en gardant l’ancien chemin valide. Le déroulement est **conçu pour ne rien perdre** :

1. Vérifications : source valide, pas déjà une jonction, destination hors de la source, rien n’existe déjà à l’arrivée, **place suffisante**, disque local.
2. Copie avec `robocopy`, puis **vérification du nombre de fichiers et de la taille**.
3. L’original est **renommé** (instantané), la jonction est créée. Si la jonction échoue, l’original est **remis en place**.
4. L’original n’est supprimé qu’**après confirmation** (ou avec `-Force`).

Fonctionne **d’un disque à l’autre**. Pensez à fermer les applications qui utilisent le dossier.

---

## ↩️ `origin.ps1` — Restaurer un dossier déplacé

```powershell
.\origin.ps1                          # boîte de dialogue
.\origin.ps1 -Jonction C:\Jeux\X -Force
```

Inverse l’opération précédente :

* Il suffit de désigner la **jonction** : sa cible est lue automatiquement.
* Le dossier est copié (`robocopy`) à l’emplacement d’origine et **vérifié** (fichiers + taille).
* Si la copie échoue, la **jonction est recréée** : rien n’est perdu.
* L’ancienne copie n’est supprimée qu’après confirmation (ou avec `-Force`).

---

## 🩺 `diag.ps1` — Diagnostic système complet

* Lance 12 contrôles et génère `$Home\Downloads\Diagnostic_PC.txt`.
* Sections : Système, RAM, CPU, Disques, Réseau, Démarrage, Services, Énergie, GPU, Journaux (24 h), Mises à jour, Sécurité.
* Chaque section s’exécute dans un **job avec timeout** (30 s par défaut, modifiable en tête de script) : un blocage n’arrête pas le rapport.
* Exécution : `.\diag.ps1` (administrateur recommandé pour tout collecter).

---

## 🎯 `diag2_cible.ps1` — Diagnostic ciblé

* Génère `$Home\Downloads\Diag2_Cible.txt`.
* Contenu : processus et installations **Java**, erreurs **.NET Runtime** (3 jours), plantages d’applications, versions .NET installées, état des applis au **démarrage**, analyse **ExpressVPN**.
* **Ne modifie rien par défaut.** Pour désactiver au démarrage les applis de la liste `$toDisable` (Steam, Discord, Docker Desktop, Figma Agent) :

```powershell
.\diag2_cible.ps1 -DesactiverDemarrage
```

---

## 🧹 `nettoyage.ps1` — Nettoyage du PC (11/10/2026)

```powershell
.\nettoyage.ps1 -Simulation    # n’efface rien, affiche ce qui serait fait
.\nettoyage.ps1                # exécution réelle, en administrateur
```

* Journal : `$Home\Downloads\Nettoyage_PC.txt`.
* Les données non régénérables partent à la **Corbeille** ; les `node_modules`, `.next`, caches et temporaires sont supprimés définitivement.
* **Docker n’est pas touché** : aucune image, conteneur ni volume n’est supprimé (pour faire de la place : `docker system prune`).
* ⚠️ C’est un **nettoyage ponctuel**, écrit pour l’état du PC à cette date. Avant de le relancer, **lancez `-Simulation` et relisez la liste** : il supprime notamment la distribution WSL `Ubuntu` et les `node_modules` de plusieurs projets.

---

## 🧹 `nettoyage_2026-11.ps1` — Nettoyage, partie administrateur (10/11/2026)

```powershell
.\nettoyage_2026-11.ps1 -Simulation    # n’efface rien
.\nettoyage_2026-11.ps1                # en administrateur
```

* Désinstalle **.NET 6.0.10 et 7.0.0** (paquets MSI ; .NET 8 est conservé).
* Supprime les restes de **VMware** (si plus aucun service VMware).
* Retire l’entrée fantôme du jeu **GRIS** dans « Programmes et fonctionnalités ».
* Journal : `$Home\Downloads\Nettoyage_PC_2026-11.txt`.

---

## 🧠 Remarques générales

* Les scripts de nettoyage ont un mode **`-Simulation`** : testez-le toujours en premier.
* Les scripts qui suppriment ou déplacent des données **vérifient avant d’effacer** et proposent un retour arrière.
