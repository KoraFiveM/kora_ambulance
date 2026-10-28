-- Duty (server realm) -- EMS duty toggle and ephemeral duty-fleet vehicles.
-- Shared vehicles are created by the server so they remain compatible with
-- strict entity lockdown. They are deliberately not inserted into the owned
-- vehicle table: returning, disconnecting, or stopping this resource deletes
-- them instead of leaking one persistent row per checkout.

Duty = Duty or {}

-- kora_core has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.kora_core:<fn>(...) call instead.
local QBCore = exports.kora_core

local currentVehicle = {}  -- src -> { plate, networkId }
local lastVehicleAction = {}
local lastDutyChange = {}

-- Pharmacy shop + EMS stash per hospital. Safe to call unconditionally at
-- load time (unlike kora_core's own Core.consumables, which has to defer to
-- onResourceStart) -- kora_ambulance declares `dependency 'kora_inventory'`, so
-- FXServer already guarantees kora_inventory is running before this resource's
-- own scripts start. THAT guarantee only covers ordering on a fresh boot,
-- though -- a `dependency` declaration says nothing about a kora_inventory
-- RESTART mid-session, which wipes kora_inventory's own shop/stash tables
-- without touching kora_ambulance at all. So this is wrapped in a function,
-- called once at load (per the load-time guarantee above) AND again on
-- every kora_inventory onResourceStart, to survive that case too.
local function registerHospitals()
    for _, hospital in ipairs(Config.hospitals) do
        if hospital.pharmacy then
            exports.kora_inventory:registerShop(('ambulance_pharmacy_%s'):format(hospital.name), {
                label = hospital.label .. ' Pharmacy',
                slots = 4,
                coords = hospital.pharmacy,
                distance = 3.0,
                inventory = {
                    { slot = 1, name = 'bandage', amount = 200, price = 15 },
                    { slot = 2, name = 'ifak', amount = 100, price = 60 },
                    { slot = 3, name = 'painkillers', amount = 150, price = 25 },
                    { slot = 4, name = 'defibrillator', amount = 20, price = 350 },
                },
            })
        end

        if hospital.stash then
            exports.kora_inventory:registerStash(
                ('ambulance_stash_%s'):format(hospital.name),
                hospital.label .. ' EMS Stash',
                hospital.stash.slots, hospital.stash.maxWeight,
                false, { [Config.job.name] = 0 }, hospital.stash.coords
            )
        end
    end
end

registerHospitals()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'kora_inventory' then registerHospitals() end
end)

local PLATE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

---@return string A fresh, unlikely-to-collide plate. Collision is not
---checked against the DB (same trade-off any qb-style garage script makes) --
---an 8-character alphanumeric space is large enough that a retry loop would
---almost always be pure overhead.
function Duty.generatePlate()
    local parts = { 'EMS' }
    for _ = 1, 5 do
        local i = math.random(1, #PLATE_CHARS)
        parts[#parts + 1] = PLATE_CHARS:sub(i, i)
    end
    return table.concat(parts)
end

---@param src integer
---@return boolean
local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param src integer
---@param garage vector3|table
---@return boolean
local function isNearGarage(src, garage)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - garage.x, coords.y - garage.y, coords.z - garage.z
    return dx * dx + dy * dy + dz * dz <= Config.dutyGarage.interactionRange ^ 2
end

local function isNearDutyPoint(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, hospital in ipairs(Config.hospitals) do
        local duty = hospital.duty
        if duty then
            local dx, dy, dz = coords.x - duty.x, coords.y - duty.y, coords.z - duty.z
            if dx * dx + dy * dy + dz * dz <= 9.0 then return true end
        end
    end
    return false
end

---@param src integer
---@param onDuty boolean
---@return boolean, string|nil
function Duty.setDuty(src, onDuty)
    local job = QBCore:getJob(src)
    if not job or job.name ~= Config.job.name then return false, 'You are not employed as EMS.' end
    if not isNearDutyPoint(src) then return false, 'Use a hospital duty point to change duty status.' end
    onDuty = onDuty == true
    if job.onduty == onDuty then return true end

    local current = GetGameTimer()
    if lastDutyChange[src] and current - lastDutyChange[src] < 1000 then
        return false, 'Wait before changing duty status again.'
    end
    local changed, err = QBCore:setJobDuty(src, onDuty)
    if changed then lastDutyChange[src] = current end
    return changed, err
end

---@param src integer
---@return boolean
local function actionAllowed(src)
    local now = GetGameTimer()
    local previous = lastVehicleAction[src]
    if previous and now - previous < Config.dutyGarage.actionCooldown then return false end
    lastVehicleAction[src] = now
    return true
end

---@param networkId integer|nil
local function deleteNetworkVehicle(networkId)
    if not networkId then return end
    local vehicle = NetworkGetEntityFromNetworkId(networkId)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

---@param src integer
local function clearDutyVehicle(src)
    local active = currentVehicle[src]
    if active and Stretcher and Stretcher.removeForVehicle then
        Stretcher.removeForVehicle(active.networkId, 'duty vehicle removed')
    end
    if active then deleteNetworkVehicle(active.networkId) end
    currentVehicle[src] = nil
end

QB.callback.register('qbambulance:server:spawnDutyVehicle', function(src, hospitalName, vehicleIndex)
    if not isOnDutyEMS(src) then return false, 'not on duty' end
    if currentVehicle[src] then return false, 'you already have a duty vehicle checked out' end
    if not actionAllowed(src) then return false, 'please wait before trying again' end

    local hospital
    for _, h in ipairs(Config.hospitals) do
        if h.name == hospitalName then hospital = h; break end
    end
    if not hospital then return false, 'unknown hospital' end
    if not isNearGarage(src, hospital.garage) then return false, 'not at this garage' end

    local vehicleDef = Config.dutyVehicles[tonumber(vehicleIndex) or 0]
    if not vehicleDef then return false, 'unknown vehicle' end

    local plate = Duty.generatePlate()
    local vehicle = CreateVehicle(
        joaat(vehicleDef.model),
        hospital.garage.x, hospital.garage.y, hospital.garage.z,
        hospital.garage.w or 0.0,
        true,
        false
    )
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'failed to create vehicle' end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, plate)

    local networkId = NetworkGetNetworkIdFromEntity(vehicle)
    if not networkId or networkId == 0 then
        DeleteEntity(vehicle)
        return false, 'failed to network vehicle'
    end

    currentVehicle[src] = {
        plate = plate,
        networkId = networkId,
        vehicleIndex = tonumber(vehicleIndex),
        model = joaat(vehicleDef.model),
    }
    return networkId
end)

QB.events.register('qbambulance:server:storeDutyVehicle', function(src)
    local active = currentVehicle[src]
    if not active or not isOnDutyEMS(src) or not actionAllowed(src) then return end

    local nearGarage = false
    for _, hospital in ipairs(Config.hospitals) do
        if hospital.garage and isNearGarage(src, hospital.garage) then nearGarage = true; break end
    end
    if not nearGarage then return end

    clearDutyVehicle(src)
    QB.notify.send(src, { title = 'EMS Garage', message = 'Vehicle returned to the fleet.', type = 'success' })
end)

---@param src integer
---@return string|nil
function Duty.currentVehiclePlate(src)
    return currentVehicle[src] and currentVehicle[src].plate or nil
end

---@param src integer
---@return integer|nil
function Duty.currentVehicleNetworkId(src)
    return currentVehicle[src] and currentVehicle[src].networkId or nil
end

---Returns a tracked ephemeral duty-vehicle record. This is an internal
---same-resource contract for the stretcher module; callers must not mutate it.
---@param networkId integer
---@return table|nil record
---@return integer|nil ownerSrc
function Duty.vehicleRecord(networkId)
    for ownerSrc, record in pairs(currentVehicle) do
        if record.networkId == networkId then return record, ownerSrc end
    end
    return nil, nil
end

QB.commands.add('ems-duty', 'Toggle EMS duty at a hospital', {}, false, function(source)
    local job = QBCore:getJob(source)
    local newDuty = job ~= nil and not job.onduty
    local changed, err = Duty.setDuty(source, newDuty)
    QB.notify.send(source, {
        message = changed and (newDuty and 'You are now on duty.' or 'You are now off duty.')
            or (err or 'Duty status could not be changed.'),
        type = changed and 'success' or 'error',
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearDutyVehicle(src)
    lastVehicleAction[src] = nil
    lastDutyChange[src] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(currentVehicle) do clearDutyVehicle(src) end
end)
