"""Verifie que tout texte passe par tr() a une traduction anglaise, avec les memes marques de mise en forme (%s, %d...)."""
import ast
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "launcher"))
import i18n  # noqa: E402
from i18n_en import EN  # noqa: E402

fails = 0


def check(name, cond, detail=""):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name + (" : " + detail if (detail and not cond) else ""))
    if not cond:
        fails += 1


used = set()
for fn in ("core.py", "app.pyw"):
    tree = ast.parse(open(os.path.join(ROOT, "launcher", fn), encoding="utf-8").read())
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "tr" and n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str):
            used.add(n.args[0].value)
check("%d textes passent par tr()" % len(used), len(used) > 100)
missing = sorted(u for u in used if u not in EN)
check("tous les textes ont une traduction anglaise", not missing, "; ".join(missing[:5]))
pl = lambda s: re.findall(r"%[-0-9.]*[sdrf]", s)
bad = [k for k, v in EN.items() if pl(k) != pl(v)]
check("marques de mise en forme identiques (FR / EN, meme ordre)", not bad, "; ".join(bad[:3]))
unused = sorted(k for k in EN if k not in used)
check("aucune traduction orpheline", not unused, "; ".join(unused[:5]))
SAME_OK = {"Mod", "ok", "Zip", "Version"}
same = [k for k, v in EN.items() if k == v and k not in SAME_OK]
check("aucune traduction identique au francais (hors mots communs)", not same, "; ".join(same[:5]))
frenchish = [v for v in EN.values() if re.search(r"\b(le|la|les|des|du|une|est|dans|vous|votre|fichier|installe|jeu)\b", v.lower())]
check("aucun mot francais courant dans les traductions", not frenchish, "; ".join(frenchish[:3]))

i18n.set_language("en")
check("tr() anglais", i18n.tr("Lancer le jeu") == "Launch the game")
i18n.set_language("fr")
check("tr() francais", i18n.tr("Lancer le jeu") == "Lancer le jeu")
check("texte inconnu : inchange", i18n.tr("texte inconnu xyz") == "texte inconnu xyz")
print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
