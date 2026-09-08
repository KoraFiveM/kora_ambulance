-- Billing (server realm) -- EMS hospital bill calculation and charging.
-- calculateCost is pure (test/smoke/billing.lua exercises it directly);
-- chargeForRespawn is the side-effecting wrapper Death.respawnAtHospital and
-- the legacy SendBillEmail/BillPlayer-style compat calls actually use.

Billing = Billing or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

---Base hospital fee plus Config.billing.perWoundCost[tier] for every still-open
---wound at respawn time -- more/worse wounds cost more, same as a real ER
---bill scaling with treatment complexity.
---@param woundData table<string, integer> bodyPart -> tier
---@return integer cost
function Billing.calculateCost(woundData)
    local cost = Config.billing.baseCost

    for _, tier in pairs(woundData or {}) do
        cost = cost + (Config.billing.perWoundCost[tier] or Config.billing.perWoundCost[#Config.billing.perWoundCost])
    end

    return cost
end

---Charges a fixed amount, draining Config.billing.account first and then the
---fallback account. This never gates care on funds: the fallback account is
---allowed to carry the remainder.
---@param src integer
---@param cost integer
---@param reason? string
---@return integer charged
function Billing.charge(src, cost, reason)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if cost <= 0 then return 0 end

    local available = QBCore:getMoney(src, Config.billing.account) or 0
    local fromPrimary = math.min(available, cost)
    if fromPrimary > 0 then
        QBCore:removeMoney(src, Config.billing.account, fromPrimary, reason or 'EMS hospital bill')
    end

    local remainder = cost - fromPrimary
    if remainder > 0 then
        QBCore:removeMoney(src, Config.billing.fallbackAccount, remainder, reason or 'EMS hospital bill')
    end

    TriggerClientEvent('hospital:client:SendBillEmail', src, cost)
    TriggerEvent('qbambulance:server:onBillCharged', src, cost)

    return cost
end

---Charges `src` Billing.calculateCost(woundData), retaining the existing
---respawn bill result and outbound compatibility notifications.
---@param src integer
---@param woundData table<string, integer>
---@return integer charged
function Billing.chargeForRespawn(src, woundData)
    return Billing.charge(src, Billing.calculateCost(woundData), 'EMS hospital bill')
end
