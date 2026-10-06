-- Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
--[[
OutOfOreAPI : couche commune pour les mods UE4SS/Lua de Out of Ore.

But : arreter de re-ecrire, dans chaque mod, le meme code deja valide en jeu ailleurs dans ce projet
(echange de fichiers avec une UI compagnon, tick sur, encodage JSON, lecture de DataTable). Chaque
fonction ici reprend un pattern deja teste en jeu (voir mods/FlatGround, mods/DataTableDump) plutot
que d'inventer une nouvelle approche.

Installation (mod utilisateur) :
    UE4SS/Mods/shared/OutOfOreAPI/OutOfOreAPI.lua   (ce fichier)
    UE4SS/Mods/<VotreMod>/Scripts/main.lua :
        local API = require("OutOfOreAPI")

Regles heritees des pitfalls de ce projet (voir CLAUDE.md) et respectees ici :
  - Jamais de LoopAsync / ExecuteInGameThread / ExecuteWithDelay (corrompt le registre Lua quand ca
    tourne en meme temps que les hooks de terrassement). RegisterSafeTick() est la seule boucle
    periodique fournie, et elle passe par un hook de tick reflechi (PS_Standard_C:ReceiveTick).
  - Jamais d'appel a une fonction "wildcard"/generique hors du contexte Blueprint qui l'appelle
    normalement (ex. DataTableFunctionLibrary:GetDataTableRowFromName) : risque de Fatal error natif
    qu'un pcall Lua ne rattrape pas. ReadDataTable() n'utilise que des fonctions a signature ordinaire.
  - RegisterKeyBind toujours a 3 arguments (2 arguments plante).
]]

local OutOfOreAPI = {}

-- =============================================================================
-- Json : encodeur minimal (pas de dependance externe disponible cote UE4SS Lua).
-- Cles/valeurs : string, number, boolean, table (array ou map), nil.
-- =============================================================================

local Json = {}
OutOfOreAPI.Json = Json

function Json.encode(value, indent)
    indent = indent or ""
    local t = type(value)
    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        local escaped = value:gsub('[\\"\n\r\t]', {
            ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
        })
        return '"' .. escaped .. '"'
    elseif t == "table" then
        local isArray, n = true, 0
        for k in pairs(value) do
            n = n + 1
            if type(k) ~= "number" then isArray = false end
        end
        local childIndent = indent .. "  "
        local parts = {}
        if isArray and n > 0 then
            for i = 1, n do
                parts[#parts + 1] = childIndent .. Json.encode(value[i], childIndent)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        elseif n == 0 then
            return "{}"
        else
            local keys = {}
            for k in pairs(value) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                parts[#parts + 1] = childIndent .. Json.encode(tostring(k)) .. ": " .. Json.encode(value[k], childIndent)
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    end
    return "null"
end

-- =============================================================================
-- IPC : echange de fichiers avec une UI compagnon (meme protocole que FlatGround,
-- valide en jeu depuis 2026-09-25). Le dossier %APPDATA%\<name> est cree par l'UI,
-- pas par le mod ; si absent, les ecritures echouent silencieusement (pcall).
-- =============================================================================

local IPC = {}
OutOfOreAPI.IPC = IPC

function IPC.dataDir(name)
    return (os.getenv("APPDATA") or ".") .. "\\" .. name
end

-- Cree le dossier de donnees s'il n'existe pas (ouvrir un fichier dedans echoue sinon). Un seul `mkdir`, au premier appel :
-- une fenetre de console peut clignoter une fraction de seconde. Renvoie le chemin du dossier.
function IPC.EnsureDataDir(name)
    local dir = IPC.dataDir(name)
    local probe = io.open(dir .. "/.probe", "w")
    if probe then
        probe:close()
        os.remove(dir .. "/.probe")
    else
        pcall(os.execute, 'mkdir "' .. dir .. '"')
    end
    return dir
end

-- Canal de commande : une ligne "id|cmd|arg", l'UI change l'id a chaque nouvelle commande.
-- :read() ne renvoie une commande qu'une seule fois (dedoublonnage par id), et ignore silencieusement
-- toute commande deja presente au moment du premier appel (pas de rejeu d'une vieille commande au
-- demarrage du mod).
function IPC.NewCommandChannel(path)
    local self = { path = path, lastId = false }

    function self:read()
        local ok, line = pcall(function()
            local f = io.open(self.path, "r")
            if not f then return nil end
            local l = f:read("*l")
            f:close()
            return l
        end)
        if not ok or not line then return nil end

        local id, cmd, arg = line:match("^([^|]*)|([^|]*)|?(.*)$")
        if not id or id == "" then return nil end

        if self.lastId == false then
            -- Premier appel : on memorise l'id present sans l'executer.
            self.lastId = id
            return nil
        end
        if id == self.lastId then return nil end
        self.lastId = id
        return cmd, tonumber(arg) or arg
    end

    return self
end

-- Canal d'etat : ecrit un tableau plat "cle=valeur" par ligne (format lisible/greppable, meme choix
-- que FlatGround). Pour un etat imbrique, ecrire du JSON a la place via Json.encode + io.open direct.
function IPC.NewStateWriter(path)
    local self = { path = path }

    function self:write(fields)
        pcall(function()
            local f = io.open(self.path, "w")
            if not f then return end
            local keys = {}
            for k in pairs(fields) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                f:write(tostring(k) .. "=" .. tostring(fields[k]) .. "\n")
            end
            f:close()
        end)
    end

    return self
end

-- =============================================================================
-- SafeTick : boucle periodique via hook de tick reflechi, jamais LoopAsync/ExecuteInGameThread/
-- ExecuteWithDelay (ces derniers corrompent le registre Lua quand ils tournent en parallele des hooks
-- de terrassement -- observe et corrige dans FlatGround le 2026-09-26, cf. CLAUDE.md).
-- =============================================================================

local SafeTick = {}
OutOfOreAPI.SafeTick = SafeTick

-- callback() est appelee au plus a `hz` fois par seconde (defaut 10), dans le game thread.
-- Toute erreur dans callback est absorbee (pcall) pour ne jamais faire planter le hook.
function SafeTick.Register(callback, hz)
    local minInterval = 1 / (hz or 10)
    local state = { hooked = false, lastTick = 0 }

    local function tryRegister()
        if state.hooked then return end
        local ok = pcall(function()
            RegisterHook("/Game/Blueprints/PS_Standard.PS_Standard_C:ReceiveTick", function()
                local now = os.clock()
                if now - state.lastTick < minInterval then return end
                state.lastTick = now
                pcall(callback)
            end)
        end)
        if ok then state.hooked = true end
    end

    tryRegister()
    RegisterLoadMapPostHook(function() tryRegister() end)

    return { isHooked = function() return state.hooked end }
end

-- =============================================================================
-- DataTable : lecture sure du contenu d'une DataTable (noms de lignes + colonnes), via les seules
-- fonctions de DataTableFunctionLibrary a signature ordinaire (pas de parametre "wildcard").
-- Ne JAMAIS ajouter ici un appel a GetDataTableRowFromName : cette fonction attend un contexte
-- Blueprint reel (compilation speciale du pin generique) et peut crasher le jeu hors de ce contexte.
-- Valide en jeu par le mod DataTableDump (2026-09-27).
-- =============================================================================

local DataTable = {}
OutOfOreAPI.DataTable = DataTable

local function toLuaString(elem, depth)
    depth = depth or 0
    if elem == nil then return nil end
    if type(elem) == "string" or type(elem) == "number" or type(elem) == "boolean" then
        return tostring(elem)
    end
    if depth > 4 then return tostring(elem) end

    local okGet, inner = pcall(function() return elem:get() end)
    if okGet and inner ~= nil and inner ~= elem then
        return toLuaString(inner, depth + 1)
    end

    local okStr, s = pcall(function() return elem:ToString() end)
    if okStr and type(s) == "string" and not s:match("^RemoteUnrealParam") then
        return s
    end

    return tostring(elem)
end

local function countEntries(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Essaie plusieurs façons de lire un tableau renvoye par UE4SS (proxy ArrayProperty avec :ForEach,
-- table Lua deja peuplee, ou indexation via GetArrayNum). Necessaire car UE4SS peut marshaller un
-- parametre de sortie de facons differentes selon le type reflechi.
local function arrayToList(arr)
    if arr == nil then return {} end

    local out = {}
    local okForEach = pcall(function()
        arr:ForEach(function(idx, elem) out[idx] = toLuaString(elem) end)
    end)
    if okForEach and countEntries(out) > 0 then return out end

    out = {}
    local okIpairs = pcall(function()
        for i, elem in ipairs(arr) do out[i] = toLuaString(elem) end
    end)
    if okIpairs and countEntries(out) > 0 then return out end

    out = {}
    pcall(function()
        local n = arr:GetArrayNum()
        for i = 1, n do out[i] = toLuaString(arr[i]) end
    end)
    return out
end

-- Une fonction peut renvoyer sa valeur soit comme un vrai retour Lua, soit en remplissant un
-- parametre de sortie fourni : on tente les deux conventions (comportement observe different selon
-- la fonction UE4SS appelee).
local function callReturningArray(fn)
    local ok1, ret1 = pcall(function() return fn() end)
    if ok1 and ret1 ~= nil then
        local list = arrayToList(ret1)
        if countEntries(list) > 0 then return list end
    end

    local outTable = {}
    local ok2 = pcall(function() fn(outTable) end)
    if ok2 then
        local list = arrayToList(outTable)
        if countEntries(list) > 0 then return list end
    end

    return {}
end

-- Lit une DataTable par son chemin complet ("/Game/.../DT_Foo.DT_Foo"). Renvoie :
--   nil, "message" en cas d'echec (table introuvable)
--   { rowNames = {...}, properties = {...}, columns = { [nomPropriete] = {...valeurs...} } } sinon
function DataTable.Read(fullObjectPath)
    local dt = FindObject(nil, nil, fullObjectPath, false)
    if not dt or not dt:IsValid() then
        return nil, "DataTable introuvable : " .. tostring(fullObjectPath)
    end

    local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    if not lib or not lib:IsValid() then
        return nil, "Default__DataTableFunctionLibrary introuvable"
    end

    local rowNames = callReturningArray(function(out)
        if out then return lib:GetDataTableRowNames(dt, out) end
        return lib:GetDataTableRowNames(dt)
    end)

    local propNames = {}
    pcall(function()
        local rowStruct = dt.RowStruct
        if rowStruct and rowStruct:IsValid() then
            rowStruct:ForEachProperty(function(p)
                propNames[#propNames + 1] = p:GetFName():ToString()
            end)
        end
    end)

    local columns = {}
    for _, propName in ipairs(propNames) do
        local ok, fname = pcall(function()
            local UEHelpers = require("UEHelpers")
            return UEHelpers.FindOrAddFName(propName)
        end)
        if ok then
            columns[propName] = callReturningArray(function(out)
                if out then return lib:GetDataTableColumnAsString(dt, fname, out) end
                return lib:GetDataTableColumnAsString(dt, fname)
            end)
        end
    end

    return { rowNames = rowNames, properties = propNames, columns = columns }
end

-- =============================================================================
-- CallFunction : appel generique et sur d'une fonction UE "ordinaire" (signature normale, pas
-- wildcard) sur un objet. Generalise le pattern deja valide dans callReturningArray ci-dessus : une
-- fonction UE4SS peut renvoyer son resultat soit comme une vraie valeur de retour Lua, soit en
-- remplissant un parametre de sortie ajoute en dernier argument -- on essaie les deux conventions.
--
-- Ne JAMAIS utiliser sur une fonction "wildcard" (ex. GetDataTableRowFromName) : ces fonctions
-- attendent un contexte Blueprint reel (pin generique resolu a la compilation) et peuvent provoquer
-- un Fatal error natif qu'aucun pcall Lua ne rattrape. CallFunction ne protege QUE contre les erreurs
-- Lua normales (objet invalide, mauvais arguments, exception Lua) -- pas contre un crash natif.
--
-- Renvoie value, nil en cas de succes (value peut etre nil pour une fonction "void" qui a reussi :
-- toujours verifier err, jamais juste "value == nil") ; nil, "message" en cas d'echec.
-- =============================================================================

function OutOfOreAPI.CallFunction(obj, fnName, ...)
    local validOk, valid = pcall(function() return obj ~= nil and obj:IsValid() end)
    if not validOk or not valid then
        return nil, "objet invalide"
    end

    -- obj[fnName] renvoie un objet fonction UE4SS (pas forcement type() == "function", d'ou l'absence
    -- de verification stricte sur le type ici -- corrige le 2026-09-28 apres un premier essai en jeu
    -- qui rejetait a tort GetDataTableRowNames, pourtant valide via obj:GetDataTableRowNames(...)).
    local fn = obj[fnName]
    if fn == nil then
        return nil, "fonction introuvable : " .. tostring(fnName)
    end

    local args = { ... }
    local nArgs = select("#", ...)

    -- 1) valeur de retour directe.
    local ok1, ret1 = pcall(function() return fn(obj, table.unpack(args, 1, nArgs)) end)
    if ok1 and ret1 ~= nil then
        return ret1, nil
    end

    -- 2) parametre de sortie ajoute en dernier argument.
    local outVal = {}
    local ok2 = pcall(function() fn(obj, table.unpack(args, 1, nArgs), outVal) end)
    if ok2 and next(outVal) ~= nil then
        return outVal, nil
    end

    if ok1 then
        return nil, nil -- appel reussi, fonction "void" (rien a lire) : err == nil, value == nil.
    end

    return nil, "echec de l'appel a " .. tostring(fnName)
end

-- =============================================================================
-- Console / Keybind / Hook : wrappers de confort autour des enregistrements UE4SS, toujours proteges
-- par pcall (une erreur dans le callback ne doit jamais faire planter le hook/la commande). Reprend
-- les regles connues du projet : RegisterKeyBind toujours a 3 arguments (le 2-arg form Fatal, voir
-- CLAUDE.md), RegisterHook/RegisterConsoleCommandHandler enveloppes pour ne jamais laisser une
-- exception Lua remonter jusqu'a UE4SS.
-- =============================================================================

local Console = {}
OutOfOreAPI.Console = Console

-- fn(FullCommand, Parameters, Ar) -> rien attendu ; toute erreur est loguee et absorbee.
function Console.Register(name, fn)
    return pcall(function()
        RegisterConsoleCommandHandler(name, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                print("[OutOfOreAPI] commande '" .. tostring(name) .. "' erreur : " .. tostring(err) .. "\n")
            end
            return true
        end)
    end)
end

-- Execute une commande de la console du jeu (comme si on la tapait avec ~) : "stat fps", "t.MaxFPS 60", "r.ScreenPercentage 80"...
-- (KismetSystemLibrary:ExecuteConsoleCommand). Renvoie true si l'appel a reussi. Valide sur capture : "stat fps" affiche le
-- compteur d'images (234 FPS, 4,26 ms) ; le renvoyer le retire. Attention : les commandes de moteur ont des effets reels.
function Console.Exec(command)
    local okU, UEH = pcall(function() return require("UEHelpers") end)
    local okP, pc = pcall(function() return FindFirstOf("PC_Standard_C") end)
    if not okU or not okP or pc == nil then return false end
    return pcall(function() UEH.GetKismetSystemLibrary():ExecuteConsoleCommand(pc, tostring(command), pc) end)
end

local Keybind = {}
OutOfOreAPI.Keybind = Keybind

-- modifierKeys : table de ModifierKey.*, meme vide ({}) -- ne JAMAIS omettre ce 3e argument.
function Keybind.Register(key, modifierKeys, fn)
    return pcall(function()
        RegisterKeyBind(key, modifierKeys or {}, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                print("[OutOfOreAPI] Keybind erreur : " .. tostring(err) .. "\n")
            end
        end)
    end)
end

local Hook = {}
OutOfOreAPI.Hook = Hook

-- fn(Context, ...) suit la signature standard d'un pre-hook RegisterHook ordinaire.
-- Idempotent par chemin : un second appel avec le meme chemin ne re-enregistre rien et renvoie true
-- (utile pour retenter l'inscription apres chaque chargement de monde). Renvoie false tant que
-- l'inscription echoue (classe pas encore chargee) : le chemin n'est memorise qu'apres un succes.
local registeredHooks = {}
function Hook.Register(path, fn)
    if registeredHooks[path] then return true end
    local ok = pcall(function()
        RegisterHook(path, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                print("[OutOfOreAPI] Hook '" .. tostring(path) .. "' erreur : " .. tostring(err) .. "\n")
            end
        end)
    end)
    if ok then registeredHooks[path] = true end
    return ok
end

-- =============================================================================
-- UI : fenetres en jeu faites de widgets natifs du jeu (popup W_GenericPopup_C + boutons W_Element_Button_C), deplacables a la
-- souris, redimensionnables (echelle), avec routage des clics. Technique validee en jeu par FlatGround2 (panneau F7).
--
--   local win = API.UI.Window{ title = "Mon mod", text = "ligne 1", x = 400, y = 200, scale = 0.8 }
--   win:AddButton{ label = "Plus", x = 20, y = 300, w = 180, onClick = function() ... end }
--   win:Open()            -- ouvre (creation du popup natif) ; win:SetText("...") ; win:SetTitle("...") ; win:SetScale(0.6)
--   win:SetInput(false)   -- rend la souris/clavier au jeu (la fenetre reste affichee) ; true = souris dans l'interface
--   win:Close()
-- Positions des boutons : pixels depuis le coin haut-gauche de la fenetre (popup natif de 800 x 400 a l'echelle 1).
-- Regles : creation/destruction dans un evenement d'interface ou le tick (jamais ExecuteInGameThread) ; le tick du joueur
-- s'arrete pendant la pause du jeu ; la fenetre n'est pas masquee par le menu Echap (a gerer par le mod).
-- =============================================================================

local UI = {}
OutOfOreAPI.UI = UI

local UI_POPUP = "/Game/Interface/InGameMenu/GenericPopup/W_GenericPopup.W_GenericPopup_C"
local UI_BUTTON = "/Game/Interface/Elements/W_Element_Button.W_Element_Button_C"
local UI_LIB = "/Script/UMG.Default__WidgetBlueprintLibrary"
local UI_PRESSED = UI_BUTTON .. ":BndEvt__W_Element_Button_MainButton_K2Node_ComponentBoundEvent_2_OnButtonPressedEvent__DelegateSignature"
local UI_RELEASED = UI_BUTTON .. ":BndEvt__W_Element_Button_MainButton_K2Node_ComponentBoundEvent_3_OnButtonReleasedEvent__DelegateSignature"

local uiWindows = {}          -- fenetres ouvertes
local uiDrag = nil            -- { win, mx, my, px, py } pendant un deplacement
local uiHooked, uiTicked = false, false

local function uiValid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

local function uiMouse()
    local pc = FindFirstOf("PC_Standard_C")
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    if uiValid(pc) and uiValid(lib) then
        local ok, v = pcall(function() return lib:GetMousePositionOnViewport(pc) end)
        if ok and v ~= nil then
            local okX, vx, vy = pcall(function() return v.X, v.Y end)
            if okX and type(vx) == "number" then return vx, vy end
        end
    end
    return nil
end

local function uiPlace(win)
    local k = win.scale or 1.0
    for _, it in ipairs(win.items) do
        if uiValid(it.widget) then
            pcall(function() it.widget:SetRenderTransformPivot({ X = 0.0, Y = 0.0 }) end)
            pcall(function() it.widget:SetRenderScale({ X = k, Y = k }) end)
            pcall(function() it.widget:SetPositionInViewport({ X = win.x + it.dx * k, Y = win.y + it.dy * k }, false) end)
        end
    end
end

local function uiSetText(it, text)
    if not it or not uiValid(it.widget) then return end
    pcall(function() it.widget["Button Text"] = FText(text) end)
    pcall(function() it.widget.Text_Button:SetText(FText(text)) end)
end

local function uiMakeButton(spec, z)
    local pc = FindFirstOf("PC_Standard_C")
    local cls, lib = StaticFindObject(UI_BUTTON), StaticFindObject(UI_LIB)
    if not (uiValid(pc) and uiValid(cls) and uiValid(lib)) then return nil end
    local ok, b = pcall(function() return lib:Create(pc, cls, pc) end)
    if not ok or not uiValid(b) then return nil end
    pcall(function() b["In Min Desired Width"] = spec.w or 180.0 end)
    pcall(function() b["In Min Desired Height"] = spec.h or 50.0 end)
    if spec.handle then pcall(function() b:SetRenderOpacity(0.02) end) end
    pcall(function() b["Use Icon Texture"] = false end)
    pcall(function() b.Icon_Button:SetVisibility(1) end)
    pcall(function() b["Button Text"] = FText(spec.label or " ") end)
    pcall(function() b.Text_Button:SetText(FText(spec.label or " ")) end)
    pcall(function() b:AddToViewport(z or 101) end)
    local full
    pcall(function() full = b:GetFullName() end)
    return { widget = b, fullName = full, dx = spec.x or 0, dy = spec.y or 0, onClick = spec.onClick, handle = spec.handle,
             label = spec.label, spec = spec }
end

local function uiEnsureHooks()
    if not uiHooked then
        local a = Hook.Register(UI_PRESSED, function(Context)
            local full
            pcall(function() full = Context:get():GetFullName() end)
            if not full then return end
            for _, win in ipairs(uiWindows) do
                for _, it in ipairs(win.items) do
                    if it.fullName == full then
                        if it.handle then
                            local mx, my = uiMouse()
                            if mx then uiDrag = { win = win, mx = mx, my = my, px = win.x, py = win.y } end
                        elseif it.onClick then
                            local ok, err = pcall(it.onClick, win)
                            if not ok then print("[OutOfOreAPI] UI : erreur dans onClick : " .. tostring(err)) end
                        end
                        return
                    end
                end
            end
        end)
        local b = Hook.Register(UI_RELEASED, function()
            if uiDrag then
                local w = uiDrag.win
                uiDrag = nil
                if w.onMoved then pcall(w.onMoved, w, w.x, w.y) end
            end
        end)
        uiHooked = a and b
    end
    if not uiTicked then
        uiTicked = true
        -- tick rapide : deplacement a la souris, textes et fermetures demandes
        SafeTick.Register(function()
            for i = #uiWindows, 1, -1 do
                local w = uiWindows[i]
                if w.pendingClose then w:_destroy() end
            end
            for _, w in ipairs(uiWindows) do
                if w.pendingText and uiValid(w.popup) then
                    pcall(function() w.popup:Update(FText(w.title or ""), FText(w.text or "")) end)
                    w.pendingText = false
                end
            end
            if uiDrag then
                local mx, my = uiMouse()
                if mx then
                    local w = uiDrag.win
                    w.x, w.y = uiDrag.px + (mx - uiDrag.mx), uiDrag.py + (my - uiDrag.my)
                    uiPlace(w)
                end
            end
        end, 60)
    end
end

local Window = {}
Window.__index = Window

-- Cree (sans afficher) une fenetre. opts : title, text, x, y (defaut 400, 200), scale (defaut 1), draggable (defaut true),
-- onMoved(win, x, y) appelee quand on lache la fenetre apres un deplacement.
function UI.Window(opts)
    opts = opts or {}
    return setmetatable({ title = opts.title or "", text = opts.text or "", x = opts.x or 400.0, y = opts.y or 200.0,
        scale = opts.scale or 1.0, draggable = opts.draggable ~= false, onMoved = opts.onMoved, items = {}, specs = {},
        open = false }, Window)
end

-- Declare un bouton (cree a l'ouverture, ou tout de suite si la fenetre est deja ouverte). spec : label, x, y, w, h, onClick(win).
-- Renvoie spec (a passer a win:SetButtonText).
function Window:AddButton(spec)
    self.specs[#self.specs + 1] = spec
    if self.open then
        local it = uiMakeButton(spec, 101)
        if it then self.items[#self.items + 1] = it; uiPlace(self) end
    end
    return spec
end

function Window:SetButtonText(spec, text)
    spec.label = text
    for _, it in ipairs(self.items) do
        if it.spec == spec then it.label = text; uiSetText(it, text) end
    end
end

function Window:SetText(text) self.text = text or ""; self.pendingText = true end
function Window:SetTitle(title) self.title = title or ""; self.pendingText = true end
function Window:SetScale(k) self.scale = math.max(0.3, math.min(1.5, k or 1.0)); uiPlace(self) end
function Window:MoveTo(x, y) self.x, self.y = x, y; uiPlace(self) end
function Window:IsOpen() return self.open and uiValid(self.popup) end

-- Souris dans l'interface (true) ou rendue au jeu (false).
function Window:SetInput(ui)
    local pc = FindFirstOf("PC_Standard_C")
    local lib = StaticFindObject(UI_LIB)
    if not (uiValid(pc) and uiValid(lib)) then return false end
    if ui then
        pcall(function() lib:SetInputMode_UIOnlyEx(pc, self.popup, 0) end)
    else
        pcall(function() lib:SetInputMode_GameOnly(pc) end)
    end
    pcall(function() pc.bShowMouseCursor = ui and true or false end)
    self.ui = ui and true or false
    return true
end

-- Ouvre la fenetre. Renvoie true si le popup a ete cree.
function Window:Open()
    if self:IsOpen() then return true end
    local pc = FindFirstOf("PC_Standard_C")
    local cls, lib = StaticFindObject(UI_POPUP), StaticFindObject(UI_LIB)
    if not (uiValid(pc) and uiValid(cls) and uiValid(lib)) then return false end
    local ok, w = pcall(function() return lib:Create(pc, cls, pc) end)
    if not ok or not uiValid(w) then return false end
    pcall(function() w.W_Element_Button_Confirm:SetVisibility(1) end)
    pcall(function() w.InfoText:SetAutoWrapText(false) end)
    pcall(function() w:Update(FText(self.title), FText(self.text)) end)
    pcall(function() w:AddToViewport(100) end)
    self.popup = w
    self.items = { { widget = w, dx = 0, dy = 0 } }
    if self.draggable then
        local h = uiMakeButton({ label = " ", x = 0, y = 0, w = 800, h = 60, handle = true }, 101)
        if h then self.items[#self.items + 1] = h end
    end
    for _, spec in ipairs(self.specs) do
        local it = uiMakeButton(spec, 101)
        if it then self.items[#self.items + 1] = it end
    end
    self.open = true
    self.pendingClose = false
    uiWindows[#uiWindows + 1] = self
    uiEnsureHooks()
    uiPlace(self)
    self:SetInput(true)
    return true
end

function Window:_destroy()
    for _, it in ipairs(self.items) do
        if uiValid(it.widget) then pcall(function() it.widget:RemoveFromParent() end) end
    end
    self.items, self.popup, self.open, self.pendingClose = {}, nil, false, false
    for i = #uiWindows, 1, -1 do if uiWindows[i] == self then table.remove(uiWindows, i) end end
    if uiDrag and uiDrag.win == self then uiDrag = nil end
    local pc = FindFirstOf("PC_Standard_C")
    local lib = StaticFindObject(UI_LIB)
    if uiValid(pc) and uiValid(lib) then
        pcall(function() lib:SetInputMode_GameOnly(pc) end)
        pcall(function() pc.bShowMouseCursor = false end)
    end
end

-- Ferme la fenetre (au prochain tick, ou tout de suite si `now`).
function Window:Close(now)
    if not self.open then return end
    if now then self:_destroy() else self.pendingClose = true end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- UI.Marker : etiquette ancree sur un point du MONDE (suit le point a l'ecran, masquee quand il est derriere la camera).
--   local m = API.UI.Marker{ text = "Plancher 13250", x = 148000, y = 119000, z = 13250, w = 200 }
--   m:Show() ; m:SetText("...") ; m:SetWorld(x, y, z) ; m:Hide()
-- Projection par PlayerController:ProjectWorldLocationToScreen (valide en jeu : le point vise se projette au centre de l'ecran,
-- 960 x 540). Le widget est un bouton natif non cliquable ; mise a jour a 20 Hz par le tick de l'API.
-- ---------------------------------------------------------------------------------------------------------------------

local uiMarkers = {}
local uiMarkerTicked = false

local function uiProject(x, y, z)
    local pc = FindFirstOf("PC_Standard_C")
    if not uiValid(pc) then return nil end
    local out = {}
    local ok, on = pcall(function() return pc:ProjectWorldLocationToScreen({ X = x, Y = y, Z = z }, out, true) end)
    if not ok or not on then return nil end
    local okX, sx, sy = pcall(function() return out.X, out.Y end)
    if not okX or type(sx) ~= "number" then return nil end
    return sx, sy
end

local function uiMarkerTick()
    for _, m in ipairs(uiMarkers) do
        if m.shown and uiValid(m.widget) then
            local sx, sy = uiProject(m.wx, m.wy, m.wz)
            if sx and sx > -200 and sy > -100 then
                pcall(function() m.widget:SetVisibility(3) end)
                pcall(function() m.widget:SetPositionInViewport({ X = sx - (m.w or 160) / 2, Y = sy - (m.h or 40) / 2 }, false) end)
            else
                pcall(function() m.widget:SetVisibility(1) end)
            end
        end
    end
end

local Marker = {}
Marker.__index = Marker

-- opts : text, x, y, z (monde, cm), w, h (pixels, defaut 160 x 40).
function UI.Marker(opts)
    opts = opts or {}
    return setmetatable({ text = opts.text or "", wx = opts.x or 0, wy = opts.y or 0, wz = opts.z or 0, w = opts.w or 160,
        h = opts.h or 40, shown = false }, Marker)
end

function Marker:Show()
    if self.shown and uiValid(self.widget) then return true end
    local it = uiMakeButton({ label = self.text, x = 0, y = 0, w = self.w, h = self.h }, 99)
    if not it then return false end
    self.widget = it.widget
    pcall(function() self.widget:SetVisibility(1) end)
    self.shown = true
    uiMarkers[#uiMarkers + 1] = self
    if not uiMarkerTicked then
        uiMarkerTicked = true
        SafeTick.Register(uiMarkerTick, 20)
    end
    return true
end

function Marker:SetText(text)
    self.text = text or ""
    if uiValid(self.widget) then uiSetText({ widget = self.widget }, self.text) end
end

function Marker:SetWorld(x, y, z) self.wx, self.wy, self.wz = x, y, z end

function Marker:Hide()
    if uiValid(self.widget) then pcall(function() self.widget:RemoveFromParent() end) end
    self.widget, self.shown = nil, false
    for i = #uiMarkers, 1, -1 do if uiMarkers[i] == self then table.remove(uiMarkers, i) end end
end

-- =============================================================================
-- Debug : inspecteur d'objets en direct (equivalent de balayage_proprietes, sans passer par le dump). Lecture seule.
-- =============================================================================

local Debug = {}
OutOfOreAPI.Debug = Debug

local function describeValue(v)
    local t = type(v)
    if t == "userdata" then
        local okN, n = pcall(function() return v:GetFullName() end)
        if okN and n then return "<" .. tostring(n) .. ">" end
        local okS, str = pcall(function() return v:ToString() end)
        if okS and str ~= nil then return "str:" .. tostring(str) end
        local okA, cnt = pcall(function() return v:GetArrayNum() end)
        if okA and cnt then return "[tableau de " .. tostring(cnt) .. "]" end
        return "<userdata>"
    end
    return tostring(v)
end

-- Liste des proprietes d'un objet avec leur valeur : { { name, type, value (texte) }, ... } (proprietes de sa classe et des
-- classes parentes). `filter` (facultatif) : motif Lua applique au nom. Chaque lecture est protegee par pcall.
function Debug.Inspect(obj, filter)
    if not obj then return nil end
    local list = {}
    local okC, cls = pcall(function() return obj:GetClass() end)
    if not okC or not cls then return nil end
    local seen = {}
    local c = cls
    local guard = 0
    while c and guard < 12 do
        guard = guard + 1
        pcall(function()
            c:ForEachProperty(function(p)
                local name, ptype = p:GetFName():ToString(), nil
                pcall(function() ptype = p:GetClass():GetFName():ToString() end)
                if not seen[name] and (not filter or name:find(filter)) and not ptype:find("Delegate") then
                    seen[name] = true
                    local okV, v = pcall(function() return obj[name] end)
                    list[#list + 1] = { name = name, type = ptype, value = okV and describeValue(v) or "<illisible>" }
                end
            end)
        end)
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        c = okS and sup or nil
        if c then
            local valid = false
            pcall(function() valid = c:IsValid() end)
            if not valid then c = nil end
        end
    end
    return list
end

-- Idem pour la 1re instance vivante d'une classe, par nom court (ex. "SchaktStateBase_C", "SchaktProgressionComponent").
function Debug.InspectClass(className, filter)
    local ok, o = pcall(function() return FindFirstOf(className) end)
    local valid = false
    if ok and o ~= nil then pcall(function() valid = o:IsValid() end) end
    if not valid then return nil, "aucune instance de " .. tostring(className) end
    return Debug.Inspect(o, filter)
end

-- =============================================================================
-- Events : abonnements nommes a des evenements du jeu (hooks de journalisation sur des fonctions vues se declencher en jeu
-- par le mod EventSpy). API.Events.On("moneyEdit", function(info) ... end). Les callbacks recoivent une table
-- { name, args = { a1, a2, ... } (valeurs lues par :get()), context = <objet> } et ne doivent rien modifier de sensible :
-- ils s'executent dans le thread du jeu. Un callback en erreur est desactive pour ne pas inonder le journal.
-- Evenements valides (declenches en jeu au chargement d'une partie) : worldLoaded, possessed, moneyEdit, equip, menuToggled.
-- =============================================================================

local Events = {}
OutOfOreAPI.Events = Events

local EVENT_HOOKS = {
    worldLoaded = "/Game/Blueprints/PC_Standard.PC_Standard_C:LoadSaveGame",          -- a1 = booleen
    possessed   = "/Game/Blueprints/BP_MainCharacter.BP_MainCharacter_C:ReceivePossessed",  -- a1 = controleur
    moneyEdit   = "/Game/Blueprints/PC_Standard.PC_Standard_C:EditMoney",               -- a1 = montant (0 au chargement)
    equip       = "/Game/Blueprints/BP_MainCharacter.BP_MainCharacter_C:EquipItem",
    menuToggled = "/Game/Blueprints/PC_Standard.PC_Standard_C:OpenPauseMenu",         -- ouverture ET fermeture
}
local eventListeners, eventPending = {}, {}

local function decodeArgs(...)
    local args = {}
    for i, a in ipairs({ ... }) do
        local ok, v = pcall(function() return a:get() end)
        if ok then args[i] = v end
    end
    return args
end

local function tryRegisterEvent(name)
    local path = EVENT_HOOKS[name]
    local ok = Hook.Register(path, function(Context, ...)
        local info = { name = name, args = decodeArgs(...) }
        pcall(function() info.context = Context:get() end)
        for i = #eventListeners[name], 1, -1 do
            local okC, err = pcall(eventListeners[name][i], info)
            if not okC then
                print("[OutOfOreAPI] callback d'evenement '" .. name .. "' desactive : " .. tostring(err))
                table.remove(eventListeners[name], i)
            end
        end
    end)
    return ok
end

-- Noms d'evenements disponibles.
function Events.Names()
    local list = {}
    for k in pairs(EVENT_HOOKS) do list[#list + 1] = k end
    table.sort(list)
    return list
end

-- S'abonne a un evenement. Renvoie true si l'evenement existe (le hook est pose tout de suite ou des que la classe est chargee).
function Events.On(name, fn)
    if not EVENT_HOOKS[name] or type(fn) ~= "function" then return false end
    eventListeners[name] = eventListeners[name] or {}
    table.insert(eventListeners[name], fn)
    if not tryRegisterEvent(name) and not eventPending[name] then
        eventPending[name] = true
        OutOfOreAPI.SafeTick.Register(function()
            if eventPending[name] and tryRegisterEvent(name) then eventPending[name] = nil end
        end, 1)
    end
    return true
end

-- =============================================================================
-- AutoLevel : lecture seule du composant natif AutoLevelComponent_C ajoute par le jeu (branche beta,
-- vu la 1ere fois build Steam 25319732). Present et monte (bAutoLevelMounted) sur les dozers/loaders/
-- graders qui en sont equipes. Ne lit QUE des proprietes reflechies ordinaires (aucun appel de
-- fonction) : risque nul, meme categorie que DataTable.Read ci-dessus.
--
-- Le composant expose aussi des fonctions (SaveFunc, LoadFunc, DisableAutoMode, LoadAutoLevel) qui
-- pourraient permettre de sauvegarder/charger une cible ou activer/desactiver le mode -- delibere-
-- ment PAS exposees ici : contrairement a une lecture de propriete, un appel de fonction peut avoir
-- un effet de bord reel (deplacer la lame, changer de mode) qu'on ne connait qu'en le testant en jeu.
-- =============================================================================

local AutoLevel = {}
OutOfOreAPI.AutoLevel = AutoLevel

local function readTransform(component, propName)
    local ok, t = pcall(function() return component[propName] end)
    if not ok or t == nil then return nil end

    local okLoc, loc = pcall(function() return t.Translation end)
    local okRot, rot = pcall(function() return t.Rotation end)
    if not okLoc or not okRot then return nil end

    return {
        x = loc.X, y = loc.Y, z = loc.Z,
        qx = rot.X, qy = rot.Y, qz = rot.Z, qw = rot.W,
    }
end

local function readField(component, propName)
    local ok, v = pcall(function() return component[propName] end)
    if not ok then return nil end
    return v
end

-- Trouve l'instance valide de la classe `className` (ex. "TerraformComponent_C") dont le proprietaire
-- est le plus proche du joueur (meme logique que NearestTerraform dans FlatGround). nil si aucune.
local function findNearestOf(className)
    local UEHelpers = require("UEHelpers")
    local ploc
    pcall(function() ploc = UEHelpers.GetPlayer():K2_GetActorLocation() end)

    local list = {}
    pcall(function() list = FindAllOf(className) or {} end)

    local best, bestD
    for _, c in ipairs(list) do
        local valid = false
        pcall(function() valid = c:IsValid() end)
        if valid then
            local d = 1e30
            pcall(function()
                local o = c:GetOwner():K2_GetActorLocation()
                if ploc then
                    local dx, dy, dz = o.X - ploc.X, o.Y - ploc.Y, o.Z - ploc.Z
                    d = dx * dx + dy * dy + dz * dz
                else
                    d = 1e29
                end
            end)
            if not bestD or d < bestD then best, bestD = c, d end
        end
    end
    return best
end

-- Trouve le AutoLevelComponent_C le plus proche du joueur. nil si aucun vehicule equipe n'est a proximite.
function AutoLevel.FindNearest()
    return findNearestOf("AutoLevelComponent_C")
end

-- Lit l'etat courant d'un AutoLevelComponent_C (obtenu via AutoLevel.FindNearest() ou autrement).
-- Renvoie nil si le composant est invalide ; sinon une table a plat, chaque champ pouvant etre nil
-- individuellement si sa lecture a echoue (ne jamais supposer que tous les champs sont presents).
function AutoLevel.ReadStatus(component)
    if not component or not component:IsValid() then return nil end

    return {
        mounted = readField(component, "bAutoLevelMounted"),
        active = readField(component, "AutoLevelActive"),
        following = readField(component, "AutoLevelFollowing"),
        onTarget = readField(component, "OnTarget"),
        hasTarget = readField(component, "bHasTarget"),
        disabled = readField(component, "Disable"),
        height = readField(component, "Height"),
        angle = readField(component, "Angle"),
        sideAngle = readField(component, "SideAngle"),
        offset = readField(component, "Offset"),
        actual = readTransform(component, "Actual"),
        target = readTransform(component, "Target"),
    }
end

-- =============================================================================
-- GPS : hauteur du tranchant (lame/godet) lue via le GPS du jeu, plus la vitesse d'avancement.
-- Repris de FlatGround (valide en jeu 2026-09-25 : hauteur et ecart identiques a l'ecran GPS du jeu).
-- Lecture seule : TerraformComponent:GetInfo_GPS(HasGPS, Target, Actual) ne modifie rien. Ses 3 sorties
-- doivent etre des tables Lua et arrivent decalees : la 1re table recue est le point de reference
-- (« SET ZERO » du GPS), la 2e la position reelle du tranchant (Actual).
-- Unites : centimetres (Z monde), cm/s pour la vitesse.
-- =============================================================================

local GPS = {}
OutOfOreAPI.GPS = GPS

-- TerraformComponent_C de l'engin que le joueur conduit (API.Vehicle.FindControlled), sinon, a defaut, celui dont
-- le proprietaire est le plus proche du joueur. nil si aucun. (Le cas « engin conduit » n'a pas encore ete
-- confirme en jeu : en cas d'echec ou de nil on retombe sur le comportement « le plus proche » valide.)
function GPS.FindNearest()
    local ok, controlled = pcall(function() return OutOfOreAPI.Vehicle.FindControlled() end)
    if ok and controlled then
        local want
        pcall(function() want = controlled:GetFullName() end)
        if want then
            for _, tf in ipairs(FindAllOf("TerraformComponent_C") or {}) do
                local same = false
                pcall(function() same = tf:IsValid() and tf:GetOwner():GetFullName() == want end)
                if same then return tf end
            end
        end
    end
    return findNearestOf("TerraformComponent_C")
end

-- Vitesse d'avancement de l'engin proprietaire en cm/s : vitesse projetee sur son axe avant
-- (+ en avant, - en marche arriere). nil si illisible.
function GPS.ReadForwardSpeed(terraform)
    local ok, v = pcall(function()
        local o = terraform:GetOwner()
        local vel, fw = o:GetVelocity(), o:GetActorForwardVector()
        return vel.X * fw.X + vel.Y * fw.Y + vel.Z * fw.Z
    end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function quat(q)
    if q and type(q.W) == "number" then return { x = q.X, y = q.Y, z = q.Z, w = q.W } end
    return nil
end

-- Le GPS et l'AutoLevel (beta) sont DEUX modules distincts d'un engin, avec chacun son ecran et son point de
-- reference (GPS : SET ZERO / Num7 ; AutoLevel : N). Verifie en jeu le 2026-10-03 sur le meme engin :
-- module GPS 13324,4 / ecart 150,6 = edge / (edge - ref) ; module AutoLevel 13340,1 / cible 13340,2 =
-- Actual / Target. Cette fonction lit le second : renvoie Z reel et Z cible (cm) de l'AutoLevelComponent_C
-- monte sur le meme proprietaire que `terraform`, ou nil, nil s'il n'y en a pas ou s'il n'est pas monte.
function GPS.ReadAutoLevelZ(terraform)
    local ownerName
    pcall(function() ownerName = terraform:GetOwner():GetFullName() end)
    if not ownerName then return nil, nil end

    local list = {}
    pcall(function() list = FindAllOf("AutoLevelComponent_C") or {} end)
    for _, al in ipairs(list) do
        local same = false
        pcall(function() same = al:IsValid() and al:GetOwner():GetFullName() == ownerName end)
        if same then
            local st = AutoLevel.ReadStatus(al)
            if st and st.mounted then
                return st.actual and st.actual.z, st.target and st.target.z
            end
        end
    end
    return nil, nil
end

-- Lit le GPS d'un TerraformComponent_C (defaut : GPS.FindNearest()). Renvoie nil si aucun composant ou
-- si l'appel echoue ; sinon une table dont chaque champ peut etre nil individuellement :
--   edge     Z du tranchant (cm)              ref      Z du point de reference GPS (cm)
--   edgeX, edgeY  position horizontale du tranchant (cm)
--   rot      quaternion {x,y,z,w} du tranchant  zeroRot  quaternion du point de reference
--   fwd      vitesse d'avancement (cm/s)      component le composant utilise
--   autoLevelCurrent, autoLevelTarget  Z reel et Z cible du module AutoLevel (autre module que le GPS,
--            voir GPS.ReadAutoLevelZ) ; nil si l'engin n'a pas d'AutoLevel monte.
-- Un Z egal a 0 est traite comme « pas de valeur » (GPS inactif), comme dans FlatGround.
function GPS.Read(terraform)
    terraform = terraform or GPS.FindNearest()
    if not terraform then return nil end

    local fwd = GPS.ReadForwardSpeed(terraform)
    local ref, tgt, act = {}, {}, {}
    local ok = pcall(function() terraform:GetInfo_GPS(ref, tgt, act) end)
    if not ok then return nil end

    local function z(t)
        local v = t and t.Translation and t.Translation.Z
        if type(v) == "number" and v ~= 0 then return v end
        return nil
    end

    local function xy(t)
        local x = t and t.Translation and t.Translation.X
        local y = t and t.Translation and t.Translation.Y
        if type(x) == "number" and type(y) == "number" and (x ~= 0 or y ~= 0) then return x, y end
        return nil, nil
    end
    local edgeX, edgeY = xy(tgt)

    local rot, zeroRot
    pcall(function() rot = quat(tgt.Rotation) end)
    pcall(function() zeroRot = quat(ref.Rotation) end)

    local current, target = GPS.ReadAutoLevelZ(terraform)

    return { edge = z(tgt), edgeX = edgeX, edgeY = edgeY, ref = z(ref), rot = rot, zeroRot = zeroRot, fwd = fwd, component = terraform,
             autoLevelCurrent = current, autoLevelTarget = target }
end

-- =============================================================================
-- Outils internes pour les modules de lecture ci-dessous (World, Vehicle).
-- Fonctions toutes testees en jeu le 2026-10-03 (voir CLAUDE.md) : lecture seule, aucun effet de bord.
-- Regle de signature (cf. README) : chaque parametre "sortie" est une table {} passee a sa place, le
-- nombre exact de tables est celui que UE4SS annonce ("expected N parameters"), pas toujours celui du
-- catalogue. Les valeurs se relisent dans la 1re table.
-- =============================================================================

local function tables(n)
    local t = {}
    for i = 1, n do t[i] = {} end
    return t
end

-- Convertit une valeur UE4SS (FString/FText/entier...) en type Lua simple si possible.
local function plain(v)
    if type(v) == "userdata" then
        local ok, r = pcall(function() return v:ToString() end)
        if ok and r ~= nil then return tostring(r) end
    end
    return v
end

-- Appelle obj[fnName](obj, <nOut tables>) et renvoie la 1re table (ou nil si l'appel echoue).
local function callOut(obj, fnName, nOut)
    if not obj then return nil end
    local out = tables(nOut)
    local ok = pcall(function() obj[fnName](obj, table.unpack(out)) end)
    if not ok then return nil end
    return out[1]
end

local function prop(obj, name)
    if not obj then return nil end
    local ok, v = pcall(function() return obj[name] end)
    if ok then return plain(v) end
    return nil
end

-- =============================================================================
-- World : heure du jeu, saison et meteo (ciel/meteo Ultra Dynamic Sky/Weather). Lecture seule.
-- =============================================================================

local World = {}
OutOfOreAPI.World = World

-- Heure du jeu : { hours, minutes, seconds, day, month, year } (day/month/year = date du ciel du jeu,
-- 22/04/2021 sur la partie de test, a recouper avec l'horloge du jeu avant de s'y fier). nil si pas de ciel.
function World.ReadTime()
    local sky = FindFirstOf("Ultra_Dynamic_Sky_C")
    if not sky or not sky:IsValid() then return nil end
    local t = callOut(sky, "Get Time of Day in Real Time Format", 1)
    if not t then return nil end
    return { hours = t.Hours, minutes = t.Minutes, seconds = t.Seconds,
             day = prop(sky, "Day"), month = prop(sky, "Month"), year = prop(sky, "Year") }
end

-- Meteo : { temperatureC, temperatureF, cloudCoverage, rain (pluie/neige), wind, windDirection, season,
-- snowPercentage, wetness, lightning }. Chaque champ peut etre nil individuellement. nil si pas de meteo.
function World.ReadWeather()
    local uw = FindFirstOf("Ultra_Dynamic_Weather_C")
    if not uw or not uw:IsValid() then return nil end
    local temp = callOut(uw, "Get Current Temperature", 2)
    return {
        temperatureC = temp and temp.Celsius, temperatureF = temp and temp.Fahrenheit,
        cloudCoverage = prop(uw, "Current Cloud Coverage"), rain = prop(uw, "Current Rain / Snow"),
        wind = prop(uw, "Current Wind Intensity"), windDirection = prop(uw, "Current Wind Direction"),
        season = prop(uw, "Season"), snowPercentage = prop(uw, "Current Snow Percentage"),
        wetness = prop(uw, "Current Material Wetness"), lightning = prop(uw, "Current Lightning Intensity"),
    }
end

-- ECRITURE : regle l'heure du ciel (Ultra Dynamic Sky, propriete « Time of Day » : heures decimales x 100, ex. 14h10 = 1416.7).
-- hours 0..23, minutes 0..59. Renvoie la valeur relue, ou nil. N'agit que sur le ciel (le jeu a aussi sa propre horloge,
-- SchaktStateBase.IngameClockComponent, non modifiee ici).
function World.SetTimeOfDay(hours, minutes)
    if type(hours) ~= "number" then return nil end
    minutes = type(minutes) == "number" and minutes or 0
    local value = (math.max(0, math.min(23, hours)) + math.max(0, math.min(59, minutes)) / 60) * 100
    local ok0, o = pcall(function() return FindFirstOf("Ultra_Dynamic_Sky_C") end)
    if not ok0 or o == nil then return nil end
    local ok = pcall(function() o["Time of Day"] = value end)
    if not ok then return nil end
    return prop(o, "Time of Day")
end

-- ECRITURE : fige (false) ou relance (true) l'ecoulement du temps du ciel (« Animate Time of Day »). Renvoie la valeur relue.
function World.SetTimeFlowing(flowing)
    local ok0, o = pcall(function() return FindFirstOf("Ultra_Dynamic_Sky_C") end)
    if not ok0 or o == nil then return nil end
    local ok = pcall(function() o["Animate Time of Day"] = flowing and true or false end)
    if not ok then return nil end
    return prop(o, "Animate Time of Day")
end

-- Marqueurs de carte (BPC_MapMarkerSource_C) : un par engin et un pour le personnage, avec leur position monde.
-- Liste de { x, y, z (cm), actor (Actor suivi), actorClass (ex. "AVS_SuperVehicleBase_C"), controlledByPlayer }.
-- Note : le marqueur du personnage a controlledByPlayer = true meme a pied.
function World.ReadMarkers()
    local list = {}
    for _, c in ipairs(FindAllOf("BPC_MapMarkerSource_C") or {}) do
        local valid = false
        pcall(function() valid = c:IsValid() end)
        if valid then
            local loc = callOut(c, "GetMarkerWorldLocation", 1)
            local tracked = callOut(c, "GetMarkerTrackedActor", 1)
            local ctl = callOut(c, "IsTrackedActorControlledByPlayer", 1)
            local actor = tracked and tracked.TrackedActor
            local cls
            pcall(function() cls = actor:GetClass():GetFName():ToString() end)
            list[#list + 1] = { x = loc and loc.X, y = loc and loc.Y, z = loc and loc.Z, actor = actor,
                                actorClass = cls, controlledByPlayer = ctl and ctl.Value }
        end
    end
    return list
end

-- Formes 3D temporaires dans le monde (validees en jeu le 2026-10-04) : un StaticMeshActor local, sans collision, non sauvegarde
-- (il disparait au redemarrage). opts : mesh (chemin d'un StaticMesh deja charge, defaut le cylindre de base du moteur de 100 cm,
-- axe Z, centre sur son milieu), x, y, z (centre, cm), pitch/yaw/roll (degres), sx/sy/sz (echelle ; defaut 1), material (chemin
-- d'un materiau EXISTANT du jeu, facultatif), axis ({ x, y, z } : direction sur laquelle coucher l'axe long du cylindre ; remplace
-- pitch/yaw/roll), collision (true pour garder les collisions ; defaut non). Renvoie l'Actor, ou nil.
-- ATTENTION : les rotations d'UE ne se composent pas comme on l'attend (un Yaw ne fait pas tourner l'axe Z d'une forme inclinee) ;
-- pour orienter une forme sur une direction utiliser `axis` (formule verifiee en jeu : { Pitch = 0, Yaw = cap + 90, Roll = elevation - 90 }).
-- Materiaux utilisables, vus en jeu : "/RedBuild/Materials/MI_Preview_Success.MI_Preview_Success" (vert),
-- "/RedBuild/Materials/MI_Preview_Fail.MI_Preview_Fail" (rouge), "/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial"
-- (blanc lumineux). Pas de couleur libre : CreateDynamicMaterialInstance demande un parametre Name (a ne pas appeler).
function World.SpawnShape(opts)
    opts = opts or {}
    local ok, actor = pcall(function()
        local world = require("UEHelpers").GetWorld()
        local cls = StaticFindObject("/Script/Engine.StaticMeshActor")
        local mesh = StaticFindObject(opts.mesh or "/Engine/BasicShapes/Cylinder.Cylinder")
        if not (world and cls and mesh) then return nil end
        local pitch, yaw, roll = opts.pitch or 0.0, opts.yaw or 0.0, opts.roll or 0.0
        if opts.axis then
            local ax, ay, az = opts.axis.x, opts.axis.y, opts.axis.z
            local n = math.sqrt(ax * ax + ay * ay + az * az)
            if n > 1e-6 then
                pitch = 0.0
                yaw = math.deg(math.atan(ay, ax)) + 90.0
                roll = math.deg(math.asin(math.max(-1.0, math.min(1.0, az / n)))) - 90.0
            end
        end
        local a = world:SpawnActor(cls, { X = opts.x or 0, Y = opts.y or 0, Z = opts.z or 0 },
            { Pitch = pitch, Yaw = yaw, Roll = roll })
        if not a then return nil end
        local comp = a.StaticMeshComponent
        comp:SetMobility(2)                       -- Movable : sinon le moteur refuse de changer le maillage
        comp:SetStaticMesh(mesh)
        comp:SetWorldScale3D({ X = opts.sx or 1.0, Y = opts.sy or 1.0, Z = opts.sz or 1.0 })
        if not opts.collision then comp:SetCollisionEnabled(0) end
        if opts.material then
            local mat = StaticFindObject(opts.material)
            if mat then comp:SetMaterial(0, mat) end
        end
        return a
    end)
    if ok and actor ~= nil then return actor end
    return nil
end

-- Texte 3D dans le monde (TextRenderActor, a tester en jeu) : opts = { text, x, y, z, size (hauteur des lettres, cm ; defaut 25),
-- yaw (degres, le texte est lisible depuis la direction yaw + 180 ou yaw selon le moteur : voir World.FaceText), color = { r, g, b } (0-255) }.
-- Renvoie l'Actor ou nil (police ou classe absente). Se detruit avec World.DestroyShape.
function World.SpawnText(opts)
    opts = opts or {}
    local ok, actor = pcall(function()
        local world = require("UEHelpers").GetWorld()
        local cls = StaticFindObject("/Script/Engine.TextRenderActor")
        if not (world and cls) then return nil end
        local a = world:SpawnActor(cls, { X = opts.x or 0, Y = opts.y or 0, Z = opts.z or 0 }, { Pitch = 0.0, Yaw = opts.yaw or 0.0, Roll = 0.0 })
        if not a then return nil end
        local comp = a.TextRender
        comp:K2_SetText(FText(opts.text or ""))
        comp:SetWorldSize(opts.size or 25.0)
        comp:SetHorizontalAlignment(1)       -- centre
        comp:SetVerticalAlignment(1)         -- centre
        local c = opts.color or { 255, 255, 255 }
        comp:SetTextRenderColor({ R = c[1], G = c[2], B = c[3], A = 255 })
        return a
    end)
    if ok and actor ~= nil then return actor end
    return nil
end

-- Change le texte d'un texte 3D (World.SpawnText). Renvoie true si l'appel a reussi.
function World.SetText(actor, text, color)
    if actor == nil then return false end
    local ok = pcall(function()
        local comp = actor.TextRender
        comp:K2_SetText(FText(text or ""))
        if color then comp:SetTextRenderColor({ R = color[1], G = color[2], B = color[3], A = 255 }) end
    end)
    return ok
end

-- Change la taille (hauteur des lettres, cm) d'un texte 3D : la faire croitre avec la distance a la camera le garde lisible de loin.
function World.SetTextSize(actor, size)
    if actor == nil then return false end
    return pcall(function() actor.TextRender:SetWorldSize(size) end)
end

-- Tourne un texte 3D autour de l'axe vertical (yaw en degres) : a appeler quand le joueur bouge pour qu'il reste lisible.
function World.FaceText(actor, yaw)
    if actor == nil then return false end
    return pcall(function() actor:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false) end)
end

-- Detruit une forme creee par SpawnShape. Renvoie true si l'appel a reussi.
function World.DestroyShape(actor)
    if actor == nil then return false end
    local ok = pcall(function() actor:K2_DestroyActor() end)
    return ok
end

-- =============================================================================
-- Vehicle : tableau de bord d'un engin (AVS_SuperVehicleBase_C) et detection de l'engin conduit.
-- =============================================================================

local Vehicle = {}
OutOfOreAPI.Vehicle = Vehicle

-- Tableau de bord : { active, rpm, kmh, fuel, fuelCapacity, engineHours, gear, parkingBrake, dirtLock }.
-- `vehicle` = l'Actor engin (ex. API.GPS.FindNearest():GetOwner()). nil si l'appel echoue.
function Vehicle.ReadCluster(vehicle)
    local c = callOut(vehicle, "Get_VehicleClusterInfo", 9)   -- le catalogue en annonce 10, UE4SS en attend 9
    if not c then return nil end
    return { active = c.Active, rpm = c.RPM, kmh = c.KMH, fuel = c.FuelActual, fuelCapacity = c.FuelTotal,
             engineHours = c.Hours, gear = plain(c.Gear), parkingBrake = c.Pbrake, dirtLock = c.DirtLock }
end

-- Texte d'interaction du moment et disponibilite (« to enter vehicle » quand on est a cote).
function Vehicle.ReadInteract(vehicle)
    local i = callOut(vehicle, "Get_Interact", 2)
    if not i then return nil end
    return { text = plain(i.Info), available = i["Avalible?"] }
end

-- Engin actuellement conduit par le joueur : celui dont l'AVSBaseComponent_C repond IsControlled? = true.
-- Renvoie l'Actor, ou nil si le joueur n'est dans aucun engin. (Fonction lue sur les deux engins de la partie
-- de test, tous deux `false` joueur a pied ; le cas `true` reste a confirmer en conduisant.)
function Vehicle.FindControlled()
    for _, comp in ipairs(FindAllOf("AVSBaseComponent_C") or {}) do
        local valid = false
        pcall(function() valid = comp:IsValid() end)
        if valid then
            local r = callOut(comp, "IsControlled?", 1)
            if r and r["Controlled?"] == true then
                local owner
                pcall(function() owner = comp:GetOwner() end)
                return owner
            end
        end
    end
    return nil
end

-- Liste d'une propriete tableau (ArrayProperty) : { v1, v2, ... } (nombres, ou chaines pour les FName/FString).
-- Les elements d'un tableau de proprietes se lisent directement par indice (arr[i]) ; les tableaux de structures
-- (ex. ItemStruct) ne se lisent pas ainsi (voir CLAUDE.md).
local function propList(obj, name)
    local ok, a = pcall(function() return obj[name] end)
    if not ok or a == nil then return nil end
    local okN, n = pcall(function() return a:GetArrayNum() end)
    if not okN or not n then return nil end
    local list = {}
    for i = 1, n do
        local okE, e = pcall(function() return a[i] end)
        list[i] = okE and plain(e) or nil
    end
    return list
end

-- Composant d'un engin par nom de classe (ex. "FluidComponent_C") : propriete du meme nom sur l'engin, sinon recherche
-- parmi les instances du jeu dont le proprietaire est cet engin.
local function componentOf(vehicle, className)
    if not vehicle then return nil end
    local ok, c = pcall(function() return vehicle[(className:gsub("_C$", ""))] end)
    if ok and c ~= nil then
        local valid = false
        pcall(function() valid = c:IsValid() end)
        if valid then return c end
    end
    local vname
    pcall(function() vname = vehicle:GetFullName() end)
    for _, comp in ipairs(FindAllOf(className) or {}) do
        local owner
        pcall(function() owner = comp:GetOwner():GetFullName() end)
        if owner and owner == vname then return comp end
    end
    return nil
end

-- Fluides de l'engin (FluidComponent_C) : { { type = "DieselFuel", amount = 700.0, capacity = 1000.0, useBase = 30.0 }, ... }.
-- Le carburant de l'engin est le fluide « DieselFuel » ; les valeurs correspondent au tableau de bord (Get_VehicleClusterInfo).
-- Lecture de proprietes, aucun appel de fonction.
function Vehicle.ReadFluids(vehicle)
    local comp = componentOf(vehicle, "FluidComponent_C")
    if not comp then return nil end
    local types = propList(comp, "FluidTypes")
    local cur, max, use = propList(comp, "f_FluidAmountActual"), propList(comp, "f_FluidAmountMax"), propList(comp, "f_FluidUseBaseValue")
    if not types then return nil end
    local list = {}
    for i, t in ipairs(types) do
        list[i] = { type = t, amount = cur and cur[i], capacity = max and max[i], useBase = use and use[i] }
    end
    return list
end

-- Caracteristiques du moteur et de la transmission (AVSDriveComponent_C) : { maxRpm, workRpm, torqueNm, brakePower,
-- gearsForward = {..}, gearsReverse = {..}, hydraulicDrivetrain, rootWeight, wheelWeight }. Lecture de proprietes.
function Vehicle.ReadEngine(vehicle)
    local d = componentOf(vehicle, "AVSDriveComponent_C")
    if not d then return nil end
    return { maxRpm = prop(d, "MaxEngineRPM"), workRpm = prop(d, "WorkRpm"), torqueNm = prop(d, "EngineTorqueNm"),
             brakePower = prop(d, "BrakePower"), gearsForward = propList(d, "GearRatios_Forward"),
             gearsReverse = propList(d, "GearRatios_Reverse"), hydraulicDrivetrain = prop(d, "HydraulicDrivetrain"),
             rootWeight = prop(d, "RootWeight"), wheelWeight = prop(d, "WheelWeight"), upShiftRpm = prop(d, "UpShiftRPM"),
             downShiftRpm = prop(d, "DownShiftRPM") }
end

-- Etat de la foreuse (DrillComponent_C), pour les engins de forage : usure et temperature du trepan, tiges, avance.
-- (tous les engins ont le composant : les engins sans foreuse renvoient les valeurs par defaut). { crownWear, crownTemperature, feedSpeed, feedForce, rods, maxRods, inContact }.
function Vehicle.ReadDrill(vehicle)
    local d = componentOf(vehicle, "DrillComponent_C")
    if not d then return nil end
    return { crownWear = prop(d, "DrillCrownWear"), crownTemperature = prop(d, "DrillCrownTemperature"),
             feedSpeed = prop(d, "FeedSpeed"), feedForce = prop(d, "FeedForce"), rods = prop(d, "AmountOfUsedRods"),
             maxRods = prop(d, "MaxAmountOfRods"), inContact = prop(d, "CrownInContact") }
end

-- Configuration complete de l'engin au format XML (texte) : nom, marque, meshes, masses, hydraulique, transmission, rapports,
-- parametres de terrassement, sons, peinture... (~22 Ko pour une pelleteuse). Passe par SchaktXmlObject:SaveToString
-- (fonction native BlueprintCallable, validee en jeu : 22 569 caracteres lus sur un Arvik EX500D). Lecture seule.
-- Renvoie le texte, ou nil + message.
function Vehicle.ReadXml(vehicle)
    if not vehicle then return nil, "engin manquant" end
    local okX, xml = pcall(function() return vehicle:GetXmlObject() end)
    if not okX or xml == nil then return nil, "GetXmlObject a echoue" end
    local out = {}
    local ok = pcall(function() xml:SaveToString(out) end)
    if not ok then return nil, "SaveToString a echoue" end
    local okS, text = pcall(function() return out.OutString:ToString() end)
    if not okS or text == nil then return nil, "chaine illisible" end
    return text
end

-- Etat d'usure de l'engin (VehicleSystemBase, proprietes de l'Actor) : { wear, rust, dirt, hours } (0..1 pour les trois
-- premiers ; valeurs lues sur deux engins de la partie de test, dont un use : 0.59 / 0.18 / 0.53).
function Vehicle.ReadCondition(vehicle)
    if not vehicle then return nil end
    return { wear = prop(vehicle, "SchaktWear"), rust = prop(vehicle, "SchaktRust"), dirt = prop(vehicle, "SchaktDirt"),
             hours = prop(vehicle, "SchaktHours") }
end

-- Conduite automatique enregistree (AutoDriveComponent_C) : { recording, following, waypoints, activeIndex, maxWaypoints }.
function Vehicle.ReadAutoDrive(vehicle)
    local d = componentOf(vehicle, "AutoDriveComponent_C")
    if not d then return nil end
    local n
    local okA, arr = pcall(function() return d.RouteArray end)
    if okA and arr ~= nil then pcall(function() n = arr:GetArrayNum() end) end
    return { recording = prop(d, "bIsRecording"), following = prop(d, "bIsFollowing"), waypoints = n,
             activeIndex = prop(d, "ActiveWaypointIndex"), maxWaypoints = prop(d, "MaxWaypoints") }
end

-- Tous les engins reels de la partie (Actors AVS_SuperVehicleBase_C valides).
function Vehicle.ListAll()
    local list = {}
    for _, v in ipairs(FindAllOf("AVS_SuperVehicleBase_C") or {}) do
        local valid = false
        pcall(function() valid = v:IsValid() end)
        if valid then list[#list + 1] = v end
    end
    return list
end

-- Charge du godet / benne d'un engin, a partir de son TerraformComponent_C (ex. API.GPS.FindNearest()).
-- { fillLevel (volume), fillPercent (valeur brute du jeu), digging, dirtLock, bulk }. Chaque champ peut etre nil.
-- Les champs bool sont les memes que ceux lus par les getters valides en jeu (GetFillLevel, GetFillPrecent,
-- IsDigging, IsDirtLockActive, GetDirtMode).
function Vehicle.ReadLoad(terraform)
    if not terraform then return nil end
    local fill = callOut(terraform, "GetFillLevel", 1)
    local pct = callOut(terraform, "GetFillPrecent", 1)
    local dig = callOut(terraform, "IsDigging", 1)
    local lock = callOut(terraform, "IsDirtLockActive", 1)
    local mode = callOut(terraform, "GetDirtMode", 1)
    return { fillLevel = fill and fill.FillLevel, fillPercent = pct and pct.Precent, digging = dig and dig["IsDigging?"],
             dirtLock = lock and lock.ManualDirtLock, bulk = mode and mode.Bulk }
end

-- =============================================================================
-- Game : partie en cours, regles de la partie, progression et quetes. Lecture de proprietes seulement (aucun appel).
-- =============================================================================

local Game = {}
OutOfOreAPI.Game = Game

local function firstOf(className)
    local ok, o = pcall(function() return FindFirstOf(className) end)
    if not ok or o == nil then return nil end
    local valid = false
    pcall(function() valid = o:IsValid() end)
    return valid and o or nil
end

-- { saveName, map, mode, gameVersion, secondsPlayed } : nom de la sauvegarde (« dossier/nom »), carte, mode (« CREATIVE »...),
-- version du jeu ecrite dans la sauvegarde (ex. « 0.36.5550 »), duree de jeu de la partie en secondes.
function Game.ReadInfo()
    local gi = firstOf("SchaktGameInstance")
    if not gi then return nil end
    local sg = prop(gi, "CachedSaveGame")
    return { saveName = prop(gi, "ActiveSaveName"), map = prop(gi, "Level"), mode = prop(gi, "GameMode"),
             gameVersion = sg and prop(sg, "GameVersion"), secondsPlayed = sg and prop(sg, "TotalSecondsPlayed") }
end

-- Regles de la partie (multiplicateurs, 1.0 = normal) et reserves du joueur, lues sur l'etat de partie (SchaktGameState).
-- { breakdown, fuelConsumption, production, conveyorConverter, conveyorTransport, interestRate, maxLoan, actionSpeed,
--   harvest, runSpeed, jumpForce, questReward, explosiveRadius, maxDebt, superMoney, skillPoints, unlockedSkills, discoveredElements }
function Game.ReadRules()
    local g = firstOf("SchaktStateBase_C") or firstOf("SchaktGameState")
    if not g then return nil end
    local function count(name)
        local ok, a = pcall(function() return g[name] end)
        local okN, n = false, nil
        if ok and a ~= nil then okN, n = pcall(function() return a:GetArrayNum() end) end
        return okN and n or nil
    end
    return { breakdown = prop(g, "BreakdownMultiplier"), fuelConsumption = prop(g, "FuelConsumptionMultiplier"),
             production = prop(g, "ProductionMultiplier"), conveyorConverter = prop(g, "ConveyorConverterMultiplier"),
             conveyorTransport = prop(g, "ConveyorTransportationRateMultiplier"), interestRate = prop(g, "InterestRateMultiplier"),
             maxLoan = prop(g, "MaxLoanMultiplier"), actionSpeed = prop(g, "ActionSpeedMultiplier"),
             harvest = prop(g, "HarvestMultiplier"), runSpeed = prop(g, "RunSpeedMultiplier"),
             jumpForce = prop(g, "JumpForceMultiplier"), questReward = prop(g, "QuestRewardMultiplier"),
             explosiveRadius = prop(g, "ExplosiveRadiusMultiplier"), maxDebt = prop(g, "MaxGameDebt"),
             superMoney = prop(g, "SuperGameMoney"), skillPoints = prop(g, "SkillPoints"),
             unlockedSkills = count("UnlockedSkills"), discoveredElements = count("DiscoveredElements") }
end

-- Multiplicateurs de la partie modifiables, par cle (les memes que ceux de ReadRules).
local RULE_PROPS = { breakdown = "BreakdownMultiplier", fuelConsumption = "FuelConsumptionMultiplier",
    production = "ProductionMultiplier", conveyorConverter = "ConveyorConverterMultiplier",
    conveyorTransport = "ConveyorTransportationRateMultiplier", interestRate = "InterestRateMultiplier",
    maxLoan = "MaxLoanMultiplier", actionSpeed = "ActionSpeedMultiplier", harvest = "HarvestMultiplier",
    runSpeed = "RunSpeedMultiplier", jumpForce = "JumpForceMultiplier", questReward = "QuestRewardMultiplier",
    explosiveRadius = "ExplosiveRadiusMultiplier" }

-- ECRITURE : change un multiplicateur de la partie (1.0 = normal). `key` : breakdown, fuelConsumption, production,
-- conveyorConverter, conveyorTransport, interestRate, maxLoan, actionSpeed, harvest, runSpeed, jumpForce, questReward,
-- explosiveRadius. `value` borne a 0..100. Renvoie la valeur relue, ou nil + message. L'ecriture est confirmee par relecture
-- (valide en jeu : JumpForceMultiplier 1.0 -> 1.25 -> 1.0) ; l'EFFET en jeu depend de chaque regle et n'a pas ete verifie.
-- Meme etat que les options de partie : la valeur peut etre sauvegardee avec la partie, pensez a la restaurer.
function Game.SetRule(key, value)
    local name = RULE_PROPS[key]
    if not name then return nil, "regle inconnue : " .. tostring(key) end
    if type(value) ~= "number" or value ~= value then return nil, "valeur numerique attendue" end
    value = math.max(0.0, math.min(100.0, value))
    local g = firstOf("SchaktStateBase_C") or firstOf("SchaktGameState")
    if not g then return nil, "etat de partie introuvable" end
    local ok, err = pcall(function() g[name] = value end)
    if not ok then return nil, tostring(err) end
    return prop(g, name)
end

-- Progression du joueur : { level, xp, xpNeeded, skillLevelName } (SchaktProgressionComponent).
function Game.ReadProgression()
    local p = firstOf("SchaktProgressionComponent")
    if not p then return nil end
    return { level = prop(p, "Level"), xp = prop(p, "Experience"), xpNeeded = prop(p, "ExperienceNeeded"),
             skillLevelName = prop(p, "SkillLevelName") }
end

-- Quetes de livraison : liste { item = "500012" (ID dans DT_GameItems), current, target, money, xp, active, locked }.
function Game.ReadQuests()
    local qc = firstOf("BP_SchaktQuestComponent_C") or firstOf("SchaktQuestComponent")
    if not qc then return nil end
    local ok, arr = pcall(function() return qc.QuestObjects end)
    if not ok or arr == nil then return nil end
    local okN, n = pcall(function() return arr:GetArrayNum() end)
    if not okN or not n then return nil end
    local list = {}
    for i = 1, n do
        local okE, q = pcall(function() return arr[i] end)
        if okE and q ~= nil then
            local item
            pcall(function() item = q.DataTableRowHandle.RowName:ToString() end)
            list[#list + 1] = { item = item, current = prop(q, "CurrentAmount"), target = prop(q, "TargetAmount"),
                                money = prop(q, "RewardMoney"), xp = prop(q, "RewardExperience"),
                                active = prop(q, "bIsActive"), locked = prop(q, "bIsLocked") }
        end
    end
    return list
end

-- =============================================================================
-- Terrain : hauteur du sol par lancer de rayon vertical (KismetSystemLibrary:LineTraceSingle, fonction de bibliotheque
-- Blueprint ordinaire, appelable comme dans le LineTraceMod du kit). Le terrain voxel porte des collisions : le rayon
-- touche le sol reel, creuse ou non. Valide en jeu : sol sous le joueur 13143.6, sous deux engins 13530.6 et 13185.3 (leur
-- propre carrosserie est ignoree), points a 0.5/1/2 m cohérents. Lecture seule.
-- =============================================================================

local Terrain = {}
OutOfOreAPI.Terrain = Terrain

local function playerPawn()
    local pc = firstOf("PC_Standard_C")
    local pawn
    if pc then pcall(function() pawn = pc.Pawn end) end
    return pc, pawn
end

-- Acteurs ignores par defaut : le personnage et tous les engins (sinon le rayon touche leur carrosserie).
local function defaultIgnore(pawn)
    local list = {}
    if pawn then list[#list + 1] = pawn end
    for _, v in ipairs(FindAllOf("AVS_SuperVehicleBase_C") or {}) do
        local valid = false
        pcall(function() valid = v:IsValid() end)
        if valid then list[#list + 1] = v end
    end
    return list
end

-- Sol sous (x, y) en cm : { z, nx, ny, nz, slopeDeg } ou nil (rien touche / appel echoue).
-- opts : zTop, zBottom (hauteurs absolues du rayon ; par defaut position du joueur +/- 5000), ignore (liste d'Actors).
function Terrain.Ground(x, y, opts)
    opts = opts or {}
    local pc, pawn = playerPawn()
    local ok0, ksl = pcall(function() return require("UEHelpers").GetKismetSystemLibrary() end)
    if not ok0 or not ksl or not pc then return nil end
    local zTop, zBottom = opts.zTop, opts.zBottom
    if not zTop or not zBottom then
        local ok, loc = pcall(function() return pawn:K2_GetActorLocation() end)
        local zc = ok and loc and loc.Z or 13000
        zTop, zBottom = zTop or (zc + 5000), zBottom or (zc - 5000)
    end
    local hit = {}
    local col = { R = 0, G = 0, B = 0, A = 0 }
    local ign = opts.ignore or defaultIgnore(pawn)
    local ok, was = pcall(function()
        return ksl:LineTraceSingle(pc, { X = x, Y = y, Z = zTop }, { X = x, Y = y, Z = zBottom }, 0, false, ign, 0, hit, true, col, col, 0.0)
    end)
    if not ok or not was then return nil end
    local z, nx, ny, nz
    pcall(function() z = hit.ImpactPoint.Z end)
    pcall(function() nx, ny, nz = hit.ImpactNormal.X, hit.ImpactNormal.Y, hit.ImpactNormal.Z end)
    if not z then return nil end
    local slope = nz and math.deg(math.acos(math.max(-1, math.min(1, nz)))) or nil
    return { z = z, nx = nx, ny = ny, nz = nz, slopeDeg = slope }
end

-- Releve de la hauteur du sol sur un carre centre en (cx, cy), de demi-cote `radius` (cm) et de pas `step` (cm, defaut 200).
-- { n, min, max, range, mean, stddev, points = { {x, y, z}, ... } } ; range et stddev mesurent a quel point le terrain est plat.
function Terrain.Sample(cx, cy, radius, step, opts)
    step = step or 200
    opts = opts or {}
    local _, pawn = playerPawn()
    local o = { zTop = opts.zTop, zBottom = opts.zBottom, ignore = opts.ignore or defaultIgnore(pawn) }
    local pts, sum, mn, mx = {}, 0, nil, nil
    local x = cx - radius
    while x <= cx + radius do
        local y = cy - radius
        while y <= cy + radius do
            local g = Terrain.Ground(x, y, o)
            if g then
                pts[#pts + 1] = { x, y, g.z }
                sum = sum + g.z
                mn = (not mn or g.z < mn) and g.z or mn
                mx = (not mx or g.z > mx) and g.z or mx
            end
            y = y + step
        end
        x = x + step
    end
    if #pts == 0 then return nil end
    local mean = sum / #pts
    local var = 0
    for _, p in ipairs(pts) do var = var + (p[3] - mean) ^ 2 end
    return { n = #pts, min = mn, max = mx, range = mx - mn, mean = mean, stddev = math.sqrt(var / #pts), points = pts }
end

-- Point vise par le joueur : rayon depuis la camera, dans sa direction, sur `distance` cm (defaut 50000).
-- { x, y, z, distance (cm), actor (Actor touche ou nil), actorClass, cameraX, cameraY, cameraZ } ou nil si rien n'est touche.
-- Ignore le personnage. (Ne cache pas les engins : viser un engin renvoie l'engin.)
function Terrain.ReadAim(distance)
    distance = distance or 50000
    local pc, pawn = playerPawn()
    local okU, UEH = pcall(function() return require("UEHelpers") end)
    if not (pc and okU) then return nil end
    local ksl, kml = UEH.GetKismetSystemLibrary(), UEH.GetKismetMathLibrary()
    local okC, from, rot = pcall(function()
        local cm = pc.PlayerCameraManager
        return cm:GetCameraLocation(), cm:GetCameraRotation()
    end)
    if not okC or not from then return nil end
    local okE, to = pcall(function()
        local fwd = kml:GetForwardVector(rot)
        return { X = from.X + fwd.X * distance, Y = from.Y + fwd.Y * distance, Z = from.Z + fwd.Z * distance }
    end)
    if not okE then return nil end
    local hit = {}
    local col = { R = 0, G = 0, B = 0, A = 0 }
    local ok, was = pcall(function()
        return ksl:LineTraceSingle(pc, from, to, 0, false, pawn and { pawn } or {}, 0, hit, true, col, col, 0.0)
    end)
    if not ok or not was then return nil end
    local r = { cameraX = from.X, cameraY = from.Y, cameraZ = from.Z }
    pcall(function() r.x, r.y, r.z = hit.ImpactPoint.X, hit.ImpactPoint.Y, hit.ImpactPoint.Z end)
    pcall(function() r.distance = hit.Distance end)
    pcall(function()
        r.actor = hit.HitObjectHandle.ReferenceObject:Get()
        r.actorClass = r.actor:GetClass():GetFName():ToString()
    end)
    return r
end

-- =============================================================================
-- Land : permissions de creusage et parcelles (SchaktVoxelWorld). Fonctions natives appelables a condition d'OMETTRE le
-- parametre nomme ReturnValue (la valeur revient par le retour Lua). Lecture seule. Validé en jeu le 2026-10-04.
-- =============================================================================

local Land = {}
OutOfOreAPI.Land = Land

local function voxelWorld()
    return firstOf("SchaktVoxelWorld") or firstOf("VoxelWorld_BlueprintReal_C")
end

-- Vrai si le jeu autorise a creuser en (x, y, z) monde (cm) : SchaktVoxelWorld:CanDigHere. nil si l'appel echoue.
-- Partie de test : toujours vrai (le systeme d'achat de terrain y est desactive, `bUseLandPurchaseSystem` = false).
function Land.CanDig(x, y, z)
    local vw = voxelWorld()
    if not vw then return nil end
    local ok, r = pcall(function() return vw:CanDigHere(vw, { X = x, Y = y, Z = z or 0 }, true) end)
    if ok then return r end
    return nil
end

-- Parcelle (chunk d'achat de terrain) contenant le point monde (x, y, z) : { x, y, z } (indices entiers), ou nil.
-- Taille de parcelle : `Land.Info().chunkSize` (20000 cm sur la partie de test).
function Land.ChunkAt(x, y, z)
    local vw = voxelWorld()
    if not vw then return nil end
    local ok, c = pcall(function() return vw:GetLandPurchaseChunkFromLocation({ X = x, Y = y, Z = z or 0 }, true) end)
    if not ok or c == nil then return nil end
    local okF, cx, cy, cz = pcall(function() return c.X, c.Y, c.Z end)
    if not okF then return nil end
    return { x = cx, y = cy, z = cz }
end

-- { purchaseSystem (bool), chunkSize (cm), dataLocked (bool), voxelSize (cm), worldSizeInVoxels }.
function Land.Info()
    local vw = voxelWorld()
    if not vw then return nil end
    local okL, locked = pcall(function() return vw:IsVoxelDataLocked() end)
    return { purchaseSystem = prop(vw, "bUseLandPurchaseSystem"), chunkSize = prop(vw, "LandPurchaseChunkSize"),
             dataLocked = okL and locked or nil, voxelSize = prop(vw, "VoxelSize"), worldSizeInVoxels = prop(vw, "WorldSizeInVoxel") }
end

-- =============================================================================
-- Settings : options du joueur (SchaktSaveProfile, un objet par partie locale : GameInstance.LocalProfile). Les proprietes
-- sont lues en direct par le jeu : ecrire FOVThirdPerson change le champ de vision a l'ecran tout de suite (valide sur capture :
-- 90 -> 50 = vue zoomee, puis restaure). Les valeurs ne sont pas sauvegardees sur disque par l'API (le jeu le fait quand le
-- joueur valide ses options) : un redemarrage restaure les reglages du joueur.
-- =============================================================================

local Settings = {}
OutOfOreAPI.Settings = Settings

local function localProfile()
    local gi = firstOf("SchaktGameInstance")
    if not gi then return nil end
    local ok, p = pcall(function() return gi.LocalProfile end)
    if ok and p ~= nil then return p end
    return nil
end

-- { fovThird, fovFirst, master, effects, engine, ambient, interface, music (volumes 0..100), autoGearbox, autoDirection,
--   returnToCenterSteering }.
function Settings.Read()
    local p = localProfile()
    if not p then return nil end
    return { fovThird = prop(p, "FOVThirdPerson"), fovFirst = prop(p, "FOVFirstPerson"), master = prop(p, "MasterSound"),
             effects = prop(p, "EffectSound"), engine = prop(p, "EngineSound"), ambient = prop(p, "AmbientSound"),
             interface = prop(p, "InterfaceSound"), music = prop(p, "MusicSound"), autoGearbox = prop(p, "bAutoGearbox"),
             autoDirection = prop(p, "bAutoDirection"), returnToCenterSteering = prop(p, "bReturnToCenterSteering") }
end

-- ECRITURE : champ de vision en degres (borne a 30..120). `which` : "third" (camera exterieure) ou "first" (vue cabine).
-- Renvoie la valeur relue, ou nil.
function Settings.SetFov(which, degrees)
    local p = localProfile()
    if not p or type(degrees) ~= "number" then return nil end
    local name = which == "first" and "FOVFirstPerson" or "FOVThirdPerson"
    degrees = math.max(30.0, math.min(120.0, degrees))
    if not pcall(function() p[name] = degrees end) then return nil end
    return prop(p, name)
end

-- =============================================================================
-- Market : bourse, marches des minerais et entreprises rivales (plugin FinancialRivals). Lecture de proprietes seulement.
-- Les champs des structures de ces tableaux se lisent directement (elem.Champ), contrairement a ItemStruct.
-- N'appelez pas les fonctions natives du plugin (GetStockPrice...) : lisez ces tableaux.
-- =============================================================================

local Market = {}
OutOfOreAPI.Market = Market

-- Lit `fields` ({ cle = "ChampUE", ... }) sur chaque element d'une propriete tableau de structures.
local function structList(obj, propName, fields)
    local ok, arr = pcall(function() return obj[propName] end)
    if not ok or arr == nil then return nil end
    local okN, n = pcall(function() return arr:GetArrayNum() end)
    if not okN or not n then return nil end
    local list = {}
    for i = 1, n do
        local okE, e = pcall(function() return arr[i] end)
        if okE and e ~= nil then
            local row = {}
            for key, field in pairs(fields) do row[key] = prop(e, field) end
            list[#list + 1] = row
        end
    end
    return list
end

-- Actions en bourse : liste { ticker, name, price, previousClose, dayChangePercent, dayHigh, dayLow, allTimeHigh,
-- allTimeLow, availableShares, maxShares }. nil si la bourse n'existe pas.
function Market.ReadStocks()
    local m = firstOf("StockMarketComponent")
    if not m then return nil end
    local info = structList(m, "Stocks", { ticker = "TickerSymbol", name = "CompanyName", maxShares = "MaxShares" })
    local dyn = structList(m, "DynamicInfos", { price = "CurrentPrice", previousClose = "PreviousClosePrice",
        dayChangePercent = "DayChangePercent", dayHigh = "DayHigh", dayLow = "DayLow", allTimeHigh = "AllTimeHigh",
        allTimeLow = "AllTimeLow", availableShares = "AvailableShares" })
    if not info then return nil end
    for i, row in ipairs(info) do
        for k, v in pairs(dyn and dyn[i] or {}) do row[k] = v end
    end
    return info
end

-- { open = bool, indexBaseline } : etat general de la bourse.
function Market.ReadStatus()
    local m = firstOf("StockMarketComponent")
    if not m then return nil end
    return { open = prop(m, "bMarketOpen"), indexBaseline = prop(m, "MarketIndexBaseline") }
end

-- Marche des minerais (SchaktDynamicEconomyComponent) : liste { id, demand, price, soldThisQuarter, soldLifetime }.
function Market.ReadOres()
    local e = firstOf("SchaktDynamicEconomyComponent") or firstOf("DynamicEconomyComponent")
    if not e then return nil end
    return structList(e, "Markets", { id = "ResourceID", demand = "DemandLevel", price = "CurrentGlobalPrice",
        soldThisQuarter = "SoldThisQuarter", soldLifetime = "SoldLifetime" })
end

-- Acheteurs (marchands) : liste { id, capital, spentLifetime }.
function Market.ReadMerchants()
    local e = firstOf("SchaktDynamicEconomyComponent") or firstOf("DynamicEconomyComponent")
    if not e then return nil end
    return structList(e, "Wallets", { id = "MerchantID", capital = "Capital", spentLifetime = "SpentLifetime" })
end

-- Classement des entreprises (CompetitiveKPIComponent) : liste { rank, id, name, score, pursuit, isPlayer }.
function Market.ReadRivals()
    local k = firstOf("CompetitiveKPIComponent")
    if not k then return nil end
    return structList(k, "CachedRankings", { rank = "Rank", id = "CompanyID", name = "DisplayName",
        score = "CompositeScore", pursuit = "PursuitIntensity", isPlayer = "bIsPlayer" })
end

-- =============================================================================
-- Inventory : contenu des inventaires (joueur, engins) via SchaktInventoryComponent. Lecture de proprietes seulement.
-- =============================================================================

local Inventory = {}
OutOfOreAPI.Inventory = Inventory

local function slotList(structArray)
    local list = {}
    local ok, items = pcall(function() return structArray.Items end)
    if not ok or items == nil then return list end
    local okN, n = pcall(function() return items:GetArrayNum() end)
    for i = 1, (okN and n or 0) do
        local okE, e = pcall(function() return items[i] end)
        if okE and e ~= nil then list[#list + 1] = { index = prop(e, "Index"), id = prop(e, "ID"), amount = prop(e, "Amount") } end
    end
    return list
end

-- Contenu d'un SchaktInventoryComponent : { name, maxSize, items = { {index, id, amount}, ... }, equipment = { ... } }.
-- `id` = identifiant dans DT_GameItems (300001 = Pickaxe...).
function Inventory.Read(component)
    if not component then return nil end
    local okI, inv = pcall(function() return component.Inventory end)
    if not okI or inv == nil then return nil end
    local okE, eq = pcall(function() return component.Equipment end)
    return { name = prop(component, "InventoryName"), maxSize = prop(component, "MaxSize"), items = slotList(inv),
             equipment = okE and eq ~= nil and slotList(eq) or {} }
end

-- Tous les inventaires de la partie : liste { owner = <Actor>, ownerClass, name, maxSize, items, equipment }.
function Inventory.ReadAll()
    local list = {}
    for _, comp in ipairs(FindAllOf("SchaktInventoryComponent") or {}) do
        local valid = false
        pcall(function() valid = comp:IsValid() end)
        if valid then
            local r = Inventory.Read(comp)
            if r then
                pcall(function() r.owner = comp:GetOwner(); r.ownerClass = r.owner:GetClass():GetFName():ToString() end)
                list[#list + 1] = r
            end
        end
    end
    return list
end

-- Inventaire du joueur (celui du PC_Standard_C, « PLAYER INVENTORY »), ou nil.
function Inventory.ReadPlayer()
    for _, r in ipairs(Inventory.ReadAll()) do
        if r.ownerClass == "PC_Standard_C" then return r end
    end
    return nil
end

-- Inventaire d'un engin (Actor AVS_SuperVehicleBase_C), ou nil.
function Inventory.ReadVehicle(vehicle)
    return Inventory.Read(componentOf(vehicle, "SchaktInventoryComponent"))
end

-- =============================================================================
-- Player : argent, dette et barre d'outils du joueur (PC_Standard_C). Lecture seule.
-- Ne JAMAIS appeler PC_Standard_C:GetPlayerData ici (fige le jeu, voir CLAUDE.md).
-- =============================================================================

local Player = {}
OutOfOreAPI.Player = Player

-- Affiche un message a l'ecran, au centre (la notification native du jeu : PC_Standard_C:SendInfoMessage). Renvoie true si
-- l'appel a reussi. Valide sur capture le 2026-10-04 (texte blanc sur bandeau sombre, au-dessus du personnage).
function Player.ShowMessage(text)
    local ok0, pc = pcall(function() return FindFirstOf("PC_Standard_C") end)
    if not ok0 or pc == nil then return false end
    local ok = pcall(function() pc:SendInfoMessage(FText(tostring(text))) end)
    return ok
end

-- { money, companyMoney, debt, maxDebt, toolbarIndex, companyRole }. Chaque champ peut etre nil.
function Player.ReadFinance()
    local pc = FindFirstOf("PC_Standard_C")
    if not pc or not pc:IsValid() then return nil end
    local money = callOut(pc, "GetMyMoney", 1)
    local company = callOut(pc, "GetMyCompanyMoney", 1)
    local debt = callOut(pc, "Get_Debt", 2)
    local toolbar = callOut(pc, "Get_ActiveToolbarIndex", 1)
    local role
    pcall(function() role = pc:GetCompanyRole() end)
    return { money = money and money.MyMoney, companyMoney = company and company.MyCompanyMoney,
             debt = debt and debt.Debt, maxDebt = debt and debt.MaxDebt,
             toolbarIndex = toolbar and toolbar.ToolbarIndex, companyRole = role }
end

-- Objet actif de la barre d'outils : { id, amount, index }. L'id se traduit avec la colonne CustomInfo de
-- DT_GameItems (ex. 300001 = Pickaxe, valide en jeu). nil si l'appel echoue.
function Player.ReadActiveItem()
    local pc = FindFirstOf("PC_Standard_C")
    if not pc or not pc:IsValid() then return nil end
    local out = tables(3)   -- ActiveItem, ActiveItemInfo, bIsValid (le 4e parametre du catalogue est une variable locale)
    local ok = pcall(function() pc:GetActiveItem(table.unpack(out)) end)
    if not ok or not out[1] then return nil end
    return { id = out[1].ID, amount = out[1].Amount, index = out[1].Index }
end

return OutOfOreAPI
