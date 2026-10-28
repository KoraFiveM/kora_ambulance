-- EMS dispatch.
--
-- Everything about presenting a call -- the feed, the map, history, response
-- states -- belongs to kora_dispatch. This file only decides what counts as an EMS
-- call and how each one is worded, which is medical-resource business that
-- dispatch has no opinion about.
--
-- The automatic alerts here restore behaviour the rewrite dropped: real
-- qb-ambulancejob fired hospital:server:ambulanceAlert on entering laststand, on
-- dying, and on the in-laststand help key. This resource had none of them, so a
-- player bleeding out had no way to reach EMS except typing a command.

Ambulance = Ambulance or {}
Ambulance.dispatch = {}

local QBCore = exports.kora_core

-- src -> os.time() of that player's last automatic call. Death and laststand
-- both fire on the way down, and a revive-then-die cycle can repeat quickly;
-- without this a single messy firefight would fill the EMS feed with the same
-- patient over and over.
local lastAutoCallAt = {}

---@param src integer
---@return boolean
local function cooldownElapsed(src)
    local last = lastAutoCallAt[src]
    if not last then return true end
    return (os.time() - last) >= math.floor(Config.dispatch.autoCallCooldown / 1000)
end

---Names a patient the way EMS would hear it, falling back through what is
---actually known rather than exposing a raw source id where a name should be.
---@param src integer
---@return string
local function patientName(src)
    -- The path form reads just the sub-table. Fetching the whole PlayerData
    -- would deep-clone the entire blob (inventory included) to read two strings,
    -- on a code path that runs every time anybody goes down.
    local charinfo = QBCore:getPlayerData(src, { 'charinfo' })
    if charinfo and charinfo.firstname then
        return ('%s %s'):format(charinfo.firstname, charinfo.lastname or ''):gsub('%s+$', '')
    end
    return ('Patient #%d'):format(src)
end

---Raises an EMS call. Targets the ems job TYPE, so a server that adds a fire
---department or a second hospital with `type = 'ems'` gets them on the same
---radio with no change here.
---@param payload table
---@return integer|false callId, integer|string recipientCountOrError
function Ambulance.dispatch.call(payload)
    payload = payload or {}
    if not payload.jobs and not payload.jobTypes then
        payload.jobTypes = { Config.job.type }
    end
    return exports.kora_dispatch:createCall(payload)
end

---@param src integer
---@param coords table|nil
local function coordsOf(src, coords)
    if coords then return coords end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local position = GetEntityCoords(ped)
    return { x = position.x, y = position.y, z = position.z }
end

-- Entering laststand: the patient is down but savable, and this is the alert
-- that actually matters -- a paramedic reaching them before the bleed-out timer
-- expires is the difference between a revive and a respawn.
AddEventHandler('qbambulance:server:onPlayerDied', function(src, cause)
    if not Config.dispatch.autoCall then return end
    if not cooldownElapsed(src) then return end
    lastAutoCallAt[src] = os.time()

    Ambulance.dispatch.call({
        code = '10-52',
        title = 'Person Down',
        message = ('%s is down and requires medical assistance.'):format(patientName(src)),
        priority = 1,
        coords = coordsOf(src),
        icon = 'heart-pulse',
        data = { patient = patientName(src), cause = cause, source = src },
    })
end)

-- Bled out. Lower priority than the laststand alert on purpose: nobody is being
-- saved now, so it must not outrank a patient who still can be. It is raised at
-- all because a body still needs collecting and the death still wants recording.
AddEventHandler('qbambulance:server:onPlayerDead', function(src)
    if not Config.dispatch.autoCall then return end

    Ambulance.dispatch.call({
        code = '10-54',
        title = 'Possible Fatality',
        message = ('%s has stopped breathing.'):format(patientName(src)),
        priority = 2,
        coords = coordsOf(src),
        icon = 'heart-pulse',
        data = { patient = patientName(src), source = src },
    })
end)

-- A patient who was picked up is no longer an open incident. Without this the
-- feed keeps showing people who were treated ten minutes ago, and a feed that
-- lies about what is outstanding stops being read at all.
AddEventHandler('qbambulance:server:onPlayerRevived', function(src)
    -- The cooldown is deliberately NOT cleared here. A patient revived and put
    -- straight back down is the same incident from EMS's point of view -- the
    -- paramedic is already standing over them -- so re-alerting would just be
    -- noise during the exact minute they are busiest. Once the cooldown lapses
    -- it is treated as a genuinely new emergency again.
    for _, call in ipairs(exports.kora_dispatch:getCalls({ service = Config.job.type, activeOnly = true })) do
        if call.data and call.data.source == src then
            exports.kora_dispatch:closeCall(call.id, 'patient treated')
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastAutoCallAt[source] = nil
end)
