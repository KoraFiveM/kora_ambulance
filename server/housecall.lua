-- HouseCall (server realm) -- two distinct EMS dispatch paths sharing one
-- file:
--   1. /911e -- an immediate, one-shot QBCore:alert broadcast to
--      every on-duty EMS (this is the "dispatch via the alert export + a
--      /911e-equivalent command" scope item).
--   2. The house-call QUEUE -- a genuine new differentiator (confirmed
--      absent from qb-ambulancejob/qbx_ambulancejob): a non-emergency
--      request sits in a shared, EMS-browsable queue until a paramedic
--      explicitly accepts it, rather than firing a single alert everyone
--      either reacts to or ignores. Queue mutation is pure (test/smoke/
--      housecall.lua exercises submitToQueue/acceptFromQueue directly);
--      only the command/event wiring below has side effects.

HouseCall = HouseCall or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local lastAlertAt = {}     -- src -> os.time()
local lastRequestAt = {}   -- citizenid -> os.time()
local queue = {}           -- array of {id, citizenid, src, coords, note, createdAt}
local nextRequestId = 0

---@param lastAt integer|nil
---@param now integer os.time()
---@param cooldownMs integer
---@return boolean
function HouseCall.cooldownElapsed(lastAt, now, cooldownMs)
    if not lastAt then return true end
    return (now - lastAt) >= math.floor(cooldownMs / 1000)
end

---@param src integer
---@param coords table|nil
---@param message string|nil
---@return table payload Ready to pass to exports.qbdispatch:createCall.
function HouseCall.buildAlertPayload(src, coords, message)
    return {
        -- Targets the ems job TYPE rather than this resource's job NAME, so a
        -- server with a fire department or a second hospital reaches all of
        -- them from one call.
        jobTypes = { Config.job.type },
        title = '911 -- Medical Emergency',
        message = message or ('Caller #%d reported a medical emergency.'):format(src),
        coords = coords,
        code = '911e',
        priority = 1,
        icon = 'heart-pulse',
        data = { requester = src },
    }
end

---A queued house call, as a dispatch call.
---
---Non-emergency, so priority 3 and a short life on the map -- it should not sit
---above a patient who is actually bleeding out. `onAccept` is the generic hook
---qbdispatch fires server-side when a paramedic first attaches: dispatch knows
---nothing about house calls, it just fires the event name it was handed, which
---is what keeps job-specific behaviour out of it.
---@param request table
---@return table payload
function HouseCall.buildQueuePayload(request)
    return {
        jobTypes = { Config.job.type },
        title = 'House Call',
        message = request.note or ('A non-emergency visit was requested by caller #%d.'):format(request.src),
        coords = request.coords,
        code = '10-51',
        priority = 3,
        icon = 'home',
        onAccept = 'qbambulance:server:housecallAccepted',
        data = { requester = request.src, requestId = request.id, note = request.note },
    }
end

---@param q table[] Existing queue (not mutated).
---@param request table {id, src, coords, note, createdAt}
---@return table[] newQueue
function HouseCall.submitToQueue(q, request)
    local newQueue = {}
    for i, entry in ipairs(q) do newQueue[i] = entry end
    newQueue[#newQueue + 1] = request
    return newQueue
end

---@param q table[]
---@param requestId integer
---@return table[] newQueue
---@return table|nil accepted The removed request, or nil if `requestId` wasn't found.
function HouseCall.acceptFromQueue(q, requestId)
    local newQueue = {}
    local accepted = nil

    for _, entry in ipairs(q) do
        if entry.id == requestId and not accepted then
            accepted = entry
        else
            newQueue[#newQueue + 1] = entry
        end
    end

    return newQueue, accepted
end

---@param q table[]
---@param now integer os.time()
---@param ttlSeconds integer
---@return table[] active
---@return table[] expired
function HouseCall.prune(q, now, ttlSeconds)
    local active, expired = {}, {}
    for _, entry in ipairs(q) do
        local destination = now - entry.createdAt < ttlSeconds and active or expired
        destination[#destination + 1] = entry
    end
    return active, expired
end

---@param q table[]
---@param citizenid string
---@return boolean
function HouseCall.hasPending(q, citizenid)
    for _, entry in ipairs(q) do
        if entry.citizenid == citizenid then return true end
    end
    return false
end

local function pruneQueue()
    local expired
    queue, expired = HouseCall.prune(queue, os.time(), math.floor(Config.dispatch.housecallTtl / 1000))
    for _, request in ipairs(expired) do
        if request.callId then exports.qbdispatch:closeCall(request.callId, 'house call expired') end
    end
end

---@return table[] A shallow copy, safe for a caller to read/serialise.
function HouseCall.list()
    pruneQueue()
    local copy = {}
    for i, entry in ipairs(queue) do copy[i] = entry end
    return copy
end

---@param src integer
---@param coords table|nil
---@param message string|nil
local function fire911e(src, coords, message)
    local now = os.time()
    if not HouseCall.cooldownElapsed(lastAlertAt[src], now, Config.dispatch.alertCooldown) then
        TriggerClientEvent('QBCore:Notify', src, 'Please wait before calling again.', 'error')
        return
    end

    lastAlertAt[src] = now

    -- createCall returns (callId, recipientCount). The count is what tells the
    -- caller whether anybody actually heard them -- "nobody is on duty" and
    -- "help is coming" are very different things to be told while bleeding.
    local _, count = exports.qbdispatch:createCall(HouseCall.buildAlertPayload(src, coords, message))
    count = tonumber(count) or 0

    TriggerClientEvent('QBCore:Notify', src,
        count > 0 and 'Your emergency has been reported to EMS.' or 'No paramedics are currently on duty.',
        count > 0 and 'success' or 'error')
end

-- The caller's own ped coords are read server-side (GetPlayerPed + Get-
-- EntityCoords) -- no client round-trip needed at all, a networked player
-- ped's position is already readable from the server under OneSync. Without
-- this, every alert reached EMS with no location, which defeats the point
-- of a "come find me" emergency call.
QBCore:addCommand('911e', 'Report a medical emergency to EMS', {
    { name = 'message', help = 'What\'s happening (optional)' },
}, false, function(source, args)
    fire911e(source, GetEntityCoords(GetPlayerPed(source)), #args > 0 and table.concat(args, ' ') or nil)
end)

---@param src integer
---@param note string|nil
local function submitHousecall(src, note)
    local now = os.time()
    local citizenid = QBCore:getPlayerData(src, { 'citizenid' })
    if type(citizenid) ~= 'string' or citizenid == '' then return end

    pruneQueue()
    if HouseCall.hasPending(queue, citizenid) then
        TriggerClientEvent('QBCore:Notify', src, 'You already have a pending request.', 'error')
        return
    end
    if not HouseCall.cooldownElapsed(lastRequestAt[citizenid], now, Config.dispatch.housecallCooldown) then
        TriggerClientEvent('QBCore:Notify', src, 'Please wait before requesting another visit.', 'error')
        return
    end
    if #queue >= Config.dispatch.maxHousecalls then
        TriggerClientEvent('QBCore:Notify', src, 'The house-call queue is currently full.', 'error')
        return
    end

    lastRequestAt[citizenid] = now
    nextRequestId = nextRequestId + 1

    local coords = GetEntityCoords(GetPlayerPed(src))
    local request = {
        id = nextRequestId,
        citizenid = citizenid,
        src = src,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        note = note and note:sub(1, 120) or nil,
        createdAt = now,
    }

    -- The queue is also published as a dispatch call, so it appears in the EMS
    -- feed and on the map alongside everything else instead of being a list you
    -- have to remember to type /housecalls to see. The in-memory queue remains
    -- the authority on what is unclaimed; the call is the view of it.
    local callId = exports.qbdispatch:createCall(HouseCall.buildQueuePayload(request))
    request.callId = callId or nil

    queue = HouseCall.submitToQueue(queue, request)

    TriggerClientEvent('QBCore:Notify', src, 'Your request has been queued for EMS.', 'success')
end

QBCore:addCommand('housecall', 'Request a non-emergency EMS visit', {
    { name = 'note', help = 'What you need (optional)' },
}, false, function(source, args)
    submitHousecall(source, #args > 0 and table.concat(args, ' ') or nil)
end)

QBCore:addCommand('housecalls', 'List open house-call requests (EMS)', {}, false, function(source)
    local job = QBCore:getJob(source)
    if not job or job.name ~= Config.job.name then
        TriggerClientEvent('QBCore:Notify', source, 'EMS only.', 'error')
        return
    end

    if #queue == 0 then
        TriggerClientEvent('QBCore:Notify', source, 'No open house-call requests.', 'primary')
        return
    end

    TriggerClientEvent('qbambulance:client:housecallList', source, HouseCall.list())
end)

---Claims a request for a paramedic. One implementation for both entry points --
---the /accepthousecall command and the dispatch UI's accept button -- so a
---request can never be handed out twice because two doors disagreed about
---whether it was still open.
---@param src integer
---@param requestId integer
---@return boolean claimed
local function claimHousecall(src, requestId)
    pruneQueue()
    local newQueue, accepted = HouseCall.acceptFromQueue(queue, requestId)
    if not accepted then return false end

    queue = newQueue
    TriggerClientEvent('qbambulance:client:housecallAccepted', src, accepted)

    if accepted.src then
        TriggerClientEvent('QBCore:Notify', accepted.src, 'A paramedic is on the way.', 'success')
    end

    -- The call has an owner now, so it leaves everyone else's live feed. It
    -- stays in history with the responding unit recorded against it.
    if accepted.callId then
        exports.qbdispatch:closeCall(accepted.callId, 'accepted by a paramedic')
    end

    return true
end

QBCore:addCommand('accepthousecall', 'Accept a house-call request', {
    { name = 'id', help = 'Request id (see /housecalls)' },
}, true, function(source, args)
    local job = QBCore:getJob(source)
    if not job or job.name ~= Config.job.name or not job.onduty then
        TriggerClientEvent('QBCore:Notify', source, 'You must be on-duty EMS.', 'error')
        return
    end

    local requestId = tonumber(args[1])
    if not requestId then return end

    if not claimHousecall(source, requestId) then
        TriggerClientEvent('QBCore:Notify', source, 'That request is no longer available.', 'error')
    end
end)

-- qbdispatch fires this when a paramedic first attaches to a house-call call.
-- The event NAME was handed to dispatch in the call's `onAccept` field --
-- dispatch has no idea what a house call is, it just fires what it was given,
-- which is what keeps job-specific behaviour out of the dispatch resource.
RegisterNetEvent('qbambulance:server:housecallAccepted', function(src, _callId, data)
    -- A net event registration would also let a client fire this directly. It
    -- is only ever raised server-side by qbdispatch (TriggerEvent, not
    -- TriggerClientEvent), so a non-zero `source` means it came over the
    -- network and is refused.
    if source ~= 0 and source ~= nil then return end
    if type(data) ~= 'table' or not data.requestId then return end

    claimHousecall(src, data.requestId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastAlertAt[src] = nil
end)
