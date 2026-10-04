# Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
"""Traduction de l'interface du launcheur (francais = langue des textes sources, anglais via i18n_en.EN).

`tr(texte)` renvoie la traduction si la langue courante est l'anglais ET si le texte est connu, sinon le texte tel quel.
Les gabarits gardent leurs marques `%s` / `%d` : on ecrit `tr("... %s") % valeur` (la traduction est faite AVANT la mise en forme).
"""
import os

try:
    from i18n_en import EN
except ImportError:      # pragma: no cover
    EN = {}

LANGS = ("fr", "en")
_lang = "fr"


def detect():
    """Langue du systeme : francais si l'interface Windows est en francais, anglais sinon. Surcharge possible par OOLAUNCHER_LANG=fr|en."""
    forced = os.environ.get("OOLAUNCHER_LANG", "").lower()
    if forced in LANGS:
        return forced
    try:
        import ctypes
        lid = ctypes.windll.kernel32.GetUserDefaultUILanguage() & 0x3FF
        return "fr" if lid == 0x0C else "en"
    except (AttributeError, OSError):
        return "en"


def set_language(lang):
    global _lang
    _lang = lang if lang in LANGS else "en"


def get_language():
    return _lang


def tr(text):
    if _lang == "en":
        return EN.get(text, text)
    return text
