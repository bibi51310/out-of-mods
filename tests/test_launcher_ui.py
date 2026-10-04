"""Test de l'interface du launcheur (Tk reel, fenetre masquee, donnees dans un dossier temporaire) : bascule de theme et de langue sans plantage."""
import importlib.util
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ["APPDATA"] = tempfile.mkdtemp(prefix="appdata_")          # reglages et journal ecrits hors du vrai profil
sys.path.insert(0, os.path.join(ROOT, "launcher"))
import tkinter as tk  # noqa: E402

spec = importlib.util.spec_from_file_location("launcher_app", os.path.join(ROOT, "launcher", "app.pyw"))
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)

fails = 0


def check(name, cond):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name)
    if not cond:
        fails += 1


root = tk.Tk()
root.withdraw()
a = app.App(root)
root.update()
check("interface construite", a.tree.winfo_exists() and a.log_box.winfo_exists())
a.log("test journal")
for i in range(4):
    before = a.theme
    a.toggle_theme()
    root.update()
    check("bascule de theme %d : %s -> %s, widgets recrees" % (i + 1, before, a.theme), a.theme != before and a.tree.winfo_exists() and a.btn_launch.winfo_exists())
check("journal conserve apres reconstruction", "test journal" in a.log_box.get("1.0", "end"))
a.lang_box.set("English")
a.change_language()
root.update()
check("langue anglaise : bouton traduit", "Launch" in a.btn_launch.cget("text"))
a.lang_box.set("Français")
a.change_language()
root.update()
check("retour au francais", "Lancer" in a.btn_launch.cget("text"))
report = a.diagnostic_report()
check("rapport de diagnostic complet", "diagnostic report" in report and "Mods:" in report and "Last log lines" in report)
a.clear_log_view()
check("effacer l'affichage", a.log_box.get("1.0", "end").strip() == "")
root.destroy()
print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
