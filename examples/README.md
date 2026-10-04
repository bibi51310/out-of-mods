# Exemples de mods sur OutOfOreAPI

Mods minimes, pour apprendre à utiliser `api/OutOfOreAPI.lua`. Non déployés par `deploy.ps1` (qui ne copie que `mods/`) :
copier le dossier dans `UE4SS/Mods/` du jeu et l'ajouter à `mods.txt` (`FuelAlert : 1`).

- **`FuelAlert`** : notification native quand le carburant de l'engin conduit passe sous un seuil (`fuelalert 30` pour changer le seuil).
  Les appels qu'il utilise sont validés en jeu séparément ; le mod lui-même n'a pas été essayé en conduisant.
