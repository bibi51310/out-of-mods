# Contribuer / Contributing

🇫🇷 Merci de votre intérêt ! Les retours des joueurs sont précieux.

* **Un bug ?** Ouvrez un ticket avec le modèle « Bug » : version du jeu, version du mod / de Out of Mods, ce que vous faisiez, et le **rapport de diagnostic** (bouton « Copier le rapport de diagnostic » dans Out of Mods) + `UE4SS.log`. Relisez le rapport avant de le coller : il contient des chemins locaux.
* **Une idée ?** Modèle « Idée / suggestion ».
* **Du code ?** Ouvrez d'abord un ticket pour en discuter. Lancez les tests (`python tests/test_launcher_core.py`, `test_i18n.py`, `test_launcher_ui.py`, `test_updates.py`, `test_launcher_updates_ui.py`) et `python tools/check_lua_strings.py <fichier.lua>` avant une pull request. Tout texte visible du launcheur passe par `tr("texte FR")` avec sa traduction dans `launcher/i18n_en.py`.
* **Règle d'or : aucune donnée, aucun fichier ni extrait de code du jeu *Out of Ore* dans ce dépôt** (tables, dumps, assets…). Les décrire est possible, les publier ne l'est pas.
* En contribuant, vous acceptez que votre contribution soit publiée sous la licence MIT du projet.

🇬🇧 Thanks for your interest! Player feedback is valuable.

* **A bug?** Open an issue with the "Bug" template: game version, mod / Out of Mods version, what you were doing, and the **diagnostic report** ("Copy the diagnostic report" button in Out of Mods) + `UE4SS.log`. Review the report before pasting it: it contains local paths.
* **An idea?** Use the "Idea / suggestion" template.
* **Code?** Open an issue first to discuss it. Run the tests (`python tests/test_launcher_core.py`, `test_i18n.py`, `test_launcher_ui.py`, `test_updates.py`, `test_launcher_updates_ui.py`) and `python tools/check_lua_strings.py <file.lua>` before a pull request. Every visible launcher text goes through `tr("French text")` with its translation in `launcher/i18n_en.py`.
* **Golden rule: no data, files or code excerpts from the game *Out of Ore* in this repository** (tables, dumps, assets…). Describing them is fine, publishing them is not.
* By contributing you agree your contribution is released under the project's MIT license.
