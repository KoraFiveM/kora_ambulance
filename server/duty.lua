-- Duty (server realm) -- EMS duty toggle and duty-fleet vehicles via
-- Core.garage. Uses the RAW CreateVehicle path (QBCore:spawnVehicle),
-- never QB.entities -- a duty ambulance must be a real networked entity
-- visible to every player, not a local-only prop (see Core.garage's own
-- header for why).

Duty = Duty or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local currentVehicle = {}      -- src -> plate of the duty vehicle currently checked out to them
local currentVehicleNetId = {} -- src -> its network id, so storeDutyVehicle can delete the live entity server-side

-- Pharmacy shop + EMS stash per hospital. Safe to call unconditionally at
-- load time (unlike qbcore's own Core.consumables, which has to defer to
-- onResourceStart) -- qbambulance declares `dependency 'qbinventory'`, so
-- FXServer already guarantees qbinventory is running before this resource's
-- own scripts start. THAT guarantee only covers ordering on a fresh boot,
-- though -- a `dependency` declaration says nothing about a qbinventory
-- RESTART mid-session, which wipes qbinventory's own shop/stash tables
-- without touching qbambulance at all. So this is wrapped in a function,
-- called once at load (per the load-time guarantee above) AND again on
-- every qbinventory onResourceStart, to survive that case too.
local function registerHospitals()
    for _, hospital in ipairs(Config.hospitals) do
        exports.qbinventory:registerShop(('ambulance_pharmacy_%s'):format(hospital.name), {
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

        exports.qbinventory:registerStash(
            ('ambulance_stash_%s'):format(hospital.name),
            hospital.label .. ' EMS Stash',
            hospital.stash.slots, hospital.stash.maxWeight,
            false, { [Config.job.name] = 0 }, hospital.stash.coords
        )
    end
end

registerHospitals()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'qbinventory' then registerHospitals() end
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

QB.callback.register('qbambulance:server:spawnDutyVehicle', function(src, hospitalName, vehicleIndex)
    if not isOnDutyEMS(src) then return false, 'not on duty' end
    if currentVehicle[src] then return false, 'you already have a duty vehicle checked out' end

    local hospital
    for _, h in ipairs(Config.hospitals) do
        if h.name == hospitalName then hospital = h; break end
    end
    if not hospital then return false, 'unknown hospital' end

    local vehicleDef = Config.dutyVehicles[tonumber(vehicleIndex) or 0]
    if not vehicleDef then return false, 'unknown vehicle' end

    local plate = Duty.generatePlate()
    local ok, err = QBCore:createVehicle(nil, vehicleDef.model, plate, Config.job.name)
    if not ok then return false, err end

    local networkId, spawnErr = QBCore:spawnVehicle(src, plate, hospital.garage, hospital.garage.w or 0.0)
    if not networkId then
        QBCore:deleteVehicle(plate)
        return false, spawnErr
    end

    currentVehicle[src] = plate
    currentVehicleNetId[src] = networkId
    return networkId
end)

QB.events.register('qbambulance:server:storeDutyVehicle', function(src, snapshot)
    local plate = currentVehicle[src]
    if not plate then return end

    QBCore:storeVehicle(plate, snapshot)

    local netId = currentVehicleNetId[src]
    if netId then
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end

    currentVehicle[src] = nil
    currentVehicleNetId[src] = nil
    QB.notify.send(src, { title = 'EMS Garage', message = 'Vehicle returned to the fleet.', type = 'success' })
end)

---@param src integer
---@return string|nil
function Duty.currentVehiclePlate(src)
    return currentVehicle[src]
end

QBCore:addCommand('ems-duty', 'Toggle EMS duty', {}, false, function(source)
    local job = QBCore:getJob(source)
    if not job or job.name ~= Config.job.name then
        TriggerClientEvent('QBCore:Notify', source, 'You are not employed as EMS.', 'error')
        return
    end

    local newDuty = not job.onduty
    QBCore:setJobDuty(source, newDuty)
    TriggerClientEvent('QBCore:Notify', source, newDuty and 'You are now on duty.' or 'You are now off duty.', 'success')
end)

AddEventHandler('playerDropped', function()
    currentVehicle[source] = nil
    currentVehicleNetId[source] = nil
end)
