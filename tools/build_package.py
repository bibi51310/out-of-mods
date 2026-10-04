# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Construit le paquet autonome d'un mod (dossier a copier dans UE4SS/Mods/ + zip).

Usage : python tools/build_package.py [NomDuMod]        (defaut : FlatGround2)

Le paquet est AUTONOME : l'API (api/OutOfOreAPI.lua) est embarquee dans le main.lua du mod par un `package.preload`, donc `require("OutOfOreAPI")`
fonctionne sans dossier `shared/`. Le dossier produit contient :
    <Mod>/enabled.txt        (UE4SS charge le mod sans toucher a mods.txt)
    <Mod>/mod.json           (metadonnees : version, build du jeu teste, fonctions, commandes)
    <Mod>/README.txt         (installation)
    <Mod>/Scripts/main.lua   (mod + API embarquee, constante globale FG2_VERSION)
Sortie : dist/<Mod>/ et dist/<Mod>-<version>.zip (le zip contient le dossier <Mod>/ a sa racine : a extraire dans UE4SS/Mods/).
"""
import json
import os
import re
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API_PATH = os.path.join(ROOT, "api", "OutOfOreAPI.lua")


def build(mod_name):
    mod_dir = os.path.join(ROOT, "mods", mod_name)
    meta_path = os.path.join(mod_dir, "mod.json")
    main_path = os.path.join(mod_dir, "Scripts", "main.lua")
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    version = meta["version"]
    with open(API_PATH, "r", encoding="utf-8") as f:
        api = f.read()
    with open(main_path, "r", encoding="utf-8") as f:
        main = f.read()
    if 'require("OutOfOreAPI")' not in main:
        raise SystemExit("le mod ne fait pas require(\"OutOfOreAPI\") : rien a embarquer")

    stamp = time.strftime("%Y-%m-%d")
    header = (
        "-- %s v%s -- paquet autonome genere le %s par tools/build_package.py (ne pas editer a la main : editer mods/%s/ et api/).\n"
        "-- Jeu teste : %s (build Steam %s, branche %s).\n"
        "FG2_VERSION = %s\n"
        % (meta["name"], version, stamp, mod_name, meta["game"].get("testedGameVersion", "?"), meta["game"].get("testedBuildId", "?"),
           meta["game"].get("branch", "?"), json.dumps(version))
    )
    # L'API devient le corps d'une fonction `preload` : meme portee de locaux qu'un chunk, `return OutOfOreAPI` final conserve.
    embedded = (
        "-- ===== OutOfOreAPI embarquee (api/OutOfOreAPI.lua) =====\n"
        "package.preload[\"OutOfOreAPI\"] = function(...)\n" + api.rstrip() + "\nend\n"
        "-- ===== fin de l'API embarquee =====\n\n"
    )
    out_dir = os.path.join(ROOT, "dist", mod_name)
    os.makedirs(os.path.join(out_dir, "Scripts"), exist_ok=True)
    with open(os.path.join(out_dir, "Scripts", "main.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(header + embedded + main)
    with open(os.path.join(out_dir, "enabled.txt"), "w", encoding="utf-8") as f:
        f.write("")
    with open(os.path.join(out_dir, "mod.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
    readme = (
        "%s v%s\n%s\n\n"
        "INSTALLATION\n"
        "  1. Installer UE4SS (kit communautaire Out of Ore) si ce n'est pas deja fait.\n"
        "  2. Copier le dossier \"%s\" dans  <Jeu>/OutOfOre/Binaries/Win64/UE4SS/Mods/\n"
        "     (le fichier enabled.txt suffit a l'activer ; sinon ajouter la ligne  %s : 1  dans mods.txt).\n"
        "  3. Lancer le jeu. F7 ouvre le panneau, F8 le ferme.\n\n"
        "Jeu teste : %s (build Steam %s, branche %s). La lame automatique demande le module AutoLevel monte sur le bulldozer.\n"
        % (meta["name"], version, meta.get("description", ""), mod_name, mod_name, meta["game"].get("testedGameVersion", "?"),
           meta["game"].get("testedBuildId", "?"), meta["game"].get("branch", "?"))
    )
    with open(os.path.join(out_dir, "README.txt"), "w", encoding="utf-8") as f:
        f.write(readme)

    zip_path = os.path.join(ROOT, "dist", "%s-%s.zip" % (mod_name, version))
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _dirs, files in os.walk(out_dir):
            for name in files:
                full = os.path.join(base, name)
                z.write(full, os.path.join(mod_name, os.path.relpath(full, out_dir)))
    size = os.path.getsize(os.path.join(out_dir, "Scripts", "main.lua"))
    print("paquet %s v%s : %s (main.lua %d Ko) + %s" % (mod_name, version, out_dir, size // 1024, zip_path))
    return out_dir, zip_path


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "FlatGround2")
