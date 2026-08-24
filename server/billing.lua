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

---Charges `src` Billing.calculateCost(woundData), draining
---Config.billing.account first and Config.billing.fallbackAccount for
---whatever that account couldn't cover. Never blocks the respawn on
---insufficient funds -- bank is allowed to go negative (qbcore's own
---Config.money.allowNegative.bank), so this always succeeds; it exists to
---charge exactly what's owed, not to gate treatment on ability to pay.
---@param src integer
---@param woundData table<string, integer>
---@return integer charged
function Billing.chargeForRespawn(src, woundData)
    local cost = Billing.calculateCost(woundData)
    if cost <= 0 then return 0 end

    local available = QBCore:getMoney(src, Config.billing.account) or 0
    local fromPrimary = math.min(available, cost)
    if fromPrimary > 0 then
        QBCore:removeMoney(src, Config.billing.account, fromPrimary, 'EMS hospital bill')
    end

    local remainder = cost - fromPrimary
    if remainder > 0 then
        QBCore:removeMoney(src, Config.billing.fallbackAccount, remainder, 'EMS hospital bill')
    end

    TriggerClientEvent('hospital:client:SendBillEmail', src, cost)
    TriggerEvent('qbambulance:server:onBillCharged', src, cost)

    return cost
end
