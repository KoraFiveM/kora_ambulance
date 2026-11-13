-- Hospital (server realm) -- server-owned, short-lived check-in sessions.
-- A client may ask for care, but it cannot choose a bed, skip the wait, or
-- keep a reservation after leaving the facility.

Hospital = Hospital or {}

local QBCore = exports.kora_core
local sessions = {} -- src -> { token, hospital, bedIndex, readyAt, expiresAt }
local reservedBeds = {} -- "hospital:index" -> src
local nextToken = 0

local function getHospital(name)
    for _, hospital in ipairs(Config.hospitals) do
        if hospital.name == name then return hospital end
    end
end

local function getBedKey(hospitalName, bedIndex)
    return ('%s:%d'):format(hospitalName, bedIndex)
end

local function isNear(src, point, range)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= range
end

local function hasInjury(src)
    if Death.isLaststand(src) then return true end
    if next(Death.getWoundData(src)) then return true end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local maxHealth = GetEntityMaxHealth(ped)
    return GetEntityHealth(ped) < maxHealth - Config.injuries.healthTolerance
end

local function releaseSession(src, reason)
    local session = sessions[src]
    if not session then return false end

    sessions[src] = nil
    reservedBeds[getBedKey(session.hospital, session.bedIndex)] = nil
    TriggerClientEvent('kora_ambulance:client:bedReleased', src, reason)
    TriggerEvent('kora_ambulance:server:onBedReleased', src, session.hospital, session.bedIndex, reason)
    return true
end

local function reserveLowestBed(src, hospital)
    for index in ipairs(hospital.beds) do
        local key = getBedKey(hospital.name, index)
        if not reservedBeds[key] then
            reservedBeds[key] = src
            return index
        end
    end
end

local function newToken(src)
    nextToken = nextToken + 1
    return ('%d:%d:%d'):format(src, GetGameTimer(), nextToken)
end

---Reserves the lowest available bed at a nearby hospital for an injured,
---non-dead patient. Returned action data is source-bound and single-use.
---@param src integer
---@param hospitalName string
---@return table|false, string|nil
function Hospital.requestCheckIn(src, hospitalName)
    if not QBCore:getPlayerData(src) then return false, Kora.lang('error.patient_unavailable') end
    if type(hospitalName) ~= 'string' then return false, Kora.lang('error.unknown_hospital') end

    local hospital = getHospital(hospitalName)
    if not hospital then return false, Kora.lang('error.unknown_hospital') end
    if sessions[src] then return false, Kora.lang('error.bed_reserved') end
    if not hospital.beds or #hospital.beds == 0 then
        if Config.Debug then print(('[kora_ambulance] check-in refused: hospital %s has no beds'):format(hospital.name)) end
        return false, Kora.lang('error.no_beds')
    end
    if Death.isDead(src) then return false, Kora.lang('error.dead_respawn') end
    if not isNear(src, hospital.checkIn or hospital.coords, Config.hospitalCare.interactionRange) then
        return false, Kora.lang('error.use_checkin')
    end
    if Config.hospitalCare.requireInjury and not hasInjury(src) then return false, Kora.lang('error.no_care_needed') end

    local bedIndex = reserveLowestBed(src, hospital)
    if not bedIndex then return false, Kora.lang('error.no_beds_available') end

    local now = GetGameTimer()
    local session = {
        token = newToken(src),
        hospital = hospital.name,
        bedIndex = bedIndex,
        readyAt = now + Config.hospitalCare.duration,
        expiresAt = now + math.max(Config.hospitalCare.actionTtl, Config.hospitalCare.duration + 1000),
    }
    sessions[src] = session

    local response = {
        token = session.token,
        hospital = session.hospital,
        bedIndex = session.bedIndex,
        bed = hospital.beds[bedIndex],
        duration = Config.hospitalCare.duration,
        readyAt = session.readyAt,
        expiresAt = session.expiresAt,
    }
    TriggerClientEvent('kora_ambulance:client:checkInAccepted', src, response)
    TriggerEvent('kora_ambulance:server:onPatientCheckedIn', src, session.hospital, session.bedIndex)
    return response
end

---Completes a server-issued bed-care session after re-checking time, identity,
---bed reservation, facility proximity, and current non-dead state.
---@param src integer
---@param token string
---@return boolean, string|nil
function Hospital.completeBedCare(src, token)
    local session = sessions[src]
    if not session or type(token) ~= 'string' or session.token ~= token then return false, Kora.lang('error.invalid_care_session') end

    local now = GetGameTimer()
    if now < session.readyAt then return false, Kora.lang('error.care_not_complete') end
    if now > session.expiresAt then
        releaseSession(src, 'expired')
        return false, Kora.lang('error.care_session_expired')
    end
    if reservedBeds[getBedKey(session.hospital, session.bedIndex)] ~= src then
        releaseSession(src, 'released')
        return false, Kora.lang('error.bed_unreserved')
    end
    if Death.isDead(src) then
        releaseSession(src, 'dead')
        return false, Kora.lang('error.dead_respawn')
    end

    local hospital = getHospital(session.hospital)
    local bed = hospital and hospital.beds[session.bedIndex]
    if not bed or not isNear(src, bed, Config.hospitalCare.bedRange) then
        releaseSession(src, 'left-bed')
        return false, Kora.lang('error.remain_bed')
    end

    if Death.isLaststand(src) then Death.reviveInField(src, 100, true) end
    Death.clearAllWounds(src)
    local cost = Billing.charge(src, Config.billing.checkInCost, 'EMS check-in care')

    releaseSession(src, 'completed')
    TriggerEvent('kora_ambulance:server:onBedCareCompleted', src, session.hospital, session.bedIndex, cost)
    return true
end

---@param src integer
---@param token? string
---@return boolean
function Hospital.leaveBed(src, token)
    local session = sessions[src]
    if not session then return false end
    if token ~= nil and token ~= session.token then return false end
    return releaseSession(src, 'left-bed')
end

---@param src integer
---@return table|nil
function Hospital.getSession(src)
    return sessions[src]
end

Kora.callback.register('kora_ambulance:server:checkInRequested', function(src, hospitalName)
    return Hospital.requestCheckIn(src, hospitalName)
end)

Kora.callback.register('kora_ambulance:server:bedCareCompleted', function(src, token)
    return Hospital.completeBedCare(src, token)
end)

Kora.events.register('kora_ambulance:server:bedLeft', function(src, token)
    Hospital.leaveBed(src, token)
end)

AddEventHandler('playerDropped', function()
    releaseSession(source, 'disconnect')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(sessions) do releaseSession(src, 'resource-stop') end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for src, session in pairs(sessions) do
            if now > session.expiresAt then releaseSession(src, 'expired') end
        end
    end
end)
