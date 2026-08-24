-- Revive (server realm) -- server-side validation for the defibrillator/CPR
-- flow. The CPR skillcheck itself runs on the REVIVER's client
-- (client/revive.lua calls QB.minigames.play locally); this module only
-- decides whether a reported success is allowed to actually revive the
-- target, and applies the real effect (Death.reviveInField) once it is.

Revive = Revive or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local lastAttemptAt = {} -- targetSrc -> os.time() of the last revive attempt made ON this target
local actionsBySrc, actionOwnerByTarget = {}, {}

local function nearby(a, b)
    if not QBCore:getPlayerData(b) then return false end
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB)) <= Config.death.reviveRange
end

---Pure eligibility check: is `targetState` revivable at all, and has enough
---time passed since the last attempt on this same target (Config.death.
---reviveInterval) to allow another one -- the cooldown exists so a failed
---CPR round can't be retried instantly, without needing per-attempt
---minigame difficulty scaling to enforce pacing.
---@param targetState "alive"|"laststand"|"dead"
---@param lastAttempt integer|nil os.time() of the last attempt, or nil
---@param now integer os.time()
---@return boolean eligible
---@return string|nil reason
function Revive.eligibility(targetState, lastAttempt, now)
    if targetState == 'alive' then return false, 'patient is not down' end

    if lastAttempt then
        local elapsed = (now - lastAttempt) * 1000
        if elapsed < Config.death.reviveInterval then
            return false, 'another reviver is already working on this patient'
        end
    end

    return true, nil
end

---@param src integer
---@return boolean
local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---Called once the reviver's OWN client reports a completed CPR minigame.
---Re-validates everything server-side (job/duty, item, target state, cooldown)
---rather than trusting the client's "I won the minigame" claim alone -- the
---minigame's pass/fail is already server-validated by QB.minigames itself,
---but job/duty/item/target-state can all have changed in the meantime.
---@param src integer The reviver.
---@param targetSrc integer The patient.
---@param success boolean Whether the reviver's minigame attempt succeeded.
---@return boolean revived
---@return string|nil reason
function Revive.complete(src, targetSrc, success)
    if not isOnDutyEMS(src) then return false, 'not an on-duty paramedic' end
    if not QBCore:hasItem(src, 'defibrillator') then return false, 'no defibrillator' end
    if not nearby(src, targetSrc) then return false, 'patient is too far away' end

    local targetState = Death.getState(targetSrc)
    local eligible, reason = Revive.eligibility(targetState, lastAttemptAt[targetSrc], os.time())
    if not eligible then return false, reason end

    lastAttemptAt[targetSrc] = os.time()

    if not success then
        QB.notify.send(src, { title = 'EMS', message = 'CPR attempt failed.', type = 'error' })
        return false, 'minigame failed'
    end

    local removed, removeErr = QBCore:removeItem(src, 'defibrillator', 1, nil, 'field-revive')
    if not removed then return false, removeErr or 'could not consume defibrillator' end
    Death.reviveInField(targetSrc, Config.death.minimumRevive)

    QB.notify.send(src, { title = 'EMS', message = 'Patient stabilised.', type = 'success' })
    TriggerEvent('qbambulance:server:onPlayerRevivedBy', targetSrc, src)

    return true, nil
end

local function clearAction(src)
    local action = actionsBySrc[src]
    if not action then return end
    actionsBySrc[src] = nil
    if actionOwnerByTarget[action.target] == src then actionOwnerByTarget[action.target] = nil end
end

QB.callback.register('qbambulance:server:beginRevive', function(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src then return nil, 'invalid patient' end
    if actionsBySrc[src] then return nil, 'revive already in progress' end
    if actionOwnerByTarget[targetSrc] then return nil, 'another reviver is already working on this patient' end
    if not isOnDutyEMS(src) then return nil, 'not an on-duty paramedic' end
    if not QBCore:hasItem(src, 'defibrillator') then return nil, 'no defibrillator' end
    if not nearby(src, targetSrc) then return nil, 'patient is too far away' end
    local eligible, reason = Revive.eligibility(Death.getState(targetSrc), lastAttemptAt[targetSrc], os.time())
    if not eligible then return nil, reason end

    local token = ('%s:%s:%s:%s'):format(src, targetSrc, GetGameTimer(), math.random(100000, 999999))
    actionsBySrc[src] = { token = token, target = targetSrc, expiresAt = GetGameTimer() + Config.death.reviveActionTtl }
    actionOwnerByTarget[targetSrc] = src
    return token
end)

QB.events.register('qbambulance:server:completeRevive', function(src, targetSrc, token, proof)
    local action = actionsBySrc[src]
    targetSrc = tonumber(targetSrc)
    if not action or action.target ~= targetSrc or action.token ~= token then return end
    clearAction(src)
    if action.expiresAt < GetGameTimer() then return end
    if not QB.minigames.consumeProof(src, proof, 'mash') then
        lastAttemptAt[targetSrc] = os.time()
        return
    end
    Revive.complete(src, targetSrc, true)
end)

AddEventHandler('playerDropped', function()
    clearAction(source)
    local owner = actionOwnerByTarget[source]
    if owner then clearAction(owner) end
    lastAttemptAt[source] = nil
end)
