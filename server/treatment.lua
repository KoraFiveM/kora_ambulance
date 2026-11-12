-- Treatment (server realm) -- on-duty EMS can inspect another player's wound
-- ledger and close one wound with supplies from their own inventory. The
-- client owns only the kora_lib action UX; job, range, item and wound checks are
-- repeated here when treatment completes.

Treatment = Treatment or {}

local QBCore = exports.kora_core
local actionsByMedic = {}
local medicByPatient = {}

local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

local function nearby(a, b)
    if not QBCore:getPlayerData(a) or not QBCore:getPlayerData(b) then return false end
    return Kora.world.resolveNearbyPlayer(a, b, { maxDistance = Config.treatment.range }) ~= nil
end

local function clearAction(medicSrc)
    local action = actionsByMedic[medicSrc]
    if not action then return end
    actionsByMedic[medicSrc] = nil
    if medicByPatient[action.patient] == medicSrc then medicByPatient[action.patient] = nil end
end

---@param medicSrc integer
---@param patientSrc integer
---@return boolean
---@return string|nil
function Treatment.canAccess(medicSrc, patientSrc)
    patientSrc = tonumber(patientSrc)
    if not patientSrc or patientSrc == medicSrc then return false, 'invalid patient' end
    if not isOnDutyEMS(medicSrc) then return false, 'not an on-duty paramedic' end
    if not nearby(medicSrc, patientSrc) then return false, 'patient is too far away' end
    return true, nil
end

---@param patientSrc integer
---@return table report
function Treatment.assessment(patientSrc)
    local report = { state = Death.getState(patientSrc), wounds = {} }
    local ledger = Death.getWoundData(patientSrc)

    -- Config order is stable, unlike pairs(ledger), so two medics see the same
    -- clinical summary and the most familiar head-to-toe ordering.
    for _, part in ipairs(Config.bodyParts) do
        local tier = ledger[part.name]
        if tier then
            local level = Wounds.woundLevelDef(tier)
            report.wounds[#report.wounds + 1] = {
                bodyPart = part.name,
                bodyPartLabel = part.label,
                tier = tier,
                severityLabel = level and level.label or ('Tier %d'):format(tier),
            }
        end
    end

    return report
end

local function selectSupply(medicSrc, patientSrc)
    local ledger = Death.getWoundData(patientSrc)
    local worstTier = Wounds.worstOpenTier(ledger)

    -- Preserve the stronger kit when a bandage can do the job. If any severe
    -- wound is open, prefer the IFAK so treatment addresses the highest-risk
    -- finding instead of quietly picking a lesser wound first.
    if worstTier and worstTier > 2 and QBCore:hasItem(medicSrc, 'ifak') then
        local bodyPart, tier = Wounds.pickTreatableWound(ledger, Wounds.MAX_TIER)
        if bodyPart then return 'ifak', Wounds.MAX_TIER, bodyPart, tier end
    end

    if QBCore:hasItem(medicSrc, 'bandage') then
        local bodyPart, tier = Wounds.pickTreatableWound(ledger, 2)
        if bodyPart then return 'bandage', 2, bodyPart, tier end
    end

    if QBCore:hasItem(medicSrc, 'ifak') then
        local bodyPart, tier = Wounds.pickTreatableWound(ledger, Wounds.MAX_TIER)
        if bodyPart then return 'ifak', Wounds.MAX_TIER, bodyPart, tier end
    end

    if not Wounds.isBleeding(ledger) then return nil, nil, nil, nil, 'patient has no open wounds' end
    return nil, nil, nil, nil, 'no suitable medical supplies'
end

---@param medicSrc integer
---@param patientSrc integer
---@return string|nil token
---@return string|nil reason
function Treatment.begin(medicSrc, patientSrc)
    patientSrc = tonumber(patientSrc)
    local allowed, reason = Treatment.canAccess(medicSrc, patientSrc)
    if not allowed then return nil, reason end

    local now = GetGameTimer()
    local current = actionsByMedic[medicSrc]
    if current and current.expiresAt <= now then clearAction(medicSrc) end

    local patientMedic = medicByPatient[patientSrc]
    local patientAction = patientMedic and actionsByMedic[patientMedic]
    if patientMedic and (not patientAction or patientAction.expiresAt <= now) then
        clearAction(patientMedic)
    end

    if actionsByMedic[medicSrc] then return nil, 'treatment already in progress' end
    if medicByPatient[patientSrc] then return nil, 'another medic is treating this patient' end

    local item, maxTier, bodyPart, tier, supplyErr = selectSupply(medicSrc, patientSrc)
    if not item then return nil, supplyErr end

    local token = ('%s:%s:%s:%s'):format(medicSrc, patientSrc, now, math.random(100000, 999999))
    actionsByMedic[medicSrc] = {
        token = token,
        patient = patientSrc,
        item = item,
        maxTier = maxTier,
        bodyPart = bodyPart,
        tier = tier,
        readyAt = now + Config.treatment.duration,
        expiresAt = now + math.max(Config.treatment.actionTtl, Config.treatment.duration + 1000),
    }
    medicByPatient[patientSrc] = medicSrc
    return token, nil
end

---@param medicSrc integer
---@param patientSrc integer
---@param token string
---@param completed boolean
---@return boolean treated
---@return string|nil reason
function Treatment.complete(medicSrc, patientSrc, token, completed)
    patientSrc = tonumber(patientSrc)
    local action = actionsByMedic[medicSrc]
    if not action or action.patient ~= patientSrc or action.token ~= token then
        return false, 'invalid treatment action'
    end

    clearAction(medicSrc)
    if not completed then return false, 'treatment cancelled' end

    local now = GetGameTimer()
    -- Allow a small scheduling tolerance: the kora_lib progress bar may return
    -- a frame before the nominal duration while server/client clocks settle.
    if now < action.readyAt - 250 then return false, 'treatment completed too quickly' end
    if now > action.expiresAt then return false, 'treatment action expired' end

    local allowed, reason = Treatment.canAccess(medicSrc, patientSrc)
    if not allowed then return false, reason end

    local currentTier = Death.getWoundData(patientSrc)[action.bodyPart]
    if not currentTier then return false, 'wound is already treated' end
    if not Wounds.canTreatWithTier(currentTier, action.maxTier) then
        return false, 'wound now needs stronger treatment'
    end
    if not QBCore:hasItem(medicSrc, action.item) then return false, 'medical supply is missing' end

    local removed, removeErr = QBCore:removeItem(medicSrc, action.item, 1, nil, 'ems-patient-treatment')
    if not removed then return false, removeErr or 'could not consume medical supply' end

    Death.clearWound(patientSrc, action.bodyPart)
    local part = Wounds.bodyPartDef(action.bodyPart)
    Kora.notify.send(patientSrc, { title = 'Patient Treatment', message = ('A medic treated your wound (%s).'):format(part and part.label or action.bodyPart), type = 'success' })
    local heal = Config.treatment.ifakHealthAmount or 0
    if action.item == 'ifak' and heal > 0 and Death.isAlive(patientSrc) then
        TriggerClientEvent('kora_ambulance:client:painkillerBenefit', patientSrc, heal)
    end
    TriggerEvent('kora_ambulance:server:onPatientTreated', patientSrc, medicSrc,
        action.bodyPart, currentTier, action.item)
    return true, nil
end

Kora.callback.register('kora_ambulance:server:assessPatient', function(src, patientSrc)
    patientSrc = tonumber(patientSrc)
    local allowed, reason = Treatment.canAccess(src, patientSrc)
    if not allowed then return nil, reason end
    return Treatment.assessment(patientSrc), nil
end, { rateLimit = { max = 10, window = 10000 } })

Kora.callback.register('kora_ambulance:server:beginTreatment', function(src, patientSrc)
    return Treatment.begin(src, patientSrc)
end, { rateLimit = { max = 5, window = 10000 } })

Kora.callback.register('kora_ambulance:server:completeTreatment', function(src, patientSrc, token, completed)
    return Treatment.complete(src, patientSrc, token, completed == true)
end, { rateLimit = { max = 5, window = 10000 } })

AddEventHandler('playerDropped', function()
    local src = source
    clearAction(src)
    local medicSrc = medicByPatient[src]
    if medicSrc then clearAction(medicSrc) end
end)
