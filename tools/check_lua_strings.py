# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Verification rapide des fichiers Lua sans interpreteur : cherche les guillemets orphelins (chaine coupee par un saut
de ligne, cause d'une erreur de syntaxe qui empeche un mod de se charger). Usage : python tools/check_lua_strings.py [fichiers]
Heuristique : ignore les chaines bien formees et les commentaires `--`; ne gere pas les chaines longues [[ ]]."""
import re
import sys

DEFAULT = ["mods/FlatGround2/Scripts/main.lua", "mods/PanelTest/Scripts/main.lua", "api/OutOfOreAPI.lua"]
DQ = re.compile(r'"(?:[^"\\]|\\.)*"')
SQ = re.compile(r"'(?:[^'\\]|\\.)*'")


def check(path):
    bad = 0
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f.read().splitlines(), 1):
            t = SQ.sub("", DQ.sub("", line)).split("--")[0]
            if '"' in t or "'" in t and t.count("'") % 2:
                print("%s:%d: guillemet orphelin ? %s" % (path, n, line.strip()[:90]))
                bad += 1
    return bad


if __name__ == "__main__":
    files = sys.argv[1:] or DEFAULT
    total = sum(check(p) for p in files)
    print("lignes suspectes : %d" % total)
    sys.exit(1 if total else 0)
