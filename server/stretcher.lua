-- Stretcher (server realm) -- server-side validation and relationship
-- tracking for dragging a downed player. The actual per-frame position sync
-- is entirely client-side (client/stretcher.lua): the dragged player's own
-- client stays network owner of their own ped and self-corrects off the
-- dragger's live (already-networked) ped coords + a broadcast relative
-- offset -- this module only decides WHO is allowed to drag WHOM, relays the
-- begin/end handshake, and verifies a low-rate relationship heartbeat.
--
-- Differentiator feature (confirmed absent from both qb-ambulancejob and
-- qbx_ambulancejob) -- see the plan's qbambulance section for why
-- QB.anim.attachProp alone can't solve this: the dragged entity is another
-- player's own networked ped, not a prop this resource owns.

Stretcher = Stretcher or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local draggerOf = {}  -- targetSrc -> draggerSrc
local targetOf = {}   -- draggerSrc -> targetSrc
local lastHeartbeatAt = {}

---Pure eligibility check for starting a drag.
---@param targetState "alive"|"laststand"|"dead"
---@param targetAlreadyDragged boolean
---@param draggerAlreadyDragging boolean
---@return boolean eligible
---@return string|nil reason
function Stretcher.canPickup(targetState, targetAlreadyDragged, draggerAlreadyDragging)
    if targetState == 'alive' then return false, 'patient is not down' end
    if targetAlreadyDragged then return false, 'someone is already carrying this patient' end
    if draggerAlreadyDragging then return false, 'you are already carrying a patient' end
    return true, nil
end

---@param src integer
---@return boolean
local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param src integer
---@return integer|nil targetSrc The patient `src` is currently dragging, if any.
function Stretcher.draggingTarget(src)
    return targetOf[src]
end

---@param targetSrc integer
---@return integer|nil draggerSrc Who is currently dragging `targetSrc`, if anyone.
function Stretcher.draggedBy(targetSrc)
    return draggerOf[targetSrc]
end

local function releaseInternal(draggerSrc, silent)
    local targetSrc = targetOf[draggerSrc]
    if not targetSrc then return end

    targetOf[draggerSrc] = nil
    draggerOf[targetSrc] = nil
    lastHeartbeatAt[draggerSrc] = nil

    if not silent then
        TriggerClientEvent('qbambulance:client:stretcherEnd', draggerSrc)
        TriggerClientEvent('qbambulance:client:stretcherEnd', targetSrc)
    end
end

QB.events.register('qbambulance:server:stretcherPickup', function(src, targetSrc)
    if type(targetSrc) ~= 'number' then return end
    if not isOnDutyEMS(src) then return end
    if not exports.qbcore:getPlayerData(targetSrc) then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return end
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not ped or ped == 0 or not targetPed or targetPed == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.death.reviveRange then return end

    local eligible, reason = Stretcher.canPickup(Death.getState(targetSrc), draggerOf[targetSrc] ~= nil, targetOf[src] ~= nil)
    if not eligible then
        QB.notify.send(src, { title = 'EMS', message = reason, type = 'error' })
        return
    end

    draggerOf[targetSrc] = src
    targetOf[src] = targetSrc

    TriggerClientEvent('qbambulance:client:stretcherBegin', src, targetSrc, true)   -- true = you are the dragger
    TriggerClientEvent('qbambulance:client:stretcherBegin', targetSrc, src, false)  -- false = you are being dragged
end)

QB.events.register('qbambulance:server:stretcherRelease', function(src)
    releaseInternal(src, false)
end)

-- Low-tick-rate relative-offset relay: forwarded to the dragged player's
-- client only (never broadcast), which is what makes this cheap regardless
-- of server population -- one small table, one targeted TriggerClientEvent,
-- at whatever interval client/stretcher.lua chooses to send it at.
QB.events.register('qbambulance:server:stretcherHeartbeat', function(src)
    local targetSrc = targetOf[src]
    if not targetSrc then return end

    local now = GetGameTimer()
    local previous = lastHeartbeatAt[src]
    if previous and now - previous < 500 then return end
    lastHeartbeatAt[src] = now

    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    local invalid = not isOnDutyEMS(src)
        or not exports.qbcore:getPlayerData(targetSrc)
        or GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc)
        or not ped or ped == 0
        or not targetPed or targetPed == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.death.reviveRange * 2.0

    if invalid then releaseInternal(src, false) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    releaseInternal(src, true)

    local draggerSrc = draggerOf[src]
    if draggerSrc then releaseInternal(draggerSrc, true) end
end)
