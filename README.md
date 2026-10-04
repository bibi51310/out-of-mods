# Out of Mods — launcher & FlatGround 2 for *Out of Ore*

🇫🇷 [Français](#français) · 🇬🇧 [English](#english)

> **Statut / Status** : version 0.1.0 (préversion / preview). Testé sur / tested on **Out of Ore 0.36.5550, build Steam 25627989, branche bêta**.
> Licence / License : **MIT** — © 2026 Out of Mods (voir / see `LICENSE`, `THIRD_PARTY_NOTICES.md`).

---

## Français

### Ce que contient ce projet

| Élément | Rôle |
|---|---|
| **FlatGround 2** (mod) | Un **plancher de creusage** : aucun terrassement sous la hauteur Z choisie → des terrains parfaitement plats. Panneau en jeu, hauteurs nommées, **lame automatique de bulldozer** qui tient le plancher. |
| **Out of Mods** (le launcheur, programme Windows) | Détecte le jeu, installe / désinstalle / active les mods et, **si vous le demandez**, installe UE4SS. **Rien n'est fait sans votre confirmation.** |
| **OutOfOreAPI** (pour les moddeurs) | Bibliothèque Lua : lecture du monde, des engins, de l'économie, fenêtres en jeu… voir `api/README.md`. |

### Fonctions de FlatGround 2

* **Plancher Z** : toute pelle, chargeuse ou bulldozer ne peut plus creuser sous la hauteur choisie (la boîte de creusage est raccourcie, jamais refusée : pas de « trou » ni de blocage).
* **Panneau en jeu** (touche **F7**, **F8** pour fermer, déplaçable à la souris, taille réglable avec `flat2_scale`, s'adapte à la résolution).
  * Onglet **Plancher** : `Dernier coup` (plancher = bas du dernier coup de pelle), `= Tranchant` (hauteur du tranchant de la lame), `= Visé` (hauteur du sol que vous visez), `Désactiver`, réglage fin `−10 −1 +1 +10` cm, texte plancher / tranchant / écart.
  * **Hauteurs nommées** : enregistrez, rappelez, mettez à jour vos hauteurs.
  * Onglet **Lame** : lame automatique (voir ci-dessous).
* **Lame automatique de bulldozer** : pilote le module **AutoLevel natif** du jeu (le même que la touche **J**) pour tenir le tranchant au plancher, à 1–2 cm près, y compris l'inclinaison latérale (gérée par le module).
  * Décalage de la cible `±1 / ±5` cm ; **marche arrière** : la lame se relève de *N* cm pour décharger la terre ; **Reprise** : le module se coupe sous la résistance du sol, le mod le réarme tout seul.
  * Sécurités : **bulldozer seulement**, plancher actif requis, arrêt en quittant l'engin, **touche J = arrêt d'urgence**.
  * ⚠ Demande le **module AutoLevel monté sur le bulldozer** (branche bêta du jeu). Sans lui, le bouton refuse de s'activer. Le plancher, lui, fonctionne partout.

### Installation

**Avec le launcheur (recommandé)** — lancez `OutOfMods.exe` (interface en français ou en anglais, selon Windows ; sélecteur en haut à droite) :

1. Il détecte votre jeu Steam. Si UE4SS manque, il propose **« Installer UE4SS (téléchargement)… »** : vous voyez d'où ça vient, la liste exacte des fichiers, et vous confirmez.
2. Sélectionnez **FlatGround 2** dans « Paquets disponibles » → **Installer…** → lisez le détail → confirmez.
3. Lancez le jeu. **F7** ouvre le panneau.

**À la main** : installez UE4SS (voir ci-dessous), copiez le dossier `FlatGround2` du zip dans `…/OutOfOre/Binaries/Win64/ue4ss/Mods/` (le fichier `enabled.txt` suffit à l'activer).

### Mises à jour

Le bouton **« Mises à jour... »** du launcheur cherche une nouvelle version du launcheur et de vos mods **uniquement quand vous le demandez** (ou au démarrage si vous cochez la case prévue). Avant la moindre connexion, il affiche l'adresse contactée ; il ne télécharge qu'un petit fichier de description. Vous choisissez ensuite ce que vous mettez à jour : le fichier est **vérifié par son empreinte SHA-256**, le détail s'affiche, puis vous confirmez. Pour le launcheur lui-même : il se ferme, remplace ses fichiers, se rouvre, et **garde la version précédente** (`OutOfMods_previous`) pour un retour arrière ; vos paquets ajoutés et vos réglages ne sont pas touchés. Un mod mis à jour est sauvegardé comme pour une réinstallation.

### Vie privée et sécurité du launcheur

* **Lecture seule par défaut** : détecter le jeu et les mods n'écrit rien.
* Chaque installation / désinstallation / activation affiche **le détail exact** (fichiers, dossier cible, sauvegardes) et attend votre « Confirmer ». *Annuler* est le bouton par défaut.
* **Aucun accès Internet**, sauf téléchargement d'UE4SS **que vous demandez** : HTTPS depuis github.com uniquement, empreinte SHA-256 vérifiée avant toute installation.
* Aucun programme n'est installé hormis `dwmapi.dll` et `UE4SS.dll` (UE4SS lui-même) ; les paquets de mods contiennent uniquement du texte (Lua, JSON…).
* Vos fichiers existants sont **sauvegardés** (`OutOfMods_backups`) ; vos réglages UE4SS et vos mods sont conservés ; la désinstallation ne retire que ce que le launcheur a installé et **restaure** ce qu'il avait remplacé. Vos données (hauteurs, réglages) ne sont jamais touchées.
* Votre antivirus peut signaler `dwmapi.dll` : c'est le chargeur d'UE4SS (faux positif connu).

### UE4SS : version recommandée

Le launcheur propose le build **`3.0.1 — e3ba1016`** d'[UE4SS-RE](https://github.com/UE4SS-RE/RE-UE4SS) (licence MIT), **validé avec Out of Ore**. ⚠ La release « stable » v3.0.1 charge les mods mais **fait échouer les hooks de terrassement** : à éviter. Les réglages recommandés (UE 4.27, console graphique désactivée) sont appliqués à un fichier de réglages *nouvellement créé* uniquement.

### Signaler un problème

Précisez : version du jeu (le menu l'affiche, ex. `v0.36.5550`), mod / launcheur et leur version, ce que vous faisiez, et joignez `UE4SS.log` (dans `…/Win64/ue4ss/`) et, pour la lame, `%APPDATA%\OutOfOreFlat2\auto_trace.txt`.
*(Adresse du dépôt / des tickets : à définir.)*

### Limites connues

* Testé sur **un seul build** du jeu ; une mise à jour peut casser un mod (le launcheur affiche un avertissement si le build diffère).
* Le plancher fonctionne en solo ; le multijoueur n'a pas été testé.
* Panneau vérifié en 1080p et 720p (formule d'adaptation valable pour les autres résolutions).

---

## English

### What's in this project

| Item | What it does |
|---|---|
| **FlatGround 2** (mod) | A **digging floor**: nothing can be dug below your chosen Z height → perfectly flat ground. In-game panel, named heights and an **automatic bulldozer blade** that holds the floor. |
| **Out of Mods** (the launcher, Windows app) | Detects the game, installs / uninstalls / enables mods and, **only if you ask**, installs UE4SS. **Nothing happens without your confirmation.** |
| **OutOfOreAPI** (for modders) | Lua library: world, vehicles, economy, in-game windows… see `api/README.md`. |

### FlatGround 2 features

* **Z floor**: excavators, loaders and bulldozers can no longer dig below the chosen height (the dig box is shortened, never refused — no stuck states).
* **In-game panel** (**F7** opens, **F8** closes, draggable, size set with `flat2_scale`, adapts to the resolution).
  * **Floor** tab: `Last cut` (floor = bottom of the last dig), `= Blade edge`, `= Aimed` (height of the ground you aim at), `Disable`, fine tuning `−10 −1 +1 +10` cm, floor / edge / gap readout.
  * **Named heights**: save, recall and update your heights.
  * **Blade** tab: automatic blade (below).
* **Automatic bulldozer blade**: drives the game's **native AutoLevel module** (the one behind the **J** key) to hold the blade edge at the floor within 1–2 cm, side tilt included (handled by the module).
  * Target offset `±1 / ±5` cm; **reverse**: the blade lifts *N* cm to dump dirt; **Resume**: the module switches itself off under ground resistance, the mod re-arms it automatically.
  * Safeguards: **bulldozer only**, active floor required, stops when you leave the vehicle, **J key = emergency stop**.
  * ⚠ Requires the **AutoLevel module mounted on the bulldozer** (game's beta branch). Without it the button refuses to start. The floor itself works everywhere.

### Installation

**With the launcher (recommended)** — run `OutOfMods.exe` (French or English interface depending on Windows; selector at the top right):

1. It detects your Steam game. If UE4SS is missing it offers **"Install UE4SS (download)…"**: you see where it comes from, the exact file list, and you confirm.
2. Select **FlatGround 2** under "Available packages" → **Install…** → read the details → confirm.
3. Start the game. **F7** opens the panel.

**Manually**: install UE4SS (see below), copy the `FlatGround2` folder from the zip into `…/OutOfOre/Binaries/Win64/ue4ss/Mods/` (the `enabled.txt` file is enough to enable it).

### Updates

The launcher's **"Updates..."** button looks for a new version of the launcher and your mods **only when you ask** (or at startup if you tick the option). It shows the address it will contact before any connection and only downloads a small description file. You then pick what to update: the file is **verified against its SHA-256 fingerprint**, the details are shown, then you confirm. For the launcher itself: it closes, replaces its files, reopens, and **keeps the previous version** (`OutOfMods_previous`) for rollback; your added packages and settings are untouched. An updated mod is backed up like a reinstall.

### Launcher privacy & safety

* **Read-only by default**: detecting the game and mods writes nothing.
* Every install / uninstall / enable shows **the exact details** (files, target folder, backups) and waits for your "Confirm". *Cancel* is the default button.
* **No network access**, except the UE4SS download **you request**: HTTPS from github.com only, SHA-256 verified before anything is installed.
* No program is installed other than `dwmapi.dll` and `UE4SS.dll` (UE4SS itself); mod packages contain text only (Lua, JSON…).
* Existing files are **backed up** (`OutOfMods_backups`); your UE4SS settings and mods are kept; uninstalling removes only what the launcher installed and **restores** what it replaced. Your data (heights, settings) is never touched.
* Your antivirus may flag `dwmapi.dll`: that is the UE4SS loader (known false positive).

### UE4SS: recommended version

The launcher offers **`3.0.1 — e3ba1016`** from [UE4SS-RE](https://github.com/UE4SS-RE/RE-UE4SS) (MIT), **validated with Out of Ore**. ⚠ The "stable" v3.0.1 release loads mods but **breaks the digging hooks**: avoid it. Recommended settings (UE 4.27, GUI console off) are applied to a *newly created* settings file only.

### Reporting a problem

Please include: game version (shown in the menu, e.g. `v0.36.5550`), mod / launcher and their version, what you were doing, and attach `UE4SS.log` (in `…/Win64/ue4ss/`) and, for the blade, `%APPDATA%\OutOfOreFlat2\auto_trace.txt`.
*(Repository / issue tracker address: to be defined.)*

### Known limitations

* Tested on **a single game build**; an update may break a mod (the launcher warns when the build differs).
* The floor works in single player; multiplayer has not been tested.
* Panel verified at 1080p and 720p (the adaptation formula applies to other resolutions).

---

## Licence / License

**MIT** — © 2026 Out of Mods. Le code (mod, launcheur, API) peut être utilisé, modifié et redistribué librement en gardant la mention de copyright. Composants tiers et leurs licences : `THIRD_PARTY_NOTICES.md`.
Projet communautaire **indépendant**, sans lien avec les développeurs ni l'éditeur d'*Out of Ore*.

**MIT** — © 2026 Out of Mods. The code (mod, launcher, API) may be freely used, modified and redistributed as long as the copyright notice is kept. Third-party components and their licenses: `THIRD_PARTY_NOTICES.md`.
An **independent** community project, not affiliated with the developers or publisher of *Out of Ore*.

## Crédits / Credits

* [UE4SS-RE](https://github.com/UE4SS-RE/RE-UE4SS) — Lua mod loader (MIT).
* *Out of Ore* community modding efforts for the loader kit and documentation.
* *Out of Ore* is the property of its developers; this project is unofficial and unaffiliated.
