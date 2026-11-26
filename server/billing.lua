-- Billing (server realm) -- EMS hospital bill calculation and charging.
-- calculateCost is pure (test/smoke/billing.lua exercises it directly);
-- chargeForRespawn is the side-effecting wrapper Death.respawnAtHospital and
-- the legacy SendBillEmail/BillPlayer-style compat calls actually use.

Billing = Billing or {}

-- kora_core has no Kora proxy: every call crosses the exports boundary.
local QBCore = exports.kora_core

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

    local account, fallbackAccount = Config.billing.account, Config.billing.fallbackAccount
    local debitReason = reason or 'EMS hospital bill'
    local bankDebit = 0
    local available = QBCore:getMoney(src, account) or 0
    local fromPrimary = math.min(available, cost)
    if fromPrimary > 0 then
        local removed = QBCore:removeMoney(src, account, fromPrimary, debitReason)
        if removed and account == 'bank' then bankDebit = fromPrimary end
    end

    local remainder = cost - fromPrimary
    if remainder > 0 then
        local removed = QBCore:removeMoney(src, fallbackAccount, remainder, debitReason)
        if removed and fallbackAccount == 'bank' then bankDebit = bankDebit + remainder end
    end

    if bankDebit > 0 and GetResourceState('kora_banking') == 'started' then
        local called, recorded = pcall(function()
            local label = Kora.lang('title.hospital_treatment')
            return Kora.bridge.createSocietyBankStatement(src, 'checking', bankDebit, label, 'withdraw')
        end)
        if not called or recorded ~= true then
            Kora.logging.warn('billing.statement_failed', 'Hospital bank statement write failed', {
                source = src,
                amount = bankDebit,
            })
        end
    end

    TriggerClientEvent('hospital:client:SendBillEmail', src, cost)
    TriggerEvent('kora_ambulance:server:onBillCharged', src, cost)

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
