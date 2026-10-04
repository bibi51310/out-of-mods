# OutOfOreAPI

Couche Lua commune pour les mods UE4SS de **Out of Ore**. Regroupe des patterns déjà validés en jeu
dans ce projet (mods `FlatGround`, `DataTableDump`) pour qu'un nouveau mod n'ait pas à les redécouvrir :
échange de fichiers avec une interface compagnon, boucle périodique sans risque, encodage JSON, lecture
sûre de tables de données.

Statut : usage interne au projet pour l'instant ; publication séparée envisagée plus tard (dépôt et
licence pas encore choisis).

## Non-régression après une mise à jour du jeu

Dans une partie chargée, console du jeu : **`api_selftest`** (mod `OutOfOreAPITest`). Passe en revue les 32 lectures de l'API
(aucune écriture) et écrit `PASS` / `FAIL` par module dans `UE4SS.log`, puis un total. État au 2026-10-04 (build bêta 25319732,
jeu 0.36.5550) : **32 PASS, 0 FAIL**. Un `FAIL` après un patch indique une classe ou une propriété renommée.

## Installation

Copier `OutOfOreAPI.lua` dans :

```
<Jeu>/OutOfOre/Binaries/Win64/UE4SS/Mods/shared/OutOfOreAPI/OutOfOreAPI.lua
```

(`deploy.ps1` à la racine du projet le fait automatiquement, comme pour les mods.)

Dans un mod :

```lua
local API = require("OutOfOreAPI")
```

## Sommaire des modules (validés en jeu, 2026-09 / 2026-10)

| Domaine | Modules |
|---|---|
| Plomberie | `Json`, `IPC` (+ `EnsureDataDir`), `SafeTick`, `Hook`, `Console`, `Keybind`, `CallFunction`, `DataTable`, `Events` |
| Monde | `World` (heure, météo, marqueurs ; **écriture** du ciel), `Terrain` (hauteur du sol, point visé), `Land` (droits de creusage, parcelles) |
| Engins | `Vehicle` (tableau de bord, fluides, moteur, foreuse, usure, XML complet, charge), `GPS`, `AutoLevel`, `Inventory` |
| Joueur / partie | `Player` (finances, objet actif), `Settings` (FOV...), `Game` (version, règles, progression, quêtes ; **écriture** des multiplicateurs) |
| Économie | `Market` (bourse, minerais, acheteurs, entreprises rivales) |
| Interface | `UI.Window` (fenêtres natives), `UI.Marker` (étiquettes ancrées au monde) |
| Outils | `Debug.Inspect` (inspecteur de propriétés), mod `EventSpy` (journal d'événements) |

Principe directeur : **lire des propriétés** (sûr) plutôt qu'appeler des fonctions ; les fonctions natives s'appellent en
**omettant** le paramètre `ReturnValue` ; ne jamais passer de table à un paramètre `NameProperty`. Détails dans « Pièges ».

## Contenu

### `API.Console.Exec(commande)` — exécuter une commande de console du jeu

```lua
API.Console.Exec("stat fps")   -- affiche / retire le compteur d'images (validé sur capture : 234 FPS, 4,26 ms)
API.Console.Exec("t.MaxFPS 60")
```
Équivaut à taper la commande dans la console (`~`). Renvoie true si l'appel a réussi (pas si la commande existe). Les commandes de
moteur ont des effets réels : à utiliser en connaissance de cause. `stat fps` est une bascule (un 2e appel le retire).

### `API.Json.encode(value)`

Encodeur JSON minimal (pas de bibliothèque JSON disponible côté UE4SS Lua). Gère string/number/
boolean/table (array ou map)/nil.

### `API.IPC` — échange de fichiers avec une UI compagnon

Même protocole que FlatGround (`%APPDATA%\<VotreMod>\...`), validé en jeu depuis 2026-09-25.

```lua
local dir = API.IPC.dataDir("MonMod")          -- %APPDATA%\MonMod
local cmd = API.IPC.NewCommandChannel(dir .. "\\command.txt")
local state = API.IPC.NewStateWriter(dir .. "\\state.txt")

-- a chaque tick :
local action, arg = cmd:read()   -- nil si pas de nouvelle commande (dedoublonnee par id en interne)
if action == "set" then ... end
state:write({ floor = 123.4, hooks = 3 })   -- ecrit floor=123.4\nhooks=3\n
```

L'UI écrit dans `command.txt` une ligne `"<id>|<commande>|<argument>"` (`id` change à chaque nouvelle
commande, ex. un timestamp ou un compteur) ; `cmd:read()` ignore silencieusement toute commande déjà
vue, et n'exécute jamais une commande laissée par une session précédente au démarrage du mod.

Pour un état imbriqué (pas juste des paires clé=valeur plates), écrire du JSON directement avec
`API.Json.encode` plutôt que `NewStateWriter`.

### `API.SafeTick.Register(callback, hz)`

Boucle périodique **sans jamais utiliser `LoopAsync`/`ExecuteInGameThread`/`ExecuteWithDelay`** : ces
derniers corrompent le registre Lua quand ils tournent en parallèle des hooks de terrassement du jeu
(observé et corrigé dans FlatGround le 2026-09-26 — voir `CLAUDE.md` du projet). Utilise à la place un
hook sur le tick du joueur (`PS_Standard_C:ReceiveTick`), limité à `hz` appels/seconde (défaut 10).

```lua
API.SafeTick.Register(function()
    -- appele au plus 10x/seconde, dans le game thread
end)
```

### `API.DataTable.Read(fullObjectPath)`

Lit le contenu d'une DataTable (noms de lignes + valeurs de chaque colonne), via les seules fonctions
de `DataTableFunctionLibrary` à signature ordinaire (`GetDataTableRowNames`, `GetDataTableColumnAsString`).

**N'appelle jamais `GetDataTableRowFromName`** : cette fonction attend un contexte Blueprint réel (le
paramètre de sortie est un pin « wildcard » résolu par le compilateur Blueprint) et peut planter le jeu
si on l'appelle depuis un contexte Lua générique.

```lua
local t, err = API.DataTable.Read("/Game/Blueprints/DataTables/DT_1_Resources.DT_1_Resources")
if t then
    for i, rowName in ipairs(t.rowNames) do
        print(rowName, t.columns["State"][i])
    end
end
```

### `API.GPS` — hauteur du tranchant et vitesse d'avancement

Lecture seule du GPS du jeu (`TerraformComponent:GetInfo_GPS`), reprise de `FlatGround` (valide en jeu
le 2026-09-25 : valeurs identiques à l'écran GPS). Unités : cm, cm/s.

```lua
local g = API.GPS.Read()          -- ou API.GPS.Read(API.GPS.FindNearest()) ; nil si aucun engin / appel echoue
-- g.edge     Z du tranchant (cm)               g.ref      Z du point de reference GPS (SET ZERO)
-- g.rot      {x,y,z,w} du tranchant            g.zeroRot  {x,y,z,w} du point de reference
-- g.fwd      vitesse d'avancement (+ avant / - arriere)    g.component  le composant lu
-- g.autoLevelCurrent / g.autoLevelTarget  Z reel / Z cible du module AutoLevel (module distinct, beta)
-- chaque champ peut etre nil individuellement ; un Z egal a 0 vaut « pas de valeur » (GPS inactif)
```

**Deux modules distincts (2026-10-03)** : le GPS (point de référence = SET ZERO, Num7) et l'AutoLevel
de la bêta (point posé avec N) sont deux équipements différents d'un engin, chacun avec son écran. Validé en
jeu sur le même engin : écran GPS 13324,4 / écart 150,6 cm ↔ `edge` 13324,2 et `edge - ref` 150,6 ; écran
AutoLevel 13340,1 / cible 13340,2 ↔ `autoLevelCurrent` / `autoLevelTarget`. Le tranchant diffère d'environ
16 cm entre les deux modules (points de mesure différents).

`API.GPS.FindNearest()` renvoie le `TerraformComponent_C` le plus proche du joueur ;
`API.GPS.ReadForwardSpeed(terraform)` donne seulement la vitesse. Appeler depuis un `API.SafeTick`
(game thread). Test de non-régression : commande `gps_check` de `mods/OutOfOreAPITest` (**à valider en
jeu après le portage**).

### `API.World`, `API.Vehicle`, `API.Player` — lectures du monde, de l'engin et du joueur

Tous en **lecture seule**, validés en jeu le 2026-10-03 (commandes `world_check`, `vehicle_check`,
`player_check` de `mods/OutOfOreAPITest`). Chaque champ peut être `nil` individuellement ; un module entier renvoie
`nil` si l'objet source n'existe pas.

```lua
API.World.ReadTime()       -- { hours, minutes, seconds, day, month, year }  (heure du ciel du jeu)
API.World.ReadWeather()    -- { temperatureC, temperatureF, cloudCoverage, rain, wind, windDirection, season,
                           --   snowPercentage, wetness, lightning }

local v = API.GPS.FindNearest():GetOwner()            -- l'Actor engin
API.Vehicle.ReadCluster(v) -- { active, rpm, kmh, fuel, fuelCapacity, engineHours, gear, parkingBrake, dirtLock }
API.Vehicle.ReadInteract(v)-- { text, available }  ("to enter vehicle" quand le joueur est a cote)
API.Vehicle.ReadLoad(API.GPS.FindNearest())   -- { fillLevel, fillPercent, digging, dirtLock, bulk }
API.Vehicle.FindControlled()   -- Actor de l'engin conduit (AVSBaseComponent_C:IsControlled?), ou nil
API.World.ReadMarkers()    -- liste de { x, y, z, actor, actorClass, controlledByPlayer } : tous les engins + le personnage
API.Player.ReadActiveItem()-- { id, amount, index } ; 300001 = Pickaxe (traduire avec DT_GameItems.CustomInfo)

API.Player.ShowMessage("Bonjour")  -- notification native au centre de l'écran (validé sur capture)
API.Player.ReadFinance()   -- { money, companyMoney, debt, maxDebt, toolbarIndex, companyRole }
```

Valeurs vues sur la partie de test : 12:09:49, 21 °C, vent 2 ; carburant 1400/2000, rapport N ; argent
100 000 000, dette 0 / 1 000 000. Notes :
- `GPS.FindNearest()` utilise maintenant `FindControlled()` en priorité et retombe sur « le plus proche » si nil (non confirmé
  quand le joueur conduit).
- `FindControlled()` renvoie `nil` joueur à pied (les deux engins répondent `false`) ; **le cas « vrai » reste à
  confirmer en conduisant**. Il devrait remplacer « l'engin le plus proche » de `GPS.FindNearest`.
- La date du ciel (22/04/2021) n'est pas forcément la date affichée par le jeu : à recouper avant usage.
- `fillPercent` est la valeur brute du jeu (`GetFillPrecent`), unité non confirmée.
- Pièges de signature rencontrés (déjà couverts par `callOut`, utile si vous appelez à la main) : le nombre de
  tables « sortie » est celui annoncé par l'erreur `UFunction expected N parameters` et non celui du catalogue
  (`Get_VehicleClusterInfo` : 9 et non 10 ; `GetSimWheelTrans` : 2 et non 6 ; `GetMyMoney`/`GetMyDebt`/... : 1,
  jamais 0) ; les fonctions dont le nom contient des espaces (`Get Current Temperature`) s'appellent avec
  `obj["Get Current Temperature"](obj, ...)`.

### Lectures de **propriétés** (2026-10-04) — `API.Vehicle.Read*`, `API.Game`

Plus sûr qu'appeler des fonctions : on lit des propriétés d'objets déjà en mémoire (`obj.Nom`), aucun appel, donc aucun
risque de gel (voir « Pièges »). Validé en jeu (commandes `vehicle2_check` et `game_check` de `mods/OutOfOreAPITest`).

```lua
for _, v in ipairs(API.Vehicle.ListAll()) do      -- tous les engins (AVS_SuperVehicleBase_C)
  API.Vehicle.ReadFluids(v)     -- { {type="DieselFuel", amount=700, capacity=1000, useBase=30}, ... } (= carburant du tableau de bord)
  API.Vehicle.ReadEngine(v)     -- { maxRpm, workRpm, torqueNm, brakePower, gearsForward={..}, gearsReverse, hydraulicDrivetrain, rootWeight... }
  API.Vehicle.ReadDrill(v)      -- { crownWear, crownTemperature, feedSpeed, feedForce, rods, maxRods, inContact } (valeurs par défaut hors foreuse)
  API.Vehicle.ReadAutoDrive(v)  -- { recording, following, waypoints, activeIndex, maxWaypoints }
end
API.Game.ReadInfo()        -- { saveName, map, mode ("CREATIVE"), gameVersion ("0.36.5550"), secondsPlayed }
API.Game.ReadRules()       -- multiplicateurs de la partie (breakdown, fuelConsumption, production, runSpeed, questReward...) + skillPoints
API.Game.ReadProgression() -- { level, xp, xpNeeded, skillLevelName }
API.Game.ReadQuests()      -- { {item="500012" (ID DT_GameItems), current, target, money, xp, active, locked}, ... }
```

- **Tableaux de propriétés** : `arr:GetArrayNum()` puis `arr[i]` donne directement un nombre ou un nom (`:ToString()`).
  Les tableaux de **structures** (`UnlockedSkills`, `DiscoveredElements`, `Inventory`) renvoient seulement le type, pas les champs.
- **Écriture du ciel** : `API.World.SetTimeOfDay(10, 30)` (propriété « Time of Day » d'Ultra Dynamic Sky, heures décimales ×100)
  et `API.World.SetTimeFlowing(false)` (fige « Animate Time of Day »). Validé en jeu : `ReadTime()` passe de 14:10 à 10:30, le
  temps reste figé, puis restauré. **Effet visuel confirmé sur capture** : à 21:45 la scène passe en pleine nuit (étoiles, silhouettes) ; restauré ensuite.
- **Écriture** : `API.Game.SetRule("jumpForce", 1.25)` change un multiplicateur de la partie (renvoie la valeur relue). L'écriture
  d'une propriété d'objet est confirmée en jeu (relecture identique) ; l'effet réel de chaque règle n'est pas vérifié.
- `gameVersion` vient de la sauvegarde (`SchaktSaveGame.GameVersion`) : c'est le vrai numéro de version du jeu.
- Les quêtes sont tirées au hasard à chaque chargement (cibles et récompenses changent).

```lua
API.Vehicle.ReadCondition(v) -- { wear, rust, dirt, hours }  (usure, rouille, saleté de l'engin, 0..1)
API.Vehicle.ReadXml(v)       -- configuration complète de l'engin en XML (~22 Ko : masses, hydraulique, transmission, godet...)

-- Plugin FinancialRivals (bourse, marchés, entreprises rivales) : validé en jeu (commande `market_check`)
API.Market.ReadStatus()    -- { open, indexBaseline }
API.Market.ReadStocks()    -- 42 actions : { ticker, name, price, previousClose, dayChangePercent, dayHigh, dayLow, allTimeHigh, allTimeLow, availableShares, maxShares }
API.Market.ReadOres()      -- 12 minerais : { id, demand, price, soldThisQuarter, soldLifetime }
API.Market.ReadMerchants() -- 7 acheteurs : { id, capital, spentLifetime }
API.Market.ReadRivals()    -- classement des entreprises : { rank, id, name, score, pursuit, isPlayer }
```
- Les champs des structures **natives** (`CompanyRecord`, `StockInfo`...) se lisent par `elem.Champ` ; ce n'est pas le cas des
  structures Blueprint (`ItemStruct`, noms suffixés d'un GUID).
- Ne pas appeler les fonctions natives de ces classes (`GetStockPrice`, `GetStockInfo`...) : lire les tableaux `Stocks`/`DynamicInfos`.

### `API.Terrain` — hauteur du sol (rayons verticaux) et `API.Inventory`

Validé en jeu le 2026-10-04 (commandes `terrain_check`, `inv_check`).

```lua
API.Terrain.Ground(x, y [, opts])  -- { z, nx, ny, nz, slopeDeg } : sol sous le point (x, y) en cm, ou nil
API.Terrain.Sample(cx, cy, radius, step)  -- { n, min, max, range, mean, stddev, points } sur un carré (pas 200 cm par défaut)
API.Land.CanDig(x, y, z)           -- le jeu autorise-t-il le creusage ici ? (SchaktVoxelWorld:CanDigHere)
API.Land.ChunkAt(x, y, z)          -- parcelle d'achat de terrain contenant le point : { x, y, z }
API.Land.Info()                    -- { purchaseSystem, chunkSize, dataLocked, voxelSize (60 cm), worldSizeInVoxels }
API.Inventory.ReadPlayer()         -- { name, maxSize, items = { {index, id, amount}, ... }, equipment }  (id = DT_GameItems)
API.Inventory.ReadVehicle(v)       -- idem pour un engin ; API.Inventory.ReadAll() = tous les inventaires (avec owner/ownerClass)
API.IPC.EnsureDataDir("MonMod")    -- crée %APPDATA%\MonMod si besoin (un mkdir, console qui peut clignoter) et renvoie le chemin
```

- `Terrain.Ground` utilise `KismetSystemLibrary:LineTraceSingle` (comme le `LineTraceMod` du kit) : le terrain voxel a des
  collisions, donc le rayon touche le sol réel, creusé ou non. Le joueur et tous les engins sont ignorés par défaut (sinon on
  touche leur carrosserie : un engin d'origine à 13698 donne un sol à 13530, pas 13715). 121 points en 0,21 s.
- Sol mesuré sous le joueur : 13143.6 ; un relevé de 20 m de côté donne min 12752 / max 13222 (terrain en pente, 30°), idéal
  pour dire « cette zone est plate à ±x cm » ou choisir un plancher de FlatGround.
- Les `id` d'objets sont ceux de `DT_GameItems` (300001 = Pickaxe, 100001/100002 = minerais...).

### `API.UI` — fenêtres en jeu (popup natif + boutons), déplaçables, redimensionnables

```lua
local win = API.UI.Window{ title = "Mon mod", text = "Compteur : 0", x = 300, y = 150, scale = 0.7 }
win:AddButton{ label = "+1", x = 20, y = 300, w = 180, onClick = function(w) w:SetText("...") end }
win:Open()          -- crée le popup natif (W_GenericPopup_C) et les boutons (W_Element_Button_C), souris dans l'interface
win:SetInput(false) -- rend la souris au jeu (la fenêtre reste affichée) ; win:Close() ferme ; win:SetScale(k) ; win:MoveTo(x, y)
```

Validé en jeu le 2026-10-04 par la commande `ui_demo [échelle]` de `OutOfOreAPITest` (vérifié sur capture d'écran) : affichage à
l'échelle 0,7, clics routés (compteur 0 -> 3 après 3 clics simulés à la souris), **déplacement à la souris par la barre de titre**
(+200/+120 px suivis), bouton « Fermer » qui ferme et rend la souris au jeu. Reprend la technique du panneau de FlatGround2
(qui n'utilise pas encore ce module). Limites : pas de champ de saisie ni de masquage pendant le menu Échap (voir le code de
FlatGround2) ; création dans un événement d'interface ou un tick ; le tick du joueur s'arrête quand le jeu est en pause.

#### `API.UI.Marker` — étiquette ancrée sur un point du monde

```lua
local m = API.UI.Marker{ text = "Sol 12876", x = 148000, y = 119000, z = 12876, w = 160 }
m:Show()   m:SetText("...")   m:SetWorld(x, y, z)   m:Hide()
```
Suit le point à l'écran (projection `PlayerController:ProjectWorldLocationToScreen`, mise à jour à 20 Hz), masquée derrière la
caméra. Validé en jeu (`marker_demo` / `marker_demo_off`, vérifié sur capture) : l'étiquette « Cible » apparaît au point visé
(centre de l'écran), « Sol 12876 » sur le sol 20 m devant le joueur. Utile pour matérialiser un plancher, des points enregistrés,
une zone... NB : `KismetSystemLibrary:DrawDebug*` s'exécute sans erreur mais **ne dessine rien** (fonctions de debug retirées
du build Shipping) : passer par ces étiquettes.

### `API.Settings` — options du joueur (lecture et champ de vision)

```lua
API.Settings.Read()              -- { fovThird, fovFirst, master, effects, engine, ambient, interface, music, autoGearbox, ... }
API.Settings.SetFov("third", 70) -- champ de vision en degrés (30..120) ; "first" = vue cabine ; renvoie la valeur relue
```
`SchaktSaveProfile` (`GameInstance.LocalProfile`) est lu en direct par le jeu : **validé sur capture** (FOV 90 -> 50 = vue nettement
zoomée, puis restauré à 90). À l'inverse, `CameraComponent:SetFieldOfView` sur la caméra du personnage est écrasé par le jeu
(aucun effet visible). Pas de sauvegarde disque par l'API.

### `API.Debug` — inspecteur d'objets en direct

```lua
API.Debug.Inspect(obj [, motif])            -- { {name, type, value}, ... } : toutes les propriétés (classe + parents), lecture seule
API.Debug.InspectClass("SchaktStateBase_C") -- idem sur la 1re instance vivante
```
Console du mod `OutOfOreAPITest` : `inspect NomDeClasse [motif]` écrit le résultat dans `%APPDATA%/OutOfOreAPITest/inspect.txt`
(validé en jeu sur `SchaktProgressionComponent` : 19 propriétés). Pratique pour découvrir quoi lire sans relancer un dump d'objets.

### `API.Events` — abonnements à des événements du jeu

```lua
API.Events.On("moneyEdit", function(info) print(info.args[1]) end)   -- info = { name, args = {a1, a2...}, context }
API.Events.Names()   -- worldLoaded, possessed, moneyEdit, equip, menuToggled
```

Chaque événement est un pre-hook sur une fonction du jeu, posé à la première inscription (réessayé chaque seconde tant que la
classe n'est pas chargée). Validé en jeu au chargement d'une partie : `worldLoaded` (a1 = booléen), `possessed` (a1 = contrôleur),
`equip`, `moneyEdit` (a1 = 0 au chargement ; les arguments suivants sont des booléens). Les callbacks tournent dans le thread du
jeu : ne rien y faire de lourd, et pas d'`ExecuteInGameThread`. Un callback qui lève une erreur est retiré.
Le mod `EventSpy` journalise 58 autres fonctions (`%APPDATA%\OutOfOreEventSpy\events.txt`) pour trouver d'autres événements :
jouez quelques minutes (acheter, vendre, conduire, finir une quête) puis lisez ce fichier.

### `API.AutoLevel` — lecture du composant natif d'auto-nivellement

Depuis la branche beta du jeu (build Steam **25319732**, ~2026-09-27), certains engins (dozer/loader/
grader équipés) ont un composant natif `AutoLevelComponent_C` avec sa propre cible et son propre suivi
d'angle — un système officiel proche de ce que fait déjà `FlatGround` à la main. Lecture seule, aucun
appel de fonction (voir avertissement plus bas).

```lua
local comp = API.AutoLevel.FindNearest()          -- composant le plus proche du joueur, ou nil
local status = API.AutoLevel.ReadStatus(comp)     -- table a plat, champs individuellement nil si echec
-- status.mounted / .active / .following / .onTarget / .hasTarget / .disabled  (bool)
-- status.height / .angle / .sideAngle / .offset                                (float)
-- status.actual / .target = { x, y, z, qx, qy, qz, qw }                        (Transform)
```

Validé en jeu (2026-09-27) : `mounted=true hasTarget=true active=false onTarget=false angle=1.96 ...`
avec des transforms `actual`/`target` cohérents.

**Fonctions du composant testées en jeu (2026-09-28, via `API.CallFunction` ou appel direct)** — voir
`CLAUDE.md` pour le détail des tests et `mods/OutOfOreAPITest` pour les commandes de non-régression :
- ✅ `CheckOnTarget()`, `SetOffset_Increase()`/`SetOffset_Decrease()`, `ZeroAutoLevel()`,
  `ActivateAutoLevel()`, `SetActiveSR(bool)`, `SetAutolevel(bool)`, `SetManualTarget(Z: float)`,
  `SaveFunc(Target, bHasTarget)` (getter), `LoadFunc(Target, bHasTarget)` (setter).
- ✅ `LoadAutoLevel(Target, Offset)` : appel réussi mais **charge une calibration sauvegardée en
  mémoire persistante** plutôt que d'utiliser les arguments fournis (contrairement à `LoadFunc`) —
  remet `Target` à `(0,0,0)` en l'absence de sauvegarde native. Rappeler `ZeroAutoLevel` après usage
  pour resynchroniser.
- ✅ Les 6 variantes `_SR` (`Set_Offset_Increse_SR`/`Decrese_SR`, `ZeroAutoLevel_SR`,
  `DisableAutoLevel_SR`, `SetAutoLevel_SR(bAutoLevelMounted: bool)`, `ActivateAutoLevel_SR`,
  `SetManualTarget_SR(InputPin: float)`) — miroirs directs des fonctions ci-dessus, toutes réussies.
- ❌ `DisableAutoMode(bool)` : échec systématique (erreur Lua propre, pas de crash) — utiliser
  `SetActiveSR(false)` ou `DisableAutoLevel_SR()` à la place (les deux marchent).
- **Bilan : 17 fonctions testées, 16 réussies, 1 échec propre.** Chantier de test clos.

Ces fonctions ne sont **pas** exposées comme wrappers `API.AutoLevel.*` (contrairement à
`ReadStatus`/`FindNearest`) : elles ont un effet de bord réel (déplacer la lame, changer de mode) et
n'ont été validées qu'au cas par cas, avec l'utilisateur aux commandes. Les appeler via
`API.CallFunction(comp, "NomFonction", ...)` en connaissant la signature exacte (voir
le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue) et les deux pièges ci-dessous).

### `TerraformComponent_C` — creuser/verser (120 fonctions cataloguées, exploration en cours)

Pas de wrapper `API.Terraform.*` pour l'instant. Repérage du composant le plus proche du joueur : même
technique que `NearestTerraform()` dans `mods/FlatGround/Scripts/main.lua` (`FindAllOf` + distance).

**7 getters testés en jeu (2026-09-28), tous réussis** : `CanSpill`, `GetFillLevel` (table de sortie,
voir piège 1 ci-dessus), `GetFillPrecent`, `IsDigging`, `IsDirtLockActive`, `GetOwnerPlayerController`,
`GetWeight('kg', {}, {})` (le nom du champ `Total` reste à corriger — `Actual` a bien été lu).

Reste à explorer (120 fonctions au total) : setters d'état (`SetDirtMode`, `SetSpillThreshold`...) et
fonctions d'action réelle (`Cut`, `RemoveBox`, `DischargeDirt`...) — celles-ci touchent au
creusage/versement réel, pas testées à l'aveugle, utilisateur aux commandes comme pour `AutoLevel`.

### `API.CallFunction(obj, fnName, ...)`

Appel générique d'une fonction UE **ordinaire** (signature normale) sur un objet, quels que soient ses
arguments. Généralise le pattern déjà validé dans `DataTable.Read` : certaines fonctions UE4SS renvoient
leur résultat comme une vraie valeur de retour Lua, d'autres remplissent un paramètre de sortie ajouté
en dernier argument — `CallFunction` essaie les deux conventions.

**Portée découverte en jeu (2026-09-28, en testant `SchaktVoxelWorld`)** : cette technique d'appel
marche de façon fiable sur les **fonctions Blueprint (classes `_C`)** et les **bibliothèques natives
conçues pour Blueprint** (ex. `DataTableFunctionLibrary`), mais **pas sur les fonctions internes de
gameplay natif** d'une classe comme `SchaktVoxelWorld` (`/Script/OutOfOre.*`) : même la fonction la
plus simple possible (`IsVoxelDataLocked`, 1 seul paramètre) échoue avec `"UFunction expected N
parameters, received N"` malgré un nombre d'arguments correct. Hypothèse la plus probable : ces
fonctions ne sont pas marquées `BlueprintCallable` côté C++, donc visibles dans le dump de réflexion
(le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue)) mais pas exposées au mécanisme d'appel générique de Blueprint/Lua. Pour
du code natif comme celui-ci, la seule approche qui marche reste le **hook** (`API.Hook.Register` sur
`RegisterHook`, comme `FlatGround` le fait déjà sur `SchaktVoxelWorld:MultiplayerRemoveRotatedBox`),
pas l'appel direct.

```lua
local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
local rowNames, err = API.CallFunction(lib, "GetDataTableRowNames", dt)
if err then
    -- echec : objet invalide, fonction introuvable, ou exception Lua
elseif rowNames == nil then
    -- appel reussi mais fonction "void" (rien a lire) -- ne pas confondre avec un echec
else
    -- rowNames exploitable (valeur de retour ou parametre de sortie rempli)
end
```

**Ne JAMAIS appeler une fonction "wildcard"** avec (ex. `GetDataTableRowFromName`) : ces fonctions
attendent un contexte Blueprint réel et peuvent provoquer un Fatal error natif que `pcall` ne rattrape
pas. `CallFunction` protège seulement contre les erreurs Lua normales, pas contre un crash natif — le
choix de la fonction appelée reste sous la responsabilité de l'appelant.

Toujours vérifier `err`, jamais seulement `value == nil` : un appel réussi sur une fonction sans retour
utile renvoie `nil, nil`.

**Pièges découverts en testant `AutoLevelComponent_C`, `TerraformComponent_C`, `SchaktVoxelWorld` et
`AVS_SuperVehicleBase_C` (2026-09-28), valables pour n'importe quelle fonction :**

1. **UE4SS exige tous les paramètres positionnellement, y compris ceux "en sortie"** — jamais en omettre
   un même s'il semble être une simple valeur de retour (erreur sinon : `"UFunction expected N
   parameters, received 0"`). **N'IMPORTE QUEL paramètre "en sortie" — struct OU primitif (float/bool/
   objet) — doit être une table vide `{}` passée à sa place, jamais une valeur brute.** Une valeur brute
   pour un paramètre sortie échoue silencieusement (erreur Lua propre, capturée par `pcall`, jamais de
   crash) ; la table, elle, est remplie en place après l'appel (relire `out.NomDuChamp`, le nom exact du
   champ correspond au nom du paramètre dans le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue)). Un paramètre struct **en
   entrée** (pas en sortie) peut recevoir directement une valeur déjà lue par réflexion (ex.
   `comp.Actual`), pas besoin de table vide dans ce cas :
   ```lua
   local targetOut = {}
   local ok, _ = pcall(function() return comp:SaveFunc(targetOut, false) end)  -- Target=out (table)
   -- targetOut.Translation.X/Y/Z exploitable ici si ok
   -- (bHasTarget=false a marche sans erreur, mais si c'est aussi un parametre sortie, utiliser {}
   --  a la place pour recuperer sa valeur -- pas encore re-teste sur SaveFunc precisement)

   local ok2 = pcall(function() return comp:LoadFunc(comp.Actual, true) end)   -- Target=in, bHasTarget=in

   local outFill = {}
   local okFill = pcall(function() return terraform:GetFillLevel(outFill) end)  -- 1 seul parametre, sortie primitive
   -- outFill.FillLevel exploitable ici si okFill (confirme en jeu : 0.38)
   ```
2. **L'ordre des paramètres dans le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue) (ordre mémoire du dump d'objets) n'est
   fiable QUE pour les fonctions à un seul paramètre.** Pour une fonction à 2+ paramètres, l'ordre
   d'appel réel peut être différent (vérifié sur `SaveFunc` : ordre dump `(bHasTarget, Target)`, ordre
   d'appel réel `(Target, bHasTarget)`). Toujours vérifier en jeu avant de se fier à l'ordre du
   catalogue.
3. **Un paramètre "sortie" nommé littéralement `ReturnValue` est une EXCEPTION à la règle 1** :
   c'est la vraie valeur de retour C++/Blueprint de la fonction, pas un paramètre "sortie" ordinaire
   — à **omettre complètement de l'appel** (pas de table `{}` à sa place), elle revient via le retour
   Lua normal. Confirmé en jeu (2026-09-28) : `avs:GetXmlObject()` (0 argument, alors que le
   catalogue liste 1 paramètre `ReturnValue`) a réussi et renvoyé un vrai `UObject` ; la même fonction
   appelée avec une table `{}` à la place échouait (`"UFunction expected 1 parameters, received 1"`,
   même symptôme que le piège suivant).
4. **⚠️ Les fonctions internes de gameplay natif (`/Script/OutOfOre.*`, ex. `SchaktVoxelWorld`,
   probablement d'autres) ne sont PAS appelables de façon fiable via `CallFunction`/pcall direct** —
   contrairement aux classes Blueprint (`_C`) et aux bibliothèques natives conçues pour Blueprint (ex.
   `DataTableFunctionLibrary`). Confirmé en jeu (2026-09-28) : même la fonction native la plus simple
   possible (`SchaktVoxelWorld:IsVoxelDataLocked`, 1 seul paramètre) échoue avec `"UFunction expected N
   parameters, received N"` malgré un nombre d'arguments correct — probablement parce que ces
   fonctions ne sont pas marquées `BlueprintCallable` côté C++. Pour du gameplay natif, seul le
   **hook** (`API.Hook.Register`) est fiable, jamais l'appel direct.
   **🔴 Une tentative de contournement a CRASHÉ LE JEU** (`AVS_SuperVehicleBase_C:GetSceneComponentByName
   ("Root")`, classe Blueprint cette fois, testée pour vérifier la règle 3 ci-dessus avec un 2e
   paramètre) : contrairement à un échec Lua propre, le **processus entier a disparu** (pas de message
   de crash dans `UE4SS.log`, qui s'arrête net). **Ne jamais rappeler cette fonction avec `"Root"`** —
   voir "Rappels" dans `CLAUDE.md`. Rappel général : `pcall` protège contre les erreurs Lua, jamais
   contre un crash natif — un appel qui "a l'air sûr" (signature simple, classe Blueprint) peut quand
   même planter le jeu.
5. **Le NOMBRE de paramètres listé dans le catalogue de fonctions (genere localement depuis un dump d'objets du jeu ; non distribue) n'est pas garanti non plus**
   (en plus de son ordre, piège 2). Le générateur classe une variable comme "paramètre" si son nom ne
   correspond à aucun préfixe interne connu (`CallFunc_`/`K2Node_`/`Temp_`/`__`) — mais une variable
   locale nommée sans préfixe technique (ex. `String`, `Components`) passe à tort pour un paramètre.
   Confirmé en jeu (2026-09-28) : `TerraformComponent_C:CalculateWeight` liste 1 paramètre (`String`)
   mais en attend réellement 0 ; `GetOverlappedComponents` en liste 2 mais en attend réellement 1.
   **L'erreur `"UFunction expected N parameters, received M"` avec N≠M donne le vrai compte** —
   rappeler avec N arguments au lieu de M résout le problème dans ces deux cas.

6. **Paramètre "sortie" de type tableau (`ArrayProperty`)** : même convention que structs/primitifs, une
   table `{}` en placeholder, remplie en place après l'appel. Confirmé en jeu (2026-09-28) :
   `AVS_SuperVehicleBase_C:Get_CtrlHints({})` -> table de 29 entrées.
7. **Éviter les paramètres `NameProperty`** (ex. `GetSceneComponentByName`, `GetSpecialWheelComponentByName`) :
   un appel avec une chaîne Lua a planté le jeu (voir piège 4). Tant que la cause n'est pas éclaircie,
   ne pas appeler ces fonctions.

8. **Bibliothèques Blueprint statiques (`BFL_General_C`, appelées via leur CDO
   `StaticFindObject("/Game/Blueprints/BFL_General.Default__BFL_General_C")`) : un paramètre d'objet de
   contexte (le `PC_Standard_C` du joueur) s'ajoute à la signature du catalogue.** Confirmé en jeu
   (2026-09-30, `lua_run`) : le compte « expected N » est toujours catalogue + 1. La position du contexte
   n'est pas constante (l'ordre du catalogue est peu fiable, piège 2). Essayer les positions ; l'erreur
   `push_objectproperty` signifie « un objet était attendu ici ». Appels validés (`pc = FindFirstOf("PC_Standard_C")`) :
   - `bfl:GetMoney(pc, pc, out)` -> `out.Money` = 100000.0
   - `bfl:GetDebt(pc, pc, o1, o2)` -> `o1.MaxDebt` = 1000000, `o1.Debt` = 0
   - `bfl:GetPlayerLevelInfo(pc, pc, o1, o2, o3, o4)` -> `o1.Level` = 12, `.Experience`, `.ExperienceNeeded`
   - `bfl:GetActiveSaveGame(pc, out)` -> `out.ActiveSaveGame` (UObject)
   - `bfl:GetPlayerInventory(pc, out)` -> `out.InventoryComponent` (UObject)
   - `bfl:GetStandardPlayerController(0, pc)` -> retour direct (le contexte est en DERNIER ici)
   - `bfl:GetVolume(pc, pc)` -> 0.5 ; `bfl:GetAllLocalGarageItems(pc, pc, out)` ; `bfl:GetCurrentLevelLandInfo(pc, o1, o2)` ;
     `bfl:GetAllInventoriesOnScreen(pc, out)`
   - Pas résolus : `GetLevelInfo`, `GetItemCategoryString`, `GetTopLevelParentWidget` (ordre à trouver).
9. **Outil de développement `lua_run`** (mod `OutOfOreAPITest`) : exécute `%APPDATA%\OutOfOreAPITest\scratch.lua`
   à chaque appel, avec `API`, `Log`, `dump`, `try` disponibles. Plus besoin de redémarrer le jeu entre
   deux essais : on édite le fichier puis `quicklaunch.py --test "lua_run"`.

### `API.Console.Register(name, fn)` / `API.Keybind.Register(key, modifierKeys, fn)` / `API.Hook.Register(path, fn)`

Wrappers de confort autour de `RegisterConsoleCommandHandler`/`RegisterKeyBind`/`RegisterHook`, protégés
par `pcall` : une erreur dans le callback est loguée (`print`) plutôt que de remonter jusqu'à UE4SS.

```lua
API.Console.Register("mon_cmd", function(FullCommand, Parameters, Ar) ... end)
API.Keybind.Register(Key.F6, {}, function() ... end)              -- 3e argument (table) obligatoire, meme vide
API.Keybind.Register(Key.N, { ModifierKey.CONTROL }, function() ... end)
API.Hook.Register("/Game/Blueprints/PS_Standard.PS_Standard_C:ReceiveTick", function(Context) ... end)
```

`Keybind.Register` respecte toujours la forme à 3 arguments (`RegisterKeyBind(Key, {Modifiers}, fn)`) :
la forme à 2 arguments provoque un Fatal error (voir pièges ci-dessous).

## Pièges hérités du projet (voir `CLAUDE.md`)

- Jamais `LoopAsync`/`ExecuteInGameThread`/`ExecuteWithDelay` (registre Lua corrompu en présence des
  hooks de terrassement du jeu).
- Jamais d'appel natif "à la main" du style `SchaktHydraulicsComponent:*` (Fatal error).
- `RegisterKeyBind` toujours à 3 arguments.
- Toujours dumper/tester dans un monde chargé, pas juste au menu principal.
