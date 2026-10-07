# Out of Mods — launcher, FlatGround 2 & Pay Dirt for *Out of Ore*

🇫🇷 [Français](#français) · 🇬🇧 [English](#english)

**Nexus Mods :** [Out of Mods (launcher)](https://www.nexusmods.com/outofore/mods/6) · [FlatGround 2 (mod)](https://www.nexusmods.com/outofore/mods/7) · [Pay Dirt (mod)](https://www.nexusmods.com/outofore/mods/8) — ou / or [GitHub Releases](https://github.com/bibi51310/out-of-mods/releases) · **Discord :** https://discord.gg/CkP5c8cpz4

> **Statut / Status** : version 0.2.0 (FlatGround 2) / 0.1.0 (Pay Dirt) / 0.1.1 (launcheur) (préversion / preview). Testé sur / tested on **Out of Ore 0.36.5550, build Steam 25627989, branche bêta**.
> Licence / License : **MIT** — © 2026 Out of Mods (voir / see `LICENSE`, `THIRD_PARTY_NOTICES.md`).

---

## Français

### Ce que contient ce projet

| Élément | Rôle |
|---|---|
| **FlatGround 2** (mod) | Un **plancher de creusage** : aucun terrassement sous la hauteur Z choisie → des terrains parfaitement plats. Panneau en jeu, hauteurs nommées, **lame automatique de bulldozer** qui tient le plancher. |
| **Pay Dirt** (mod) | **Ventes x2** : le prix de vente des **ressources et minerais** est doublé, affiché et reçu. Aucune sauvegarde modifiée. |
| **Out of Mods** (le launcheur, programme Windows) | Détecte le jeu, installe / désinstalle / active les mods et, **si vous le demandez**, installe UE4SS. **Rien n'est fait sans votre confirmation.** |
| **OutOfOreAPI** (pour les moddeurs) | Bibliothèque Lua : lecture du monde, des engins, de l'économie, fenêtres en jeu… voir `api/README.md`. **Publier votre propre mod : [MODDING.md](MODDING.md).** |

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
* **Plancher en pente et piquets** (onglet **Pente**) : le plancher peut être un plan incliné au lieu d'un plat.
  * `Départ ici` pose le départ du plan au sol réel, à la position de la lame (ou du personnage) ; `Piquet A` / `Piquet B` définissent la pente en visant deux points du sol (2 m minimum, 40 % maximum) ; ou réglez le pourcentage à la main (`±0,5 / ±1`, `0 %` = plat). Le plan démarre au départ et va vers l'avant (ou s'arrête en B).
  * **Piquets 3D** tous les 5 m avec un fil lumineux : **blanc** = remblayer, **rouge** = creuser, **vert** = ok (±10 cm), avec la hauteur cible en texte 3D. `Piquets : ON/off` les affiche ou les masque.
  * Le creusage est limité par le plan et la **lame automatique le suit** en avançant (le décalage entre le point du GPS et l'endroit où la lame coupe est pris en compte).
  * Commandes : `flat2_slope <pourcent>`, `flat2_start`, `flat2_stakes`, `flat2_stake_a`, `flat2_stake_b`.
* **Panneau bilingue FR / EN** : langue du jeu détectée, bouton `FR / EN` dans le panneau, commande `flat2_lang fr|en|auto`.

### Fonctions de Pay Dirt

* **Prix de vente x2** (facteur réglable) pour les **ressources et les minerais** : minerais, roches, terre, asphalte, fluides, métaux affinés (fer, cuivre, or, rubis, platine, silicium, lithium, acier…). Le **prix affiché** dans le magasin et l'**argent reçu** sont identiques, que vous vendiez depuis l'inventaire ou au magasin.
* **Ni les achats ni les quêtes ne changent.** Les engins, bâtiments, pièces, équipements et matériaux qui s'achètent (bois, caoutchouc, plastique, électronique…) ne sont **pas** doublés : tout se revend à environ 70 % de sa valeur, doublé ça dépasserait le prix d'achat (boucle achat / revente).
* **Aucune sauvegarde modifiée** : le mod se charge sur une partie existante ; le retirer rend l'économie normale. Rien n'est écrit dans les règles de la partie.
* Console (`~` ou F10) : `boost <facteur>` (`boost 1` = normal, `boost 3` = x3), `boost_status`, `boost_scope ore|all` (⚠ `all` double aussi engins et bâtiments : risque de boucle achat / revente), `boost_mode price|bonus` (repli), `boost_log 0|1` (diagnostic).
* Le nom vient du « pay dirt », le minerai à laver du jeu.

### Installation

**Avec le launcheur (recommandé)** — lancez `OutOfMods.exe` (interface en français ou en anglais, selon Windows ; sélecteur en haut à droite) :

1. Il détecte votre jeu Steam. Si UE4SS manque, il propose **« Installer UE4SS (téléchargement)… »** : vous voyez d'où ça vient, la liste exacte des fichiers, et vous confirmez.
2. Sélectionnez **FlatGround 2** dans « Paquets disponibles » → **Installer…** → lisez le détail → confirmez. Pour **Pay Dirt** : téléchargez `PayDirt-0.1.0.zip` puis **« Ouvrir un paquet (.zip)… »** → lisez le détail → confirmez.
3. Lancez le jeu. **F7** ouvre le panneau.

**À la main** : installez UE4SS (voir ci-dessous), copiez le dossier `FlatGround2` (ou `PayDirt`) du zip dans `…/OutOfOre/Binaries/Win64/ue4ss/Mods/` (le fichier `enabled.txt` suffit à l'activer).

### Mises à jour

Le bouton **« Mises à jour... »** du launcheur cherche une nouvelle version du launcheur et de vos mods **uniquement quand vous le demandez** (ou au démarrage si vous cochez la case prévue). Avant la moindre connexion, il affiche l'adresse contactée ; il ne télécharge qu'un petit fichier de description. Vous choisissez ensuite ce que vous mettez à jour : le fichier est **vérifié par son empreinte SHA-256**, le détail s'affiche, puis vous confirmez. Pour le launcheur lui-même : il se ferme, remplace ses fichiers, se rouvre, et **garde la version précédente** (`OutOfMods_previous`) pour un retour arrière ; vos paquets ajoutés et vos réglages ne sont pas touchés. Un mod mis à jour est sauvegardé comme pour une réinstallation.

### Vie privée et sécurité du launcheur

* **Lecture seule par défaut** : détecter le jeu et les mods n'écrit rien.
* Chaque installation / désinstallation / activation affiche **le détail exact** (fichiers, dossier cible, sauvegardes) et attend votre « Confirmer ». *Annuler* est le bouton par défaut.
* **Aucun accès Internet**, sauf téléchargement d'UE4SS **que vous demandez** : HTTPS depuis github.com uniquement, empreinte SHA-256 vérifiée avant toute installation.
* Aucun programme n'est installé hormis `dwmapi.dll` et `UE4SS.dll` (UE4SS lui-même) ; les paquets de mods contiennent uniquement du texte (Lua, JSON…).
* Vos fichiers existants sont **sauvegardés** (`OutOfMods_backups`) ; vos réglages UE4SS et vos mods sont conservés ; la désinstallation ne retire que ce que le launcheur a installé et **restaure** ce qu'il avait remplacé. Vos données (hauteurs, réglages) ne sont jamais touchées.
* Votre antivirus peut signaler `dwmapi.dll` : c'est le chargeur d'UE4SS (faux positif connu).

#### Vérifier votre téléchargement et faux positifs possibles (v0.1.1)

Empreintes SHA-256 (PowerShell : `Get-FileHash <fichier>`) :

| Fichier | SHA-256 |
|---|---|
| `OutOfMods-0.1.1-win64.zip` | `94ffc020f402d84b9dbea5c7148d19378d2fb2e2b20667cf09b8f62b31ce999e` |
| `PayDirt-0.1.0.zip` | `3fa4b09311e720b29137a5ad2014b9b4ed9ee0f5fa05b6a619c3f28df31dc146` |
| `OutOfMods.exe` (dans le zip) | `f4bf2c1516d024d3cc3d63b9de67140338b2cd45cf82dd01edb9a568b28c956c` |

Le launcheur est écrit en Python et empaqueté avec PyInstaller, **sans signature de code** pour l'instant. Ce type d'exécutable est parfois signalé à tort par des antivirus (détection par comportement : il décompresse du code en mémoire). Analyse VirusTotal de la 0.1.0 (2026-10-04, la 0.1.1 n'a pas encore été analysée) : `OutOfMods.exe` **3 moteurs sur 71** (Arctic Wolf, SecureAge, Skyhigh), aucun des principaux antivirus (Avast, AVG, Avira, BitDefender, ClamAV, CrowdStrike...). Le zip complet : **1 moteur sur 67** (Zillya, `Trojan.Blank.Script.2228`, détection générique de script Python empaqueté). Le code est entièrement ouvert dans ce dépôt, vous pouvez le lire, lancer les tests et reconstruire l'exe vous-même (`python tools/build_launcher.py`). En cas de doute, comparez l'empreinte ci-dessus ; si votre antivirus bloque le fichier, vous pouvez le signaler comme faux positif à son éditeur.

### UE4SS : version recommandée

Le launcheur propose le build **`3.0.1 — e3ba1016`** d'[UE4SS-RE](https://github.com/UE4SS-RE/RE-UE4SS) (licence MIT), **validé avec Out of Ore**. ⚠ La release « stable » v3.0.1 charge les mods mais **fait échouer les hooks de terrassement** : à éviter. Les réglages recommandés (UE 4.27, console graphique désactivée) sont appliqués à un fichier de réglages *nouvellement créé* uniquement.

### Signaler un problème

Précisez : version du jeu (le menu l'affiche, ex. `v0.36.5550`), mod / launcheur et leur version, ce que vous faisiez, et joignez `UE4SS.log` (dans `…/Win64/ue4ss/`) et, pour la lame, `%APPDATA%\OutOfOreFlat2\auto_trace.txt`.
**Tickets :** [GitHub Issues](https://github.com/bibi51310/out-of-mods/issues) · **Discord :** https://discord.gg/CkP5c8cpz4 (salons #support, #bugs, #suggestions).

### Limites connues

* Testé sur **un seul build** du jeu ; une mise à jour peut casser un mod (le launcheur affiche un avertissement si le build diffère).
* Le plancher fonctionne en solo ; le multijoueur n'a pas été testé.
* **Pay Dirt** : testé à la vente **depuis l'inventaire** et aux **magasins de ville** ; le multijoueur n'a pas été testé. La liste des objets doublés correspond au build 25627989 : un minerai ajouté plus tard ne sera doublé qu'après mise à jour du mod.
* Panneau vérifié en 1080p et 720p (formule d'adaptation valable pour les autres résolutions).

---

## English

### What's in this project

| Item | What it does |
|---|---|
| **FlatGround 2** (mod) | A **digging floor**: nothing can be dug below your chosen Z height → perfectly flat ground. In-game panel, named heights and an **automatic bulldozer blade** that holds the floor. |
| **Pay Dirt** (mod) | **Sales x2**: the sale price of **resources and ores** is doubled, shown and received. Saves untouched. |
| **Out of Mods** (the launcher, Windows app) | Detects the game, installs / uninstalls / enables mods and, **only if you ask**, installs UE4SS. **Nothing happens without your confirmation.** |
| **OutOfOreAPI** (for modders) | Lua library: world, vehicles, economy, in-game windows… see `api/README.md`. **Publishing your own mod: [MODDING.md](MODDING.md).** |

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
* **Sloped floor and stakes** (**Slope** tab): the floor can be an inclined plane instead of a flat one.
  * `Start here` sets the plane's start at the real ground level, at the blade (or character) position; `Stake A` / `Stake B` define the slope by aiming at two ground points (2 m minimum, 40 % maximum); or set the percentage by hand (`±0.5 / ±1`, `0 %` = flat). The plane starts at the start point and runs forward (or stops at B).
  * **3D stakes** every 5 m with a glowing line: **white** = fill, **red** = dig, **green** = ok (±10 cm), with the target height as 3D text. `Stakes: ON/off` shows or hides them.
  * Digging is limited by the plane and the **automatic blade follows it** as you drive (the offset between the GPS point and where the blade actually cuts is taken into account).
  * Commands: `flat2_slope <percent>`, `flat2_start`, `flat2_stakes`, `flat2_stake_a`, `flat2_stake_b`.
* **Bilingual FR / EN panel**: game language detected, `FR / EN` button in the panel, `flat2_lang fr|en|auto` command.

### Pay Dirt features

* **Sale prices x2** (adjustable factor) for **resources and ores**: ores, rock, dirt, asphalt, fluids, refined metals (iron, copper, gold, ruby, platinum, silicon, lithium, steel…). The **price shown** in the store and the **money received** are identical, whether you sell from the inventory or at the store.
* **Purchases and quests are unchanged.** Vehicles, buildings, parts, equipment and materials you can buy (wood, rubber, plastics, electronics…) are **not** doubled: everything resells at about 70 % of its value, so doubling would exceed the purchase price (buy / resell loop).
* **Saves untouched**: the mod loads on an existing game; removing it restores the normal economy. Nothing is written to the game rules.
* Console (`~` or F10): `boost <factor>` (`boost 1` = normal, `boost 3` = x3), `boost_status`, `boost_scope ore|all` (⚠ `all` also doubles vehicles and buildings: buy / resell loop risk), `boost_mode price|bonus` (fallback), `boost_log 0|1` (diagnostics).
* The name comes from "pay dirt", the game's ore-bearing dirt you wash.

### Installation

**With the launcher (recommended)** — run `OutOfMods.exe` (French or English interface depending on Windows; selector at the top right):

1. It detects your Steam game. If UE4SS is missing it offers **"Install UE4SS (download)…"**: you see where it comes from, the exact file list, and you confirm.
2. Select **FlatGround 2** under "Available packages" → **Install…** → read the details → confirm.
3. Start the game. **F7** opens the panel.

For **Pay Dirt**: download `PayDirt-0.1.0.zip`, then **"Open a package (.zip)…"** → read the details → confirm.

**Manually**: install UE4SS (see below), copy the `FlatGround2` (or `PayDirt`) folder from the zip into `…/OutOfOre/Binaries/Win64/ue4ss/Mods/` (the `enabled.txt` file is enough to enable it).

### Updates

The launcher's **"Updates..."** button looks for a new version of the launcher and your mods **only when you ask** (or at startup if you tick the option). It shows the address it will contact before any connection and only downloads a small description file. You then pick what to update: the file is **verified against its SHA-256 fingerprint**, the details are shown, then you confirm. For the launcher itself: it closes, replaces its files, reopens, and **keeps the previous version** (`OutOfMods_previous`) for rollback; your added packages and settings are untouched. An updated mod is backed up like a reinstall.

### Launcher privacy & safety

* **Read-only by default**: detecting the game and mods writes nothing.
* Every install / uninstall / enable shows **the exact details** (files, target folder, backups) and waits for your "Confirm". *Cancel* is the default button.
* **No network access**, except the UE4SS download **you request**: HTTPS from github.com only, SHA-256 verified before anything is installed.
* No program is installed other than `dwmapi.dll` and `UE4SS.dll` (UE4SS itself); mod packages contain text only (Lua, JSON…).
* Existing files are **backed up** (`OutOfMods_backups`); your UE4SS settings and mods are kept; uninstalling removes only what the launcher installed and **restores** what it replaced. Your data (heights, settings) is never touched.
* Your antivirus may flag `dwmapi.dll`: that is the UE4SS loader (known false positive).

#### Verifying your download & possible false positives (v0.1.1)

SHA-256 fingerprints (PowerShell: `Get-FileHash <file>`):

| File | SHA-256 |
|---|---|
| `OutOfMods-0.1.1-win64.zip` | `94ffc020f402d84b9dbea5c7148d19378d2fb2e2b20667cf09b8f62b31ce999e` |
| `PayDirt-0.1.0.zip` | `3fa4b09311e720b29137a5ad2014b9b4ed9ee0f5fa05b6a619c3f28df31dc146` |
| `OutOfMods.exe` (inside the zip) | `f4bf2c1516d024d3cc3d63b9de67140338b2cd45cf82dd01edb9a568b28c956c` |

The launcher is written in Python and packaged with PyInstaller, **not code-signed** for now. This kind of executable is sometimes wrongly flagged by antivirus products (behavioural detection: it unpacks code in memory). VirusTotal scan of 2026-10-04: `OutOfMods.exe` **3 engines out of 71** (Arctic Wolf, SecureAge, Skyhigh), none of the major antivirus products (Avast, AVG, Avira, BitDefender, ClamAV, CrowdStrike...). The full zip: **1 engine out of 67** (Zillya, `Trojan.Blank.Script.2228`, a generic detection of packaged Python scripts). The code is fully open in this repository: you can read it, run the tests and rebuild the exe yourself (`python tools/build_launcher.py`). If in doubt, compare the fingerprint above; if your antivirus blocks the file, you can report it to its vendor as a false positive.

### UE4SS: recommended version

The launcher offers **`3.0.1 — e3ba1016`** from [UE4SS-RE](https://github.com/UE4SS-RE/RE-UE4SS) (MIT), **validated with Out of Ore**. ⚠ The "stable" v3.0.1 release loads mods but **breaks the digging hooks**: avoid it. Recommended settings (UE 4.27, GUI console off) are applied to a *newly created* settings file only.

### Reporting a problem

Please include: game version (shown in the menu, e.g. `v0.36.5550`), mod / launcher and their version, what you were doing, and attach `UE4SS.log` (in `…/Win64/ue4ss/`) and, for the blade, `%APPDATA%\OutOfOreFlat2\auto_trace.txt`.
**Issues:** [GitHub Issues](https://github.com/bibi51310/out-of-mods/issues) · **Discord:** https://discord.gg/CkP5c8cpz4 (#support, #bugs, #suggestions channels).

### Known limitations

* Tested on **a single game build**; an update may break a mod (the launcher warns when the build differs).
* The floor works in single player; multiplayer has not been tested.
* **Pay Dirt**: tested when selling **from the inventory** and at **town stores**; multiplayer has not been tested. The list of doubled items matches build 25627989: an ore added later is only doubled after a mod update.
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
