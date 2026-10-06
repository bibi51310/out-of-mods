# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Construit le launcheur en programme Windows autonome (PyInstaller, mode dossier -- moins souvent signale par les antivirus qu'un .exe unique).

Usage : python tools/build_launcher.py
Prerequis (poste de DEVELOPPEMENT seulement, pas pour les joueurs) : pip install pyinstaller

Sortie : dist/OutOfMods/            OutOfMods.exe + packages/ (paquets de mods .zip) + LISEZMOI.txt
         dist/OutOfMods-<version>-win64.zip
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import build_package  # noqa: E402

NAME = "OutOfMods"


def app_version():
    with open(os.path.join(ROOT, "launcher", "app.pyw"), "r", encoding="utf-8") as f:
        m = re.search(r'APP_VERSION\s*=\s*"([^"]+)"', f.read())
    return m.group(1) if m else "0.0.0"


def copy_licenses(target):
    """Licence du projet (MIT) + mentions + textes de licence des composants embarques (Python, Tk, sv-ttk, PyInstaller)."""
    import glob
    import importlib.metadata as md
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(os.path.join(ROOT, name), os.path.join(target, name))
    lic = os.path.join(target, "licenses")
    os.makedirs(lic, exist_ok=True)
    sources = [("Python-LICENSE.txt", os.path.join(sys.base_prefix, "LICENSE.txt")),
               ("Tk-license.terms", (glob.glob(os.path.join(sys.base_prefix, "tcl", "tk*", "license.terms")) or [None])[0])]
    for dist_name, out_name, member in (("sv-ttk", "sv-ttk-LICENSE.txt", "LICENSE"), ("pyinstaller", "PyInstaller-COPYING.txt", "COPYING.txt")):
        d = md.distribution(dist_name)
        found = [f for f in d.files if str(f).replace("\\", "/").endswith("licenses/" + member)]
        sources.append((out_name, str(d.locate_file(found[0])) if found else None))
    for out_name, src in sources:
        if not src or not os.path.isfile(src):
            raise SystemExit("texte de licence introuvable pour %s : la distribution ne doit pas partir sans lui" % out_name)
        shutil.copy2(src, os.path.join(lic, out_name))


def main():
    version = app_version()
    # paquets de mods embarques (a jour)
    _out, mod_zip = build_package.build("FlatGround2")
    work = os.path.join(ROOT, "build_tmp")
    out = os.path.join(ROOT, "dist")
    for d in (work, os.path.join(out, NAME)):
        shutil.rmtree(d, ignore_errors=True)
    cmd = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--windowed", "--name", NAME,
           "--collect-data", "sv_ttk", "--icon", os.path.join(ROOT, "launcher", "assets", "icon.ico"),
           "--add-data", os.path.join(ROOT, "launcher", "assets", "icon.ico") + os.pathsep + "assets",
           "--add-data", os.path.join(ROOT, "launcher", "assets", "logo_256.png") + os.pathsep + "assets",
           "--add-data", os.path.join(ROOT, "launcher", "assets", "banner_header.png") + os.pathsep + "assets", "--distpath", out, "--workpath", work, "--specpath", work, "--paths", os.path.join(ROOT, "launcher"),
           os.path.join(ROOT, "launcher", "app.pyw")]
    print(" ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)
    target = os.path.join(out, NAME)
    os.makedirs(os.path.join(target, "packages"), exist_ok=True)
    shutil.copy2(mod_zip, os.path.join(target, "packages", os.path.basename(mod_zip)))
    with open(os.path.join(target, "LISEZMOI.txt"), "w", encoding="utf-8") as f:
        f.write(
            "Out of Mods %s\n\n"
            "Lancez OutOfMods.exe. Le launcheur detecte le jeu (Steam), UE4SS et les mods installes.\n"
            "Rien n'est installe, modifie ni supprime sans que vous ayez lu le detail exact et confirme.\n"
            "Aucun acces Internet, sauf si vous demandez le telechargement d'UE4SS (fenetre de confirmation avant).\n"
            "Les paquets de mods (.zip) places dans le dossier packages/ apparaissent dans la liste.\n"
            "Journal : %%APPDATA%%/OutOfMods/launcher.log\n" % version)
    copy_licenses(target)
    zip_path = os.path.join(out, "%s-%s-win64.zip" % (NAME, version))
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _dirs, files in os.walk(target):
            for name in files:
                full = os.path.join(base, name)
                z.write(full, os.path.join(NAME, os.path.relpath(full, target)))
    shutil.rmtree(work, ignore_errors=True)
    size = sum(os.path.getsize(os.path.join(b, f)) for b, _d, fs in os.walk(target) for f in fs)
    print("\nlauncheur %s : %s (%d Mo) + %s (%d Mo)" % (version, target, size // 2**20, zip_path, os.path.getsize(zip_path) // 2**20))


if __name__ == "__main__":
    main()
