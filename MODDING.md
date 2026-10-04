# Publishing a mod compatible with Out of Mods / Publier un mod compatible

[Français](#français) · [English](#english)

---

## Français

Ce guide explique comment empaqueter un mod Lua (UE4SS) pour *Out of Ore* afin que les joueurs puissent l'installer avec le launcheur **Out of Mods**, et comment le publier (Nexus Mods, GitHub, Discord...).

### 1. Ce que le launcheur accepte

Un mod = **un fichier `.zip`** contenant **un seul dossier racine**, nommé comme l'`id` du mod :

```
MonMod.zip
└── MonMod/
    ├── mod.json            (obligatoire)
    ├── Scripts/
    │   └── main.lua        (obligatoire)
    ├── README.txt          (facultatif)
    └── ...                 (autres .lua, .json, .txt, .md, .png)
```

Le launcheur **refuse** le paquet (avec un message clair) si :
- il y a plusieurs dossiers à la racine, ou des fichiers à la racine ;
- `mod.json` ou `Scripts/main.lua` manque, ou si l'`id` de `mod.json` ≠ nom du dossier ;
- il contient un fichier d'un autre type que `.lua .json .txt .md .png` (**jamais de `.dll` ni `.exe`**, c'est voulu : c'est ce qui permet au joueur d'installer sans risque d'exécutable) ;
- il dépasse 20 Mo, ou contient un chemin dangereux (`..`, chemin absolu).

Le nom du dossier/`id` : lettres, chiffres, `_`, `.`, `-`, 64 caractères max.

### 2. `mod.json`

Minimum utilisé par le launcheur et par `tools/build_package.py` :

```json
{
  "id": "MonMod",
  "name": "Mon Mod",
  "version": "1.0.0",
  "description": "Ce que fait le mod (une phrase).",
  "author": "Votre pseudo",
  "license": "MIT",
  "game": {
    "name": "Out of Ore",
    "testedBuildId": "25627989",
    "testedGameVersion": "0.36.5550",
    "branch": "beta"
  }
}
```

- `id`, `name`, `version` : affichés dans la liste. `version` sert à détecter une version plus récente.
- `game.testedBuildId` / `branch` : le launcheur **avertit** (sans bloquer) si le build Steam ou la branche du joueur diffère. Renseignez le build avec lequel **vous avez réellement testé** (visible dans `steamapps/appmanifest_2009350.acf`, champ `buildid`).
- Facultatif mais utile : `description_en`, `controls` (touches), `console` (commandes), `dataDirs` (dossiers que le mod crée dans `%APPDATA%`). Voir `mods/FlatGround2/mod.json` pour un exemple complet.

### 3. Écrire le mod

- Script : `Scripts/main.lua`. UE4SS le charge au démarrage du jeu (**pas de rechargement à chaud** : redémarrer le jeu après chaque modification).
- Pour utiliser l'API du projet : `local API = require("OutOfOreAPI")` (voir [`api/README.md`](api/README.md), un exemple minimal dans [`examples/FuelAlert`](examples/FuelAlert)).
- Règles de prudence apprises à la dure (détails dans `api/README.md`, section « Pièges ») :
  - préférer **lire des propriétés** plutôt qu'appeler des fonctions ;
  - ne pas utiliser `LoopAsync` / `ExecuteInGameThread` / `ExecuteWithDelay` : `API.SafeTick.Register(fn, hz)` fait la boucle périodique sans risque ;
  - ne jamais passer une table Lua à un paramètre de type `Name` (le jeu peut se figer) ;
  - envelopper vos callbacks dans `pcall` et journaliser les erreurs.
- Tester dans une vraie partie (de préférence une **partie de test**), jeu redémarré, et lire `UE4SS/UE4SS.log`.

### 4. Construire le paquet

**Option A : avec l'API embarquée (recommandé).** Le joueur n'a rien d'autre à installer.

1. Cloner ce dépôt, placer votre mod dans `mods/MonMod/` (`Scripts/main.lua` + `mod.json`).
2. `python tools/build_package.py MonMod`
3. Résultat : `dist/MonMod-<version>.zip` (API embarquée dans `main.lua`, `enabled.txt`, `README.txt` générés). Le script refuse un mod qui ne fait pas `require("OutOfOreAPI")`.

**Option B : à la main** (mod sans l'API, ou paquet personnalisé) : créez le dossier `MonMod/` comme au §1 et zippez-le **avec le dossier à la racine** (clic droit > Envoyer vers > Dossier compressé, sur le dossier `MonMod`, pas sur son contenu).

**Vérifier avant de publier** : dans Out of Mods, « Ouvrir un paquet (.zip)... » et choisir votre zip : si le launcheur l'accepte et affiche le détail d'installation, il est valide. Installez-le, lancez le jeu, vérifiez le journal.

### 5. Publier

- **Nexus Mods / GitHub / autre** : déposez le `.zip` tel quel. Dans la description, indiquez : *le mod nécessite UE4SS (le launcheur Out of Mods peut l'installer), le build de jeu testé, la branche (stable / bêta), les touches et commandes*.
- Donnez l'**empreinte SHA-256** du zip dans la description (`Get-FileHash MonMod-1.0.0.zip` sous PowerShell) : les joueurs peuvent vérifier leur téléchargement.
- Si le code est ouvert (licence MIT ou autre), dites-le : c'est la meilleure réponse aux inquiétudes de sécurité.
- N'**embarquez aucun fichier du jeu** (tables extraites, assets, dumps) : seulement votre code.
- À chaque mise à jour du jeu, retestez et mettez à jour `game.testedBuildId`.

### 6. Mises à jour pour vos joueurs

Aujourd'hui, la vérification de mises à jour du launcheur ne lit que **son propre** manifeste : un mod tiers se met à jour en **réinstallant le nouveau zip** (« Ouvrir un paquet (.zip)... » ; l'ancienne version est sauvegardée automatiquement). Un joueur peut aussi garder votre zip dans `packages/` à côté de `OutOfMods.exe`. Dites-le dans votre description : « pour mettre à jour, installez le nouveau zip par-dessus ».

### 7. Ce que le launcheur ne fait pas

- Il **n'analyse pas** le code Lua de votre mod : un mod Lua tourne dans le jeu, le joueur vous fait confiance (d'où l'intérêt du code ouvert).
- Il n'y a **pas de catalogue** de mods dans le launcheur.
- Projet communautaire, **sans lien avec les développeurs ni l'éditeur d'Out of Ore**.

---

## English

This guide explains how to package a Lua (UE4SS) mod for *Out of Ore* so players can install it with the **Out of Mods** launcher, and how to publish it (Nexus Mods, GitHub, Discord...).

### 1. What the launcher accepts

A mod = **one `.zip` file** containing **a single root folder**, named after the mod's `id`:

```
MyMod.zip
└── MyMod/
    ├── mod.json            (required)
    ├── Scripts/
    │   └── main.lua        (required)
    ├── README.txt          (optional)
    └── ...                 (other .lua, .json, .txt, .md, .png)
```

The launcher **rejects** the package (with a clear message) if:
- there are several root folders, or loose files at the root;
- `mod.json` or `Scripts/main.lua` is missing, or the `id` in `mod.json` ≠ the folder name;
- it contains any file type other than `.lua .json .txt .md .png` (**never `.dll` or `.exe`**, by design: this is what lets players install without running foreign executables);
- it is larger than 20 MB or has an unsafe path (`..`, absolute path).

Folder name/`id`: letters, digits, `_`, `.`, `-`, 64 characters max.

### 2. `mod.json`

Minimum used by the launcher and `tools/build_package.py`:

```json
{
  "id": "MyMod",
  "name": "My Mod",
  "version": "1.0.0",
  "description": "What the mod does (one sentence).",
  "author": "Your handle",
  "license": "MIT",
  "game": {
    "name": "Out of Ore",
    "testedBuildId": "25627989",
    "testedGameVersion": "0.36.5550",
    "branch": "beta"
  }
}
```

- `id`, `name`, `version`: shown in the list; `version` is used to detect a newer one.
- `game.testedBuildId` / `branch`: the launcher **warns** (without blocking) if the player's Steam build or branch differs. Put the build you **actually tested with** (`buildid` in `steamapps/appmanifest_2009350.acf`).
- Optional but useful: `description_en`, `controls` (keys), `console` (commands), `dataDirs` (folders the mod creates in `%APPDATA%`). See `mods/FlatGround2/mod.json` for a full example.

### 3. Writing the mod

- Script: `Scripts/main.lua`, loaded by UE4SS at game start (**no hot reload**: restart the game after each change).
- To use the project's API: `local API = require("OutOfOreAPI")` (see [`api/README.md`](api/README.md); a minimal example is in [`examples/FuelAlert`](examples/FuelAlert)).
- Safety rules learned the hard way (details in `api/README.md`, "Pitfalls"):
  - prefer **reading properties** over calling functions;
  - do not use `LoopAsync` / `ExecuteInGameThread` / `ExecuteWithDelay`: `API.SafeTick.Register(fn, hz)` provides a safe periodic loop;
  - never pass a Lua table to a `Name`-typed parameter (the game can freeze);
  - wrap your callbacks in `pcall` and log errors.
- Test in a real game (preferably a **test save**), game restarted, and read `UE4SS/UE4SS.log`.

### 4. Building the package

**Option A: with the API embedded (recommended).** Players need nothing else.

1. Clone this repository and put your mod in `mods/MyMod/` (`Scripts/main.lua` + `mod.json`).
2. `python tools/build_package.py MyMod`
3. Result: `dist/MyMod-<version>.zip` (API embedded in `main.lua`; `enabled.txt` and `README.txt` generated). The script refuses a mod that does not `require("OutOfOreAPI")`.

**Option B: by hand** (mod without the API, or custom package): create the `MyMod/` folder as in §1 and zip it **with the folder at the root** (right-click > Send to > Compressed folder on the `MyMod` folder itself, not on its contents).

**Check before publishing**: in Out of Mods, "Open a package (.zip)..." and pick your zip: if the launcher accepts it and shows the install details, it is valid. Install it, start the game, check the log.

### 5. Publishing

- **Nexus Mods / GitHub / elsewhere**: upload the `.zip` as is. In the description state: *the mod requires UE4SS (the Out of Mods launcher can install it), the game build tested, the branch (stable / beta), keys and commands*.
- Give the zip's **SHA-256 fingerprint** in the description (`Get-FileHash MyMod-1.0.0.zip` in PowerShell) so players can verify their download.
- If the code is open (MIT or other), say so: it is the best answer to security concerns.
- **Do not bundle any game file** (extracted tables, assets, dumps): only your own code.
- After each game update, retest and update `game.testedBuildId`.

### 6. Updates for your players

Today the launcher's update check only reads **its own** manifest: a third-party mod is updated by **installing the new zip** ("Open a package (.zip)..."; the previous version is backed up automatically). A player can also keep your zip in `packages/` next to `OutOfMods.exe`. Say it in your description: "to update, install the new zip over the old one".

### 7. What the launcher does not do

- It does **not audit** your Lua code: a Lua mod runs inside the game, players trust you (hence the value of open source).
- There is **no mod catalogue** in the launcher.
- Community project, **not affiliated with the developers or publisher of Out of Ore**.
