# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Genere `dist/updates.json` (manifeste de mises a jour lu par le launcheur) a partir des archives deja construites dans dist/.

Usage : python tools/make_update_manifest.py --base-url https://github.com/<compte>/<depot>/releases/download/v0.1.0
        (base-url = dossier ou seront telecharges les .zip ; chaque archive est referencee par base-url + "/" + nom du fichier)

Prerequis : `python tools/build_launcher.py` (cree le zip du launcheur ET celui du mod) ; pour chaque mod ayant un mods/<Mod>/mod.json, le zip
`dist/<Mod>-<version>.zip` (tools/build_package.py). Notes de version facultatives : publish/release_notes/<id>-<version>.fr.md et .en.md.

Publication : deposer dans la meme release GitHub les .zip ET updates.json. L'adresse de updates.json (lien « latest/download/updates.json »)
se renseigne dans launcher/core.py (UPDATE_MANIFEST_URL) au moment de choisir le depot.
"""
import argparse
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def read_notes(ident, version):
    notes = {}
    for lang in ("fr", "en"):
        p = os.path.join(ROOT, "publish", "release_notes", "%s-%s.%s.md" % (ident, version, lang))
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8") as f:
                notes[lang] = f.read().strip()
    return notes


def entry(path, base_url, version, **extra):
    e = {"version": version, "url": base_url.rstrip("/") + "/" + os.path.basename(path), "sha256": sha256(path), "size": os.path.getsize(path)}
    e.update(extra)
    return e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--out", default=os.path.join(DIST, "updates.json"))
    args = ap.parse_args()
    if not args.base_url.startswith("https://github.com/"):
        sys.exit("base-url doit etre une adresse https://github.com/... (le launcheur refuse les autres hotes)")

    with open(os.path.join(ROOT, "launcher", "app.pyw"), "r", encoding="utf-8") as f:
        version = re.search(r'APP_VERSION\s*=\s*"([^"]+)"', f.read()).group(1)
    manifest = {"schema": 1}
    lz = os.path.join(DIST, "OutOfMods-%s-win64.zip" % version)
    if not os.path.isfile(lz):
        sys.exit("archive du launcheur absente : %s (lancer tools/build_launcher.py)" % lz)
    manifest["launcher"] = entry(lz, args.base_url, version, notes=read_notes("OutOfMods", version))
    manifest["mods"] = []
    mods_root = os.path.join(ROOT, "mods")
    for name in sorted(os.listdir(mods_root)):
        mj = os.path.join(mods_root, name, "mod.json")
        if not os.path.isfile(mj):
            continue
        with open(mj, "r", encoding="utf-8") as f:
            meta = json.load(f)
        zp = os.path.join(DIST, "%s-%s.zip" % (meta["id"], meta["version"]))
        if not os.path.isfile(zp):
            sys.exit("archive du mod absente : %s (lancer tools/build_package.py %s)" % (zp, name))
        manifest["mods"].append(entry(zp, args.base_url, meta["version"], id=meta["id"], name=meta.get("name", meta["id"]), notes=read_notes(meta["id"], meta["version"])))
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("manifeste ecrit : %s (launcheur %s, %d mod(s))" % (args.out, version, len(manifest["mods"])))


if __name__ == "__main__":
    main()
