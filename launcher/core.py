# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Out of Mods -- logique (sans interface). Principes :

* LECTURE SEULE par defaut : detecter le jeu, UE4SS et les mods n'ecrit rien.
* Toute ecriture (installer, desinstaller, activer/desactiver) est decrite par un PLAN que l'interface montre a l'utilisateur ; rien n'est
  fait sans son accord explicite.
* Aucun acces reseau. Aucun fichier executable (.dll / .exe...) n'est jamais installe : liste blanche d'extensions.
* Tout fichier remplace est sauvegarde ; chaque installation laisse un manifeste (`.outofmods_install.json`) qui permet de desinstaller
  exactement ce qui a ete installe. Les donnees des mods (%APPDATA%) ne sont jamais touchees.
"""
import datetime
import hashlib
import json
import os
import re
import shutil
import zipfile

from i18n import tr

APP_ID = "2009350"
GAME_EXE = os.path.join("OutOfOre", "Binaries", "Win64", "OutOfOre-Win64-Shipping.exe")
WIN64 = os.path.join("OutOfOre", "Binaries", "Win64")
MANIFEST_NAME = ".outofmods_install.json"
ALLOWED_EXT = {".lua", ".json", ".txt", ".md", ".png"}      # jamais de binaire executable
MAX_PACKAGE_BYTES = 20 * 1024 * 1024
KIT_URL = "https://github.com/tonyoo/out-of-ore-modding"


# ------------------------------------------------------------------ detection du jeu (lecture seule)
def _steam_path():
    try:
        import winreg
        for root, sub in ((winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"), (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam")):
            try:
                with winreg.OpenKey(root, sub) as k:
                    for name in ("SteamPath", "InstallPath"):
                        try:
                            v = winreg.QueryValueEx(k, name)[0]
                            if v and os.path.isdir(v):
                                return os.path.normpath(v)
                        except OSError:
                            pass
            except OSError:
                pass
    except ImportError:
        pass
    for guess in (r"C:\Program Files (x86)\Steam", r"C:\Program Files\Steam"):
        if os.path.isdir(guess):
            return guess
    return None


def _library_folders(steam):
    libs = [steam]
    vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
    try:
        with open(vdf, "r", encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r'"path"\s+"([^"]+)"', f.read()):
                p = os.path.normpath(m.group(1).replace("\\\\", "\\"))
                if p not in libs and os.path.isdir(p):
                    libs.append(p)
    except OSError:
        pass
    return libs


def _acf_value(text, key):
    m = re.search(r'"%s"\s+"([^"]*)"' % re.escape(key), text)
    return m.group(1) if m else None


def find_game(steam=None):
    """Renvoie {'dir', 'build_id', 'branch', 'updated'} ou None si le jeu n'est pas trouve."""
    steam = steam or _steam_path()
    if not steam:
        return None
    for lib in _library_folders(steam):
        acf = os.path.join(lib, "steamapps", "appmanifest_%s.acf" % APP_ID)
        if not os.path.isfile(acf):
            continue
        try:
            with open(acf, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        installdir = _acf_value(text, "installdir")
        if not installdir:
            continue
        game_dir = os.path.join(lib, "steamapps", "common", installdir)
        if os.path.isdir(game_dir):
            upd = _acf_value(text, "LastUpdated")
            when = datetime.datetime.fromtimestamp(int(upd)).strftime("%Y-%m-%d") if upd and upd.isdigit() else None
            return {"dir": game_dir, "build_id": _acf_value(text, "buildid"), "branch": _acf_value(text, "BetaKey") or "public", "updated": when}
    return None


def game_from_dir(path):
    """Jeu choisi a la main par l'utilisateur : verifie que le dossier contient bien l'executable."""
    if path and os.path.isfile(os.path.join(path, GAME_EXE)):
        return {"dir": os.path.normpath(path), "build_id": None, "branch": None, "updated": None}
    return None


def find_ue4ss(game_dir):
    """UE4SS est-il installe ? Renvoie {'installed', 'mods_dir', 'dir', 'layout', 'problems'} (lecture seule).
    Deux dispositions existent : `Win64/ue4ss/` (kit communautaire, builds recents) ou tout dans `Win64/` (release 3.0.x : UE4SS.dll et Mods/ a cote de dwmapi.dll)."""
    win64 = os.path.join(game_dir, WIN64)
    info = {"installed": False, "mods_dir": None, "dir": None, "layout": None, "problems": []}
    if not os.path.isdir(win64):
        info["problems"].append(tr("dossier Win64 introuvable"))
        return info
    names = {n.lower(): n for n in os.listdir(win64)}
    has_proxy = "dwmapi.dll" in names
    manifest = read_json(os.path.join(win64, UE4SS_MANIFEST)) or {}
    prefer_flat = manifest.get("layout") == "flat"        # installe par ce launcheur : on sait quelle disposition le chargeur utilise
    if not prefer_flat and "ue4ss" in names and os.path.isdir(os.path.join(win64, names["ue4ss"])):
        ue_dir = os.path.join(win64, names["ue4ss"])
        sub = {n.lower(): n for n in os.listdir(ue_dir)}
        if "mods" in sub:
            info.update(dir=ue_dir, mods_dir=os.path.join(ue_dir, sub["mods"]), layout="subfolder")
    if not info["mods_dir"] and "ue4ss.dll" in names and "mods" in names:
        info.update(dir=win64, mods_dir=os.path.join(win64, names["mods"]), layout="flat")
    if not has_proxy:
        info["problems"].append(tr("dwmapi.dll absent (le chargeur UE4SS n'est pas installe)"))
    if not info["mods_dir"]:
        info["problems"].append(tr("dossier de mods UE4SS absent"))
    info["installed"] = has_proxy and bool(info["mods_dir"])
    return info


# ------------------------------------------------------------------ mods installes (lecture seule)
def _mods_txt_state(mods_dir, mod_id):
    """True / False si mods.txt contient une ligne `mod : 1|0` pour ce mod, None s'il n'en parle pas."""
    try:
        with open(os.path.join(mods_dir, "mods.txt"), "r", encoding="utf-8-sig", errors="replace") as f:
            for line in f:
                m = re.match(r"^\s*([^\s:;#]+)\s*:\s*([01])\s*$", line)
                if m and m.group(1).lower() == mod_id.lower():
                    return m.group(2) == "1"
    except OSError:
        pass
    return None


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def list_installed(mods_dir):
    """Mods presents dans UE4SS/Mods : dossiers avec Scripts/main.lua. `managed` = installe par ce launcheur (manifeste present)."""
    mods = []
    if not mods_dir or not os.path.isdir(mods_dir):
        return mods
    for name in sorted(os.listdir(mods_dir), key=str.lower):
        d = os.path.join(mods_dir, name)
        if not os.path.isfile(os.path.join(d, "Scripts", "main.lua")):
            continue
        meta = read_json(os.path.join(d, "mod.json")) or {}
        manifest = read_json(os.path.join(d, MANIFEST_NAME))
        txt = _mods_txt_state(mods_dir, name)
        has_enabled = os.path.isfile(os.path.join(d, "enabled.txt"))
        enabled = txt if txt is not None else has_enabled
        mods.append({"id": name, "dir": d, "name": meta.get("name", name), "version": meta.get("version"), "meta": meta,
                     "managed": manifest is not None, "enabled": bool(enabled), "via_mods_txt": txt is not None})
    return mods


def compat_warnings(meta, game):
    """Avertissements de compatibilite entre un mod (mod.json) et le jeu installe. Liste vide = rien a signaler."""
    out = []
    tested = (meta.get("game") or {})
    if game and game.get("build_id") and tested.get("testedBuildId") and game["build_id"] != tested["testedBuildId"]:
        out.append(tr("teste sur le build %s, le jeu est en %s (le mod peut ne pas fonctionner)") % (tested["testedBuildId"], game["build_id"]))
    if game and game.get("branch") and tested.get("branch") and game["branch"] != tested["branch"] and not (game["branch"] == "public" and tested["branch"] == "stable"):
        out.append(tr("teste sur la branche « %s », le jeu est sur « %s »") % (tested["branch"], game["branch"]))
    return out


# ------------------------------------------------------------------ paquets (.zip) : lecture et validation (aucune ecriture)
class PackageError(Exception):
    pass


def read_package(zip_path):
    """Valide un paquet et renvoie {'id','meta','files':[(chemin_relatif,taille)],'sha256','size'} ; leve PackageError sinon.
    Un paquet = un dossier racine unique <Id>/ contenant mod.json et Scripts/main.lua (zip produit par tools/build_package.py)."""
    try:
        size = os.path.getsize(zip_path)
    except OSError as e:
        raise PackageError(tr("fichier illisible : %s") % e)
    if size > MAX_PACKAGE_BYTES:
        raise PackageError(tr("paquet trop gros (%d Mo, limite %d Mo)") % (size // 2**20, MAX_PACKAGE_BYTES // 2**20))
    try:
        z = zipfile.ZipFile(zip_path)
    except (zipfile.BadZipFile, OSError) as e:
        raise PackageError(tr("ce n'est pas un zip valide : %s") % e)
    with z:
        infos = [i for i in z.infolist() if not i.is_dir()]
        if not infos:
            raise PackageError(tr("paquet vide"))
        roots = {i.filename.replace("\\", "/").split("/")[0] for i in infos}
        if len(roots) != 1:
            raise PackageError(tr("le paquet doit contenir un seul dossier racine (trouve : %s)") % ", ".join(sorted(roots)))
        mod_id = roots.pop()
        if not re.match(r"^[A-Za-z0-9_.-]{1,64}$", mod_id):
            raise PackageError(tr("nom de dossier de mod invalide : %r") % mod_id)
        files = []
        for i in infos:
            name = i.filename.replace("\\", "/")
            parts = name.split("/")
            if name.startswith("/") or ".." in parts or ":" in parts[0] or len(parts) < 2:
                raise PackageError(tr("chemin dangereux dans le paquet : %s") % i.filename)
            ext = os.path.splitext(name)[1].lower()
            if ext not in ALLOWED_EXT:
                raise PackageError(tr("type de fichier refuse (%s) : %s -- seuls %s sont acceptes") % (ext or tr("sans extension"), name, ", ".join(sorted(ALLOWED_EXT))))
            if i.file_size > MAX_PACKAGE_BYTES:
                raise PackageError(tr("fichier trop gros : %s") % name)
            files.append(("/".join(parts[1:]), i.file_size))
        rels = {f[0] for f in files}
        if "Scripts/main.lua" not in rels:
            raise PackageError(tr("Scripts/main.lua manquant"))
        if "mod.json" not in rels:
            raise PackageError(tr("mod.json manquant"))
        try:
            meta = json.loads(z.read("%s/mod.json" % mod_id).decode("utf-8"))
        except (ValueError, KeyError) as e:
            raise PackageError(tr("mod.json illisible : %s") % e)
    if meta.get("id") != mod_id:
        raise PackageError(tr("l'id du mod.json (%r) ne correspond pas au dossier (%r)") % (meta.get("id"), mod_id))
    sha = hashlib.sha256()
    with open(zip_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            sha.update(chunk)
    return {"id": mod_id, "meta": meta, "files": files, "sha256": sha.hexdigest(), "size": size, "path": zip_path}


# ------------------------------------------------------------------ plans d'ecriture (decrits avant d'etre executes)
def backup_root(mods_dir):
    return os.path.join(os.path.dirname(mods_dir), "OutOfMods_backups")


def plan_install(pkg, mods_dir):
    """Decrit ce qu'installer ce paquet ferait. N'ecrit rien."""
    dest = os.path.join(mods_dir, pkg["id"])
    existing = os.path.isdir(dest)
    managed = existing and os.path.isfile(os.path.join(dest, MANIFEST_NAME))
    files = [f[0] for f in pkg["files"]]
    if "enabled.txt" not in files:
        files.append("enabled.txt")
    return {"kind": "install", "pkg": pkg, "dest": dest, "existing": existing, "managed": managed,
            "backup_dir": backup_root(mods_dir) if existing else None, "files": files, "mods_dir": mods_dir}


def describe_plan(plan):
    p = plan["pkg"]
    lines = [tr("Installer « %s » version %s") % (p["meta"].get("name", p["id"]), p["meta"].get("version", "?")),
             tr("Dans le dossier : %s") % plan["dest"], tr("%d fichier(s) :") % len(plan["files"])]
    lines += ["    " + f for f in plan["files"]]
    if plan["existing"]:
        lines.append("")
        lines.append(tr("Ce mod est DEJA installe : l'ancienne version sera sauvegardee dans"))
        lines.append("    %s" % plan["backup_dir"])
        if not plan["managed"]:
            lines.append(tr("(elle n'avait pas ete installee par ce launcheur)"))
    lines += ["", tr("Aucun fichier en dehors de ce dossier n'est modifie. Vos donnees (parametres, hauteurs) ne sont pas touchees.")]
    return "\n".join(lines)


def do_install(plan, log=lambda s: None):
    """Execute un plan d'installation (apres accord de l'utilisateur). Sauvegarde l'existant, extrait, ecrit le manifeste."""
    pkg, dest, mods_dir = plan["pkg"], plan["dest"], plan["mods_dir"]
    if plan["existing"]:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        bdir = os.path.join(plan["backup_dir"], "%s-%s" % (pkg["id"], stamp))
        os.makedirs(os.path.dirname(bdir), exist_ok=True)
        shutil.copytree(dest, bdir)
        log(tr("sauvegarde : %s") % bdir)
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)
    written = []
    with zipfile.ZipFile(pkg["path"]) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            rel = "/".join(info.filename.replace("\\", "/").split("/")[1:])
            target = os.path.normpath(os.path.join(dest, rel))
            if os.path.commonpath([dest, target]) != os.path.normpath(dest):
                raise PackageError(tr("chemin hors du dossier du mod : %s") % rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            written.append(rel)
    if "enabled.txt" not in written:
        open(os.path.join(dest, "enabled.txt"), "w").close()
        written.append("enabled.txt")
    manifest = {"id": pkg["id"], "version": pkg["meta"].get("version"), "files": sorted(written), "sha256": pkg["sha256"],
                "installedAt": datetime.datetime.now().isoformat(timespec="seconds"), "by": "Out of Mods"}
    with open(os.path.join(dest, MANIFEST_NAME), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    log(tr("installe : %s (%d fichiers)") % (dest, len(written)))
    return manifest


def plan_uninstall(mod, mods_dir):
    manifest = read_json(os.path.join(mod["dir"], MANIFEST_NAME))
    if manifest is None:
        return {"kind": "uninstall", "mod": mod, "refused": tr("ce mod n'a pas ete installe par ce launcheur : suppression manuelle uniquement (dossier %s)") % mod["dir"]}
    return {"kind": "uninstall", "mod": mod, "files": manifest["files"] + [MANIFEST_NAME], "mods_dir": mods_dir, "refused": None,
            "backup_dir": backup_root(mods_dir)}


def describe_uninstall(plan):
    if plan["refused"]:
        return plan["refused"]
    m = plan["mod"]
    return "\n".join([tr("Desinstaller « %s » (%s)") % (m["name"], m["version"] or "?"), tr("Dossier : %s") % m["dir"], tr("%d fichier(s) supprime(s) (ceux installes par le launcheur) :") % len(plan["files"])]
                     + ["    " + f for f in plan["files"]]
                     + ["", tr("Une copie est conservee dans %s") % plan["backup_dir"], tr("Vos donnees (parametres, hauteurs) ne sont pas touchees.")])


def do_uninstall(plan, log=lambda s: None):
    if plan["refused"]:
        raise PackageError(plan["refused"])
    mod = plan["mod"]
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(plan["backup_dir"], "%s-%s-desinstalle" % (mod["id"], stamp))
    os.makedirs(os.path.dirname(bdir), exist_ok=True)
    shutil.copytree(mod["dir"], bdir)
    log(tr("sauvegarde : %s") % bdir)
    for rel in plan["files"]:
        p = os.path.normpath(os.path.join(mod["dir"], rel))
        if os.path.commonpath([mod["dir"], p]) == os.path.normpath(mod["dir"]) and os.path.isfile(p):
            os.remove(p)
    for base, dirs, files in os.walk(mod["dir"], topdown=False):      # supprime les dossiers devenus vides (jamais un dossier non vide)
        if not os.listdir(base):
            os.rmdir(base)
    log(tr("desinstalle : %s") % mod["id"])


def plan_set_enabled(mod, enabled, mods_dir):
    """Activer / desactiver : si mods.txt cite le mod on modifie SA ligne (sauvegarde de mods.txt), sinon on cree / retire enabled.txt."""
    if mod["via_mods_txt"]:
        what = [tr("mods.txt : la ligne « %s : %d » devient « %s : %d »") % (mod["id"], 1 if mod["enabled"] else 0, mod["id"], 1 if enabled else 0),
                tr("(copie de mods.txt dans %s)") % backup_root(mods_dir)]
    else:
        what = [tr("%s enabled.txt dans %s") % (tr("Creer") if enabled else tr("Supprimer"), mod["dir"])]
    return {"kind": "enable", "mod": mod, "enabled": enabled, "mods_dir": mods_dir, "describe": what}


def do_set_enabled(plan, log=lambda s: None):
    mod, enabled, mods_dir = plan["mod"], plan["enabled"], plan["mods_dir"]
    if mod["via_mods_txt"]:
        path = os.path.join(mods_dir, "mods.txt")
        os.makedirs(backup_root(mods_dir), exist_ok=True)
        shutil.copy2(path, os.path.join(backup_root(mods_dir), "mods-%s.txt" % datetime.datetime.now().strftime("%Y%m%d-%H%M%S")))
        with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
            lines = f.read().split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^(\s*)([^\s:;#]+)(\s*:\s*)([01])(\s*)$", line)
            if m and m.group(2).lower() == mod["id"].lower():
                lines[i] = "%s%s%s%d%s" % (m.group(1), m.group(2), m.group(3), 1 if enabled else 0, m.group(5))
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(lines))
    else:
        flag = os.path.join(mod["dir"], "enabled.txt")
        if enabled:
            open(flag, "w").close()
        elif os.path.isfile(flag):
            os.remove(flag)
    log("%s : %s" % (tr("active") if enabled else tr("desactive"), mod["id"]))


# ------------------------------------------------------------------ installation d'UE4SS (reseau SEULEMENT apres accord, jamais en arriere-plan)
UE4SS_SOURCES = {
    # Source proposee par defaut : build experimental de UE4SS-RE (MIT) VALIDE avec Out of Ore le 2026-10-04 (chargement des mods, hooks de terrassement).
    "e3ba1016": {"label": tr("UE4SS 3.0.1 - build e3ba1016 (UE4SS-RE, licence MIT, valide avec Out of Ore)"),
                 "url": "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-1152-ge3ba1016.zip",
                 "sha256": "af8ea9d8975e8eff7967423f43b8b50875e66a29a0f434cffce6e0867ea17252", "size": 8730191,
                 "page": "https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest"},
}
DEFAULT_SOURCE = "e3ba1016"
# Release « v3.0.1 » (stable) : NON proposee. Testee le 2026-10-04 : elle charge les mods mais les hooks de terrassement echouent
# ([push_floatproperty] data pointer is nullptr) -> le plancher ne serait pas applique. Son empreinte reste « connue » pour un fichier local.
OTHER_KNOWN_SHA256 = {"4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec"}
# Reglages d'UE4SS recommandes pour Out of Ore (ceux du kit communautaire), appliques SEULEMENT a un UE4SS-settings.ini que l'installation cree.
RECOMMENDED_INI = {"MajorVersion": "4", "MinorVersion": "27", "bUseUObjectArrayCache": "false", "GuiConsoleEnabled": "0"}
KNOWN_UE4SS_SHA256 = {v["sha256"] for v in UE4SS_SOURCES.values()} | OTHER_KNOWN_SHA256
ALLOWED_HOSTS = ("github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com")
UE4SS_BINARIES = {"dwmapi.dll", "ue4ss.dll"}           # les SEULS binaires acceptes dans un paquet UE4SS
UE4SS_TEXT_EXT = {".lua", ".json", ".txt", ".ini", ".md"}
KEEP_IF_EXISTS = ("mods.txt", "ue4ss-settings.ini")     # fichiers de reglages de l'utilisateur : jamais ecrases
UE4SS_MANIFEST = ".outofmods_ue4ss.json"


def sha256_file(path):
    sha = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            sha.update(chunk)
    return sha.hexdigest()


def is_game_running():
    """Le jeu tourne-t-il ? (installer UE4SS pendant que le jeu est ouvert est refuse)."""
    import subprocess
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq OutOfOre-Win64-Shipping.exe", "/NH"], capture_output=True, text=True, timeout=10).stdout
        return "OutOfOre-Win64-Shipping" in out
    except (OSError, subprocess.SubprocessError):
        return False


def describe_download(src):
    return "\n".join([tr("Telechargement de %s") % tr(src["label"]), tr("Adresse : %s") % src["url"], tr("Taille : environ %.1f Mo") % (src["size"] / 2**20),
                      tr("Connexion Internet vers github.com (rien d'autre n'est envoye que la demande du fichier)."),
                      tr("Le fichier est verifie (empreinte SHA-256 connue) AVANT toute installation."),
                      tr("Rien n'est installe a cette etape : vous verrez la liste exacte des fichiers ensuite."), "", tr("Page de la version : %s") % src["page"]])


def download_file(url, dest, progress=lambda done, total: True, max_bytes=60 * 1024 * 1024):
    """Telecharge un fichier HTTPS d'un hote autorise. `progress(done, total)` renvoie False pour annuler. Renvoie le sha256."""
    import urllib.parse
    import urllib.request

    check = check_url_allowed

    check(url)

    class Guard(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            check(newurl)
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    opener = urllib.request.build_opener(Guard())
    req = urllib.request.Request(url, headers={"User-Agent": "OutOfMods"})
    sha = hashlib.sha256()
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    try:
        with opener.open(req, timeout=30) as r, open(tmp, "wb") as out:
            total = int(r.headers.get("Content-Length") or 0)
            done = 0
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                done += len(chunk)
                if done > max_bytes:
                    raise PackageError(tr("fichier trop gros (> %d Mo)") % (max_bytes // 2**20))
                sha.update(chunk)
                out.write(chunk)
                if progress(done, total) is False:
                    raise PackageError(tr("telechargement annule"))
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return sha.hexdigest()


def read_ue4ss_zip(zip_path):
    """Valide un zip UE4SS (release officielle, build `ue4ss/`, ou kit communautaire `payload/`) et renvoie
    {'layout','entries':[(chemin_relatif_dans_Win64, nom_dans_le_zip)],'ignored':[...],'sha256','known','path'} ; PackageError sinon.
    Seuls dwmapi.dll et UE4SS.dll sont acceptes comme binaires ; le reste doit etre du texte (lua/json/txt/ini/md)."""
    try:
        z = zipfile.ZipFile(zip_path)
    except (zipfile.BadZipFile, OSError) as e:
        raise PackageError(tr("ce n'est pas un zip valide : %s") % e)
    with z:
        names = [i.filename.replace("\\", "/") for i in z.infolist() if not i.is_dir()]
        base = None
        for n in names:                                  # trouve le dossier qui contient dwmapi.dll
            if n.lower().endswith("dwmapi.dll"):
                base = n[: -len("dwmapi.dll")]
                break
        if base is None:
            raise PackageError(tr("dwmapi.dll introuvable dans ce zip : ce n'est pas un paquet UE4SS"))
        entries, ignored = [], []
        layout = None
        for n in names:
            if not n.startswith(base):
                ignored.append(n)
                continue
            rel = n[len(base):]
            parts = rel.split("/")
            if n.startswith("/") or ".." in parts or ":" in parts[0] or not rel:
                raise PackageError(tr("chemin dangereux dans le paquet : %s") % n)
            low = rel.lower()
            if low.startswith(("modmanager/", "optional/")) or low.endswith(".exe") or low.endswith(".ooomod"):
                ignored.append(n)                         # le gestionnaire / l'installeur du kit ne sont pas installes
                continue
            ext = os.path.splitext(low)[1]
            leaf = parts[-1].lower()
            if ext == ".dll":
                if leaf not in UE4SS_BINARIES:
                    raise PackageError(tr("binaire refuse : %s (seuls dwmapi.dll et UE4SS.dll sont acceptes)") % n)
            elif ext not in UE4SS_TEXT_EXT and leaf not in ("license", "ue4ss.json"):
                raise PackageError(tr("type de fichier refuse : %s") % n)
            entries.append((rel, n))
            if low == "ue4ss.dll":
                layout = "flat"
            elif low == "ue4ss/ue4ss.dll":
                layout = "subfolder"
        if layout is None or not any(r.lower() == "dwmapi.dll" for r, _ in entries):
            raise PackageError(tr("dwmapi.dll / UE4SS.dll manquants"))
    sha = hashlib.sha256()
    with open(zip_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            sha.update(chunk)
    return {"layout": layout, "entries": entries, "ignored": ignored, "sha256": sha.hexdigest(), "known": sha.hexdigest() in KNOWN_UE4SS_SHA256, "path": zip_path}


def plan_ue4ss_install(kit, game_dir):
    """Decrit l'installation d'UE4SS (n'ecrit rien) : par fichier, `create`, `replace` (ancienne version sauvegardee) ou `keep` (reglages de l'utilisateur conserves)."""
    win64 = os.path.join(game_dir, WIN64)
    if os.path.isfile(os.path.join(win64, UE4SS_MANIFEST)):
        return {"kind": "ue4ss", "refused": tr("UE4SS a deja ete installe par ce launcheur. Retirez-le d'abord (ses fichiers d'origine sont alors restaures), puis reinstallez.")}
    actions = []
    for rel, zname in kit["entries"]:
        dest = os.path.join(win64, rel.replace("/", os.sep))
        leaf = rel.split("/")[-1].lower()
        if os.path.exists(dest):
            keep = leaf in KEEP_IF_EXISTS or ("/mods/" in "/" + rel.lower() and not leaf.endswith(".dll"))
            actions.append({"rel": rel, "zip": zname, "dest": dest, "action": "keep" if keep else "replace"})
        else:
            act = {"rel": rel, "zip": zname, "dest": dest, "action": "create"}
            if leaf == "ue4ss-settings.ini":
                act["patch"] = dict(RECOMMENDED_INI)       # nouveau fichier de reglages : on y applique les reglages recommandes pour Out of Ore
            actions.append(act)
    return {"kind": "ue4ss", "kit": kit, "game_dir": game_dir, "win64": win64, "actions": actions,
            "backup_dir": os.path.join(win64, "OutOfMods_backups")}


def describe_ue4ss_plan(plan):
    if plan.get("refused"):
        return plan["refused"]
    kit = plan["kit"]
    c = {"create": [], "replace": [], "keep": []}
    for a in plan["actions"]:
        c[a["action"]].append(a["rel"])
    trust = (tr("correspond a une version CONNUE de ce launcheur") if kit["known"] else
             tr("INCONNUE de ce launcheur (version differente ou fichier modifie) : n'installez que si vous faites confiance a la source"))
    lines = [tr("Installer UE4SS (disposition « %s ») dans :") % kit["layout"], "    %s" % plan["win64"], "",
             tr("Empreinte SHA-256 : %s") % kit["sha256"], "    -> %s" % trust, "",
             tr("%d fichier(s) a creer, %d a remplacer (copie dans %s), %d existant(s) conserve(s) tel(s) quel(s) :") % (len(c["create"]), len(c["replace"]), plan["backup_dir"], len(c["keep"]))]
    for key, label in (("replace", tr("REMPLACER")), ("create", tr("creer")), ("keep", tr("conserver"))):
        for rel in c[key]:
            lines.append("    %-10s %s" % (label, rel))
    patched = [a for a in plan["actions"] if a.get("patch")]
    if patched:
        lines += ["", tr("Reglages recommandes pour Out of Ore appliques au NOUVEAU fichier %s :") % patched[0]["rel"]] + ["    %s = %s" % kv for kv in patched[0]["patch"].items()]
    if kit["ignored"]:
        lines += ["", tr("%d element(s) du zip ignores (installeur, gestionnaire de mods, paquets optionnels).") % len(kit["ignored"])]
    lines += ["", tr("Les seuls programmes (.dll) installes sont dwmapi.dll et UE4SS.dll. Votre antivirus peut signaler dwmapi.dll (c'est le chargeur d'UE4SS, un faux positif connu)."),
              tr("Le jeu doit etre FERME.")]
    return "\n".join(lines)


def do_ue4ss_install(plan, log=lambda s: None):
    if plan.get("refused"):
        raise PackageError(plan["refused"])
    if is_game_running():
        raise PackageError(tr("le jeu est en cours d'execution : fermez-le avant d'installer UE4SS"))
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(plan["backup_dir"], "ue4ss-%s" % stamp)
    written, replaced = [], []
    win64_n = os.path.normpath(plan["win64"])
    with zipfile.ZipFile(plan["kit"]["path"]) as z:
        for a in plan["actions"]:
            if a["action"] == "keep":
                continue
            dest = os.path.normpath(a["dest"])
            if os.path.commonpath([win64_n, dest]) != win64_n:
                raise PackageError(tr("chemin hors du dossier du jeu : %s") % a["rel"])
            if a["action"] == "replace":
                bpath = os.path.join(bdir, a["rel"].replace("/", os.sep))
                os.makedirs(os.path.dirname(bpath), exist_ok=True)
                shutil.copy2(dest, bpath)
                replaced.append(a["rel"])
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if a.get("patch"):
                import re as _re
                text = z.read(a["zip"]).decode("utf-8-sig", errors="replace")
                for key, value in a["patch"].items():
                    text = _re.sub(r"(?m)^(\s*%s\s*=).*$" % _re.escape(key), lambda m, v=value: "%s %s" % (m.group(1), v), text)
                with open(dest, "w", encoding="utf-8", newline="") as out:
                    out.write(text)
            else:
                with z.open(a["zip"]) as src, open(dest, "wb") as out:
                    shutil.copyfileobj(src, out)
            written.append(a["rel"])
    manifest = {"layout": plan["kit"]["layout"], "sha256": plan["kit"]["sha256"], "files": sorted(written), "replaced": sorted(replaced), "backup": bdir,
                "installedAt": datetime.datetime.now().isoformat(timespec="seconds"), "by": "Out of Mods"}
    with open(os.path.join(plan["win64"], UE4SS_MANIFEST), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    log(tr("UE4SS installe : %d fichier(s) ecrit(s)%s") % (len(written), (tr(", anciennes versions dans ") + bdir) if os.path.isdir(bdir) else ""))
    return manifest


def plan_ue4ss_uninstall(game_dir):
    win64 = os.path.join(game_dir, WIN64)
    manifest = read_json(os.path.join(win64, UE4SS_MANIFEST))
    if manifest is None:
        return {"kind": "ue4ss-uninstall", "refused": tr("UE4SS n'a pas ete installe par ce launcheur : retrait manuel uniquement.")}
    return {"kind": "ue4ss-uninstall", "refused": None, "win64": win64, "files": manifest["files"], "replaced": manifest.get("replaced", []),
            "backup": manifest.get("backup"), "backup_dir": os.path.join(win64, "OutOfMods_backups")}


def describe_ue4ss_uninstall(plan):
    if plan["refused"]:
        return plan["refused"]
    restore = []
    if plan["replaced"] and plan["backup"]:
        restore = ["", tr("Les %d fichier(s) que l'installation avait REMPLACES seront RESTAURES depuis %s :") % (len(plan["replaced"]), plan["backup"])] + ["    " + r for r in plan["replaced"]]
    return "\n".join([tr("Retirer UE4SS (uniquement les %d fichier(s) installes par ce launcheur) de :") % len(plan["files"]), "    %s" % plan["win64"]] + restore + [""] + [
                      tr("Vos mods et vos reglages ajoutes apres coup ne sont pas touches ; une copie de ce qui est retire est conservee dans"), "    %s" % plan["backup_dir"],
                      tr("Le jeu doit etre FERME.")])


def do_ue4ss_uninstall(plan, log=lambda s: None):
    if plan["refused"]:
        raise PackageError(plan["refused"])
    if is_game_running():
        raise PackageError(tr("le jeu est en cours d'execution : fermez-le d'abord"))
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(plan["backup_dir"], "ue4ss-retrait-%s" % stamp)
    win64 = os.path.normpath(plan["win64"])
    for rel in plan["files"]:
        p = os.path.normpath(os.path.join(win64, rel.replace("/", os.sep)))
        if os.path.commonpath([win64, p]) == win64 and os.path.isfile(p):
            bpath = os.path.join(bdir, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(bpath), exist_ok=True)
            shutil.copy2(p, bpath)
            os.remove(p)
    # restauration des fichiers que l'installation avait remplaces (depuis la sauvegarde faite a ce moment-la)
    if plan.get("backup") and os.path.isdir(plan["backup"]):
        for rel in plan.get("replaced", []):
            src = os.path.join(plan["backup"], rel.replace("/", os.sep))
            dst = os.path.normpath(os.path.join(win64, rel.replace("/", os.sep)))
            if os.path.isfile(src) and os.path.commonpath([win64, dst]) == win64:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                log(tr("restaure : %s") % rel)
    for base, dirs, files in os.walk(win64, topdown=False):      # dossiers devenus vides sous Win64/ue4ss ou Win64/Mods uniquement
        rel = os.path.relpath(base, win64).replace("\\", "/").lower()
        if base != win64 and rel.split("/")[0] in ("ue4ss", "mods") and not os.listdir(base):
            os.rmdir(base)
    manifest_path = os.path.join(win64, UE4SS_MANIFEST)
    if os.path.isfile(manifest_path):
        os.remove(manifest_path)
    log(tr("UE4SS retire (copie dans %s)") % bdir)


# ------------------------------------------------------------------ mises a jour (reseau SEULEMENT sur demande de l'utilisateur)
# Adresse du manifeste de mises a jour (release GitHub la plus recente ; ne repond qu'une fois le depot PUBLIC).
# Vide = fonction desactivee (l'interface l'indique). `OOLAUNCHER_UPDATE_URL` permet de tester avec un serveur local (voir ALLOW_ENV).
UPDATE_MANIFEST_URL = "https://github.com/bibi51310/out-of-mods/releases/latest/download/updates.json"
ALLOW_ENV = "OOLAUNCHER_ALLOW_HOST"       # developpement / tests uniquement : autorise explicitement UN hote supplementaire (http accepte pour lui)
MANIFEST_MAX_BYTES = 256 * 1024


def update_manifest_url():
    return os.environ.get("OOLAUNCHER_UPDATE_URL") or UPDATE_MANIFEST_URL


def check_url_allowed(url):
    """Seuls HTTPS + hotes GitHub sont autorises (plus l'hote de test explicitement nomme dans OOLAUNCHER_ALLOW_HOST)."""
    import urllib.parse
    pu = urllib.parse.urlparse(url)
    extra = os.environ.get(ALLOW_ENV)
    if extra and pu.hostname == extra and pu.scheme in ("http", "https"):
        return
    if pu.scheme != "https" or pu.hostname not in ALLOWED_HOSTS:
        raise PackageError(tr("adresse refusee (%s) : seuls les telechargements HTTPS depuis GitHub sont autorises") % url)


def parse_version(text):
    """'0.1.10' -> (0, 1, 10). Les suffixes (-beta...) sont ignores. Version illisible -> (0,)."""
    import re as _re
    nums = _re.findall(r"\d+", (text or "").split("-")[0])
    return tuple(int(n) for n in nums) if nums else (0,)


def is_newer(candidate, current):
    return parse_version(candidate) > parse_version(current)


def fetch_manifest(url=None, timeout=15):
    """Telecharge et valide le manifeste de mises a jour (JSON, 256 Ko max). Une requete GET, rien d'autre."""
    import urllib.request
    url = url or update_manifest_url()
    if not url:
        raise PackageError(tr("Aucune source de mises a jour n'est configuree dans cette version."))
    check_url_allowed(url)

    class Guard(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            check_url_allowed(newurl)
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    opener = urllib.request.build_opener(Guard())
    try:
        with opener.open(urllib.request.Request(url, headers={"User-Agent": "OutOfMods"}), timeout=timeout) as r:
            raw = r.read(MANIFEST_MAX_BYTES + 1)
    except Exception as e:      # noqa: BLE001  (reseau : toute erreur est presentee a l'utilisateur)
        raise PackageError(tr("connexion impossible : %s") % e)
    if len(raw) > MANIFEST_MAX_BYTES:
        raise PackageError(tr("manifeste de mises a jour trop gros"))
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError as e:
        raise PackageError(tr("manifeste de mises a jour illisible : %s") % e)
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise PackageError(tr("manifeste de mises a jour non reconnu"))
    return data


def _entry_ok(e):
    return (isinstance(e, dict) and isinstance(e.get("version"), str) and isinstance(e.get("url"), str) and isinstance(e.get("sha256"), str)
            and len(e["sha256"]) == 64 and isinstance(e.get("size"), int))


def find_updates(manifest, launcher_version, installed_mods):
    """Compare le manifeste a ce qui est installe. Renvoie {'launcher': entree|None, 'mods': [entrees avec 'installed']}. N'ecrit rien."""
    out = {"launcher": None, "mods": []}
    entry = manifest.get("launcher")
    if _entry_ok(entry) and is_newer(entry["version"], launcher_version):
        out["launcher"] = entry
    have = {m["id"]: m for m in installed_mods}
    for e in manifest.get("mods", []):
        if _entry_ok(e) and isinstance(e.get("id"), str) and e["id"] in have and is_newer(e["version"], have[e["id"]].get("version") or "0"):
            out["mods"].append(dict(e, installed=have[e["id"]].get("version") or "?"))
    return out


def note_for(entry, lang):
    notes = entry.get("notes") or {}
    return notes.get(lang) or notes.get("en") or notes.get("fr") or ""


def describe_update(kind, entry, current):
    lines = [tr("Mise a jour : %s") % entry.get("name", entry.get("id", kind)), tr("Version actuelle : %s") % current, tr("Nouvelle version : %s") % entry["version"],
             tr("Taille : environ %.1f Mo") % (entry["size"] / 2**20), tr("Adresse : %s") % entry["url"],
             tr("Le fichier sera verifie (empreinte SHA-256 annoncee par le manifeste) AVANT toute installation.")]
    return "\n".join(lines)


def prepare_launcher_update(zip_path, entry, install_dir):
    """Valide le zip de la nouvelle version du launcheur (empreinte + structure + chemins), l'extrait dans un dossier temporaire a cote
    de l'installation et renvoie {'new_dir','script','backup_dir'} (script .cmd a lancer apres la fermeture du launcheur)."""
    if sha256_file(zip_path) != entry["sha256"]:
        raise PackageError(tr("l'empreinte du fichier telecharge ne correspond pas a celle attendue : le fichier est refuse et supprime."))
    parent = os.path.dirname(os.path.normpath(install_dir))
    new_dir = os.path.join(parent, "OutOfMods_update")
    shutil.rmtree(new_dir, ignore_errors=True)
    with zipfile.ZipFile(zip_path) as z:
        names = [i.filename.replace("\\", "/") for i in z.infolist() if not i.is_dir()]
        roots = {n.split("/")[0] for n in names}
        if len(roots) != 1 or not any(n.endswith("/OutOfMods.exe") and n.count("/") == 1 for n in names):
            raise PackageError(tr("paquet de mise a jour invalide (OutOfMods.exe introuvable)"))
        root = roots.pop()
        total = 0
        for i in z.infolist():
            if i.is_dir():
                continue
            rel = i.filename.replace("\\", "/")
            parts = rel.split("/")
            if rel.startswith("/") or ".." in parts or ":" in parts[0]:
                raise PackageError(tr("chemin dangereux dans le paquet : %s") % i.filename)
            total += i.file_size
            if total > 400 * 1024 * 1024:
                raise PackageError(tr("mise a jour trop volumineuse"))
            target = os.path.normpath(os.path.join(new_dir, *parts[1:]))
            if os.path.commonpath([new_dir, target]) != os.path.normpath(new_dir):
                raise PackageError(tr("chemin dangereux dans le paquet : %s") % i.filename)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(i) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
    backup_dir = os.path.join(parent, "OutOfMods_previous")
    script = os.path.join(parent, "OutOfMods_apply_update.cmd")
    exe = os.path.join(os.path.normpath(install_dir), "OutOfMods.exe")
    lines = ["@echo off", "setlocal", "rem Applique la mise a jour du launcheur apres sa fermeture (genere par Out of Mods).",
             ":wait", 'tasklist /FI "IMAGENAME eq OutOfMods.exe" 2>nul | find /I "OutOfMods.exe" >nul', "if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait)",
             'rd /s /q "%s" 2>nul' % backup_dir,
             'robocopy "%s" "%s" /E /NFL /NDL /NJH /NJS /NP >nul' % (os.path.normpath(install_dir), backup_dir),
             'robocopy "%s" "%s" /E /NFL /NDL /NJH /NJS /NP >nul' % (new_dir, os.path.normpath(install_dir)),
             "if errorlevel 8 (echo echec de la copie & pause & exit /b 1)",
             'rd /s /q "%s" 2>nul' % new_dir, 'start "" "%s" --updated' % exe, '(goto) 2>nul & del "%~f0"']
    with open(script, "w", encoding="mbcs", newline="\r\n") as f:
        f.write("\r\n".join(lines) + "\r\n")
    return {"new_dir": new_dir, "script": script, "backup_dir": backup_dir, "files": len(names), "install_dir": os.path.normpath(install_dir)}


def describe_launcher_update(info, entry, current):
    return "\n".join([tr("Mettre a jour le launcheur : %s -> %s") % (current, entry["version"]), tr("Dossier : %s") % info["install_dir"],
                      tr("%d fichier(s) seront remplaces ; la version actuelle est conservee dans %s (retour arriere possible en la recopiant).") % (info["files"], info["backup_dir"]),
                      tr("Vos paquets ajoutes dans packages/ et vos reglages (%APPDATA%) ne sont pas touches."),
                      tr("Le launcheur va se fermer, appliquer la mise a jour puis se rouvrir tout seul.")])


def start_update_script(script):
    """Lance le script de mise a jour detache (il attend la fermeture du launcheur)."""
    import subprocess
    subprocess.Popen(["cmd", "/c", script], creationflags=0x00000008 | 0x00000200, close_fds=True)       # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP


def launch_game(game):
    """Lance le jeu via Steam (comme le bouton Jouer). A appeler seulement sur clic de l'utilisateur."""
    os.startfile("steam://rungameid/%s" % APP_ID)
