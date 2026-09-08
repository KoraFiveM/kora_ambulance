-- Death (server realm) -- authoritative ALIVE/LASTSTAND/DEAD state, wound
-- ledger, injury-report validation, replicated down state, and persistence.

Death = Death or {}

local QBCore = exports.qbcore
local MEDICAL_VERSION = 1
local MAX_SEQUENCE = 9007199254740991

local woundData = {}
local laststandAt = {}
local deadAt = {}
local observations = {}

local VALID_TRANSITIONS = {
    alive = { died = 'laststand' },
    laststand = { bledOut = 'dead', revived = 'alive', died = 'dead' },
    dead = { respawned = 'alive', revived = 'alive' },
}

---@param state "alive"|"laststand"|"dead"
---@param event "died"|"bledOut"|"revived"|"respawned"
---@return "alive"|"laststand"|"dead" nextState
---@return boolean changed
function Death.transition(state, event)
    local row = VALID_TRANSITIONS[state]
    local nextState = row and row[event]
    if not nextState then return state, false end
    return nextState, true
end

---@param src integer
---@return "alive"|"laststand"|"dead"
function Death.getState(src)
    if QBCore:getMetaData(src, 'isdead') == true then return 'dead' end
    if QBCore:getMetaData(src, 'inlaststand') == true then return 'laststand' end
    return 'alive'
end

---@param src integer
---@return boolean
function Death.isDead(src) return Death.getState(src) == 'dead' end

---@param src integer
---@return boolean
function Death.isLaststand(src) return Death.getState(src) == 'laststand' end

---@param src integer
---@return boolean
function Death.isAlive(src) return Death.getState(src) == 'alive' end

local function copyWounds(src)
    local copy = {}
    for bodyPart, tier in pairs(woundData[src] or {}) do copy[bodyPart] = tier end
    return copy
end

local function persistMedical(src)
    if not QBCore:getPlayerData(src) then return end
    QBCore:setMetaData(src, 'qbambulanceMedical', {
        version = MEDICAL_VERSION,
        wounds = copyWounds(src),
        laststandAt = laststandAt[src],
        deadAt = deadAt[src],
    })
end

local function publishDownState(src, state)
    local player = Player(src)
    if not player or not player.state then return end
    local value = state
    if state == 'alive' then value = false end
    player.state:set('emsDown', value, true)
end

---@param src integer
---@return table<string, integer> A live internal reference; mutate only through Death helpers.
function Death.getWoundData(src)
    woundData[src] = woundData[src] or {}
    return woundData[src]
end

---@param src integer
function Death._syncStatus(src)
    local tier = Wounds.worstOpenTier(Death.getWoundData(src))
    if not tier then
        QB.status.remove(src, 'bleeding')
        QB.status.remove(src, 'limping')
        return
    end

    QB.status.apply(src, 'bleeding', { severity = tier })
    local level = Wounds.woundLevelDef(tier)
    if level and not level.canWalk then
        QB.status.apply(src, 'limping', { severity = tier })
    else
        QB.status.remove(src, 'limping')
    end
end

---@param src integer
---@param bodyPart string
---@param tier integer
---@return boolean changed
function Death.recordWound(src, bodyPart, tier)
    if type(bodyPart) ~= 'string' or not Wounds.bodyPartDef(bodyPart) then return false end
    if type(tier) ~= 'number' or tier ~= tier then return false end
    tier = math.floor(tier)
    if tier < 1 or tier > Wounds.MAX_TIER then return false end

    local bucket = Death.getWoundData(src)
    local existing = bucket[bodyPart]
    if existing and existing >= tier then return false end
    bucket[bodyPart] = tier
    Death._syncStatus(src)
    persistMedical(src)
    return true
end

---@param src integer
---@param bodyPart string
---@return boolean changed
function Death.clearWound(src, bodyPart)
    local bucket = Death.getWoundData(src)
    if bucket[bodyPart] == nil then return false end
    bucket[bodyPart] = nil
    Death._syncStatus(src)
    persistMedical(src)
    return true
end

---@param src integer
---@return boolean changed
function Death.clearAllWounds(src)
    local hadWounds = next(Death.getWoundData(src)) ~= nil
    woundData[src] = {}
    QB.status.remove(src, 'bleeding')
    QB.status.remove(src, 'limping')
    if hadWounds then persistMedical(src) end
    return hadWounds
end

---@param src integer
---@param cause? string
---@return boolean
function Death.enterLaststand(src, cause)
    local newState, changed = Death.transition(Death.getState(src), 'died')
    if not changed or newState ~= 'laststand' then return false end

    QBCore:setMetaData(src, 'inlaststand', true)
    QBCore:setMetaData(src, 'isdead', false)
    laststandAt[src] = os.time()
    deadAt[src] = nil
    persistMedical(src)
    publishDownState(src, 'laststand')

    TriggerClientEvent('qbambulance:client:enterLaststand', src, Config.death.deathTime)
    TriggerEvent('qbambulance:server:onPlayerDied', src, cause)
    return true
end

---@param src integer
---@param effectiveDeadAt? integer Unix timestamp used when restoring an elapsed laststand.
---@return boolean
function Death.markDead(src, effectiveDeadAt)
    local state = Death.getState(src)
    local newState, changed

    if state == 'alive' then
        newState, changed = Death.transition('laststand', 'died')
        state = 'laststand'
    end
    if state == 'laststand' then newState, changed = Death.transition(state, 'bledOut') end
    if not changed or newState ~= 'dead' then return false end

    QBCore:setMetaData(src, 'isdead', true)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil
    deadAt[src] = effectiveDeadAt or os.time()
    persistMedical(src)
    publishDownState(src, 'dead')

    TriggerClientEvent('qbambulance:client:markDead', src, Death.respawnWaitRemaining(src) * 1000)
    TriggerEvent('qbambulance:server:onPlayerDead', src)
    return true
end

---@param src integer
---@param healthPct? number
---@return boolean
function Death.reviveInField(src, healthPct)
    local state = Death.getState(src)
    if state ~= 'laststand' and state ~= 'dead' then return false end
    local _, changed = Death.transition(state, 'revived')
    if not changed then return false end

    QBCore:setMetaData(src, 'isdead', false)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil
    deadAt[src] = nil
    persistMedical(src)
    publishDownState(src, 'alive')
    QB.status.remove(src, 'bleeding')

    TriggerClientEvent('qbambulance:client:revived', src, healthPct or Config.death.minimumRevive)
    TriggerEvent('qbambulance:server:onPlayerRevived', src)
    return true
end

---@param src integer
---@return integer seconds
function Death.respawnWaitRemaining(src)
    local diedAt = deadAt[src]
    if not diedAt then return 0 end
    return math.max(0, math.floor(Config.death.respawnTime / 1000) - (os.time() - diedAt))
end

---@param src integer
---@param hospitalName? string
---@return boolean, string|nil
function Death.respawnAtHospital(src, hospitalName)
    local state = Death.getState(src)
    if state ~= 'dead' then return false, 'You are not dead.' end

    local remaining = Death.respawnWaitRemaining(src)
    if remaining > 0 then return false, ('You cannot respawn for another %ds.'):format(remaining) end

    local hospital
    for _, candidate in ipairs(Config.hospitals) do
        if candidate.name == hospitalName then hospital = candidate; break end
    end
    hospital = hospital or Config.hospitals[1]

    Billing.chargeForRespawn(src, Death.getWoundData(src))
    local _, changed = Death.transition(state, 'respawned')
    if not changed then return false, 'invalid transition' end

    QBCore:setMetaData(src, 'isdead', false)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil
    deadAt[src] = nil
    Death.clearAllWounds(src)
    persistMedical(src)
    publishDownState(src, 'alive')
    QBCore:reset(src)

    TriggerClientEvent('qbambulance:client:respawnedAtHospital', src, hospital.coords)
    TriggerEvent('qbambulance:server:onPlayerRespawned', src, hospital.name)
    return true
end

---@param src integer
---@return integer seconds
function Death.laststandElapsed(src)
    local startedAt = laststandAt[src]
    if not startedAt then return 0 end
    return math.max(0, os.time() - startedAt)
end

local function validTimestamp(value, now)
    return type(value) == 'number' and value == value and value % 1 == 0 and value > 0 and value <= now
end

local function sanitizeWounds(value)
    local clean = {}
    if type(value) ~= 'table' then return clean end
    for bodyPart, tier in pairs(value) do
        if type(bodyPart) == 'string' and Wounds.bodyPartDef(bodyPart)
            and type(tier) == 'number' and tier == tier and tier % 1 == 0
            and tier >= 1 and tier <= Wounds.MAX_TIER then
            clean[bodyPart] = tier
        end
    end
    return clean
end

local function medicalMatches(raw, clean)
    if type(raw) ~= 'table' or raw.version ~= MEDICAL_VERSION then return false end
    if raw.laststandAt ~= clean.laststandAt or raw.deadAt ~= clean.deadAt then return false end
    if type(raw.wounds) ~= 'table' then return false end
    for bodyPart, tier in pairs(raw.wounds) do if clean.wounds[bodyPart] ~= tier then return false end end
    for bodyPart, tier in pairs(clean.wounds) do if raw.wounds[bodyPart] ~= tier then return false end end
    for key in pairs(raw) do
        if key ~= 'version' and key ~= 'wounds' and key ~= 'laststandAt' and key ~= 'deadAt' then return false end
    end
    return true
end

local function restorePlayer(src)
    if not QBCore:getPlayerData(src) then return end

    local now = os.time()
    local raw = QBCore:getMetaData(src, 'qbambulanceMedical')
    local versioned = type(raw) == 'table' and raw.version == MEDICAL_VERSION
    local clean = {
        version = MEDICAL_VERSION,
        wounds = sanitizeWounds(versioned and raw.wounds or nil),
        laststandAt = versioned and validTimestamp(raw.laststandAt, now) and raw.laststandAt or nil,
        deadAt = versioned and validTimestamp(raw.deadAt, now) and raw.deadAt or nil,
    }

    woundData[src] = clean.wounds
    local state = Death.getState(src)
    local expectedDead = state == 'dead'
    local expectedLaststand = state == 'laststand'
    if QBCore:getMetaData(src, 'isdead') ~= expectedDead then QBCore:setMetaData(src, 'isdead', expectedDead) end
    if QBCore:getMetaData(src, 'inlaststand') ~= expectedLaststand then
        QBCore:setMetaData(src, 'inlaststand', expectedLaststand)
    end
    if state == 'dead' then
        laststandAt[src] = nil
        deadAt[src] = clean.deadAt
        clean.laststandAt = nil
    elseif state == 'laststand' then
        laststandAt[src] = clean.laststandAt or now
        deadAt[src] = nil
        clean.laststandAt = laststandAt[src]
        clean.deadAt = nil
    else
        laststandAt[src] = nil
        deadAt[src] = nil
        clean.laststandAt = nil
        clean.deadAt = nil
    end

    Death._syncStatus(src)

    local deathTimeSeconds = math.floor(Config.death.deathTime / 1000)
    if state == 'laststand' and now - laststandAt[src] >= deathTimeSeconds then
        local effectiveDeadAt = laststandAt[src] + deathTimeSeconds
        Death.markDead(src, effectiveDeadAt)
        return
    end

    if not medicalMatches(raw, clean) then persistMedical(src) end
    publishDownState(src, state)

    if state == 'laststand' then
        local remaining = math.max(0, deathTimeSeconds - (now - laststandAt[src]))
        TriggerClientEvent('qbambulance:client:enterLaststand', src, remaining * 1000)
    elseif state == 'dead' then
        TriggerClientEvent('qbambulance:client:markDead', src, Death.respawnWaitRemaining(src) * 1000)
    end
end

QB.callback.register('qbambulance:server:reportDeath', function(src, cause)
    if not QBCore:getPlayerData(src) then return false end
    if Death.isLaststand(src) then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) > 0 then return false end
    if type(cause) ~= 'string' then cause = 'died' end
    return Death.enterLaststand(src, cause:sub(1, 64))
end, { rateLimit = { max = Config.death.reportRetryAttempts, window = 2000 } })

local function isFinite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function resolveObservedBodyPart(payload)
    local mapped = Wounds.bodyPartFromBone(payload.bone)
    if mapped then
        if payload.fallback ~= false then return nil end
        return mapped
    end
    if payload.fallback ~= true or type(payload.bodyPart) ~= 'string' then return nil end
    if not Wounds.bodyPartDef(payload.bodyPart) then return nil end
    return payload.bodyPart
end

QB.events.register('qbambulance:server:hitObserved', function(src, payload)
    if not QBCore:getPlayerData(src) or not Death.isAlive(src) then return end
    if type(payload) ~= 'table' then return end

    local sequence = payload.sequence
    if not isFinite(sequence) or sequence % 1 ~= 0 or sequence < 1 or sequence > MAX_SEQUENCE then return end
    if not isFinite(payload.damage) or payload.damage < Config.injuries.minDamage
        or payload.damage > Config.injuries.maxDamage then return end
    if not isFinite(payload.healthAfter) or payload.healthAfter < 0 or payload.healthAfter > 10000 then return end
    if payload.bone ~= false and payload.bone ~= nil
        and (not isFinite(payload.bone) or payload.bone % 1 ~= 0 or payload.bone < 0 or payload.bone > 65535) then return end

    local bodyPart = resolveObservedBodyPart(payload)
    if not bodyPart then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if math.abs(GetEntityHealth(ped) - payload.healthAfter) > Config.injuries.healthTolerance then return end

    local previous = observations[src]
    if previous and sequence <= previous.sequence then return end

    local now = GetGameTimer()
    observations[src] = { sequence = sequence, acceptedAt = previous and previous.acceptedAt or nil }
    if previous and now - previous.acceptedAt < Config.injuries.reportCooldown then return end

    observations[src].acceptedAt = now
    Death.recordWound(src, bodyPart, Wounds.severityFromDamage(payload.damage, bodyPart))
end)

AddEventHandler('qbcore:server:playerLoaded', restorePlayer)

CreateThread(function()
    Wait(0)
    for _, src in ipairs(QBCore:getPlayers()) do restorePlayer(src) end
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, startedAt in pairs(laststandAt) do
            if os.time() - startedAt >= math.floor(Config.death.deathTime / 1000) then Death.markDead(src) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    woundData[src] = nil
    laststandAt[src] = nil
    deadAt[src] = nil
    observations[src] = nil
end)

---Returns a detached medical snapshot. Mutating it cannot alter the ledger.
---@param src integer
---@return table|nil status
local function getPatientStatus(src)
    src = tonumber(src)
    if not src or not QBCore:getPlayerData(src) then return nil end
    return {
        version = MEDICAL_VERSION,
        state = Death.getState(src),
        wounds = copyWounds(src),
        laststandAt = laststandAt[src],
        deadAt = deadAt[src],
    }
end

exports('getPatientStatus', getPatientStatus)
