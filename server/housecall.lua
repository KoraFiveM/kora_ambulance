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
local lastRequestAt = {}   -- src -> os.time()
local queue = {}           -- array of {id, src, coords, note, createdAt}
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
---@return table payload Ready to pass to QBCore:alert.
function HouseCall.buildAlertPayload(src, coords, message)
    return {
        jobs = { Config.job.name },
        title = '911 -- Medical Emergency',
        message = message or ('Caller #%d reported a medical emergency.'):format(src),
        coords = coords,
        code = '911e',
        blip = { sprite = 61, color = 1, scale = 1.0 },
        data = { requester = src },
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

---@return table[] A shallow copy, safe for a caller to read/serialise.
function HouseCall.list()
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
    local count = QBCore:alert(HouseCall.buildAlertPayload(src, coords, message))

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
    if not HouseCall.cooldownElapsed(lastRequestAt[src], now, Config.dispatch.housecallCooldown) then
        TriggerClientEvent('QBCore:Notify', src, 'You already have a pending request.', 'error')
        return
    end

    lastRequestAt[src] = now
    nextRequestId = nextRequestId + 1

    queue = HouseCall.submitToQueue(queue, {
        id = nextRequestId,
        src = src,
        coords = GetEntityCoords(GetPlayerPed(src)),
        note = note and note:sub(1, 120) or nil,
        createdAt = now,
    })

    TriggerClientEvent('QBCore:Notify', src, 'Your request has been queued for EMS.', 'success')

    for _, medicSrc in ipairs(QBCore:getPlayersByJob(Config.job.name, true)) do
        TriggerClientEvent('QBCore:Notify', medicSrc, 'A new house-call request is available (/housecalls).', 'primary')
    end
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

    local newQueue, accepted = HouseCall.acceptFromQueue(queue, requestId)
    if not accepted then
        TriggerClientEvent('QBCore:Notify', source, 'That request is no longer available.', 'error')
        return
    end

    queue = newQueue
    TriggerClientEvent('qbambulance:client:housecallAccepted', source, accepted)

    if accepted.src then
        TriggerClientEvent('QBCore:Notify', accepted.src, 'A paramedic is on the way.', 'success')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastAlertAt[src] = nil
    lastRequestAt[src] = nil
end)
