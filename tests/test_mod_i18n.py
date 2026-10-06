# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Controle des traductions de FlatGround2 (mods/FlatGround2/Scripts/main.lua) : chaque texte francais passe par T("...") ou
affecte a Auto.status doit avoir une traduction anglaise, sans traduction orpheline, avec les memes marques de format (%s %d %.1f...)."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, "mods", "FlatGround2", "Scripts", "main.lua"), encoding="utf-8").read()
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name + ("" if cond else " : " + detail))
    if not cond:
        fails += 1


STR = r'"((?:[^"\\]|\\.)*)"'

# table EN = { ... } du fichier
m = re.search(r"local EN = \{(.*?)\n\}\nlocal Lang", SRC, re.S)
check("table EN trouvee", bool(m))
body = m.group(1) if m else ""
pairs = re.findall(r"\[" + STR + r"\]\s*=\s*" + STR, body)
EN = dict(pairs)
check("table EN lisible (%d traductions)" % len(EN), len(EN) > 60)
check("pas de cle en double", len(pairs) == len(EN), "%d paires, %d cles" % (len(pairs), len(EN)))

# textes a traduire : arguments de T(...) et etats de la lame automatique
code = SRC.replace(m.group(0), "") if m else SRC
NL = chr(10)
code = NL.join(l for l in code.split(NL) if not l.lstrip().startswith("--"))      # lignes de commentaire entieres
used = set()
for call in re.finditer(r"\bT\(([^()]*(?:\([^()]*\)[^()]*)*)\)", code):
    used.update(re.findall(STR, call.group(1)))
for line in code.split(NL):
    for part in re.findall(r"Auto\.status = ([^;]*)", line):      # jusqu'au « ; » : « if ... ~= "Dozer" then Auto.status = "..." ; return »
        used.update(re.findall(STR, part))
for s in re.findall(r"AutoStop\(" + STR, code):
    used.add(s)
used.update(re.findall(r'status = "([^"]+)", ctl', code))   # etat initial
m2 = re.search(r"local TAB_NAMES = \{([^}]*)\}", code)           # noms d'onglets traduits dynamiquement (T(TAB_NAMES[i]))
used.update(re.findall(STR, m2.group(1)) if m2 else [])
m3 = re.search(r"local texts = \{(.*?)\}", code, re.S)           # messages de SlopeMessage (T(texts[why]))
used.update(re.findall(r"=\s*" + STR, m3.group(1)) if m3 else [])
check("onglets et messages de pente trouves", bool(m2) and bool(m3))
used.discard("")
check("textes traduisibles trouves (%d)" % len(used), len(used) > 50)

missing = sorted(s for s in used if s not in EN)
check("tout texte a une traduction anglaise", not missing, "; ".join(missing))
orphan = sorted(k for k in EN if k not in used)
check("aucune traduction orpheline", not orphan, "; ".join(orphan))


def marks(s):
    return sorted(re.findall(r"%[-+ #0]*\d*(?:\.\d+)?[sdfgx]", s))


bad = [k for k, v in EN.items() if marks(k) != marks(v)]
check("memes marques de format FR / EN", not bad, "; ".join(bad))
same = [k for k, v in EN.items() if k == v and re.search(r"[a-zA-Z]{3}", k) and k not in ("Plancher : %.1f",)]
print("  info  traductions identiques au francais :", same if same else "aucune")

# le bouton de langue et la commande existent
check("commande flat2_lang presente", 'Register("flat2_lang"' in SRC)
check("bouton de langue present", "LangLabel()" in SRC and "wantRebuild" in SRC)

print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
