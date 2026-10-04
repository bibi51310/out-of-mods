# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Prepare l'arborescence du depot PUBLIC dans publish/repo/ (copie propre, sans l'historique ni les donnees du jeu) et la verifie.

Usage : python tools/prepare_publication.py

Principe (voir publish/PUBLICATION_SCOPE.md) : on copie une LISTE BLANCHE de fichiers ; rien d'autre ne part. Puis un controle automatique refuse
le resultat s'il contient un chemin interdit (donnees extraites du jeu, vendor, sauvegardes...), un fichier trop gros, ou une trace personnelle
(nom de compte Windows, e-mail, chemins locaux). Le depot public est un NOUVEAU depot git : l'historique de ce dossier de travail n'est jamais publie.
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "publish", "repo")

# (source relative a la racine du projet, destination relative au depot) -- fichiers ou dossiers
INCLUDE = [
    ("LICENSE", "LICENSE"), ("THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.md"),
    ("publish/README.md", "README.md"), ("publish/CHANGELOG.md", "CHANGELOG.md"),
    ("publish/CONTRIBUTING.md", "CONTRIBUTING.md"), ("publish/MODDING.md", "MODDING.md"), ("publish/github", ".github"),
    ("mods/FlatGround2", "mods/FlatGround2"),
    ("api/OutOfOreAPI.lua", "api/OutOfOreAPI.lua"), ("api/README.md", "api/README.md"),
    ("launcher", "launcher"),
    ("tools/build_package.py", "tools/build_package.py"), ("tools/build_launcher.py", "tools/build_launcher.py"),
    ("tools/make_update_manifest.py", "tools/make_update_manifest.py"), ("tools/check_lua_strings.py", "tools/check_lua_strings.py"),
    ("tools/prepare_publication.py", "tools/prepare_publication.py"),
    ("tests/test_launcher_core.py", "tests/test_launcher_core.py"), ("tests/test_i18n.py", "tests/test_i18n.py"), ("tests/test_launcher_ui.py", "tests/test_launcher_ui.py"),
    ("tests/test_updates.py", "tests/test_updates.py"), ("tests/test_launcher_updates_ui.py", "tests/test_launcher_updates_ui.py"),
    ("examples", "examples"),
]
SKIP_NAMES = {"__pycache__", ".pyc"}
# Reecritures appliquees a la COPIE (jamais aux sources) : references a des fichiers non publies
REWRITES = {
    "api/README.md": [("`data/function_catalog.json`", "le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue)")],
}
FORBIDDEN_PREFIXES = ("data/", "vendor/", "backups/", "notes/", "calcul/", "ui/", "dist/", "build_tmp/", "tools/pak_export", "mods/DigSpy", "mods/AutoLevelSpy",
                      "mods/PanelTest", "mods/EventSpy", "mods/DataTableDump", "mods/EconDump", "mods/FlatGround/", "mods/OutOfOreAPITest")
FORBIDDEN_NAMES = ("CLAUDE.md", "UE4SS_ObjectDump", "function_catalog", "game_tables", "production.json", "planner_data", "readable_properties", "tables_extra", "tables_beta")
PUBLIC_ACCOUNT = "bibi" + "51310"      # compte GitHub publie volontairement dans les adresses du depot (releases, mises a jour)
# motifs construits par morceaux pour que ce fichier ne se declenche pas lui-meme
_BITS = ["ju" + "lie", "deman" + "geot", "bibi" + "51310", "C:" + chr(92) * 2 + "Users", "AppData" + chr(92) * 2 + "Local" + chr(92) * 2 + "Temp"]
PERSONAL = re.compile("|".join(re.escape(b) if "Users" in b or "AppData" in b else b for b in _BITS), re.I)
MAX_BYTES = 1_500_000


TEXT_EXT = (".txt", ".md", ".py", ".pyw", ".lua", ".json", ".yml", ".yaml", ".cmd", ".ini", ".terms")


def copy_file(s, d):
    """Copie un fichier ; les fichiers texte sont normalises en fins de ligne LF (depot public coherent, pas de bruit CRLF)."""
    os.makedirs(os.path.dirname(d), exist_ok=True)
    if s.lower().endswith(TEXT_EXT) or os.path.basename(s) in ("LICENSE",):
        data = open(s, "rb").read().replace(b"\r\n", b"\n")
        with open(d, "wb") as f:
            f.write(data)
    else:
        shutil.copy2(s, d)


def copy_item(src, dst):
    if os.path.isdir(src):
        for base, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if d not in SKIP_NAMES]
            for f in files:
                if f.endswith(".pyc") or f.endswith(".log"):
                    continue
                s = os.path.join(base, f)
                copy_file(s, os.path.join(dst, os.path.relpath(s, src)))
    else:
        copy_file(src, dst)


def main():
    # Nettoie le contenu SAUF .git (le dossier peut etre un clone du depot public : son historique ne doit jamais etre touche)
    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):
        if name == ".git":
            continue
        path = os.path.join(OUT, name)
        if os.path.isdir(path):
            shutil.rmtree(path, onerror=lambda f, p, e: (os.chmod(p, 0o700), f(p)))
        else:
            os.remove(path)
    missing = []
    for src, dst in INCLUDE:
        s = os.path.join(ROOT, src.replace("/", os.sep))
        if not os.path.exists(s):
            missing.append(src)
            continue
        copy_item(s, os.path.join(OUT, dst.replace("/", os.sep)))
    for rel, pairs in REWRITES.items():
        p = os.path.join(OUT, rel.replace("/", os.sep))
        if os.path.isfile(p):
            text = open(p, encoding="utf-8").read()
            for a, b in pairs:
                text = text.replace(a, b)
            open(p, "w", encoding="utf-8", newline="\n").write(text)
    with open(os.path.join(OUT, ".gitattributes"), "w", encoding="utf-8", newline="\n") as f:
        f.write("* text=auto eol=lf\n*.zip binary\n*.exe binary\n")
    with open(os.path.join(OUT, ".gitignore"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# artefacts de construction\ndist/\nbuild_tmp/\n__pycache__/\n*.pyc\n*.log\n")
    problems = []
    n_files = 0
    for base, _dirs, files in os.walk(OUT):
        for f in files:
            n_files += 1
            p = os.path.join(base, f)
            rel = os.path.relpath(p, OUT).replace(os.sep, "/")
            if rel.startswith(FORBIDDEN_PREFIXES) or any(k in rel for k in FORBIDDEN_NAMES):
                problems.append("chemin interdit : " + rel)
            if os.path.getsize(p) > MAX_BYTES:
                problems.append("fichier trop gros (%d Ko) : %s" % (os.path.getsize(p) // 1024, rel))
            if f.lower().endswith((".txt", ".md", ".py", ".pyw", ".lua", ".json", ".yml", ".yaml", ".cmd", ".ini")):
                try:
                    text = open(p, encoding="utf-8").read()
                except UnicodeDecodeError:
                    problems.append("fichier texte illisible en UTF-8 : " + rel)
                    continue
                for i, line in enumerate(text.split("\n"), 1):
                    if PERSONAL.search(line.replace("github.com/" + PUBLIC_ACCOUNT + "/", "github.com/ACCOUNT/")):
                        problems.append("trace personnelle %s:%d : %s" % (rel, i, line.strip()[:90]))
    for m in missing:
        problems.append("fichier a publier introuvable : " + m)
    print("%d fichier(s) copies dans %s" % (n_files, OUT))
    if problems:
        print("\nPROBLEMES (%d) -- a corriger avant toute publication :" % len(problems))
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    print("controle : aucun chemin interdit, aucun fichier trop gros, aucune trace personnelle.")


if __name__ == "__main__":
    main()
