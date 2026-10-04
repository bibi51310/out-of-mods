# Third-party notices / Mentions des composants tiers

**Out of Mods** (launcher, FlatGround 2, OutOfOreAPI) is released under the MIT License (see `LICENSE`).
It is an independent community project, **not affiliated with, endorsed by or sponsored by the developers or publisher of *Out of Ore***.
*Out of Ore* and its content remain the property of their owners. / Projet communautaire indépendant, **sans lien avec les développeurs ni l'éditeur d'*Out of Ore***.

The distributed launcher (`OutOfMods.exe` + `_internal/`) bundles the following components. Their full license texts are in the `licenses/` folder shipped with it.

| Component | Used for | License | Source |
|---|---|---|---|
| **Python 3.12** runtime | runs the launcher | PSF License Agreement | https://www.python.org/ — `licenses/Python-LICENSE.txt` |
| **Tcl/Tk** (tkinter) | windows and widgets | Tcl/Tk (BSD-style) license | https://www.tcl.tk/software/tcltk/license.html — `licenses/Tk-license.terms` |
| **sv-ttk** (Sun Valley theme) | modern look (light / dark) | MIT | https://github.com/rdbende/Sun-Valley-ttk-theme — `licenses/sv-ttk-LICENSE.txt` |
| **PyInstaller** bootloader | packages the launcher as a Windows program | GPL-2.0-or-later **with the bootloader exception** (the packaged program is not itself GPL) | https://pyinstaller.org/ — `licenses/PyInstaller-COPYING.txt` |

## Downloaded on request (not bundled) / Téléchargé sur demande (non inclus)

* **UE4SS** (Lua mod loader) — MIT License, © UE4SS contributors — https://github.com/UE4SS-RE/RE-UE4SS.
  The launcher can download it **only when the user asks**, verifies its SHA-256 fingerprint, and installs `dwmapi.dll` / `UE4SS.dll` after a detailed confirmation.
  The upstream license text is included in the downloaded archive (`LICENSE`).

## Not redistributed / Non redistribué

* Game data, dumps, assets or code of *Out of Ore* are **not** part of this project and must not be added to it.
* The community modding kit (`tonyoo/out-of-ore-modding`, MIT) is not bundled; its documentation inspired the setup instructions.
