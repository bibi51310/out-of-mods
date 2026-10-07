-- Copyright (c) 2026 Out of Mods -- MIT License (see LICENSE)
-- Pay Dirt : multiplie par N (2 par defaut) les prix de VENTE, affiches ET recus, sans rien ecrire dans la sauvegarde.
-- Principe (mode "price", defaut) : callback sur la fin de SchaktStateBase_C:CalculateSellPriceByCompanyId, qui calcule le prix de
-- vente d'un objet / minerai / lingot (apercu du magasin ET SellItemDirect avant EditMoney) ; on multiplie sa sortie Price.
-- Repli (mode "bonus") : on memorise le dernier gain vu par PC_Standard_C:EditMoney et, quand une vente est declenchee juste
-- apres, on verse le bonus (gain * (facteur - 1)) ; le prix affiche ne change alors pas.
-- Quetes, remboursements et depenses ne sont pas touches. Retirer le mod suffit a revenir a l'economie normale :
-- aucune propriete du jeu n'est modifiee.
--
-- Commandes console (~ ou F10) :
--   boost <facteur>          facteur des ventes (1 = neutre, 0 = ignore), ex. boost 3
--   boost_status             etat et statistiques
--   boost_mode price|bonus   price (defaut) = prix double a la source ; bonus = argent ajoute apres la vente
--   boost_scope ore|all      ore (defaut) = ressources et minerais seulement ; all = tout (engins, batiments... : risque de boucle achat / revente)
--   boost_all 0|1            mode bonus seulement : 1 = double aussi les gains hors vente (quetes...), non teste
--   boost_log 0|1            journal detaille (pour verifier ce qui se passe) et remise a zero des compteurs de lignes

local API = require("OutOfOreAPI")

local Factor = 2
local LogCalls = true            -- journal des 40 premiers appels, pour verifier le comportement en jeu
local Stats = { calls = 0, boosted = 0, gained = 0, extra = 0, seen = 0 }
local MAX_LOG = 120
local AllGains = false           -- boost_all 1 : doubler aussi les gains hors vente (quetes...)
local NOW = os.clock

-- Fonctions qui ouvrent la fenetre de vente (objets / minerai). Les autres candidats sont seulement journalises.
local SALE_OPEN = {
    "/Game/Blueprints/PC_Standard.PC_Standard_C:SellItem",
    "/Game/Blueprints/PC_Standard.PC_Standard_C:SellItemDirect",
    "/Game/Blueprints/PC_Standard.PC_Standard_C:ServerSellItem",
    "/Game/Blueprints/BP_SellPlace.BP_SellPlace_C:SellOre",
}
local SALE_SPY = {   -- journal seulement (peuvent se declencher souvent : pas de fenetre)
    "/Game/Blueprints/BP_SellPointManager.BP_SellPointManager_C:CacheSellValue",
    "/Game/Blueprints/BP_SellPointComponent.BP_SellPointComponent_C:CacheSellValue",
    "/Game/Blueprints/QuestComponent.QuestComponent_C:GiveQuestReward",
}

local function Log(msg) print("[PayDirt] " .. msg .. "\n") end

-- Constat en jeu (2026-10-07) : EditMoney se declenche ~1 ms AVANT les fonctions de vente (SellItemDirect, SellItem,
-- ServerSellItem). On memorise donc le dernier gain, et quand la vente est annoncee on verse le bonus
-- (gain * (facteur - 1)) par un EditMoney supplementaire (la reentree dans notre propre hook est ignoree).
local LastGain, LastGainT, LastPC = 0, -1, nil
local Granting = false
local Mode = "price"             -- "price" (essai) : sortie de CalculateSellPriceByCompanyId corrigee ; "bonus" (valide en jeu) : bonus verse apres la vente
local PriceLogs = 0

-- Mode "price" : constat en jeu (2026-10-07) -- le callback "pre" d'une fonction Blueprint appelee depuis un autre Blueprint
-- s'execute en FIN de fonction (EditMoney est vu avant SellItemDirect ; a l'entree de CalculateSellPriceByCompanyId l'argument
-- Price vaut deja 39) et les hooks "post" ne se declenchent pas. Modifier une ENTREE (UnitPrice, Amount) n'a aucun effet (calcul
-- deja fait) : on multiplie donc la SORTIE Price (6e argument : CompanyID, ResourceID, Amount, Item, bNotifyResourceFlow, Price),
-- avant que l'appelant (apercu du magasin W_Menu_Store:OnDragOver, ou SellItemDirect -> EditMoney) ne la relise.
-- Objets dont la vente est doublee (mode "ore", defaut) : ressources brutes (1xxxxx : minerais, roches, terre, asphalte, fluides...)
-- et minerais / metaux affines (2xxxxx, sous-categorie "Ore"). Tout se revend a ~70 % de la valeur de l'objet : doubler une vente
-- d'engin, de batiment, de piece ou de materiau achetable (bois, caoutchouc, plastique...) ferait depasser le prix d'achat
-- (boucle achat / revente) ; les ressources se revendent a 4-28 % de leur prix d'achat, donc sans risque. ID inconnu = pas double.
-- Liste generee depuis le catalogue du jeu (build 25319732 / 25627989) ; "boost_scope all" double tout (risque d'exploit).
local BOOST_IDS = {}
for _, id in ipairs({
    "100001", "100002", "100003", "100004", "100005", "100006", "100007", "100008",
    "100009", "100010", "100011", "100012", "100013", "100014", "100015", "100016",
    "100017", "100018", "100019", "100020", "100021", "100022", "100023", "100024",
    "100025", "100026", "100027", "200001", "200002", "200003", "200004", "200005",
    "200006", "200007", "200008", "200009", "200010", "200014", "200026", "200027",
    "200028", "200029", "200030", "200031", "200032", "200033", "200052",
}) do BOOST_IDS[id] = true end
local Scope = "ore"
local PRICE_ARG = 6
local SeenKinds, KindLogs = {}, 0
-- Diagnostic (boost_log 1) : journalise une fois chaque objet distinct (prix de base) avec CompanyID, ResourceID et les champs lisibles de Item.
local function DescribeSale(args, p)
    local function rd(a, f)
        local ok, v = pcall(function() return f(a:get()) end)
        return ok and tostring(v) or "?"
    end
    local comp = rd(args[1], function(v) return v:ToString() end)
    local res = rd(args[2], function(v) return v:ToString() end)
    local id = rd(args[4], function(v) return v.ID end)
    local amt = rd(args[3], function(v) return v end)
    local key = res .. "|" .. id .. "|" .. tostring(p)
    if SeenKinds[key] or KindLogs >= 40 then return end
    SeenKinds[key] = true
    KindLogs = KindLogs + 1
    Log(string.format("objet : company=%s resource=%s itemID=%s quantite=%s prix=%d", comp, res, id, amt, p))
end
local LastBase, LastNew, LastPriceT = 0, 0, -1   -- dernier prix vu par le hook (pour verifier ce que EditMoney recoit)
local function OnSellPricePre(Context, ...)
    if Mode ~= "price" or Factor == 1 then return end
    local args = { ... }
    local arg = args[PRICE_ARG]
    if not arg then return end
    local ok, p = pcall(function() return arg:get() end)
    if not ok or type(p) ~= "number" or p <= 0 then return end
    if LogCalls then DescribeSale(args, p) end
    if Scope == "ore" then
        local okr, res = pcall(function() return args[2]:get():ToString() end)
        if not okr or not BOOST_IDS[res] then return end
    end
    local new = math.floor(p * Factor + 0.5)
    arg:set(new)
    LastBase, LastNew, LastPriceT = p, new, NOW()
    Stats.priced = (Stats.priced or 0) + 1
    if LogCalls and PriceLogs < 6 then
        PriceLogs = PriceLogs + 1
        Log(string.format("prix : %d -> %d (relu %s)", p, new, tostring(arg:get())))
    end
end

local function OnEditMoney(Context, Amount, bForce)
    Stats.calls = Stats.calls + 1
    if Granting then return end
    local a = Amount:get()
    if type(a) ~= "number" then return end
    if LogCalls and Stats.seen < MAX_LOG and a ~= 0 then
        Stats.seen = Stats.seen + 1
        Log(string.format("EditMoney montant=%d | dernier prix hook : %d -> %d il y a %.2fs", a, LastBase, LastNew, NOW() - LastPriceT))
    end
    if a <= 0 then return end
    if AllGains and Factor ~= 1 then   -- option : double directement tous les gains (ecrit le parametre)
        local new = math.floor(a * Factor + 0.5)
        Amount:set(new)
        Stats.boosted, Stats.gained, Stats.extra = Stats.boosted + 1, Stats.gained + a, Stats.extra + (new - a)
        return
    end
    LastGain, LastGainT, LastPC = a, NOW(), Context:get()
end

local function GrantBonus(path)
    if Mode ~= "bonus" or AllGains or Factor <= 1 or LastGain <= 0 or NOW() - LastGainT > PAIR_WINDOW then return end
    local extra = math.floor(LastGain * (Factor - 1) + 0.5)
    local pc, base = LastPC, LastGain
    LastGain = 0                                   -- un gain ne sert qu'une fois (SellItem / ServerSellItem enchaines)
    if not pc or extra <= 0 then return end
    Granting = true
    local ok, err = pcall(function() pc:EditMoney(extra, false, {}) end)
    Granting = false
    if ok then
        Stats.boosted, Stats.gained, Stats.extra = Stats.boosted + 1, Stats.gained + base, Stats.extra + extra
    end
    if LogCalls and Stats.seen < MAX_LOG then
        Stats.seen = Stats.seen + 1
        Log(string.format("bonus +%d sur gain %d (%s) : %s", extra, base, path, ok and "ok" or tostring(err)))
    end
end

local function Install()
    for _, path in ipairs(SALE_OPEN) do
        API.Hook.Register(path, function()
            GrantBonus(path:match(":(.+)$"))
            if LogCalls and Stats.seen < MAX_LOG then Stats.seen = Stats.seen + 1; Log("vente : " .. path:match(":(.+)$")) end
        end)
    end
    for _, path in ipairs(SALE_SPY) do
        API.Hook.Register(path, function()
            if LogCalls and Stats.seen < MAX_LOG then Stats.seen = Stats.seen + 1; Log("(espion) " .. path:match(":(.+)$")) end
        end)
    end
    API.Hook.Register("/Game/Blueprints/SchaktStateBase.SchaktStateBase_C:CalculateSellPriceByCompanyId", OnSellPricePre)
    local ok = API.Hook.Register("/Game/Blueprints/PC_Standard.PC_Standard_C:EditMoney", OnEditMoney)
    Log(ok and "hook EditMoney actif" or "hook EditMoney : echec (classe pas encore chargee ?)")
    return ok
end

local function Cmd(_, Parameters, Ar)
    local n = tonumber(Parameters and Parameters[1])
    if n and n >= 0 and n <= 1000 then Factor = n end
    Log("facteur = " .. tostring(Factor))
    return true
end

API.Console.Register("boost", Cmd)
API.Console.Register("boost_status", function()
    Log(string.format("facteur x%s | appels %d | gains boostes %d (montant de base %d, bonus %d) | mode %s, prix doubles %d",
        tostring(Factor), Stats.calls, Stats.boosted, Stats.gained, Stats.extra, Mode, Stats.priced or 0))
    return true
end)
API.Console.Register("boost_mode", function(_, Parameters)
    local m = Parameters and Parameters[1]
    if m == "price" or m == "bonus" then Mode = m end
    Log("mode = " .. Mode)
    return true
end)
API.Console.Register("boost_scope", function(_, Parameters)
    local m = Parameters and Parameters[1]
    if m == "ore" or m == "all" then Scope = m end
    Log("portee = " .. Scope .. (Scope == "all" and " (ATTENTION : engins, batiments, pieces aussi : revente > achat possible)" or " (ressources et minerais seulement)"))
    return true
end)
API.Console.Register("boost_all", function(_, Parameters)
    AllGains = (Parameters and Parameters[1]) == "1"
    Log("gains hors vente " .. (AllGains and "boostes aussi" or "non boostes"))
    return true
end)
API.Console.Register("boost_log", function(_, Parameters)
    LogCalls = (Parameters and Parameters[1]) ~= "0"
    Stats.seen = 0
    PriceLogs = 0
    SeenKinds, KindLogs = {}, 0
    Log("journal " .. (LogCalls and "ON" or "off"))
    return true
end)

-- La classe PC_Standard_C n'existe qu'une fois la partie chargee : on retente a chaque tick (10 Hz) jusqu'au succes.
local installed = Install()
if not installed then
    API.SafeTick.Register(function()
        if not installed then installed = Install() end
    end, 1)
end
Log("charge, facteur x" .. tostring(Factor))
