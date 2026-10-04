"""Tests du systeme de mises a jour (serveur HTTP LOCAL sur 127.0.0.1, aucun acces Internet) : manifeste, comparaison de versions, empreintes,
mise a jour d'un mod, mise a jour du launcheur (extraction + script appliquant le remplacement dans un dossier temporaire)."""
import hashlib
import http.server
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
sys.path.insert(0, os.path.join(ROOT, "launcher"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import core  # noqa: E402
import i18n  # noqa: E402

i18n.set_language(os.environ.get("OOLAUNCHER_LANG", "fr"))
fails = 0


def check(name, cond):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name)
    if not cond:
        fails += 1


TMP = tempfile.mkdtemp(prefix="oolauncher_upd_")
srv_dir = os.path.join(TMP, "srv")
os.makedirs(srv_dir)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class Quiet(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=srv_dir, **k)

    def log_message(self, *a):
        pass


httpd = socketserver.TCPServer(("127.0.0.1", 0), Quiet)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % port

try:
    def zipit(path, entries):
        with zipfile.ZipFile(path, "w") as z:
            for n, c in entries.items():
                z.writestr(n, c)
        return path

    whoami = os.path.join(os.environ.get("SystemRoot", "C:/Windows"), "System32", "whoami.exe")
    exe_bytes = open(whoami, "rb").read()
    launcher_zip = zipit(os.path.join(srv_dir, "OutOfMods-9.9.9-win64.zip"), {
        "OutOfMods/OutOfMods.exe": exe_bytes, "OutOfMods/_internal/lib.txt": "NEW-LIB", "OutOfMods/packages/nouveau.txt": "x"})
    mod_zip = zipit(os.path.join(srv_dir, "TestMod-2.0.0.zip"), {"TestMod/mod.json": json.dumps({"id": "TestMod", "version": "2.0.0", "name": "Test"}),
                                                                 "TestMod/Scripts/main.lua": "-- v2"})
    manifest = {"schema": 1,
                "launcher": {"version": "9.9.9", "url": BASE + "/OutOfMods-9.9.9-win64.zip", "sha256": sha(launcher_zip), "size": os.path.getsize(launcher_zip),
                             "notes": {"fr": "Nouveautes", "en": "What's new"}},
                "mods": [{"id": "TestMod", "name": "Test", "version": "2.0.0", "url": BASE + "/TestMod-2.0.0.zip", "sha256": sha(mod_zip), "size": os.path.getsize(mod_zip)},
                         {"id": "AutreMod", "version": "1.0.0", "url": BASE + "/x.zip", "sha256": "0" * 64, "size": 1},
                         {"id": "TestMod2", "version": "oops"}]}
    json.dump(manifest, open(os.path.join(srv_dir, "updates.json"), "w"))
    json.dump({"schema": 2}, open(os.path.join(srv_dir, "bad.json"), "w"))
    open(os.path.join(srv_dir, "notjson.json"), "w").write("<html>")

    # ---- versions
    check("versions : 0.1.10 > 0.1.9", core.is_newer("0.1.10", "0.1.9") and not core.is_newer("0.1.0", "0.1.0") and not core.is_newer("0.0.9", "0.1.0"))
    check("versions : suffixe ignore, illisible = 0", core.parse_version("1.2.3-beta") == (1, 2, 3) and core.parse_version("???") == (0,))

    # ---- hotes autorises
    os.environ.pop(core.ALLOW_ENV, None)
    for bad in (BASE + "/updates.json", "http://github.com/x.json", "https://evil.example.com/x.json"):
        try:
            core.fetch_manifest(bad)
            check("hote refuse : " + bad, False)
        except core.PackageError:
            check("hote refuse : " + bad, True)
    try:
        core.fetch_manifest("")
        check("source non configuree : refuse proprement", False)
    except core.PackageError:
        check("source non configuree : refuse proprement", True)

    # ---- manifeste (l'hote de test est autorise EXPLICITEMENT)
    os.environ[core.ALLOW_ENV] = "127.0.0.1"
    m = core.fetch_manifest(BASE + "/updates.json")
    check("manifeste valide lu", m["schema"] == 1 and m["launcher"]["version"] == "9.9.9")
    for name in ("bad.json", "notjson.json", "absent.json"):
        try:
            core.fetch_manifest(BASE + "/" + name)
            check("manifeste refuse : " + name, False)
        except core.PackageError:
            check("manifeste refuse : " + name, True)

    # ---- comparaison
    upd = core.find_updates(m, "0.1.0", [{"id": "TestMod", "version": "1.0.0"}, {"id": "Other", "version": "5"}])
    check("mise a jour du launcheur detectee", upd["launcher"] is not None and upd["launcher"]["version"] == "9.9.9")
    check("mise a jour du mod detectee (entrees invalides ignorees)", [u["id"] for u in upd["mods"]] == ["TestMod"] and upd["mods"][0]["installed"] == "1.0.0")
    upd2 = core.find_updates(m, "9.9.9", [{"id": "TestMod", "version": "2.0.0"}])
    check("deja a jour : rien a proposer", upd2["launcher"] is None and upd2["mods"] == [])
    check("notes : langue demandee puis repli", core.note_for(m["launcher"], "fr") == "Nouveautes" and core.note_for(m["launcher"], "de") == "What's new")

    # ---- mise a jour d'un mod (telechargement + empreinte + installation avec sauvegarde)
    mods_dir = os.path.join(TMP, "game", "Mods")
    os.makedirs(os.path.join(mods_dir, "TestMod", "Scripts"))
    open(os.path.join(mods_dir, "TestMod", "Scripts", "main.lua"), "w").write("-- v1")
    json.dump({"id": "TestMod", "version": "1.0.0"}, open(os.path.join(mods_dir, "TestMod", "mod.json"), "w"))
    entry = upd["mods"][0]
    dl = os.path.join(TMP, "dl", "TestMod.zip")
    h = core.download_file(entry["url"], dl)
    check("telechargement du mod : empreinte conforme", h == entry["sha256"])
    pkg = core.read_package(dl)
    plan = core.plan_install(pkg, mods_dir)
    check("plan de mise a jour du mod : existant detecte, rien d'ecrit", plan["existing"] and open(os.path.join(mods_dir, "TestMod", "Scripts", "main.lua")).read() == "-- v1")
    core.do_install(plan)
    check("mod mis a jour + ancienne version sauvegardee", open(os.path.join(mods_dir, "TestMod", "Scripts", "main.lua")).read() == "-- v2"
          and os.path.isdir(core.backup_root(mods_dir)))

    # ---- mise a jour du launcheur
    lz = os.path.join(TMP, "dl", "launcher.zip")
    core.download_file(m["launcher"]["url"], lz)
    install_dir = os.path.join(TMP, "app", "OutOfMods")
    os.makedirs(os.path.join(install_dir, "_internal"))
    os.makedirs(os.path.join(install_dir, "packages"))
    open(os.path.join(install_dir, "OutOfMods.exe"), "wb").write(b"OLD-EXE")
    open(os.path.join(install_dir, "_internal", "lib.txt"), "w").write("OLD-LIB")
    open(os.path.join(install_dir, "packages", "perso.zip"), "w").write("mon paquet")
    bad_entry = dict(m["launcher"], sha256="f" * 64)
    try:
        core.prepare_launcher_update(lz, bad_entry, install_dir)
        check("mauvaise empreinte : mise a jour refusee", False)
    except core.PackageError:
        check("mauvaise empreinte : mise a jour refusee", True)
    check("mauvaise empreinte : rien n'a ete extrait", not os.path.exists(os.path.join(TMP, "app", "OutOfMods_update")))
    evil = zipit(os.path.join(TMP, "dl", "evil.zip"), {"OutOfMods/OutOfMods.exe": "x", "OutOfMods/../../evil.txt": "x"})
    try:
        core.prepare_launcher_update(evil, dict(m["launcher"], sha256=sha(evil)), install_dir)
        check("chemin '..' refuse", False)
    except core.PackageError:
        check("chemin '..' refuse", True)
    noexe = zipit(os.path.join(TMP, "dl", "noexe.zip"), {"OutOfMods/lib.txt": "x"})
    try:
        core.prepare_launcher_update(noexe, dict(m["launcher"], sha256=sha(noexe)), install_dir)
        check("paquet sans exe refuse", False)
    except core.PackageError:
        check("paquet sans exe refuse", True)
    info = core.prepare_launcher_update(lz, m["launcher"], install_dir)
    desc = core.describe_launcher_update(info, m["launcher"], "0.1.0")
    check("plan decrit : versions, dossier, sauvegarde", "9.9.9" in desc and install_dir in desc and info["backup_dir"] in desc)
    check("extraction hors de l'installation (rien remplace avant la confirmation)", open(os.path.join(install_dir, "_internal", "lib.txt")).read() == "OLD-LIB"
          and open(os.path.join(info["new_dir"], "_internal", "lib.txt")).read() == "NEW-LIB")
    # le script s'execute pour de bon dans le dossier temporaire (le launcheur factice n'est pas en cours d'execution)
    subprocess.run(["cmd", "/c", info["script"]], timeout=60, capture_output=True)
    time.sleep(1.5)
    check("script : nouveaux fichiers en place", open(os.path.join(install_dir, "_internal", "lib.txt")).read() == "NEW-LIB" and os.path.exists(os.path.join(install_dir, "packages", "nouveau.txt")))
    check("script : paquet de l'utilisateur conserve", open(os.path.join(install_dir, "packages", "perso.zip")).read() == "mon paquet")
    check("script : ancienne version sauvegardee", open(os.path.join(info["backup_dir"], "_internal", "lib.txt")).read() == "OLD-LIB"
          and open(os.path.join(info["backup_dir"], "OutOfMods.exe"), "rb").read() == b"OLD-EXE")
    check("script : dossier temporaire et script supprimes", not os.path.exists(info["new_dir"]) and not os.path.exists(info["script"]))
finally:
    httpd.shutdown()
    shutil.rmtree(TMP, ignore_errors=True)

print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
