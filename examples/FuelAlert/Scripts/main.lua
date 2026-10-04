-- Exemple de mod construit sur OutOfOreAPI : alerte de carburant bas.
-- Toutes les 5 s, lit le carburant de l'engin conduit (ou, a pied, du plus proche) et affiche une notification native
-- quand il passe sous le seuil (une seule fois par passage sous le seuil). Commande console : fuelalert <pourcent>.
-- Utilise : API.SafeTick, API.Vehicle (FindControlled / ListAll / ReadFluids), API.Player.ShowMessage, API.Console.
local API = require("OutOfOreAPI")

local THRESHOLD = 20.0      -- pourcent
local warned = {}           -- engin -> true tant qu'il est sous le seuil

local function CheckFuel()
    local vehicles = {}
    local driven = API.Vehicle.FindControlled()
    if driven then vehicles[1] = driven end          -- on ne surveille que l'engin conduit
    for _, v in ipairs(vehicles) do
        local name = v:GetFullName()
        for _, f in ipairs(API.Vehicle.ReadFluids(v) or {}) do
            if f.type == "DieselFuel" and f.capacity and f.capacity > 0 then
                local pct = 100.0 * (f.amount or 0) / f.capacity
                if pct < THRESHOLD and not warned[name] then
                    warned[name] = true
                    API.Player.ShowMessage(string.format("Carburant bas : %.0f %%", pct))
                elseif pct >= THRESHOLD + 5 then
                    warned[name] = nil               -- plein refait : on pourra reprevenir
                end
            end
        end
    end
end

API.SafeTick.Register(CheckFuel, 0.2)    -- 0,2 Hz = toutes les 5 s

API.Console.Register("fuelalert", function(_, Params)
    local p = tonumber(Params and Params[1])
    if p then THRESHOLD = math.max(1, math.min(99, p)) end
    warned = {}
    print("[FuelAlert] seuil = " .. THRESHOLD .. " %\n")
end)

print("[FuelAlert] charge, seuil " .. THRESHOLD .. " %\n")
