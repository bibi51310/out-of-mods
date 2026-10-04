"""Tests de launcher/core.py sur un faux dossier de jeu (aucun acces au vrai jeu, aucune ecriture hors du dossier temporaire)."""
import json
import os
import shutil
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "launcher"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import core  # noqa: E402
import i18n  # noqa: E402

i18n.set_language(os.environ.get("OOLAUNCHER_LANG", "fr"))
import build_package  # noqa: E402

fails = 0


def check(name, cond):
    global fails
    print(("  OK    " if cond else "  ECHEC ") + name)
    if not cond:
        fails += 1


TMP = tempfile.mkdtemp(prefix="oolauncher_")
try:
    # faux jeu + UE4SS
    game_dir = os.path.join(TMP, "steamapps", "common", "OutofOre")
    win64 = os.path.join(game_dir, core.WIN64)
    os.makedirs(os.path.join(win64, "UE4SS", "Mods", "ModManuel", "Scripts"))
    open(os.path.join(game_dir, core.GAME_EXE), "w").close()
    open(os.path.join(win64, "dwmapi.dll"), "w").close()
    open(os.path.join(win64, "UE4SS", "Mods", "ModManuel", "Scripts", "main.lua"), "w").write("print('x')")
    mods_dir = os.path.join(win64, "UE4SS", "Mods")
    open(os.path.join(mods_dir, "mods.txt"), "w").write("ModManuel : 1\nKeybinds : 1\n")
    with open(os.path.join(TMP, "steamapps", "appmanifest_%s.acf" % core.APP_ID), "w") as f:
        f.write('"AppState"\n{\n\t"installdir"\t\t"OutofOre"\n\t"buildid"\t\t"25627989"\n\t"LastUpdated"\t\t"1790000000"\n\t"UserConfig"\n\t{\n\t\t"BetaKey"\t\t"beta"\n\t}\n}\n')

    g = core.find_game(steam=TMP)
    check("jeu detecte via l'appmanifest", g is not None and g["build_id"] == "25627989" and g["branch"] == "beta")
    check("jeu choisi a la main valide / invalide", core.game_from_dir(game_dir) is not None and core.game_from_dir(TMP) is None)
    ue = core.find_ue4ss(game_dir)
    check("UE4SS detecte", ue["installed"] and ue["mods_dir"] == mods_dir)
    check("UE4SS absent signale", not core.find_ue4ss(TMP)["installed"])

    # le paquet reel
    out_dir, zip_path = build_package.build("FlatGround2")
    pkg = core.read_package(zip_path)
    check("paquet valide (id, version, fichiers)", pkg["id"] == "FlatGround2" and pkg["meta"]["version"] and len(pkg["files"]) >= 4)
    plan = core.plan_install(pkg, mods_dir)
    check("plan : rien n'est ecrit", not os.path.exists(os.path.join(mods_dir, "FlatGround2")))
    check("plan : description lisible", "FlatGround2" in core.describe_plan(plan) and "enabled.txt" in core.describe_plan(plan))
    core.do_install(plan)
    mods = core.list_installed(mods_dir)
    fg = [m for m in mods if m["id"] == "FlatGround2"]
    check("installe : liste, active, gere", len(fg) == 1 and fg[0]["enabled"] and fg[0]["managed"])
    check("mod manuel vu mais non gere", [m for m in mods if m["id"] == "ModManuel"][0]["managed"] is False)
    check("compat : build different signale", core.compat_warnings({"game": {"testedBuildId": "1", "branch": "beta"}}, g) != [])
    check("compat : meme build = rien", core.compat_warnings(fg[0]["meta"], g) == [])

    # reinstallation = sauvegarde
    plan2 = core.plan_install(pkg, mods_dir)
    check("plan reinstall : existant detecte", plan2["existing"] and plan2["managed"])
    core.do_install(plan2)
    check("sauvegarde creee", os.path.isdir(core.backup_root(mods_dir)) and len(os.listdir(core.backup_root(mods_dir))) == 1)

    # activer / desactiver (enabled.txt)
    mod = [m for m in core.list_installed(mods_dir) if m["id"] == "FlatGround2"][0]
    core.do_set_enabled(core.plan_set_enabled(mod, False, mods_dir))
    check("desactive : enabled.txt retire", not os.path.exists(os.path.join(mods_dir, "FlatGround2", "enabled.txt")))
    core.do_set_enabled(core.plan_set_enabled([m for m in core.list_installed(mods_dir) if m["id"] == "FlatGround2"][0], True, mods_dir))
    check("reactive : enabled.txt cree", os.path.exists(os.path.join(mods_dir, "FlatGround2", "enabled.txt")))
    # activer / desactiver (mods.txt)
    manuel = [m for m in core.list_installed(mods_dir) if m["id"] == "ModManuel"][0]
    core.do_set_enabled(core.plan_set_enabled(manuel, False, mods_dir))
    txt = open(os.path.join(mods_dir, "mods.txt")).read()
    check("mods.txt : seule la ligne du mod change", "ModManuel : 0" in txt and "Keybinds : 1" in txt)

    # desinstallation
    open(os.path.join(mods_dir, "FlatGround2", "fichier_utilisateur.txt"), "w").write("a moi")
    mod = [m for m in core.list_installed(mods_dir) if m["id"] == "FlatGround2"][0]
    up = core.plan_uninstall(mod, mods_dir)
    core.do_uninstall(up)
    check("desinstalle : fichiers du paquet supprimes", not os.path.exists(os.path.join(mods_dir, "FlatGround2", "Scripts", "main.lua")))
    check("desinstalle : fichier utilisateur conserve", os.path.exists(os.path.join(mods_dir, "FlatGround2", "fichier_utilisateur.txt")))
    check("mod manuel : desinstallation refusee", core.plan_uninstall(manuel, mods_dir)["refused"] is not None)

    # paquets hostiles
    def zipof(name, entries):
        p = os.path.join(TMP, name)
        with zipfile.ZipFile(p, "w") as z:
            for n, c in entries.items():
                z.writestr(n, c)
        return p
    good_meta = json.dumps({"id": "X", "version": "1"})
    for label, entries in (("dll refusee", {"X/mod.json": good_meta, "X/Scripts/main.lua": "", "X/evil.dll": "MZ"}),
                           ("chemin '..' refuse", {"X/mod.json": good_meta, "X/Scripts/main.lua": "", "X/../../evil.lua": ""}),
                           ("deux racines refusees", {"X/mod.json": good_meta, "X/Scripts/main.lua": "", "Y/a.lua": ""}),
                           ("main.lua manquant refuse", {"X/mod.json": good_meta}),
                           ("id different refuse", {"X/mod.json": json.dumps({"id": "Z"}), "X/Scripts/main.lua": ""}),
                           ("exe refuse", {"X/mod.json": good_meta, "X/Scripts/main.lua": "", "X/setup.exe": "MZ"})):
        try:
            core.read_package(zipof("h.zip", entries))
            check(label, False)
        except core.PackageError:
            check(label, True)
    try:
        core.read_package(os.path.join(TMP, "inexistant.zip"))
        check("zip absent refuse", False)
    except core.PackageError:
        check("zip absent refuse", True)

    # ---------------- UE4SS : installation
    def make_zip(path, entries):
        with zipfile.ZipFile(path, "w") as z:
            for n, c in entries.items():
                z.writestr(n, c)
        return path
    upstream = {"dwmapi.dll": "MZ1", "UE4SS.dll": "MZ2", "UE4SS-settings.ini": "[Overlay] ", "Mods/mods.txt": "Keybinds : 1 ",
                "Mods/shared/UEHelpers/UEHelpers.lua": "-- h", "Mods/Keybinds/Scripts/main.lua": "-- k", "README.md": "x"}
    kitlayout = {"Kit/payload/dwmapi.dll": "MZ1", "Kit/payload/UE4SS/UE4SS.dll": "MZ2", "Kit/payload/UE4SS/UE4SS-settings.ini": "[o]",
                 "Kit/payload/UE4SS/Mods/mods.txt": "Keybinds : 1 ", "Kit/payload/ModManager/OutOfOreModManager.exe": "MZ", "Kit/Install Out of Ore Mods.exe": "MZ",
                 "Kit/payload/Optional/MiniMapMod.ooomod": "zip"}
    z1 = core.read_ue4ss_zip(make_zip(os.path.join(TMP, "up.zip"), upstream))
    z2 = core.read_ue4ss_zip(make_zip(os.path.join(TMP, "kit.zip"), kitlayout))
    check("zip UE4SS officiel : disposition 'flat'", z1["layout"] == "flat" and not z1["known"])
    check("zip du kit : disposition 'subfolder', exe / gestionnaire ignores", z2["layout"] == "subfolder" and len(z2["ignored"]) >= 3
          and not any(r.endswith(".exe") for r, _ in z2["entries"]))
    for label, entries in (("UE4SS : dll inconnue refusee", dict(upstream, **{"Evil.dll": "MZ"})), ("UE4SS : chemin '..' refuse", dict(upstream, **{"../x.lua": ""})),
                           ("UE4SS : sans dwmapi refuse", {"UE4SS.dll": "MZ"})):
        try:
            core.read_ue4ss_zip(make_zip(os.path.join(TMP, "h2.zip"), entries))
            check(label, False)
        except core.PackageError:
            check(label, True)
    # jeu vierge (sans UE4SS)
    g2 = os.path.join(TMP, "game2")
    os.makedirs(os.path.join(g2, core.WIN64))
    open(os.path.join(g2, core.GAME_EXE), "w").close()
    check("jeu vierge : UE4SS absent", not core.find_ue4ss(g2)["installed"])
    plan = core.plan_ue4ss_install(z1, g2)
    check("plan UE4SS : tout est 'create', rien n'est ecrit", all(a["action"] == "create" for a in plan["actions"]) and not os.path.exists(os.path.join(g2, core.WIN64, "dwmapi.dll")))
    check("plan UE4SS : description mentionne l'empreinte et les dll", "SHA-256" in core.describe_ue4ss_plan(plan) and "dwmapi.dll" in core.describe_ue4ss_plan(plan))
    core.is_game_running = lambda: False
    core.do_ue4ss_install(plan)
    ue2 = core.find_ue4ss(g2)
    check("UE4SS installe (flat) : detecte", ue2["installed"] and ue2["layout"] == "flat")
    check("reinstall par-dessus une install du launcheur : refuse", core.plan_ue4ss_install(z1, g2).get("refused") is not None)
    # jeu avec UE4SS d'origine (non installe par le launcheur) : reglages conserves, dll remplacees puis RESTAUREES au retrait
    g4 = os.path.join(TMP, "game4")
    w4 = os.path.join(g4, core.WIN64)
    os.makedirs(os.path.join(w4, "Mods"))
    open(os.path.join(w4, "dwmapi.dll"), "w").write("ORIGINAL-DWMAPI")
    open(os.path.join(w4, "UE4SS.dll"), "w").write("ORIGINAL-UE4SS")
    open(os.path.join(w4, "Mods", "mods.txt"), "w").write("MonMod : 1 ")
    open(os.path.join(w4, "UE4SS-settings.ini"), "w").write("[perso] ")
    plan = core.plan_ue4ss_install(z1, g4)
    acts = {a["rel"]: a["action"] for a in plan["actions"]}
    check("existant : mods.txt et settings conserves, dll remplacees", acts["Mods/mods.txt"] == "keep" and acts["UE4SS-settings.ini"] == "keep" and acts["UE4SS.dll"] == "replace")
    core.is_game_running = lambda: False
    core.do_ue4ss_install(plan)
    check("existant : reglages intacts apres installation", open(os.path.join(w4, "Mods", "mods.txt")).read() == "MonMod : 1 " and open(os.path.join(w4, "UE4SS-settings.ini")).read() == "[perso] ")
    check("existant : nouvelle dll en place", open(os.path.join(w4, "UE4SS.dll")).read() == "MZ2")
    # reglages recommandes : appliques a un NOUVEAU UE4SS-settings.ini seulement
    ini_text = "MajorVersion = " + chr(10) + "MinorVersion = " + chr(10) + "bUseUObjectArrayCache = true" + chr(10) + "GuiConsoleEnabled = 1" + chr(10) + "autre = 5" + chr(10) + ""
    ini_zip = core.read_ue4ss_zip(make_zip(os.path.join(TMP, "ini.zip"), {"dwmapi.dll": "MZ", "UE4SS.dll": "MZ", "UE4SS-settings.ini": ini_text, "Mods/mods.txt": "x"}))
    g6 = os.path.join(TMP, "game6")
    os.makedirs(os.path.join(g6, core.WIN64))
    plan6 = core.plan_ue4ss_install(ini_zip, g6)
    check("plan : reglages recommandes annonces", "MajorVersion = 4" in core.describe_ue4ss_plan(plan6))
    core.do_ue4ss_install(plan6)
    ini = open(os.path.join(g6, core.WIN64, "UE4SS-settings.ini")).read()
    check("reglages recommandes appliques, autres lignes intactes", "MajorVersion = 4" in ini and "MinorVersion = 27" in ini and "bUseUObjectArrayCache = false" in ini
          and "GuiConsoleEnabled = 0" in ini and "autre = 5" in ini)
    # jeu en cours : refus
    core.is_game_running = lambda: True
    try:
        core.do_ue4ss_install(core.plan_ue4ss_install(z1, os.path.join(TMP, "game5")))
        check("jeu ouvert : installation refusee", False)
    except core.PackageError:
        check("jeu ouvert : installation refusee", True)
    core.is_game_running = lambda: False
    # disposition 'subfolder' du kit sur un autre jeu vierge
    g3 = os.path.join(TMP, "game3")
    os.makedirs(os.path.join(g3, core.WIN64))
    core.do_ue4ss_install(core.plan_ue4ss_install(z2, g3))
    check("UE4SS installe (subfolder) : detecte", core.find_ue4ss(g3)["installed"] and core.find_ue4ss(g3)["layout"] == "subfolder")
    # retrait : seulement ce que le launcheur a installe
    open(os.path.join(w4, "Mods", "MonMod_perso.txt"), "w").write("a moi")
    up = core.plan_ue4ss_uninstall(g4)
    core.do_ue4ss_uninstall(up)
    check("retrait : dll d'origine restaurees", open(os.path.join(w4, "UE4SS.dll")).read() == "ORIGINAL-UE4SS" and open(os.path.join(w4, "dwmapi.dll")).read() == "ORIGINAL-DWMAPI")
    check("retrait : fichiers crees par l'installation supprimes", not os.path.exists(os.path.join(w4, "Mods", "Keybinds")) and not os.path.exists(os.path.join(w4, "README.md")))
    check("retrait : fichier de l'utilisateur conserve", os.path.exists(os.path.join(w4, "Mods", "MonMod_perso.txt")) and open(os.path.join(w4, "Mods", "mods.txt")).read() == "MonMod : 1 ")
    check("retrait refuse si pas installe par le launcheur", core.plan_ue4ss_uninstall(game_dir)["refused"] is not None)
    # telechargement : garde-fous (aucun acces reseau dans ce test)
    for bad in ("http://github.com/x.zip", "https://evil.example.com/x.zip", "ftp://github.com/x.zip"):
        try:
            core.download_file(bad, os.path.join(TMP, "dl.zip"))
            check("telechargement refuse : " + bad, False)
        except core.PackageError:
            check("telechargement refuse : " + bad, True)
    check("source UE4SS : hash fige", len(core.UE4SS_SOURCES[core.DEFAULT_SOURCE]["sha256"]) == 64 and core.UE4SS_SOURCES[core.DEFAULT_SOURCE]["url"].startswith("https://github.com/UE4SS-RE/"))
finally:
    shutil.rmtree(TMP, ignore_errors=True)

print("\nTOUT OK" if not fails else "\n%d ECHEC(S)" % fails)
sys.exit(1 if fails else 0)
