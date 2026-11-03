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
---@return table|nil
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

    local patient = patientName(src)
    Ambulance.dispatch.call({
        code = '10-52',
        title = 'Person Down',
        message = ('%s is down and requires medical assistance.'):format(patient),
        priority = 1,
        coords = coordsOf(src),
        icon = 'heart-pulse',
        data = { patient = patient, cause = cause, source = src },
    })
end)

-- Bled out. Lower priority than the laststand alert on purpose: nobody is being
-- saved now, so it must not outrank a patient who still can be. It is raised at
-- all because a body still needs collecting and the death still wants recording.
AddEventHandler('qbambulance:server:onPlayerDead', function(src)
    if not Config.dispatch.autoCall then return end

    local patient = patientName(src)
    Ambulance.dispatch.call({
        code = '10-54',
        title = 'Possible Fatality',
        message = ('%s has stopped breathing.'):format(patient),
        priority = 2,
        coords = coordsOf(src),
        icon = 'heart-pulse',
        data = { patient = patient, source = src },
    })
end)

---Whether `call` is about `src` as the patient: an automatic person-down call
---(data.source), or a /911e the player raised themself (data.requester), which
---the downed screen tells them to use (Config.dispatch.closeCallerAlerts).
---@param call table
---@param src integer
---@return boolean
local function isPatientCall(call, src)
    local data = call.data
    if type(data) ~= 'table' then return false end
    if data.source == src then return true end
    return Config.dispatch.closeCallerAlerts ~= false and call.code == '911e' and data.requester == src
end

---Closes every open EMS call raised for this patient, which also removes the
---call's map blip for everyone. Used when the patient is revived, healed,
---respawns or leaves the server (Config.dispatch.closeOnResolve).
---@param src integer
---@param reason string
local function closePatientCalls(src, reason)
    if Config.dispatch.closeOnResolve == false then return end
    for _, call in ipairs(exports.kora_dispatch:getCalls({ service = Config.job.type, activeOnly = true })) do
        if isPatientCall(call, src) then
            exports.kora_dispatch:closeCall(call.id, reason)
        end
    end
end

-- A patient who was picked up is no longer an open incident. Without this the
-- feed keeps showing people who were treated ten minutes ago, and a feed that
-- lies about what is outstanding stops being read at all.
AddEventHandler('qbambulance:server:onPlayerRevived', function(src)
    -- The cooldown is deliberately NOT cleared here. A patient revived and put
    -- straight back down is the same incident from EMS's point of view -- the
    -- paramedic is already standing over them -- so re-alerting would just be
    -- noise during the exact minute they are busiest. Once the cooldown lapses
    -- it is treated as a genuinely new emergency again.
    closePatientCalls(src, 'patient treated')
end)

-- An admin /heal (server/death.lua confirms the health) leaves nobody to treat.
AddEventHandler('qbambulance:server:onPlayerHealed', function(src)
    closePatientCalls(src, 'patient healed')
end)

-- Respawning at the hospital resolves the incident just as a revive does.
AddEventHandler('qbambulance:server:onPlayerRespawned', function(src)
    closePatientCalls(src, 'patient respawned')
end)

-- Dead-player alert key (Config.death.alertEms). The client only asks; the server
-- decides whether the player is really dead, enforces the cooldown and reads the
-- coordinates itself. The street name is the client's own label, so it is only
-- ever used as bounded display text.
local lastKeyAlertAt = {}

---@param street any
---@return string|nil
local function cleanStreet(street)
    if type(street) ~= 'string' then return nil end
    street = street:gsub('%c', ''):sub(1, 60):match('^%s*(.-)%s*$')
    return street ~= '' and street or nil
end

RegisterNetEvent('qbambulance:server:alertEms', function(street)
    local src = source
    local alert = Config.death.alertEms
    if not alert or alert.enabled ~= true or not Death.isDead(src) then return end

    local now = os.time()
    local last = lastKeyAlertAt[src]
    local cooldown = math.floor(alert.cooldown / 1000)
    if last and now - last < cooldown then
        Kora.notify.send(src, {
            title = 'EMS',
            message = ('You already alerted EMS. Try again in %ds.'):format(cooldown - (now - last)),
            type = 'error',
        })
        return
    end
    lastKeyAlertAt[src] = now

    local patient = patientName(src)
    local coords = coordsOf(src)
    street = cleanStreet(street)
    local where = street or (coords and ('%.0f, %.0f'):format(coords.x, coords.y)) or 'an unknown location'

    local _, count = Ambulance.dispatch.call({
        code = '10-52',
        title = 'Person Down -- Assistance Requested',
        message = ('%s is down and is asking for a medic at %s.'):format(patient, where),
        priority = 1,
        coords = coords,
        icon = 'heart-pulse',
        data = { patient = patient, source = src, street = street },
    })
    count = tonumber(count) or 0
    Kora.notify.send(src, {
        title = 'EMS',
        message = count > 0 and 'Your location has been sent to EMS.' or 'No paramedics are currently on duty.',
        type = count > 0 and 'success' or 'error',
    })
end)

AddEventHandler('playerDropped', function()
    closePatientCalls(source, 'patient left')
    lastAutoCallAt[source] = nil
    lastKeyAlertAt[source] = nil
end)
