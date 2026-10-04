-- Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
-- FlatGround2 : meme principe que FlatGround (plancher Z, on raccourcit les coups de pelle sous le plancher),
-- reecrit sur OutOfOreAPI. Version minimale : pas d'interface, pas de lame automatique.
-- FlatGround reste intact ; les deux peuvent etre charges ensemble (commandes flat2_*, fichier a part),
-- mais pour comparer proprement desactivez l'un des deux dans mods.txt.
--
-- Commandes console (~ ou F10) :
--   flat2_lock          plancher = bas du dernier coup de pelle
--   flat2_set <z>       plancher = Z absolu en cm
--   flat2_adj <delta>   deplace le plancher de <delta> cm
--   flat2_off           desactive la limite
--   flat2_status        etat et statistiques
--   flat2_debug 0|1     journalise chaque correction

local API = require("OutOfOreAPI")

local Floor = nil
local Debug = false
local LastBottom = nil
local Stats = { box = 0, boxClamped = 0, boxNeutral = 0, sphere = 0, sphereClamped = 0, planeBelow = 0 }
local WriteChecked = false

local function Log(msg) print("[FlatGround2] " .. tostring(msg) .. "\n") end

-- ---------------------------------------------------------------- persistance
local DataDir = API.IPC.EnsureDataDir("OutOfOreFlat2")
local SavePath = DataDir .. "\\flat_floor.txt"

local function SaveFloor()
    pcall(function()
        local f = io.open(SavePath, "w")
        if f then
            f:write(Floor and string.format("%.1f", Floor) or "off")
            f:close()
        end
    end)
end

pcall(function()
    local f = io.open(SavePath, "r")
    if f then
        local n = tonumber(f:read("*l"))
        f:close()
        if n then Floor = n end
    end
end)

-- ---------------------------------------------------------------- geometrie
local function Rad(d) return d * math.pi / 180 end

-- Demi-hauteur verticale (monde) d'une boite tournee de demi-tailles ext (FRotator en degres).
local function VerticalHalf(rot, ext)
    local ok, hv = pcall(function()
        local p, r = Rad(rot.Pitch), Rad(rot.Roll)
        return math.abs(math.sin(p)) * ext.X
             + math.abs(math.sin(r) * math.cos(p)) * ext.Y
             + math.abs(math.cos(r) * math.cos(p)) * ext.Z
    end)
    if ok and type(hv) == "number" then return hv end
    return ext.Z
end

-- ---------------------------------------------------------------- hooks (erreurs deja absorbees par API.Hook)
local function OnRemoveBox(Context, ResultPosition, ResultValue, ResultMaterial, ModifiedValues,
                           EditedBounds, OutMessage, WorldLocation, Rotation, Extent)
    local loc, rot, ext = WorldLocation:get(), Rotation:get(), Extent:get()
    local z = loc.Z
    local hv = VerticalHalf(rot, ext)
    local bottom = z - hv
    LastBottom = bottom
    Stats.box = Stats.box + 1
    if not Floor then return end

    local d = Floor - bottom
    if d <= 0 then return end

    if d >= 2 * hv then
        -- boite entierement sous le plancher : boite minuscule au-dessus
        loc.Z = Floor + 5
        ext.X, ext.Y, ext.Z = 0.5, 0.5, 0.5
        Stats.boxNeutral = Stats.boxNeutral + 1
    else
        -- on raccourcit par le bas : le haut de la boite reste en place
        ext.Z = ext.Z * (2 * hv - d) / (2 * hv)
        loc.Z = z + d / 2
        -- boite inclinee : si elle depasse encore, on la remonte du reste
        local newBottom = loc.Z - VerticalHalf(rot, ext)
        if newBottom < Floor then loc.Z = loc.Z + (Floor - newBottom) end
        Stats.boxClamped = Stats.boxClamped + 1
    end

    if not WriteChecked then
        WriteChecked = true
        local after = WorldLocation:get().Z
        Log(string.format("verif ecriture des parametres : Z avant=%.1f apres=%.1f (%s)", z, after,
            math.abs(after - z) > 0.01 and "OK, la modification est prise en compte" or "ECHEC, non prise en compte"))
    end
    if Debug then Log(string.format("coup corrige : bas %.0f -> plancher %.0f (delta %.0f)", bottom, Floor, d)) end
end

local function OnRemoveSphere(Context, ResultPosition, ResultValue, ResultMaterial, ModifiedValues,
                              EditedBounds, OutMessage, WorldLocation, Radius)
    Stats.sphere = Stats.sphere + 1
    if not Floor then return end
    local loc, r = WorldLocation:get(), Radius:get()
    if type(r) ~= "number" then return end
    if loc.Z - r < Floor then
        local newR = loc.Z - Floor
        if newR < 0.5 then
            newR = 0.5
            loc.Z = Floor + 1
        end
        Radius:set(newR)
        Stats.sphereClamped = Stats.sphereClamped + 1
        if Debug then Log(string.format("sphere corrigee : rayon %.0f -> %.0f", r, newR)) end
    end
end

-- Observation seulement : la fonction "plane" n'est pas modifiee.
local function OnEditPlane(Context, ResultPosition, ResultValue, ResultMaterial, ModifiedValues,
                           EditedBounds, OutMessage, WorldLocation)
    if Floor and WorldLocation:get().Z < Floor then Stats.planeBelow = Stats.planeBelow + 1 end
end

local W = "/Script/OutOfOre.SchaktVoxelWorld:"
local HOOKS = {
    { W .. "MultiplayerRemoveRotatedBox", OnRemoveBox },
    { W .. "MultiplayerRemoveSphere", OnRemoveSphere },
    { W .. "MultiplayerEditVoxelValuesPlane", OnEditPlane },
}
local HookOk = {}
local function RegisterHooks()
    for _, h in ipairs(HOOKS) do
        HookOk[h[1]] = API.Hook.Register(h[1], h[2])   -- idempotent
    end
end
RegisterHooks()

-- ---------------------------------------------------------------- commandes
local function Say(Ar, msg)
    Log(msg)
    pcall(function() Ar:Log("[FlatGround2] " .. msg) end)
end

local function FloorText() return Floor and string.format("%.0f cm", Floor) or "inactif" end

API.Console.Register("flat2_lock", function(_, _, Ar)
    if not LastBottom then
        Say(Ar, "aucun coup de pelle vu pour l'instant : creusez d'abord un peu.")
    else
        Floor = LastBottom
        SaveFloor()
        Say(Ar, "plancher fixe a Z=" .. FloorText() .. " (bas du dernier coup de pelle).")
    end
end)

API.Console.Register("flat2_set", function(_, Params, Ar)
    local z = tonumber(Params and Params[1])
    if not z then return Say(Ar, "usage : flat2_set <z en cm>") end
    Floor = z
    SaveFloor()
    Say(Ar, "plancher fixe a Z=" .. FloorText())
end)

API.Console.Register("flat2_adj", function(_, Params, Ar)
    local d = tonumber(Params and Params[1])
    if not d or not Floor then return Say(Ar, "usage : flat2_adj <delta cm> (un plancher doit etre defini)") end
    Floor = Floor + d
    SaveFloor()
    Say(Ar, "plancher deplace a Z=" .. FloorText())
end)

API.Console.Register("flat2_off", function(_, _, Ar)
    Floor = nil
    SaveFloor()
    Say(Ar, "limite desactivee.")
end)

API.Console.Register("flat2_debug", function(_, Params, Ar)
    Debug = (Params and Params[1]) == "1"
    Say(Ar, "debug " .. (Debug and "actif" or "inactif"))
end)

API.Console.Register("flat2_status", function(_, _, Ar)
    Say(Ar, string.format("plancher : %s | dernier bas de coupe : %s", FloorText(),
        LastBottom and string.format("%.0f cm", LastBottom) or "?"))
    Say(Ar, string.format("coups vus=%d corriges=%d neutralises=%d | spheres vues=%d corrigees=%d | plane sous plancher=%d",
        Stats.box, Stats.boxClamped, Stats.boxNeutral, Stats.sphere, Stats.sphereClamped, Stats.planeBelow))
    local n = 0
    for _, ok in pairs(HookOk) do if ok then n = n + 1 end end
    Say(Ar, string.format("%d/%d hooks actifs", n, #HOOKS))
end)

-- ---------------------------------------------------------------- lien avec l'interface (ui/flatground_ui.pyw --mod2)
-- Meme protocole que FlatGround, dans %APPDATA%\OutOfOreFlat2 :
--   command.txt  "<id>|<cmd>|<arg>" ecrit par l'interface : set <z>, off, adj <delta>, gps <0|1>
--   state.txt    etat ecrit ici (cles floor, last_bottom, box, clamped, neutral, plane_below, hooks, gps, edge,
--                gps_ref, seq, fwd, rot, zero_rot, time). "?" = valeur absente.
-- La lecture du GPS (API.GPS) n'est faite que si l'interface la demande (commande "gps") ou si le panneau est ouvert.
local Cmd = API.IPC.NewCommandChannel(DataDir .. "\\command.txt")
local State = API.IPC.NewStateWriter(DataDir .. "\\state.txt")
local GpsOn, Gps, Seq, TickN = false, nil, 0, 0

-- Type de l'engin conduit par le joueur (« Dozer », « Excavator »... = AVS_SuperVehicleBase_C.VehicleSubCategory), ou "none" a pied.
-- Lecture mise en cache 0,5 s. Publie dans state.txt (cle `driven`) : la lame automatique n'est autorisee que dans un « Dozer ».
local Driven = { t = -10, kind = "none" }
local function DrivenKind()
    if os.clock() - Driven.t > 0.5 then
        Driven.t = os.clock()
        local kind, veh = "none", nil
        pcall(function()
            local v = API.Vehicle.FindControlled()
            if v then kind = v.VehicleSubCategory:ToString(); veh = v end
        end)
        Driven.kind, Driven.vehicle = kind, veh
    end
    return Driven.kind
end

local function Fmt(v) return v and string.format("%.1f", v) or "?" end
local function QuatText(q) return q and string.format("%.5f,%.5f,%.5f,%.5f", q.x, q.y, q.z, q.w) or "?" end

local function HookCount()
    local n = 0
    for _, ok in pairs(HookOk) do if ok then n = n + 1 end end
    return n
end

-- ---------------------------------------------------------------- panneau en jeu (F7 / F8)
-- Deux popups natifs du jeu (W_GenericPopup_C, bouton « Confirm » retire) + boutons natifs (W_Element_Button_C) + un champ
-- de saisie natif (W_Element_TextEntry_C), valides en jeu via mods/PanelTest et les sessions precedentes (2026-10-03).
--   Popup du haut : plancher actuel, tranchant, ecart, reglages (-10 / -1 / +1 / +10), actions, rappel des touches.
--   Popup du bas  : hauteurs nommees (liste de 5 par page : appliquer, « = plancher » pour la mettre a jour, supprimer ;
--                   champ nom + « Ajouter » ; < > pour changer de page). Partagees avec la fenetre Python
--                   (%APPDATA%\OutOfOreFlat\presets.json, liste de { "name": ..., "z": ... }).
-- F7 ouvre (souris dans l'interface) ; F7 deja ouvert : la souris passe de l'interface au jeu et inversement ; F8 ferme.
-- Creation / destruction des widgets dans le tick ou dans un evenement d'interface (jamais ExecuteInGameThread) ; les
-- touches ne levent qu'un drapeau. Tout est sous pcall.
local POPUP_CLASS = "/Game/Interface/InGameMenu/GenericPopup/W_GenericPopup.W_GenericPopup_C"
local BUTTON_CLASS = "/Game/Interface/Elements/W_Element_Button.W_Element_Button_C"
local ENTRY_CLASS = "/Game/Interface/Elements/W_Element_TextEntry.W_Element_TextEntry_C"
local UMG_LIB = "/Script/UMG.Default__WidgetBlueprintLibrary"
local BUTTON_PRESSED_EVT = BUTTON_CLASS .. ":BndEvt__W_Element_Button_MainButton_K2Node_ComponentBoundEvent_2_OnButtonPressedEvent__DelegateSignature"
local BUTTON_RELEASED_EVT = BUTTON_CLASS .. ":BndEvt__W_Element_Button_MainButton_K2Node_ComponentBoundEvent_3_OnButtonReleasedEvent__DelegateSignature"
local PC_PATH = "/Game/Blueprints/PC_Standard.PC_Standard_C:"

local POPUP_H = 400.0          -- hauteur d'un popup ; le second est pose juste en dessous (+10 px)
local PRESETS_DY = POPUP_H + 10.0
local ROWS = 5                 -- hauteurs nommees affichees par page
local ROW_Y0, ROW_STEP = 70.0, 52.0

-- items = tous les widgets (popups, boutons, champ) avec leur decalage (dx, dy) par rapport au coin du popup du haut ;
-- buttons = les items cliquables (hook de clic) ; widget = popup du haut.
local Panel = { widget = nil, items = {}, buttons = {}, wantToggle = false, wantClose = false, wantInput = nil,
               tab = 1, scale = 1.0, lastText = nil, refreshAt = 0, pos = { x = 400.0, y = 200.0 }, drag = nil,
               page = 1, rows = {}, entry = nil, lastFloor = false, presetsPopup = nil, presetsShown = true, toggle = nil }

local function Valid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

local function PanelOpen() return Valid(Panel.widget) end

-- ---------------------------------------------------------------- lame automatique (AutoLevel NATIF du bulldozer)
-- Le jeu (branche beta) fournit un module AutoLevel qui regule la lame sur une cible Z (touche J). On le pilote directement
-- depuis Lua, sans simuler de touches : SetManualTarget_SR(z) pose la cible, ActivateAutoLevel_SR() active (les fonctions que la
-- touche J declenche), DisableAutoLevel_SR() desactive. Valide en jeu le 2026-10-04 : tranchant de +83 cm a -1 cm du plancher en
-- 1 s, puis stable.
-- La mesure du module (Actual.Z) differe de quelques cm de celle du GPS : d = Actual.Z - tranchant GPS, mesure avant l'activation,
-- cible = plancher + decalage (+ levee en marche arriere) + d ; une petite correction integrale (d += erreur) annule le residu.
-- Securites : bulldozer seulement (DrivenKind), plancher actif requis, arret si le joueur reprend la main (J ou commande manuelle de
-- la lame : le module repasse inactif), arret en quittant l'engin.
local AutoPath = DataDir .. "/auto.txt"
local Auto = { on = false, resume = true, offset = 0.0, rev = false, revCm = 25.0, reversing = false, d = nil, lastTarget = nil, engagedAt = 0,
               lastSet = 0, lastCorr = 0, inactiveTicks = 0, revSince = nil, status = "Inactif", ctl = nil }

local function SaveAuto()
    pcall(function()
        local f = io.open(AutoPath, "w")
        if f then
            f:write(string.format("%.1f,%d,%.0f,%d", Auto.offset, Auto.rev and 1 or 0, Auto.revCm, Auto.resume and 1 or 0))
            f:close()
        end
    end)
end
pcall(function()
    local f = io.open(AutoPath, "r")
    if f then
        local o, r, c, q = (f:read("*l") or ""):match("^(-?[%d%.]+),(%d),([%d%.]+),?(%d?)$")
        f:close()
        if o then Auto.offset, Auto.rev, Auto.revCm = tonumber(o), r == "1", tonumber(c) end
        if q == "0" then Auto.resume = false end
    end
end)

-- Evenements du module natif : DisableAutoMode(true) = le joueur commande la lame a la main (a verifier) ; ActivateAutoLevel_SR hors de nos
-- appels = touche J. Une desactivation SANS l'un ni l'autre (resistance du sol...) est consideree comme native : on rearme la lame.
local AL_PATH = "/Game/VehicleComponents/AutoLevelComponent.AutoLevelComponent_C:"
local AlEv = { manualAt = -100.0, jAt = -100.0, ownAt = -100.0 }
local function RegisterAlHooks()
    API.Hook.Register(AL_PATH .. "DisableAutoMode", function(Context, a1)
        local ok, v = pcall(function() return a1:get() end)
        if ok and v == true then AlEv.manualAt = os.clock() end
    end)
    API.Hook.Register(AL_PATH .. "ActivateAutoLevel_SR", function()
        if os.clock() - AlEv.ownAt > 0.5 then AlEv.jAt = os.clock() end
    end)
end
RegisterAlHooks()

-- Journal de diagnostic (2 Hz tant que la lame auto tourne) : %APPDATA%/OutOfOreFlat2/auto_trace.txt, tronque a 400 Ko.
local TracePath = DataDir .. "/auto_trace.txt"
local function Trace(line)
    pcall(function()
        local f = io.open(TracePath, "a")
        if f then
            if f:seek("end") > 400000 then f:close(); f = io.open(TracePath, "w") end
            f:write(string.format("%.2f  %s", os.clock(), line) .. string.char(10))
            f:close()
        end
    end)
end

local function AutoComp()
    local v = Driven.vehicle
    if not v then return nil end
    local ok, c = pcall(function() return v.AutoLevelComponent end)
    if not ok or c == nil then return nil end
    local valid = false
    pcall(function() valid = c:IsValid() end)
    return valid and c or nil
end

local function AutoStop(message)
    local c = Auto.ctl
    if Auto.on and c then pcall(function() c:DisableAutoLevel_SR() end) end
    if Auto.on then Log("lame auto : arret (" .. tostring(message) .. ")") end
    Auto.on, Auto.d, Auto.lastTarget, Auto.reversing, Auto.revSince = false, nil, nil, false, nil
    Auto.status = message or "Inactif"
end

-- Demarre la lame automatique (appele par le bouton Auto). Renvoie true si elle demarre.
local function AutoStart()
    if Auto.on then return true end
    if DrivenKind() ~= "Dozer" then Auto.status = "Bulldozer requis"; return false end
    if not Floor then Auto.status = "Aucun plancher actif"; return false end
    if not AutoComp() then Auto.status = "Pas d'AutoLevel sur cet engin"; return false end
    Auto.on, Auto.d, Auto.lastTarget, Auto.engagedAt, Auto.inactiveTicks = true, nil, nil, 0, 0
    Auto.status = "Demarrage"
    Auto.rearms, Auto.rearmTimes = 0, nil
    Trace("--- demarrage plancher=" .. string.format("%.1f", Floor) .. " decalage=" .. string.format("%+.1f", Auto.offset))
    Log("lame auto : demarree (plancher " .. string.format("%.1f", Floor) .. ", decalage " .. string.format("%+.1f", Auto.offset) .. ")")
    return true
end

-- Un pas de regulation (appele a chaque tick, GPS lu). g = lecture GPS courante.
local function AutoStep(g)
    if not Auto.on then return end
    if DrivenKind() ~= "Dozer" then return AutoStop("Arret : plus dans un bulldozer") end
    if not Floor then return AutoStop("Arret : plus de plancher") end
    local c = AutoComp()
    if not c then return AutoStop("Arret : AutoLevel introuvable") end
    if not (g and g.edge) then Auto.status = "Attente du GPS"; return end
    local now = os.clock()

    -- marche arriere (hysteresis -25 / +15 cm/s, 0,3 s) : la levee de N cm ne s'applique qu'en reculant
    if Auto.rev and g.fwd then
        local want
        if Auto.reversing then want = not (g.fwd > 15.0) else want = g.fwd < -25.0 end
        if want ~= Auto.reversing then
            Auto.revSince = Auto.revSince or now
            if now - Auto.revSince >= 0.3 then Auto.reversing, Auto.revSince = want, nil; Log("lame auto : marche arriere " .. (want and "ACTIVE" or "terminee")) end
        else
            Auto.revSince = nil
        end
    else
        Auto.reversing, Auto.revSince = false, nil
    end
    local desired = Floor + Auto.offset + ((Auto.rev and Auto.reversing) and Auto.revCm or 0.0)

    local active = false
    pcall(function() active = c.AutoLevelActive == true end)
    if not active then
        if Auto.engagedAt > 0 then
            -- active par nous puis repasse inactif : J ou commande manuelle = le joueur reprend la main (arret) ; sinon c'est le module
            -- lui-meme qui s'est desactive (resistance du sol...) : on le rearme.
            Auto.inactiveTicks = Auto.inactiveTicks + 1
            if now - Auto.engagedAt <= 1.0 or Auto.inactiveTicks < 2 then return end
            local ageJ, ageM = now - AlEv.jAt, now - AlEv.manualAt
            if Auto.inactiveTicks == 2 then
                Trace(string.format("DESACTIVE : ageJ=%.2f ageDisable(true)=%.2f edge=%.1f plancher=%.1f", ageJ, ageM, g.edge, Floor))
            end
            if ageJ < 2.0 then return AutoStop("Arret : touche J") end
            if not Auto.resume then return AutoStop("Arret : desactivee par le module") end
            -- Le module appelle DisableAutoMode(true) tant que sa condition de coupure dure (resistance du sol, commande manuelle de la
            -- lame...) : on attend qu'elle cesse (0,5 s) puis on reactive. Plus de 12 reactivations en 30 s : arret.
            Auto.status = "Reprise..."
            if ageM < 0.5 then return end
            Auto.rearms = (Auto.rearms or 0) + 1
            Auto.rearmTimes = Auto.rearmTimes or {}
            Auto.rearmTimes[#Auto.rearmTimes + 1] = now
            while Auto.rearmTimes[1] and now - Auto.rearmTimes[1] > 30.0 do table.remove(Auto.rearmTimes, 1) end
            if #Auto.rearmTimes > 12 then return AutoStop("Arret : coupures repetees") end
            Log("lame auto : desactivee par le module (resistance ?), reactivation #" .. Auto.rearms)
        end
        -- (re)engagement : mesure d (mesure du module - tranchant GPS) AVANT d'activer
        local s = API.AutoLevel.ReadStatus(c)
        if not (s and s.actual and s.actual.z) then Auto.status = "AutoLevel illisible"; return end
        Auto.d = s.actual.z - g.edge
        local target = desired + Auto.d
        pcall(function() c:SetManualTarget_SR(target) end)
        AlEv.ownAt = os.clock()
        pcall(function() c:ActivateAutoLevel_SR() end)
        Auto.ctl = c
        Auto.lastTarget, Auto.engagedAt, Auto.inactiveTicks, Auto.lastSet, Auto.lastCorr = target, now, 0, now, now
        Auto.status = "Activee"
        return
    end

    Auto.inactiveTicks = 0
    if now - (Auto.lastTrace or 0) > 0.5 then
        Auto.lastTrace = now
        local st = API.AutoLevel.ReadStatus(c) or {}
        Trace(string.format("edge=%.1f desire=%.1f err=%+.1f angle=%s side=%s onTarget=%s fwd=%s rev=%s d=%.1f", g.edge, desired, desired - g.edge,
            tostring(st.angle), tostring(st.sideAngle), tostring(st.onTarget), g.fwd and string.format("%.0f", g.fwd) or "?", tostring(Auto.reversing), Auto.d or 0.0))
    end
    local target = desired + (Auto.d or 0.0)
    -- correction integrale : le tranchant reel (GPS) doit etre a `desired` ; erreur e -> d += e
    local err = desired - g.edge
    local onTarget = false
    pcall(function() onTarget = c.OnTarget == true end)
    if onTarget and now - Auto.lastCorr > 0.6 and math.abs(err) > 0.4 and math.abs(err) < 15.0 then
        Auto.d = (Auto.d or 0.0) + err * 0.8
        Auto.lastCorr = now
        target = desired + Auto.d
    end
    if (not Auto.lastTarget or math.abs(target - Auto.lastTarget) > 0.15) and now - Auto.lastSet > 0.18 then
        pcall(function() c:SetManualTarget_SR(target) end)
        Auto.lastTarget, Auto.lastSet = target, now
    end
    Auto.status = Auto.reversing and "Marche arriere" or "Tient le plancher"
end

-- ---------------------------------------------------------------- position memorisee
local PosPath = DataDir .. "\\panel_pos.txt"
-- Hauteur totale du panneau = 2 popups (810 px) : borne basse pour qu'il reste entierement visible en 1080p.
local POS_MIN_X, POS_MAX_X, POS_MIN_Y, POS_MAX_Y = -600.0, 1700.0, 0.0, 260.0

-- Taille de l'ecran d'interface (pixels / echelle d'interface), relue toutes les secondes : le panneau s'adapte a la resolution.
-- Valeurs par defaut = 1920 x 1080. Un panneau de 800 x 810 (400 si les hauteurs nommees sont masquees) est reduit
-- automatiquement pour tenir a l'ecran (EffScale), sans toucher a l'echelle voulue par l'utilisateur (Panel.scale).
local View = { w = 1920.0, h = 1080.0, t = -10.0 }
local function ViewAvail()
    if os.clock() - View.t > 1.0 then
        View.t = os.clock()
        pcall(function()
            local pc = FindFirstOf("PC_Standard_C")
            local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local v = lib:GetViewportSize(pc)
            local sc = lib:GetViewportScale(pc)
            if v and v.X and v.X > 200 and v.Y > 200 and sc and sc > 0.1 then View.w, View.h = v.X / sc, v.Y / sc end
        end)
    end
    return View.w, View.h
end
local function PanelHeight() return Panel.presetsShown and 810.0 or 410.0 end
local function EffScale()
    local vw, vh = ViewAvail()
    local fit = math.min((vw - 20.0) / 800.0, (vh - 20.0) / PanelHeight())
    return math.max(0.3, math.min(Panel.scale or 1.0, fit))
end

local function ClampPos(x, y)
    local vw, vh = ViewAvail()
    local k = EffScale()
    local minX, maxX = -(800.0 * k - 120.0), vw - 120.0     -- au moins 120 px de large restent visibles
    local maxY = math.max(0.0, vh - PanelHeight() * k - 10.0)
    return math.max(minX, math.min(maxX, x)), math.max(0.0, math.min(maxY, y))
end

local function SavePanelPos()
    pcall(function()
        local f = io.open(PosPath, "w")
        if f then
            f:write(string.format("%.1f,%.1f,%d,%.2f,%d", Panel.pos.x, Panel.pos.y, Panel.presetsShown and 1 or 0, Panel.scale or 1.0, Panel.tab or 1))
            f:close()
        end
    end)
end

pcall(function()
    local f = io.open(PosPath, "r")
    if f then
        local x, y, shown, sc, tab = f:read("*l"):match("^(-?[%d%.]+),(-?[%d%.]+),?(%d?),?([%d%.]*),?(%d?)$")
        f:close()
        if tonumber(sc) and tonumber(sc) >= 0.3 and tonumber(sc) <= 1.5 then Panel.scale = tonumber(sc) end
        if x and y then Panel.pos.x, Panel.pos.y = ClampPos(tonumber(x), tonumber(y)) end
        if shown == "0" then Panel.presetsShown = false end
        if tab == "2" then Panel.tab = 2 end
    end
end)

-- Position de la souris. GetMousePositionOnViewport lit le curseur systeme en direct ; PlayerController:GetMousePosition,
-- lui, reste fige a la position du clic tant que le bouton est maintenu (l'interface capture la souris).
local function MouseXY()
    local pc = FindFirstOf("PC_Standard_C")
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    if Valid(pc) and Valid(lib) then
        local ok, v = pcall(function() return lib:GetMousePositionOnViewport(pc) end)
        if ok and v ~= nil then
            local okX, vx, vy = pcall(function() return v.X, v.Y end)
            if okX and type(vx) == "number" then return vx, vy end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- hauteurs nommees (fichier partage avec la fenetre Python)
local PRESETS_PATH = API.IPC.EnsureDataDir("OutOfOreFlat") .. "\\presets.json"
local Presets = {}   -- { { name = , z = }, ... }

local function LoadPresets()
    local list = {}
    pcall(function()
        local f = io.open(PRESETS_PATH, "r")
        if not f then return end
        local text = f:read("*a")
        f:close()
        for obj in text:gmatch("{(.-)}") do
            local name = obj:match('"name"%s*:%s*"(.-)"')
            local z = tonumber(obj:match('"z"%s*:%s*(-?[%d%.]+[eE]?[%+%-]?%d*)'))
            if name and z then list[#list + 1] = { name = name, z = z } end
        end
    end)
    Presets = list
end

local function SavePresets()
    pcall(function()
        local parts = {}
        for _, p in ipairs(Presets) do
            parts[#parts + 1] = string.format('  {\n    "name": "%s",\n    "z": %.1f\n  }', p.name, p.z)
        end
        local f = io.open(PRESETS_PATH, "w")
        if f then
            f:write("[\n" .. table.concat(parts, ",\n") .. "\n]\n")
            f:close()
        end
    end)
end

local function PageCount() return math.max(1, math.ceil(#Presets / ROWS)) end

-- ---------------------------------------------------------------- entree (souris interface / jeu)
local function PanelSetInput(ui)
    local pc = FindFirstOf("PC_Standard_C")
    local lib = StaticFindObject(UMG_LIB)
    if not Valid(pc) or not Valid(lib) then return Log("panneau : PC ou bibliotheque UMG introuvable") end
    local ok, err
    if ui then
        ok, err = pcall(function() lib:SetInputMode_UIOnlyEx(pc, Panel.widget, 0) end)   -- 0 = DoNotLock
    else
        ok, err = pcall(function() lib:SetInputMode_GameOnly(pc) end)
    end
    if not ok then Log("panneau : SetInputMode a echoue : " .. tostring(err)) end
    pcall(function() pc.bShowMouseCursor = ui and true or false end)
    Panel.ui = ui and true or false      -- true = souris dans l'interface, false = souris au jeu
    if not ui then Panel.drag = nil end  -- pas de glissement en cours quand la souris revient au jeu
end

-- ---------------------------------------------------------------- texte du popup du haut
local function PanelText()
    -- Lignes courtes (~20 car. max, sans unite : elle est dans le titre).
    local lines = { Floor and string.format("Plancher : %.1f", Floor) or "Plancher : inactif" }
    local e = Gps and Gps.edge
    if e then
        lines[#lines + 1] = string.format("Tranchant : %.1f", e)
        lines[#lines + 1] = Floor and string.format("Ecart : %+.1f", e - Floor) or "Ecart : --"
        -- Sans engin conduit, GPS.FindNearest retombe sur l'engin le plus proche : on le signale.
        local okC, ctl = pcall(function() return API.Vehicle.FindControlled() end)
        if not (okC and ctl) then lines[#lines + 1] = "(engin proche)" end
        if Auto.on then lines[#lines + 1] = "Lame : " .. Auto.status end
    else
        lines[#lines + 1] = "Tranchant : --"
        lines[#lines + 1] = "(pas d'engin avec GPS)"
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- items (widgets) : creation, visibilite, deplacement
local function SetItemVisibility(it)
    if not Valid(it.widget) then return end
    local v = (Panel.hidden or (it.group and not Panel.presetsShown) or (it.tab and it.tab ~= Panel.tab)) and 1 or it.vis   -- 1 = Collapsed, 0 = Visible, 3 = HitTestInvisible
    pcall(function() it.widget:SetVisibility(v) end)
end

-- Affiche / cache un item (les lignes inutilisees de la liste sont repliees). Les etiquettes restent non cliquables (3).
local function SetItemShown(it, shown)
    it.vis = shown and (it.label and 3 or 0) or 1
    SetItemVisibility(it)
end

local function SetItemText(it, text)
    if not it or not Valid(it.widget) then return end
    pcall(function() it.widget["Button Text"] = FText(text) end)
    pcall(function() it.widget.Text_Button:SetText(FText(text)) end)
end

local function MakePopup(dy, title, text, keepInfo, group)
    local pc = FindFirstOf("PC_Standard_C")
    local cls = StaticFindObject(POPUP_CLASS)
    local lib = StaticFindObject(UMG_LIB)
    if not (Valid(pc) and Valid(cls) and Valid(lib)) then return nil end
    local ok, w = pcall(function() return lib:Create(pc, cls, pc) end)
    if not ok or not Valid(w) then return nil end
    pcall(function() w.W_Element_Button_Confirm:SetVisibility(1) end)   -- plus de bouton « Confirm » : F8 ferme
    if keepInfo then
        -- Le bloc de texte se repliait a une largeur variable : chaque ligne reste telle qu'ecrite (separees par \n).
        pcall(function() w.InfoText:SetAutoWrapText(false) end)
    else
        pcall(function() w.InfoText:SetVisibility(1) end)
    end
    pcall(function() w:Update(FText(title), FText(text)) end)
    pcall(function() w:AddToViewport(100) end)
    pcall(function() w:SetPositionInViewport({ X = Panel.pos.x, Y = Panel.pos.y + dy }, false) end)
    Panel.items[#Panel.items + 1] = { widget = w, dx = 0, dy = dy, vis = 0, group = group }
    return w
end

-- Bouton place par rapport au coin du popup du haut (dx, dy). opts : handle (poignee de deplacement quasi transparente),
-- height, label (etiquette non cliquable), shown = false (replie au depart).
local function PanelButton(label, dx, dy, width, action, opts)
    opts = opts or {}
    local pc = FindFirstOf("PC_Standard_C")
    local cls = StaticFindObject(BUTTON_CLASS)
    local lib = StaticFindObject(UMG_LIB)
    if not (Valid(pc) and Valid(cls) and Valid(lib)) then return nil end
    local ok, b = pcall(function() return lib:Create(pc, cls, pc) end)
    if not ok or not Valid(b) then Log("panneau : creation du bouton '" .. label .. "' echouee"); return nil end
    pcall(function() b["In Min Desired Width"] = width end)
    pcall(function() b["In Min Desired Height"] = opts.height or 50.0 end)
    if opts.handle then pcall(function() b:SetRenderOpacity(0.02) end) end
    pcall(function() b["Use Icon Texture"] = false end)
    pcall(function() b.Icon_Button:SetVisibility(1) end)   -- retire l'icone par defaut
    pcall(function() b["Button Text"] = FText(label) end)
    pcall(function() b.Text_Button:SetText(FText(label)) end)
    pcall(function() b:AddToViewport(101) end)
    pcall(function() b:SetPositionInViewport({ X = Panel.pos.x + dx, Y = Panel.pos.y + dy }, false) end)
    local full
    pcall(function() full = b:GetFullName() end)
    local it = { widget = b, fullName = full, action = action, dx = dx, dy = dy, handle = opts.handle, label = opts.label, vis = 0, group = opts.group, tab = opts.tab }
    Panel.items[#Panel.items + 1] = it
    if action or opts.handle then Panel.buttons[#Panel.buttons + 1] = it end
    if opts.label or opts.shown == false then SetItemShown(it, opts.shown ~= false) end
    return it
end

local function PanelApplyScale()
    local k = EffScale()
    Panel.lastEff, Panel.lastView = k, View.w * 10000 + View.h
    for _, it in ipairs(Panel.items) do
        if Valid(it.widget) then
            pcall(function() it.widget:SetRenderTransformPivot({ X = 0.0, Y = 0.0 }) end)
            pcall(function() it.widget:SetRenderScale({ X = k, Y = k }) end)
        end
    end
end

local function PanelMoveTo(x, y)
    x, y = ClampPos(x, y)
    Panel.pos.x, Panel.pos.y = x, y
    local k = EffScale()
    for _, it in ipairs(Panel.items) do
        if Valid(it.widget) then pcall(function() it.widget:SetPositionInViewport({ X = x + it.dx * k, Y = y + it.dy * k }, false) end) end
    end
end

-- Masque / reaffiche tout le panneau (pour ne pas recouvrir le menu du jeu).
local function PanelSetHidden(hidden)
    if not PanelOpen() then return end
    Panel.hidden = hidden and true or false
    Panel.hiddenAt = os.clock()
    for _, it in ipairs(Panel.items) do SetItemVisibility(it) end
end

local function PanelHide()
    Panel.drag, Panel.hidden = nil, false
    PanelSetInput(false)   -- toujours rendre la main au jeu avant de retirer les widgets
    for _, it in ipairs(Panel.items) do
        if Valid(it.widget) then pcall(function() it.widget:RemoveFromParent() end) end
    end
    Panel.items, Panel.buttons, Panel.rows, Panel.entry, Panel.toggle = {}, {}, {}, nil, nil
    Panel.autoBtn, Panel.autoOff, Panel.autoBtnText, Panel.autoOffText = nil, nil, nil, nil
    Panel.revBtn, Panel.revBtnText, Panel.tiltBtn, Panel.tiltBtnText = nil, nil, nil, nil
    Panel.resumeBtn, Panel.resumeBtnText = nil, nil
    Panel.widget, Panel.presetsPopup, Panel.lastText, Panel.lastFloor = nil, nil, nil, false
end

-- ---------------------------------------------------------------- liste des hauteurs nommees
local function RefreshPresets()
    if not PanelOpen() then return end
    Panel.page = math.max(1, math.min(Panel.page, PageCount()))
    for i = 1, ROWS do
        local row = Panel.rows[i]
        if row then
            local p = Presets[(Panel.page - 1) * ROWS + i]
            if p then
                local active = Floor and math.abs(p.z - Floor) < 0.05
                SetItemText(row.apply, (active and "> " or "") .. p.name .. "   " .. string.format("%.1f", p.z))
            end
            SetItemShown(row.apply, p ~= nil)
            SetItemShown(row.update, p ~= nil)
            SetItemShown(row.delete, p ~= nil)
        end
    end
    local pages = PageCount()
    if Panel.prev then SetItemShown(Panel.prev, pages > 1) end
    if Panel.next then SetItemShown(Panel.next, pages > 1) end
    local title = "Hauteurs nommees"
    if pages > 1 then title = title .. string.format("  (page %d/%d)", Panel.page, pages) end
    if Valid(Panel.presetsPopup) then
        pcall(function() Panel.presetsPopup:Update(FText(title), FText(#Presets == 0 and "" or "")) end)
    end
end

-- Etat de la lame automatique -> libelles des boutons de l'onglet « Lame ».
local function RefreshAuto()
    local btn
    if Auto.on then btn = "Auto : ACTIVE"
    elseif DrivenKind() == "Dozer" then btn = "Auto : arretee"
    else btn = "Auto : bulldozer requis" end
    local off = string.format("cible %+.1f", Auto.offset)
    local rev = string.format("Arriere : %s %.0f cm%s", Auto.rev and "ON" or "off", Auto.revCm, Auto.reversing and " *" or "")
    local resume = "Reprise : " .. (Auto.resume and "ON" or "off")
    if resume ~= Panel.resumeBtnText and Panel.resumeBtn then Panel.resumeBtnText = resume; SetItemText(Panel.resumeBtn, resume) end
    if rev ~= Panel.revBtnText and Panel.revBtn then Panel.revBtnText = rev; SetItemText(Panel.revBtn, rev) end
    if btn ~= Panel.autoBtnText and Panel.autoBtn then Panel.autoBtnText = btn; SetItemText(Panel.autoBtn, btn) end
    if off ~= Panel.autoOffText and Panel.autoOff then Panel.autoOffText = off; SetItemText(Panel.autoOff, off) end
end

local function PanelRefresh(force)
    if not PanelOpen() then return end
    RefreshAuto()
    local t = PanelText()
    if force or t ~= Panel.lastText then
        Panel.lastText = t
        local ok, err = pcall(function() Panel.widget:Update(FText("FlatGround2 (cm)"), FText(t)) end)
        if not ok then Log("panneau : Update a echoue : " .. tostring(err)) end
    end
    if force or Floor ~= Panel.lastFloor then   -- le plancher a change : remet a jour la marque « > » de la hauteur active
        Panel.lastFloor = Floor
        RefreshPresets()
    end
end

local function ReadEntry()
    if not Panel.entry or not Valid(Panel.entry.widget) then return "" end
    local out = {}
    local ok = pcall(function() Panel.entry.widget:GetEntryText(out) end)
    if not ok then return "" end
    local v = out.Text
    if type(v) == "userdata" then
        local okS, s = pcall(function() return v:ToString() end)
        v = okS and s or ""
    end
    return tostring(v or "")
end

-- ---------------------------------------------------------------- actions (executees dans l'evenement de clic)
local function Adjust(d)
    return function()
        if Floor then Floor = Floor + d; SaveFloor() end
        PanelRefresh(true)
    end
end
local ACTION_LOCK = function()
    if LastBottom then Floor = LastBottom; SaveFloor() end
    PanelRefresh(true)
end
local ACTION_EDGE = function()
    local e = Gps and Gps.edge
    if e then Floor = e; SaveFloor() end
    PanelRefresh(true)
end
-- Plancher = hauteur du sol au point vise par la camera (rayon vertical API.Terrain.ReadAim ; un engin vise ne compte pas).
local ACTION_AIM = function()
    local aim = API.Terrain.ReadAim()
    if aim and aim.z and not aim.actorClass then
        Floor = aim.z
        SaveFloor()
        API.Player.ShowMessage(string.format("Plancher = sol vise : %.1f", aim.z))
    else
        API.Player.ShowMessage("Visez le sol (pas un engin) puis cliquez")
    end
    PanelRefresh(true)
end
local ACTION_OFF = function()
    Floor = nil
    SaveFloor()
    PanelRefresh(true)
end

local function PresetAt(i) return Presets[(Panel.page - 1) * ROWS + i] end

local function ActionApply(i)
    return function()
        local p = PresetAt(i)
        if p then Floor = p.z; SaveFloor() end
        PanelRefresh(true)
    end
end
local function ActionUpdate(i)
    return function()
        local p = PresetAt(i)
        if p and Floor then p.z = Floor; SavePresets() end
        PanelRefresh(true)
    end
end
local function ActionDelete(i)
    return function()
        local idx = (Panel.page - 1) * ROWS + i
        if Presets[idx] then table.remove(Presets, idx); SavePresets() end
        PanelRefresh(true)
    end
end
local function ActionPage(d)
    return function()
        Panel.page = math.max(1, math.min(PageCount(), Panel.page + d))
        RefreshPresets()
    end
end
local ACTION_ADD = function()
    if not Floor then return end                       -- rien a enregistrer sans plancher actif
    local name = ReadEntry()
    name = name:gsub(string.char(34), ""):gsub(string.char(92), "")   -- retire " et \ (non geres par le fichier JSON)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Hauteur " .. (#Presets + 1) end
    local idx
    for i, p in ipairs(Presets) do if p.name == name then idx = i; break end end
    if idx then
        Presets[idx].z = Floor
    else
        Presets[#Presets + 1] = { name = name, z = Floor }
        idx = #Presets
    end
    SavePresets()
    Panel.page = math.ceil(idx / ROWS)
    if Panel.entry and Valid(Panel.entry.widget) then pcall(function() Panel.entry.widget:SetEntryText(FText("")) end) end
    PanelRefresh(true)
end

local function ToggleLabel() return Panel.presetsShown and "Masquer hauteurs" or "Voir hauteurs" end
local ACTION_TOGGLE = function()
    Panel.presetsShown = not Panel.presetsShown
    for _, it in ipairs(Panel.items) do
        if it.group then SetItemVisibility(it) end
    end
    SetItemText(Panel.toggle, ToggleLabel())
    SavePanelPos()
    PanelApplyScale()
    PanelMoveTo(Panel.pos.x, Panel.pos.y)
end

-- ---------------------------------------------------------------- evenements de clic
-- Inscrits a la premiere ouverture (API.Hook.Register est idempotent). Le hook des boutons s'applique a TOUS les
-- W_Element_Button_C du jeu ; on ne reagit qu'aux notres. Executes dans les evenements d'interface (game thread), y compris
-- sous le menu pause ou le tick ne tourne pas.
local function PanelRegisterEvents()
    API.Hook.Register(BUTTON_PRESSED_EVT, function(Context)
        if not PanelOpen() then return end
        local full
        pcall(function() full = Context:get():GetFullName() end)
        for _, b in ipairs(Panel.buttons) do
            if b.fullName == full then
                if b.handle then
                    -- debut de deplacement : on memorise la souris et la position du panneau
                    local mx, my = MouseXY()
                    if mx then Panel.drag = { mx = mx, my = my, px = Panel.pos.x, py = Panel.pos.y } end
                    return
                end
                return b.action()
            end
        end
    end)
    -- Relachement : fin du deplacement (le bouton garde la capture de la souris jusqu'au relachement).
    API.Hook.Register(BUTTON_RELEASED_EVT, function()
        if Panel.drag then
            Panel.drag = nil
            SavePanelPos()
        end
    end)
    -- Menu du jeu (Echap) : PC_Standard_C:OpenPauseMenu s'execute a CHAQUE appui sur Echap (ouverture comme fermeture ;
    -- les fonctions « close » ne sont jamais appelees, verifie en jeu). On masque le panneau a l'ouverture ; il est
    -- reaffiche par PanelTick, car le tick du joueur ne tourne pas pendant la pause : des qu'il reprend, le menu est ferme.
    -- Si le panneau est deja masque, l'appel est celui de la fermeture : on l'ignore.
    for _, name in ipairs({ "OpenPauseMenu", "OpenIngameMenu" }) do
        API.Hook.Register(PC_PATH .. name, function()
            if not Panel.hidden then PanelSetHidden(true) end
        end)
    end
end

-- ---------------------------------------------------------------- creation du panneau
-- Bascule d'onglet du popup du haut (1 = plancher, 2 = lame) : affiche / cache les items concernes, memorise le choix.
local function SetPanelTab(n)
    Panel.tab = n
    for _, it in ipairs(Panel.items) do
        if it.tab then SetItemVisibility(it) end
    end
    if Panel.tabBtns then
        SetItemText(Panel.tabBtns[1], n == 1 and "[Plancher]" or "Plancher")
        SetItemText(Panel.tabBtns[2], n == 2 and "[Lame]" or "Lame")
    end
    SavePanelPos()
end

local function PanelShow()
    local pc = FindFirstOf("PC_Standard_C")
    if not Valid(pc) then return Log("panneau : PC_Standard_C introuvable") end
    LoadPresets()    -- relit le fichier (la fenetre Python a pu le modifier)
    Panel.page = 1

    local main = MakePopup(0, "FlatGround2 (cm)", PanelText(), true)
    if not main then return Log("panneau : creation du popup echouee") end
    Panel.widget = main
    Panel.presetsPopup = MakePopup(PRESETS_DY, "Hauteurs nommees", "", false, true)

    -- Popup du haut (800x400) : poignee de deplacement sur la barre de titre (a gauche), deux onglets a droite de la barre :
    --   onglet 1 « Plancher » : actions + reglage fin ; onglet 2 « Lame » : lame automatique, marche arriere, inclinaison.
    PanelButton(" ", 0, 0, 540, nil, { handle = true, height = 60.0 })
    Panel.tabBtns = {
        PanelButton(Panel.tab == 1 and "[Plancher]" or "Plancher", 545, 8, 115, function() SetPanelTab(1) end, { height = 44.0 }),
        PanelButton(Panel.tab == 2 and "[Lame]" or "Lame", 665, 8, 115, function() SetPanelTab(2) end, { height = 44.0 }),
    }
    -- Onglet 1 : plancher
    PanelButton("Dernier coup", 20, 70, 145, ACTION_LOCK, { tab = 1 })
    PanelButton("= Tranchant", 170, 70, 145, ACTION_EDGE, { tab = 1 })
    PanelButton("= Vise", 320, 70, 145, ACTION_AIM, { tab = 1 })
    PanelButton("Desactiver", 470, 70, 145, ACTION_OFF, { tab = 1 })
    Panel.toggle = PanelButton(ToggleLabel(), 620, 70, 160, ACTION_TOGGLE, { tab = 1 })
    PanelButton("-10", 20, 295, 175, Adjust(-10), { tab = 1 })
    PanelButton("-1", 205, 295, 175, Adjust(-1), { tab = 1 })
    PanelButton("+1", 390, 295, 175, Adjust(1), { tab = 1 })
    PanelButton("+10", 575, 295, 175, Adjust(10), { tab = 1 })
    -- Onglet 2 : lame automatique (regulation dans la fenetre Python), decalage de la cible, marche arriere, inclinaison
    Panel.autoBtn = PanelButton("Auto : ...", 20, 70, 250, function()
        if Auto.on then AutoStop("Arretee") else AutoStart() end
        if Auto.on and Panel.ui then Panel.wantInput = false end   -- souris rendue au jeu : la lame se commande au clavier
        PanelRefresh(true)
    end, { tab = 2 })
    PanelButton("-5", 275, 70, 75, function() Auto.offset = Auto.offset - 5; SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    PanelButton("-1", 355, 70, 75, function() Auto.offset = Auto.offset - 1; SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    Panel.autoOff = PanelButton("+0.0", 435, 70, 140, nil, { label = true, tab = 2 })
    PanelButton("+1", 580, 70, 75, function() Auto.offset = Auto.offset + 1; SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    PanelButton("+5", 660, 70, 100, function() Auto.offset = Auto.offset + 5; SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    Panel.revBtn = PanelButton("Arriere : ...", 20, 295, 300, function() Auto.rev = not Auto.rev; SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    PanelButton("-5", 325, 295, 70, function() Auto.revCm = math.max(0, Auto.revCm - 5); SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    PanelButton("+5", 400, 295, 70, function() Auto.revCm = math.min(80, Auto.revCm + 5); SaveAuto(); PanelRefresh(true) end, { tab = 2 })
    Panel.resumeBtn = PanelButton("Reprise : ...", 475, 295, 305, function() Auto.resume = not Auto.resume; SaveAuto(); PanelRefresh(true) end, { tab = 2 })

    -- Popup du bas : liste (5 lignes : appliquer / = plancher / supprimer), puis champ nom, Ajouter et pages.
    for i = 1, ROWS do
        local y = PRESETS_DY + ROW_Y0 + (i - 1) * ROW_STEP
        Panel.rows[i] = {
            apply = PanelButton(" ", 20, y, 500, ActionApply(i), { shown = false, group = true }),
            update = PanelButton("= plancher", 530, y, 130, ActionUpdate(i), { shown = false, group = true }),
            delete = PanelButton("Suppr.", 670, y, 110, ActionDelete(i), { shown = false, group = true }),
        }
    end
    local ey = PRESETS_DY + 338.0
    -- Champ de saisie du nom (widget du jeu) : proprietes posees avant AddToViewport, comme pour les boutons.
    local cls = StaticFindObject(ENTRY_CLASS)
    local lib = StaticFindObject(UMG_LIB)
    if Valid(cls) and Valid(lib) then
        local okE, e = pcall(function() return lib:Create(pc, cls, pc) end)
        if okE and Valid(e) then
            -- Le champ = une etiquette (« Ne pas localiser » par defaut, texte de developpement du jeu) + une zone de saisie.
            -- Etiquette courte et zone etroite : l'ensemble (~350 px) tient avant le bouton « Ajouter » (x = 410).
            pcall(function() e["Settings Text"] = FText("Nom") end)
            pcall(function() e["Use Settings Text"] = true end)
            pcall(function() e["Hint_Settings_Text"] = FText("Nom de la hauteur") end)
            pcall(function() e["TextBoxWidth"] = 280.0 end)
            pcall(function() e:AddToViewport(101) end)
            pcall(function() e.Text_Button:SetText(FText("Nom")) end)
            pcall(function() e:SetPositionInViewport({ X = Panel.pos.x + 20, Y = Panel.pos.y + ey }, false) end)
            local it = { widget = e, dx = 20, dy = ey, vis = 0, group = true }
            Panel.items[#Panel.items + 1] = it
            Panel.entry = it
        else
            Log("panneau : creation du champ de saisie echouee : " .. tostring(e))
        end
    end
    PanelButton("Ajouter", 410, ey, 170, ACTION_ADD, { group = true })
    Panel.prev = PanelButton("<", 590, ey, 80, ActionPage(-1), { shown = false, group = true })
    Panel.next = PanelButton(">", 680, ey, 80, ActionPage(1), { shown = false, group = true })

    for _, it in ipairs(Panel.items) do
        if it.group or it.tab then SetItemVisibility(it) end
    end
    PanelApplyScale()
    PanelMoveTo(Panel.pos.x, Panel.pos.y)
    PanelRefresh(true)
    PanelSetInput(true)
end

-- ---------------------------------------------------------------- tick
-- Appelee a chaque tick (avant tout retour anticipe de UiTick).
local function PanelTick()
    -- Resolution ou taille effective changee (fenetre redimensionnee, plein ecran...) : on rescale et on recadre le panneau.
    if PanelOpen() and (Panel.lastEff ~= EffScale() or Panel.lastView ~= View.w * 10000 + View.h) then
        PanelApplyScale()
        PanelMoveTo(Panel.pos.x, Panel.pos.y)
    end
    if Panel.wantInput ~= nil then
        local want = Panel.wantInput
        Panel.wantInput = nil
        PanelSetInput(want and PanelOpen())
    end
    if Panel.wantClose then
        Panel.wantClose = false
        if PanelOpen() then PanelHide() end
    end
    if Panel.wantToggle then
        Panel.wantToggle = false
        if not PanelOpen() then
            PanelRegisterEvents()
            PanelShow()                      -- ouvre, souris dans l'interface
        else
            PanelSetInput(not Panel.ui)      -- deja ouvert : la souris passe de l'interface au jeu, ou inversement
        end
    end
    -- Panneau masque par le menu du jeu : si ce tick s'execute, le jeu n'est plus en pause (le tick s'arrete pendant la
    -- pause). Delai de 0,5 s pour ignorer les derniers ticks avant que la pause ne prenne effet.
    if Panel.hidden and PanelOpen() and os.clock() - (Panel.hiddenAt or 0) > 0.5 then PanelSetHidden(false) end
    if PanelOpen() and TickN >= Panel.refreshAt then
        Panel.refreshAt = TickN + 3
        PanelRefresh(false)
    end
end

-- Deplacement : tick rapide (60 Hz max, hook de tick du joueur) ; ne fait rien tant qu'aucun deplacement n'est en cours.
local function DragTick()
    local d = Panel.drag
    if not d then return end
    if not PanelOpen() then return end
    local mx, my = MouseXY()
    if not mx then return end
    local x, y = ClampPos(d.px + (mx - d.mx), d.py + (my - d.my))
    if x ~= Panel.pos.x or y ~= Panel.pos.y then PanelMoveTo(x, y) end
end
API.SafeTick.Register(function()
    local ok, err = pcall(DragTick)   -- SafeTick absorbe les erreurs en silence : on les journalise ici (une fois)
    if not ok and not Panel.dragErr then
        Panel.dragErr = true
        Log("panneau : erreur dans le tick de deplacement : " .. tostring(err))
    end
end, 60)
-- flat2_scale <s> : taille du panneau (0.3 a 1.5, 1 = normal), memorisee. Prend effet tout de suite si le panneau est ouvert.
API.Console.Register("flat2_scale", function(_, Params)
    local k = tonumber(Params and Params[1])
    if not k or k < 0.3 or k > 1.5 then Log("flat2_scale : valeur 0.3 a 1.5 attendue (actuelle " .. tostring(Panel.scale) .. ")"); return end
    Panel.scale = k
    if PanelOpen() then PanelApplyScale(); PanelMoveTo(Panel.pos.x, Panel.pos.y) end
    SavePanelPos()
    Log("flat2_scale : echelle " .. tostring(k))
end)
-- flat2_panel_reset : remet le panneau a sa position d'origine (secours s'il est sorti de l'ecran).
API.Console.Register("flat2_panel_reset", function()
    Panel.pos.x, Panel.pos.y = 400.0, 200.0
    SavePanelPos()
    if PanelOpen() then PanelMoveTo(400.0, 200.0) end
    Log("panneau : position remise a (400, 200)")
end)

-- F7 : ouvre le panneau ; une fois ouvert, F7 bascule la souris entre l'interface et le jeu (le panneau reste affiche,
-- utile pour garder l'ecart sous les yeux en conduisant). F8 : ferme. Echap n'est plus lie au panneau.
API.Keybind.Register(Key.F7, {}, function() Panel.wantToggle = true end)
API.Keybind.Register(Key.F8, {}, function() if PanelOpen() then Panel.wantClose = true end end)
-- flat2_input 0 : secours, rend la main au jeu (mode jeu seul + curseur masque) si le panneau a laisse les commandes bloquees.
API.Console.Register("flat2_input", function(_, Params) Panel.wantInput = (Params and Params[1]) == "1" end)

local function UiTick()
    TickN = TickN + 1
    PanelTick()
    if TickN % 10 == 0 then RegisterHooks(); RegisterAlHooks() end            -- retente les hooks (idempotent) chaque seconde
    local readGps = GpsOn or PanelOpen() or Auto.on                   -- le panneau ouvert lit aussi le GPS (ecart au plancher)
    if not readGps and TickN % 3 ~= 0 then return end     -- ~3 Hz sans GPS, 10 Hz avec

    local cmd, arg = Cmd:read()
    if cmd == "set" and type(arg) == "number" then
        Floor = arg
        SaveFloor()
        Log("interface : plancher fixe a Z=" .. FloorText())
    elseif cmd == "off" then
        Floor = nil
        SaveFloor()
        Log("interface : limite desactivee")
    elseif cmd == "adj" and type(arg) == "number" and Floor then
        Floor = Floor + arg
        SaveFloor()
        Log("interface : plancher deplace a Z=" .. FloorText())
    elseif cmd == "gps" and type(arg) == "number" then
        GpsOn = (arg == 1)
        if not GpsOn then Gps = nil end
        Log("interface : lecture GPS du tranchant " .. (GpsOn and "activee" or "desactivee"))
    end

    if readGps then
        Gps = API.GPS.Read()
        if Gps then Seq = Seq + 1 end
    else
        Gps = nil
    end
    local g = Gps or {}
    AutoStep(Gps)
    State:write({
        time = os.time(),
        floor = Floor and string.format("%.1f", Floor) or "off",
        last_bottom = Fmt(LastBottom),
        box = Stats.box, clamped = Stats.boxClamped, neutral = Stats.boxNeutral, plane_below = Stats.planeBelow,
        hooks = HookCount(),
        gps = GpsOn and 1 or 0,
        edge = Fmt(g.edge), gps_ref = Fmt(g.ref), seq = Seq, fwd = Fmt(g.fwd),
        rot = QuatText(g.rot), zero_rot = QuatText(g.zeroRot),
        driven = DrivenKind(),
    })
end
-- Un seul hook de tick (10 Hz max) : jamais LoopAsync / ExecuteInGameThread / ExecuteWithDelay.
API.SafeTick.Register(UiTick, 10)

Log("charge" .. (FG2_VERSION and (" v" .. FG2_VERSION) or "") .. ". Plancher : " .. FloorText() .. ". F7 = panneau (F7 de nouveau = souris interface/jeu, F8 = fermer). Commandes : flat2_lock, flat2_set, flat2_adj, flat2_off, flat2_status, flat2_debug, flat2_input.")
