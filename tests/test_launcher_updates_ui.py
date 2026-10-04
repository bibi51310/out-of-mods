"""Test de la partie interface des mises a jour : serveur HTTP local, dialogues confirmes automatiquement, mise a jour d'un mod et du launcheur
(dossier temporaire ; le script de remplacement est execute pour de bon, le programme factice remplace l'exe)."""
import hashlib
import http.server
import importlib.util
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.mkdtemp(prefix="oolauncher_updui_")
os.environ["APPDATA"] = os.path.join(TMP, "appdata")
os.environ["TEMP"] = os.path.join(TMP, "temp")
os.makedirs(os.environ["TEMP"])
sys.path.insert(0, os.path.join(ROOT, "launcher"))
import tkinter as tk  # noqa: E402

spec = importlib.util.spec_from_file_location("launcher_app", os.path.join(ROOT, "launcher", "app.pyw"))
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)
core = app.core
fails = 0


def check(name, cond):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name)
    if not cond:
        fails += 1


srv = os.path.join(TMP, "srv")
os.makedirs(srv)


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=srv, **k)

    def log_message(self, *a):
        pass


httpd = socketserver.TCPServer(("127.0.0.1", 0), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % httpd.server_address[1]
os.environ[core.ALLOW_ENV] = "127.0.0.1"
os.environ["OOLAUNCHER_UPDATE_URL"] = BASE + "/updates.json"


def zipit(path, entries):
    with zipfile.ZipFile(path, "w") as z:
        for n, c in entries.items():
            z.writestr(n, c)
    return path


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


try:
    whoami = os.path.join(os.environ.get("SystemRoot", "C:/Windows"), "System32", "whoami.exe")
    lz = zipit(os.path.join(srv, "L.zip"), {"OutOfMods/OutOfMods.exe": open(whoami, "rb").read(), "OutOfMods/_internal/v.txt": "NEW"})
    mz = zipit(os.path.join(srv, "M.zip"), {"TestMod/mod.json": json.dumps({"id": "TestMod", "version": "2.0.0"}), "TestMod/Scripts/main.lua": "-- v2"})
    json.dump({"schema": 1, "launcher": {"version": "9.9.9", "url": BASE + "/L.zip", "sha256": sha(lz), "size": os.path.getsize(lz), "notes": {"fr": "n"}},
               "mods": [{"id": "TestMod", "version": "2.0.0", "url": BASE + "/M.zip", "sha256": sha(mz), "size": os.path.getsize(mz)}]},
              open(os.path.join(srv, "updates.json"), "w"))

    # faux jeu avec UE4SS et un mod en version 1.0.0
    game = os.path.join(TMP, "game")
    mods_dir = os.path.join(game, core.WIN64, "UE4SS", "Mods")
    os.makedirs(os.path.join(mods_dir, "TestMod", "Scripts"))
    open(os.path.join(game, core.GAME_EXE), "w").close() if os.makedirs(os.path.dirname(os.path.join(game, core.GAME_EXE)), exist_ok=True) is None else None
    open(os.path.join(game, core.WIN64, "dwmapi.dll"), "w").close()
    open(os.path.join(mods_dir, "TestMod", "Scripts", "main.lua"), "w").write("-- v1")
    json.dump({"id": "TestMod", "version": "1.0.0", "name": "Test"}, open(os.path.join(mods_dir, "TestMod", "mod.json"), "w"))
    sys.argv = ["app.pyw", "--game-dir", game]

    # dialogues confirmes automatiquement
    class Auto:
        def __init__(self, *a, **k):
            self.result = True

    app.ConfirmDialog = Auto
    shown = []
    app.messagebox.showinfo = lambda *a, **k: shown.append(("info", a))
    app.messagebox.showerror = lambda *a, **k: shown.append(("error", a))
    # le telechargement passe par run_download : version synchrone sans fenetre
    app.App.run_download = lambda self, url, dest: (core.download_file(url, dest), dest)[1]
    app.App.run_blocking = lambda self, title, fn: (fn(), None)

    root = tk.Tk()
    root.withdraw()
    a = app.App(root)
    root.update()
    check("fausse installation detectee", a.ue and a.ue["installed"] and any(m["id"] == "TestMod" for m in a.installed))
    # recherche -> fenetre des mises a jour (neutralisee) : on appelle directement les actions
    manifest = core.fetch_manifest()
    upd = core.find_updates(manifest, app.APP_VERSION, a.installed)
    check("mise a jour du mod proposee", [u["id"] for u in upd["mods"]] == ["TestMod"])
    a.update_mod(upd["mods"][0], "1.0.0")
    root.update()
    check("mod mis a jour par l'interface", open(os.path.join(mods_dir, "TestMod", "Scripts", "main.lua")).read() == "-- v2")
    check("liste rafraichie (version 2.0.0)", [m["version"] for m in a.installed if m["id"] == "TestMod"] == ["2.0.0"])
    # launcheur : simulation « .exe installe »
    install_dir = os.path.join(TMP, "inst", "OutOfMods")
    os.makedirs(os.path.join(install_dir, "_internal"))
    open(os.path.join(install_dir, "OutOfMods.exe"), "wb").write(b"OLD")
    open(os.path.join(install_dir, "_internal", "v.txt"), "w").write("OLD")
    app.BASE_DIR = install_dir
    sys.frozen = True
    launched = []
    core.start_update_script = lambda script: (subprocess.run(["cmd", "/c", script], capture_output=True, timeout=60), launched.append(script))
    try:
        a.update_launcher(upd["launcher"], app.APP_VERSION)
        check("update_launcher termine par la sortie du programme", False)
    except SystemExit:
        check("update_launcher termine par la sortie du programme", True)
    time.sleep(1.5)
    check("script de remplacement lance", len(launched) == 1)
    check("launcheur remplace (nouveaux fichiers)", open(os.path.join(install_dir, "_internal", "v.txt")).read() == "NEW")
    check("ancienne version conservee", open(os.path.join(TMP, "inst", "OutOfMods_previous", "_internal", "v.txt")).read() == "OLD")
    check("aucune erreur affichee", not [s for s in shown if s[0] == "error"])
    # source non configuree
    os.environ.pop("OOLAUNCHER_UPDATE_URL")
    core.UPDATE_MANIFEST_URL = ""
    shown.clear()
    a2 = app.App.__new__(app.App)
    a2.check_updates()
    check("source non configuree : message clair, aucune connexion", shown and "source" in shown[0][1][1].lower() or "update" in str(shown).lower())
finally:
    httpd.shutdown()
    shutil.rmtree(TMP, ignore_errors=True)

print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
