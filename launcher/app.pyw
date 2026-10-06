# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Out of Mods -- interface (tkinter). Rien n'est installe, modifie ni supprime sans que l'utilisateur ait lu le detail et confirme.

Lancer :  pythonw launcher/app.pyw        (ou l'.exe produit par PyInstaller)
Les paquets de mods (.zip) sont lus dans le dossier `packages/` a cote du programme, ou ouverts a la main.
"""
import json
import os
import sys
import tkinter as tk
import webbrowser
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core  # noqa: E402
import i18n  # noqa: E402
from i18n import tr  # noqa: E402

try:
    import sv_ttk
except ImportError:      # le theme moderne est facultatif : sans lui, l'apparence ttk standard est utilisee
    sv_ttk = None

DARK = {"bg": "#1c1c1c", "card": "#242424", "fg": "#e6e6e6", "muted": "#9a9a9a", "border": "#3a3a3a", "accent": "#4cc2ff", "ok": "#6ccb5f", "warn": "#f0b429", "err": "#ff6b6b"}
LIGHT = {"bg": "#f3f3f3", "card": "#ffffff", "fg": "#1a1a1a", "muted": "#6b6b6b", "border": "#d0d0d0", "accent": "#005fb8", "ok": "#107c10", "warn": "#b86e00", "err": "#c42b1c"}
PALETTE = dict(LIGHT)


def system_prefers_dark():
    """Windows est-il en mode d'application sombre ? (lecture du registre, sans ecriture)"""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize") as k:
            return winreg.QueryValueEx(k, "AppsUseLightTheme")[0] == 0
    except (ImportError, OSError):
        return False


APP_NAME = "Out of Mods"
APP_VERSION = "0.1.1"
BASE_DIR = os.path.dirname(sys.executable) if getattr(sys, "frozen", False) else os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR = os.path.join(getattr(sys, "_MEIPASS", BASE_DIR), "assets")      # logo / icone (embarques dans l'exe par build_launcher.py)
DATA_DIR = os.path.join(os.environ.get("APPDATA", "."), "OutOfMods")
SETTINGS = os.path.join(DATA_DIR, "settings.json")
LOG_FILE = os.path.join(DATA_DIR, "launcher.log")


def shutil_rmtree_quiet(path):
    import shutil
    shutil.rmtree(path, ignore_errors=True)


def migrate_legacy_data():
    """L'application s'appelait « OutOfOre Launcher » : on reprend ses reglages et son journal une seule fois (renommage du dossier)."""
    old = os.path.join(os.environ.get("APPDATA", "."), "OutOfOreLauncher")
    if os.path.isdir(old) and not os.path.isdir(DATA_DIR):
        try:
            os.replace(old, DATA_DIR)
        except OSError:
            pass


def load_settings():
    migrate_legacy_data()
    return core.read_json(SETTINGS) or {}


def save_settings(data):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


class ConfirmDialog(tk.Toplevel):
    """Fenetre modale : affiche le detail exact de ce qui va etre fait. « Annuler » est le bouton par defaut."""

    def __init__(self, parent, title, text, confirm_label):
        super().__init__(parent)
        self.title(title)
        self.geometry("700x470")
        self.configure(bg=PALETTE["bg"])
        self.transient(parent)
        self.result = False
        body = ttk.Frame(self, padding=(16, 14, 16, 12))
        body.pack(fill="both", expand=True)
        row = ttk.Frame(body)
        row.pack(side="bottom", fill="x", pady=(12, 0))
        cancel = ttk.Button(row, text=tr("Annuler"), command=self.destroy)
        cancel.pack(side="right")
        ttk.Button(row, text=confirm_label, command=self.ok, style="Accent.TButton").pack(side="right", padx=8)
        ttk.Label(row, text=tr("Rien ne sera modifie tant que vous ne confirmez pas."), foreground=PALETTE["muted"]).pack(side="left")
        frame = ttk.Frame(body)
        frame.pack(side="top", fill="both", expand=True)
        box = tk.Text(frame, wrap="word", font=("Consolas", 9), bg=PALETTE["card"], fg=PALETTE["fg"], relief="flat", highlightthickness=1,
                      highlightbackground=PALETTE["border"], padx=10, pady=8)
        sb = ttk.Scrollbar(frame, command=box.yview)
        box.configure(yscrollcommand=sb.set)
        box.insert("1.0", text)
        box.configure(state="disabled")
        sb.pack(side="right", fill="y")
        box.pack(side="left", fill="both", expand=True)
        cancel.focus_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()
        self.wait_window(self)

    def ok(self):
        self.result = True
        self.destroy()


class App:
    def __init__(self, root):
        self.root = root
        root.title("%s %s" % (APP_NAME, APP_VERSION))
        try:
            root.iconbitmap(os.path.join(ASSETS_DIR, "icon.ico"))       # icone de la fenetre (facultative : sans le fichier, icone par defaut)
        except Exception:
            pass
        try:
            self.icon_img = tk.PhotoImage(file=os.path.join(ASSETS_DIR, "logo_256.png"))    # icone de la barre des taches (reference gardee)
            root.iconphoto(True, self.icon_img)
        except Exception:
            pass
        root.geometry("900x960+70+10")
        root.minsize(820, 760)
        self.settings = load_settings()
        i18n.set_language(self.settings.get("language") or i18n.detect())
        self.log_lines = []
        self.game = None
        self.ue = None
        self.installed = []
        self.packages = []
        self.pending_updates = None
        self.build()
        self.refresh()
        if "--updated" in sys.argv:
            self.log(tr("Le launcheur a ete mis a jour vers la version %s.") % APP_VERSION)
        self.startup_check()

    # ------------------------------------------------------------------ theme (clair / sombre, suit Windows par defaut)
    def apply_theme(self):
        name = self.settings.get("theme") or ("dark" if system_prefers_dark() else "light")
        self.theme = name
        if sv_ttk is not None:
            try:
                sv_ttk.set_theme(name)
            except Exception:      # noqa: BLE001
                pass
        PALETTE.update(DARK if name == "dark" else LIGHT)
        self.root.configure(bg=PALETTE["bg"])
        for widget in getattr(self, "themed_text", []):
            try:
                self.style_text(widget)
            except tk.TclError:      # widget deja detruit (reconstruction de l'interface)
                pass

    def style_text(self, widget):
        widget.configure(bg=PALETTE["card"], fg=PALETTE["fg"], insertbackground=PALETTE["fg"], relief="flat", highlightthickness=1,
                         highlightbackground=PALETTE["border"], highlightcolor=PALETTE["accent"], padx=8, pady=6)

    def style_tree_tags(self):
        self.tree.tag_configure("on", foreground=PALETTE["ok"])
        self.tree.tag_configure("off", foreground=PALETTE["muted"])
        self.tree.tag_configure("warn", foreground=PALETTE["warn"])

    def toggle_theme(self):
        self.settings["theme"] = "light" if self.theme == "dark" else "dark"
        save_settings(self.settings)
        self.rebuild()

    # ------------------------------------------------------------------ interface
    def rebuild(self):
        """Reconstruit toute l'interface (langue, theme) en conservant le journal affiche."""
        for child in self.root.winfo_children():
            child.destroy()
        self.build()
        for text, level in self.log_lines:
            self.log_insert(text, level)
        self.refresh()

    def change_language(self, event=None):
        lang = "en" if self.lang_box.get().startswith("English") else "fr"
        if lang == i18n.get_language():
            return
        i18n.set_language(lang)
        self.settings["language"] = lang
        save_settings(self.settings)
        self.rebuild()

    def build(self):
        self.themed_text = []
        self.apply_theme()
        outer = ttk.Frame(self.root, padding=(18, 12, 18, 14))
        outer.pack(fill="both", expand=True)

        # --- banniere (facultative : sans le fichier, titre texte)
        head = ttk.Frame(outer)
        head.pack(fill="x", pady=(0, 10))
        self.banner_img = None
        try:
            self.banner_img = tk.PhotoImage(file=os.path.join(ASSETS_DIR, "banner_header.png"))
        except Exception:
            self.banner_img = None
        if self.banner_img:
            ttk.Label(head, image=self.banner_img).pack(side="left")
            ttk.Label(head, text="  v%s" % APP_VERSION, foreground=PALETTE["muted"]).pack(side="left", anchor="s", pady=(0, 6))
        else:
            ttk.Label(head, text="Out of", font=("Segoe UI Semibold", 20)).pack(side="left")
            ttk.Label(head, text=" Mods", font=("Segoe UI Semibold", 20), foreground=PALETTE["accent"]).pack(side="left")
            ttk.Label(head, text="  v%s" % APP_VERSION, foreground=PALETTE["muted"]).pack(side="left", pady=(10, 0))
        self.lang_box = ttk.Combobox(head, values=["Français", "English"], width=9, state="readonly")
        self.lang_box.set("English" if i18n.get_language() == "en" else "Français")
        self.lang_box.bind("<<ComboboxSelected>>", self.change_language)
        self.lang_box.pack(side="right")
        ttk.Button(head, text="☀" if self.theme == "dark" else "☾", width=3, command=self.toggle_theme).pack(side="right", padx=(0, 8))
        self.btn_updates = ttk.Button(head, text="⟳  " + tr("Mises a jour..."), command=self.check_updates)
        self.btn_updates.pack(side="right", padx=(0, 8))

        # --- carte Jeu
        game = ttk.LabelFrame(outer, text=tr("Jeu"), padding=(14, 8, 14, 10))
        game.pack(fill="x", pady=(0, 10))
        st = ttk.Frame(game)
        st.pack(fill="x")
        self.dot_game = ttk.Label(st, text="●", font=("Segoe UI", 11))
        self.dot_game.grid(row=0, column=0, sticky="w")
        self.lbl_game = ttk.Label(st, text="", justify="left")
        self.lbl_game.grid(row=0, column=1, sticky="w", padx=(6, 0))
        self.dot_ue = ttk.Label(st, text="●", font=("Segoe UI", 11))
        self.dot_ue.grid(row=1, column=0, sticky="nw", pady=(4, 0))
        self.lbl_ue = ttk.Label(st, text="", justify="left", wraplength=760)
        self.lbl_ue.grid(row=1, column=1, sticky="w", padx=(6, 0), pady=(4, 0))
        row = ttk.Frame(game)
        row.pack(fill="x", pady=(10, 0))
        self.btn_launch = ttk.Button(row, text="▶  " + tr("Lancer le jeu"), command=self.launch, style="Accent.TButton")
        self.btn_launch.pack(side="left")
        ttk.Button(row, text=tr("Dossier des mods"), command=self.open_mods_dir).pack(side="left", padx=8)
        ttk.Button(row, text=tr("Choisir le dossier du jeu..."), command=self.choose_game).pack(side="left")
        ttk.Button(row, text="⟳  " + tr("Actualiser"), command=self.refresh).pack(side="right")
        self.ue_row = ttk.Frame(game)
        self.btn_ue_dl = ttk.Button(self.ue_row, text=tr("Installer UE4SS (telechargement)..."), command=self.ue4ss_download, style="Accent.TButton")
        self.btn_ue_file = ttk.Button(self.ue_row, text=tr("Installer UE4SS depuis un fichier..."), command=self.ue4ss_from_file)
        self.btn_ue_rm = ttk.Button(self.ue_row, text=tr("Retirer UE4SS..."), command=self.ue4ss_remove)
        self.btn_ue_page = ttk.Button(self.ue_row, text=tr("Page d'UE4SS"), command=lambda: webbrowser.open(core.UE4SS_SOURCES[core.DEFAULT_SOURCE]["page"]))

        # --- carte Mods
        mods = ttk.LabelFrame(outer, text=tr("Mods installes"), padding=(14, 8, 14, 10))
        mods.pack(fill="both", expand=True, pady=(0, 10))
        box = ttk.Frame(mods)
        box.pack(fill="both", expand=True)
        cols = ("name", "version", "state", "origin", "compat")
        self.tree = ttk.Treeview(box, columns=cols, show="headings", height=6, selectmode="browse")
        for c, t, w in (("name", tr("Mod"), 200), ("version", "Version", 70), ("state", tr("Etat"), 110), ("origin", tr("Origine"), 120), ("compat", tr("Compatibilite"), 320)):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=w, anchor="w")
        sb = ttk.Scrollbar(box, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.style_tree_tags()
        row = ttk.Frame(mods)
        row.pack(fill="x", pady=(8, 0))
        ttk.Button(row, text=tr("Activer / desactiver..."), command=self.toggle_selected).pack(side="left")
        ttk.Button(row, text=tr("Desinstaller..."), command=self.uninstall_selected).pack(side="left", padx=8)

        # --- carte Paquets
        pk = ttk.LabelFrame(outer, text=tr("Paquets disponibles (dossier packages/ ou fichier .zip)"), padding=(14, 8, 14, 10))
        pk.pack(fill="x", pady=(0, 10))
        self.pk_tree = ttk.Treeview(pk, columns=("name", "version", "file"), show="headings", height=2, selectmode="browse")
        for c, t, w in (("name", tr("Paquet"), 260), ("version", "Version", 80), ("file", tr("Fichier"), 380)):
            self.pk_tree.heading(c, text=t)
            self.pk_tree.column(c, width=w, anchor="w")
        self.pk_tree.pack(fill="x")
        self.pk_tree.bind("<<TreeviewSelect>>", lambda e: self.show_package())
        # zone de description a hauteur FIXE (3 lignes) : sa taille ne change pas selon le paquet, la carte « Journal » en dessous n'est plus rognee
        desc_box = ttk.Frame(pk, height=62)
        desc_box.pack(fill="x", pady=(6, 0))
        desc_box.pack_propagate(False)
        self.lbl_pkg = ttk.Label(desc_box, text="", justify="left", wraplength=780, foreground=PALETTE["muted"])
        self.lbl_pkg.pack(anchor="nw")
        row = ttk.Frame(pk)
        row.pack(fill="x", pady=(8, 0))
        self.btn_install = ttk.Button(row, text=tr("Installer..."), command=self.install_selected, style="Accent.TButton")
        self.btn_install.pack(side="left")
        ttk.Button(row, text=tr("Ouvrir un paquet (.zip)..."), command=self.open_package).pack(side="left", padx=8)

        # --- carte Journal
        logf = ttk.LabelFrame(outer, text=tr("Journal (rien n'est envoye sur Internet)"), padding=(14, 8, 14, 10))
        logf.pack(fill="both", expand=True)
        self.log_box = tk.Text(logf, height=6, font=("Consolas", 9), state="disabled", wrap="word")
        self.themed_text.append(self.log_box)
        self.style_text(self.log_box)
        self.log_box.pack(fill="both", expand=True)
        for level, key in (("ok", "ok"), ("warn", "warn"), ("error", "err"), ("info", "fg")):
            self.log_box.tag_configure(level, foreground=PALETTE[key])
        self.log_box.tag_configure("time", foreground=PALETTE["muted"])
        row = ttk.Frame(logf)
        row.pack(fill="x", pady=(8, 0))
        ttk.Button(row, text=tr("Ouvrir le fichier journal"), command=self.open_log_file).pack(side="left")
        ttk.Button(row, text=tr("Copier le rapport de diagnostic"), command=self.copy_report).pack(side="left", padx=8)
        ttk.Button(row, text=tr("Effacer l'affichage"), command=self.clear_log_view).pack(side="left")
        self.root.update_idletasks()

    # ------------------------------------------------------------------ journal (affichage colore + fichier avec rotation)
    OK_PREFIXES = ("installe", "installed", "ue4ss installe", "ue4ss installed", "desinstalle", "uninstalled", "restaure", "restored", "ue4ss retire", "ue4ss removed",
                   "telecharge", "downloaded", "telechargement verifie", "download verified", "jeu lance", "game launched", "active", "enabled", "desactive", "disabled")

    @staticmethod
    def infer_level(text):
        low = text.lower()
        if any(w in low for w in ("echec", "failed", "refus", "refused", "impossible")):
            return "error"
        if any(w in low for w in ("annul", "cancel", "attention", "warning")):
            return "warn"
        if low.startswith(App.OK_PREFIXES):
            return "ok"
        return "info"

    def log_insert(self, text, level):
        import time
        self.log_box.configure(state="normal")
        self.log_box.insert("end", time.strftime("%H:%M:%S  "), "time")
        self.log_box.insert("end", text + "\n", level)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def log(self, text, level=None):
        import time
        level = level or self.infer_level(text)
        self.log_lines.append((text, level))
        self.log_insert(text, level)
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 1_000_000:       # rotation : un seul fichier .old
                os.replace(LOG_FILE, LOG_FILE + ".old")
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write("%s [%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), level.upper(), text))
        except OSError:
            pass

    def clear_log_view(self):
        self.log_lines = []
        self.log_box.configure(state="normal")
        self.log_box.delete("1.0", "end")
        self.log_box.configure(state="disabled")

    def open_log_file(self):
        os.makedirs(DATA_DIR, exist_ok=True)
        if not os.path.exists(LOG_FILE):
            open(LOG_FILE, "a", encoding="utf-8").close()
        os.startfile(LOG_FILE)

    def diagnostic_report(self):
        import platform
        import time
        g, ue = self.game or {}, self.ue or {}
        lines = ["Out of Mods %s -- diagnostic report" % APP_VERSION, time.strftime("%Y-%m-%d %H:%M:%S"), "Windows: %s" % platform.platform(),
                 "Language: %s   Theme: %s" % (i18n.get_language(), getattr(self, "theme", "?")), "",
                 "Game: %s" % (g.get("dir") or "not found"), "Steam build: %s   Branch: %s   Updated: %s" % (g.get("build_id"), g.get("branch"), g.get("updated")),
                 "UE4SS: installed=%s layout=%s" % (ue.get("installed"), ue.get("layout")), "UE4SS problems: %s" % (ue.get("problems") or "none")]
        manifest = core.read_json(os.path.join(g["dir"], core.WIN64, core.UE4SS_MANIFEST)) if g.get("dir") else None
        if manifest:
            lines.append("UE4SS installed by launcher: %s (%s) sha256 %s" % (manifest.get("installedAt"), manifest.get("layout"), (manifest.get("sha256") or "")[:16]))
        lines += ["", "Mods:"]
        for m in self.installed:
            warns = core.compat_warnings(m["meta"], self.game) if m["meta"] else []
            lines.append("  %s %s | %s | %s | %s" % (m["id"], m["version"] or "-", "enabled" if m["enabled"] else "disabled", "launcher" if m["managed"] else "manual", "; ".join(warns) or "ok"))
        lines += ["", "Packages:"] + ["  %s %s (%s)" % (p["id"], p["meta"].get("version"), p["sha256"][:12]) for p in self.packages]
        lines += ["", "Last log lines:"] + ["  [%s] %s" % (lv, tx) for tx, lv in self.log_lines[-40:]]
        return "\n".join(lines)

    def copy_report(self):
        self.root.clipboard_clear()
        self.root.clipboard_append(self.diagnostic_report())
        self.log(tr("Rapport de diagnostic copie dans le presse-papiers (il contient des chemins locaux : relisez-le avant de le partager)."))
        messagebox.showinfo(APP_NAME, tr("Rapport de diagnostic copie dans le presse-papiers (il contient des chemins locaux : relisez-le avant de le partager)."))

    # ------------------------------------------------------------------ etat (lecture seule)
    def refresh(self):
        manual = self.settings.get("game_dir")
        forced = sys.argv[sys.argv.index("--game-dir") + 1] if "--game-dir" in sys.argv and sys.argv.index("--game-dir") + 1 < len(sys.argv) else None
        self.game = (core.game_from_dir(forced) if forced else None) or core.find_game() or (core.game_from_dir(manual) if manual else None)
        if self.game:
            g = self.game
            self.dot_game.config(foreground=PALETTE["ok"])
            self.lbl_game.config(text=tr("Jeu : %s\nBuild Steam : %s   Branche : %s   Derniere mise a jour : %s") % (
                g["dir"], g["build_id"] or "?", g["branch"] or "?", g["updated"] or "?"))
            self.ue = core.find_ue4ss(g["dir"])
            if self.ue["installed"]:
                self.dot_ue.config(foreground=PALETTE["ok"])
                self.lbl_ue.config(text=tr("UE4SS : installe  (%s)") % self.ue["mods_dir"])
                managed = os.path.isfile(os.path.join(g["dir"], core.WIN64, core.UE4SS_MANIFEST))
                self.show_ue_buttons([self.btn_ue_rm] if managed else [])
            else:
                self.dot_ue.config(foreground=PALETTE["warn"])
                self.lbl_ue.config(text=tr("UE4SS : NON installe -- %s.\nIl est necessaire pour charger les mods. Rien n'est installe sans votre accord : vous verrez la liste exacte des fichiers avant de confirmer.") % "; ".join(self.ue["problems"]))
                self.show_ue_buttons([self.btn_ue_dl, self.btn_ue_file, self.btn_ue_page])
        else:
            self.dot_game.config(foreground=PALETTE["err"])
            self.dot_ue.config(foreground=PALETTE["muted"])
            self.lbl_game.config(text=tr("Jeu introuvable. Cliquez sur « Choisir le dossier du jeu... » (le dossier qui contient OutOfOre.exe)."))
            self.lbl_ue.config(text="")
            self.ue = None
            self.show_ue_buttons([])
        self.btn_launch.state(["!disabled"] if self.game else ["disabled"])
        self.installed = core.list_installed(self.ue["mods_dir"]) if self.ue and self.ue["installed"] else []
        self.tree.delete(*self.tree.get_children())
        for i, m in enumerate(self.installed):
            warns = core.compat_warnings(m["meta"], self.game) if m["meta"] else []
            compat = "; ".join(warns) if warns else (tr("ok") if m["meta"] else tr("(pas de mod.json)"))
            state = ("●  " + tr("active")) if m["enabled"] else ("○  " + tr("desactive"))
            tag = "warn" if warns else ("on" if m["enabled"] else "off")
            self.tree.insert("", "end", iid=str(i), tags=(tag,), values=(m["name"], m["version"] or "-", state,
                                                                          tr("ce launcheur") if m["managed"] else tr("manuel"), compat))
        self.scan_packages()

    def show_ue_buttons(self, buttons):
        for b in (self.btn_ue_dl, self.btn_ue_file, self.btn_ue_rm, self.btn_ue_page):
            b.pack_forget()
        self.ue_row.pack_forget()
        if buttons:
            self.ue_row.pack(fill="x", pady=(8, 0))
            for b in buttons:
                b.pack(side="left", padx=(0, 8))

    def scan_packages(self):
        self.packages = []
        self.pk_tree.delete(*self.pk_tree.get_children())
        seen = set()
        for folder in (os.path.join(BASE_DIR, "packages"), os.path.join(os.path.dirname(BASE_DIR), "dist")):
            if not os.path.isdir(folder):
                continue
            for n in sorted(os.listdir(folder)):
                p = os.path.join(folder, n)
                if n.lower().endswith(".zip") and p not in seen:
                    seen.add(p)
                    self.add_package(p, quiet=True)
        self.show_package()

    def add_package(self, path, quiet=False):
        try:
            pkg = core.read_package(path)
        except core.PackageError as e:
            if not quiet:
                messagebox.showerror(APP_NAME, tr("Paquet refuse :\n%s") % e)
                self.log(tr("paquet refuse (%s) : %s") % (os.path.basename(path), e))
            return None
        self.packages.append(pkg)
        self.pk_tree.insert("", "end", iid=str(len(self.packages) - 1),
                            values=(pkg["meta"].get("name", pkg["id"]), pkg["meta"].get("version", "?"), os.path.basename(path)))
        return pkg

    def current_package(self):
        sel = self.pk_tree.selection()
        return self.packages[int(sel[0])] if sel else None

    def show_package(self):
        pkg = self.current_package()
        if not pkg:
            self.lbl_pkg.config(text=tr("Selectionnez un paquet pour voir sa description."))
            self.btn_install.state(["disabled"])
            return
        m = pkg["meta"]
        warns = core.compat_warnings(m, self.game)
        desc = (m.get("description_en") if i18n.get_language() == "en" else None) or m.get("description", "")     # langue de l'interface si le paquet la fournit
        text = tr("%s\n%d fichier(s), %d Ko, sha256 %s...\n") % (desc, len(pkg["files"]), pkg["size"] // 1024, pkg["sha256"][:12])
        if warns:
            text += tr("Attention : ") + "; ".join(warns)
        self.lbl_pkg.config(text=text)
        self.btn_install.state(["!disabled"] if self.ue and self.ue["installed"] else ["disabled"])

    # ------------------------------------------------------------------ mises a jour (reseau seulement apres accord)
    def run_blocking(self, title, fn):
        """Execute `fn` dans un thread pendant qu'une petite fenetre « en cours » reste affichee. Renvoie (resultat, erreur)."""
        import threading
        win = tk.Toplevel(self.root)
        win.title(title)
        win.transient(self.root)
        win.resizable(False, False)
        body = ttk.Frame(win, padding=20)
        body.pack()
        ttk.Label(body, text=tr("Recherche en cours...")).pack(pady=(0, 10))
        bar = ttk.Progressbar(body, length=300, mode="indeterminate")
        bar.pack()
        bar.start(12)
        state = {"done": False, "result": None, "error": None}

        def work():
            try:
                state["result"] = fn()
            except Exception as e:      # noqa: BLE001
                state["error"] = e
            state["done"] = True

        threading.Thread(target=work, daemon=True).start()
        win.grab_set()

        def poll():
            if state["done"]:
                win.destroy()
            else:
                win.after(100, poll)

        poll()
        win.wait_window(win)
        return state["result"], state["error"]

    def check_updates(self):
        url = core.update_manifest_url()
        if not url:
            messagebox.showinfo(APP_NAME, tr("Aucune source de mises a jour n'est configuree dans cette version."))
            return
        if not ConfirmDialog(self.root, tr("Rechercher les mises a jour ?"),
                             tr("Une connexion Internet sera ouverte vers :\n%s\nUn seul petit fichier de description (quelques Ko) est telecharge ; rien n'est envoye sur vous. Rien n'est installe a cette etape.") % url,
                             tr("Rechercher")).result:
            return
        manifest, err = self.run_blocking(tr("Mises a jour"), lambda: core.fetch_manifest(url))
        if err:
            self.log(tr("recherche de mises a jour impossible : %s") % err)
            messagebox.showerror(APP_NAME, tr("Recherche impossible :\n%s") % err)
            return
        self.show_updates(manifest)

    def show_updates(self, manifest):
        upd = core.find_updates(manifest, APP_VERSION, self.installed)
        self.pending_updates = upd
        count = (1 if upd["launcher"] else 0) + len(upd["mods"])
        self.update_button_text(count)
        if not count:
            self.log(tr("Tout est a jour."))
            messagebox.showinfo(APP_NAME, tr("Tout est a jour."))
            return
        win = tk.Toplevel(self.root)
        win.title(tr("Mises a jour disponibles"))
        win.geometry("760x420")
        win.configure(bg=PALETTE["bg"])
        win.transient(self.root)
        body = ttk.Frame(win, padding=16)
        body.pack(fill="both", expand=True)
        tree = ttk.Treeview(body, columns=("item", "cur", "new", "size"), show="headings", height=6, selectmode="browse")
        for c, t, w in (("item", tr("Element"), 280), ("cur", tr("Actuelle"), 100), ("new", tr("Nouvelle"), 100), ("size", tr("Taille"), 100)):
            tree.heading(c, text=t)
            tree.column(c, width=w, anchor="w")
        tree.pack(fill="x")
        rows = []
        if upd["launcher"]:
            e = upd["launcher"]
            rows.append(("launcher", e, APP_VERSION))
            tree.insert("", "end", iid="0", values=(tr("Launcheur"), APP_VERSION, e["version"], "%.1f Mo" % (e["size"] / 2**20)))
        for e in upd["mods"]:
            rows.append(("mod", e, e["installed"]))
            tree.insert("", "end", iid=str(len(rows) - 1), values=(e.get("name", e["id"]), e["installed"], e["version"], "%.1f Mo" % (e["size"] / 2**20)))
        notes = tk.Text(body, height=8, wrap="word", font=("Segoe UI", 9))
        self.style_text(notes)
        notes.configure(state="disabled")
        notes.pack(fill="both", expand=True, pady=(10, 0))

        def show_notes(_e=None):
            sel = tree.selection()
            text = core.note_for(rows[int(sel[0])][1], i18n.get_language()) if sel else ""
            notes.configure(state="normal")
            notes.delete("1.0", "end")
            notes.insert("1.0", text)
            notes.configure(state="disabled")

        tree.bind("<<TreeviewSelect>>", show_notes)
        row = ttk.Frame(body)
        row.pack(fill="x", pady=(10, 0))

        def go():
            sel = tree.selection()
            if not sel:
                return
            kind, entry, current = rows[int(sel[0])]
            win.destroy()
            (self.update_launcher if kind == "launcher" else self.update_mod)(entry, current)

        ttk.Button(row, text=tr("Mettre a jour..."), command=go, style="Accent.TButton").pack(side="right")
        ttk.Button(row, text=tr("Annuler"), command=win.destroy).pack(side="right", padx=8)
        var = tk.BooleanVar(value=bool(self.settings.get("check_updates_at_start")))

        def save_pref():
            self.settings["check_updates_at_start"] = bool(var.get())
            save_settings(self.settings)

        ttk.Checkbutton(row, text=tr("Verifier au demarrage (une requete vers l'adresse de mise a jour a chaque lancement)"), variable=var, command=save_pref).pack(side="left")
        tree.selection_set("0")
        show_notes()

    def update_button_text(self, count):
        if getattr(self, "btn_updates", None) is not None and self.btn_updates.winfo_exists():
            label = tr("Mises a jour...") if not count else (tr("Mises a jour...") + " (%d)" % count)
            self.btn_updates.config(text="⟳  " + label, style="Accent.TButton" if count else "TButton")

    def download_verified(self, entry):
        """Telecharge l'archive d'une mise a jour et verifie son empreinte (annoncee par le manifeste) ; supprime le fichier si elle ne correspond pas."""
        dest = os.path.join(os.environ.get("TEMP", DATA_DIR), "OutOfMods", os.path.basename(entry["url"].split("?")[0]) or "update.zip")
        path = self.run_download(entry["url"], dest)
        if not path:
            return None
        if core.sha256_file(path) != entry["sha256"]:
            self.remove_quiet(path)
            self.log(tr("telechargement refuse : %s") % tr("l'empreinte du fichier telecharge ne correspond pas a celle attendue : le fichier est refuse et supprime."))
            messagebox.showerror(APP_NAME, tr("Fichier refuse :\n%s") % tr("l'empreinte du fichier telecharge ne correspond pas a celle attendue : le fichier est refuse et supprime."))
            return None
        self.log(tr("telechargement verifie (sha256 %s...)") % entry["sha256"][:12])
        return path

    def update_mod(self, entry, current):
        if not (self.ue and self.ue["installed"]):
            return
        if not ConfirmDialog(self.root, tr("Telecharger"), core.describe_update("mod", entry, current), tr("Telecharger")).result:
            return
        path = self.download_verified(entry)
        if not path:
            return
        try:
            pkg = core.read_package(path)
            plan = core.plan_install(pkg, self.ue["mods_dir"])
            if ConfirmDialog(self.root, tr("Confirmer l'installation"), core.describe_plan(plan), tr("Installer")).result:
                core.do_install(plan, self.log)
                self.log(tr("installe : %s (%d fichiers)") % (plan["dest"], len(plan["files"])))
        except Exception as e:      # noqa: BLE001
            messagebox.showerror(APP_NAME, tr("Echec de la mise a jour : %s") % e)
            self.log(tr("ECHEC de la mise a jour : %s") % e)
        self.remove_quiet(path)
        self.refresh()

    def update_launcher(self, entry, current):
        if not getattr(sys, "frozen", False):
            messagebox.showinfo(APP_NAME, tr("La mise a jour du launcheur n'est possible que depuis la version installee (.exe), pas depuis le code Python."))
            return
        if not ConfirmDialog(self.root, tr("Telecharger"), core.describe_update("launcher", dict(entry, name=tr("Launcheur")), current), tr("Telecharger")).result:
            return
        path = self.download_verified(entry)
        if not path:
            return
        try:
            info = core.prepare_launcher_update(path, entry, BASE_DIR)
        except core.PackageError as e:
            self.remove_quiet(path)
            messagebox.showerror(APP_NAME, tr("Echec de la mise a jour : %s") % e)
            self.log(tr("ECHEC de la mise a jour : %s") % e)
            return
        if not ConfirmDialog(self.root, tr("Mettre a jour le launcheur"), core.describe_launcher_update(info, entry, current), tr("Mettre a jour et redemarrer")).result:
            shutil_rmtree_quiet(info["new_dir"])
            self.remove_quiet(info["script"])
            self.remove_quiet(path)
            self.log(tr("mise a jour du launcheur annulee"))
            return
        self.remove_quiet(path)
        self.log(tr("mise a jour du launcheur : fermeture et remplacement des fichiers"))
        core.start_update_script(info["script"])
        self.root.destroy()
        sys.exit(0)

    def startup_check(self):
        """Verification au demarrage : SEULEMENT si l'utilisateur l'a activee (case a cocher de la fenetre des mises a jour). Aucune installation."""
        if not self.settings.get("check_updates_at_start") or not core.update_manifest_url():
            return
        import threading

        def work():
            try:
                manifest = core.fetch_manifest()
            except Exception:      # noqa: BLE001  (hors ligne : silence)
                return
            upd = core.find_updates(manifest, APP_VERSION, self.installed)
            count = (1 if upd["launcher"] else 0) + len(upd["mods"])
            if count:
                self.root.after(0, lambda: (self.update_button_text(count), self.log(tr("Des mises a jour sont disponibles (%d).") % count)))

        threading.Thread(target=work, daemon=True).start()

    # ------------------------------------------------------------------ actions (chacune demande confirmation avant d'ecrire)
    def launch(self):
        if messagebox.askyesno(APP_NAME, tr("Lancer Out of Ore via Steam ?")):
            core.launch_game(self.game)
            self.log(tr("jeu lance via Steam"))

    def open_mods_dir(self):
        if self.ue and self.ue["mods_dir"]:
            os.startfile(self.ue["mods_dir"])

    def choose_game(self):
        d = filedialog.askdirectory(title=tr("Dossier du jeu (celui qui contient OutOfOre.exe)"))
        if not d:
            return
        if not core.game_from_dir(d):
            messagebox.showerror(APP_NAME, tr("Ce dossier ne ressemble pas a Out of Ore (OutOfOre\\Binaries\\Win64\\OutOfOre-Win64-Shipping.exe introuvable)."))
            return
        self.settings["game_dir"] = d
        save_settings(self.settings)
        self.log(tr("dossier du jeu memorise : %s") % d)
        self.refresh()

    def open_package(self):
        f = filedialog.askopenfilename(title=tr("Paquet de mod"), filetypes=[(tr("Paquet zip"), "*.zip")])
        if f:
            pkg = self.add_package(f)
            if pkg:
                self.pk_tree.selection_set(str(len(self.packages) - 1))
                self.show_package()

    def install_selected(self):
        pkg = self.current_package()
        if not pkg or not (self.ue and self.ue["installed"]):
            return
        plan = core.plan_install(pkg, self.ue["mods_dir"])
        extra = core.compat_warnings(pkg["meta"], self.game)
        text = core.describe_plan(plan) + (tr("\n\nATTENTION : ") + "; ".join(extra) if extra else "")
        if ConfirmDialog(self.root, tr("Confirmer l'installation"), text, tr("Installer")).result:
            try:
                core.do_install(plan, self.log)
            except Exception as e:      # noqa: BLE001
                messagebox.showerror(APP_NAME, tr("Echec de l'installation : %s") % e)
                self.log(tr("ECHEC installation : %s") % e)
            self.refresh()

    # ------------------------------------------------------------------ UE4SS : installation proposee (jamais automatique)
    def ue4ss_download(self):
        if not self.game:
            return
        if core.is_game_running():
            messagebox.showinfo(APP_NAME, tr("Le jeu est ouvert : fermez-le avant d'installer UE4SS."))
            return
        src = core.UE4SS_SOURCES[core.DEFAULT_SOURCE]
        if not ConfirmDialog(self.root, tr("Telecharger UE4SS ?"), core.describe_download(src), tr("Telecharger")).result:
            return
        dest = os.path.join(os.environ.get("TEMP", DATA_DIR), "OutOfMods", os.path.basename(src["url"]))
        zip_path = self.run_download(src["url"], dest)
        if not zip_path:
            return
        kit = None
        try:
            if core.sha256_file(zip_path) != src["sha256"]:
                raise core.PackageError(tr("l'empreinte du fichier telecharge ne correspond pas a celle attendue : le fichier est refuse et supprime."))
            kit = core.read_ue4ss_zip(zip_path)
        except core.PackageError as e:
            self.log(tr("telechargement refuse : %s") % e)
            messagebox.showerror(APP_NAME, tr("Fichier refuse :\n%s") % e)
            self.remove_quiet(zip_path)
            return
        self.log(tr("telechargement verifie (sha256 %s...)") % kit["sha256"][:12])
        self.finish_ue4ss_install(kit)
        self.remove_quiet(zip_path)

    def ue4ss_from_file(self):
        if not self.game:
            return
        f = filedialog.askopenfilename(title=tr("Zip UE4SS (release officielle ou kit communautaire)"), filetypes=[(tr("Zip"), "*.zip")])
        if not f:
            return
        try:
            kit = core.read_ue4ss_zip(f)
        except core.PackageError as e:
            messagebox.showerror(APP_NAME, tr("Fichier refuse :\n%s") % e)
            self.log(tr("zip UE4SS refuse : %s") % e)
            return
        self.finish_ue4ss_install(kit)

    def finish_ue4ss_install(self, kit):
        """Etape commune : montre le plan exact, demande confirmation, installe."""
        plan = core.plan_ue4ss_install(kit, self.game["dir"])
        if plan.get("refused"):
            messagebox.showinfo(APP_NAME, plan["refused"])
            return
        if not ConfirmDialog(self.root, tr("Confirmer l'installation d'UE4SS"), core.describe_ue4ss_plan(plan), tr("Installer UE4SS")).result:
            self.log(tr("installation d'UE4SS annulee"))
            return
        try:
            core.do_ue4ss_install(plan, self.log)
        except Exception as e:      # noqa: BLE001
            messagebox.showerror(APP_NAME, tr("Echec de l'installation d'UE4SS : %s") % e)
            self.log(tr("ECHEC installation UE4SS : %s") % e)
        self.refresh()

    def ue4ss_remove(self):
        plan = core.plan_ue4ss_uninstall(self.game["dir"])
        if plan["refused"]:
            messagebox.showinfo(APP_NAME, plan["refused"])
            return
        if ConfirmDialog(self.root, tr("Confirmer le retrait d'UE4SS"), core.describe_ue4ss_uninstall(plan), tr("Retirer UE4SS")).result:
            try:
                core.do_ue4ss_uninstall(plan, self.log)
            except Exception as e:      # noqa: BLE001
                messagebox.showerror(APP_NAME, tr("Echec : %s") % e)
                self.log(tr("ECHEC retrait UE4SS : %s") % e)
            self.refresh()

    @staticmethod
    def remove_quiet(path):
        try:
            os.remove(path)
        except OSError:
            pass

    def run_download(self, url, dest):
        """Telecharge dans un thread avec une barre de progression et un bouton Annuler. Renvoie le chemin ou None."""
        import queue
        import threading
        win = tk.Toplevel(self.root)
        win.title(tr("Telechargement"))
        win.transient(self.root)
        win.resizable(False, False)
        ttk.Label(win, text=tr("Telechargement en cours (annulable)...")).pack(padx=16, pady=(14, 4))
        bar = ttk.Progressbar(win, length=360, maximum=100)
        bar.pack(padx=16, pady=4)
        txt = ttk.Label(win, text="")
        txt.pack()
        state = {"cancel": False, "done": False, "error": None, "bytes": 0, "total": 0}
        q = queue.Queue()

        def progress(done, total):
            state["bytes"], state["total"] = done, total
            return not state["cancel"]

        def work():
            try:
                core.download_file(url, dest, progress)
            except Exception as e:      # noqa: BLE001
                state["error"] = str(e)
            state["done"] = True
            q.put(1)

        def cancel():
            state["cancel"] = True

        ttk.Button(win, text=tr("Annuler"), command=cancel).pack(pady=10)
        win.protocol("WM_DELETE_WINDOW", cancel)
        threading.Thread(target=work, daemon=True).start()
        win.grab_set()

        def poll():
            if state["total"]:
                bar["value"] = 100.0 * state["bytes"] / state["total"]
            txt.config(text="%.1f Mo" % (state["bytes"] / 2**20))
            if state["done"]:
                win.destroy()
            else:
                win.after(100, poll)

        poll()
        win.wait_window(win)
        if state["error"]:
            self.log(tr("telechargement : %s") % state["error"])
            if not state["cancel"]:
                messagebox.showerror(APP_NAME, tr("Telechargement impossible :\n%s") % state["error"])
            return None
        self.log(tr("telecharge : %s (%.1f Mo)") % (url, os.path.getsize(dest) / 2**20))
        return dest

    def selected_mod(self):
        sel = self.tree.selection()
        return self.installed[int(sel[0])] if sel else None

    def toggle_selected(self):
        mod = self.selected_mod()
        if not mod:
            return
        plan = core.plan_set_enabled(mod, not mod["enabled"], self.ue["mods_dir"])
        text = tr("%s « %s »\n\n%s") % (tr("Activer") if plan["enabled"] else tr("Desactiver"), mod["name"], "\n".join(plan["describe"]))
        if ConfirmDialog(self.root, tr("Confirmer"), text, tr("Activer") if plan["enabled"] else tr("Desactiver")).result:
            core.do_set_enabled(plan, self.log)
            self.refresh()

    def uninstall_selected(self):
        mod = self.selected_mod()
        if not mod:
            return
        plan = core.plan_uninstall(mod, self.ue["mods_dir"])
        if plan["refused"]:
            messagebox.showinfo(APP_NAME, core.describe_uninstall(plan))
            return
        if ConfirmDialog(self.root, tr("Confirmer la desinstallation"), core.describe_uninstall(plan), tr("Desinstaller")).result:
            try:
                core.do_uninstall(plan, self.log)
            except Exception as e:      # noqa: BLE001
                messagebox.showerror(APP_NAME, tr("Echec : %s") % e)
                self.log(tr("ECHEC desinstallation : %s") % e)
            self.refresh()


def main():
    try:    # sous Windows, un identifiant propre separe la fenetre de python(w).exe : la barre des taches affiche NOTRE icone
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("OutOfMods.Launcher")
    except Exception:
        pass
    root = tk.Tk()
    try:
        ttk.Style().theme_use("vista")
    except tk.TclError:
        pass
    App(root)
    if "--selftest" in sys.argv:
        root.after(2500, root.destroy)
    root.mainloop()


if __name__ == "__main__":
    main()
