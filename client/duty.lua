-- Duty (client realm) -- duty toggle prompt and duty-fleet vehicle
-- spawn/store at each hospital's garage point. Actual persistence goes
-- through Core.garage server-side (server/duty.lua) -- this file only
-- resolves the spawned network id into a real local entity handle and warps
-- the player into it.

local function isOnDutyEMS()
    local job = exports.qbcore:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

local function resolveNetworkEntity(networkId)
    QB.loops.controlled(function() return NetworkDoesEntityExistWithNetworkId(networkId) end, 50, 2500, 50)
    return NetworkGetEntityFromNetworkId(networkId)
end

local function spawnVehicle(hospital, vehicleIndex)
    local result = QB.callback.trigger('qbambulance:server:spawnDutyVehicle', hospital.name, vehicleIndex)
    if not result then
        QB.notify.send({ title = 'EMS Garage', message = 'Could not check out a vehicle.', type = 'error' })
        return
    end

    local veh = resolveNetworkEntity(result)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    TaskWarpPedIntoVehicle(QB.cache.ped(), veh, -1)
    QB.notify.send({ title = 'EMS Garage', message = 'Vehicle checked out.', type = 'success' })
end

local function storeVehicle()
    local veh = QB.cache.vehicle()
    if not veh then
        QB.notify.send({ title = 'EMS Garage', message = 'Get in the vehicle first.', type = 'error' })
        return
    end

    local snapshot = {
        fuel = math.floor(GetVehicleFuelLevel(veh)),
        engineHealth = math.floor(GetVehicleEngineHealth(veh)),
        bodyHealth = math.floor(GetVehicleBodyHealth(veh)),
    }

    TaskLeaveVehicle(QB.cache.ped(), veh, 0)
    Wait(1500)
    QB.events.trigger('qbambulance:server:storeDutyVehicle', snapshot)
end

for _, hospital in ipairs(Config.hospitals) do
    local options = {}

    for index, vehicleDef in ipairs(Config.dutyVehicles) do
        options[#options + 1] = {
            label = ('Check out %s'):format(vehicleDef.label),
            icon = 'car',
            job = Config.job.name,
            canInteract = isOnDutyEMS,
            action = function() spawnVehicle(hospital, index) end,
        }
    end

    options[#options + 1] = {
        label = 'Return Vehicle',
        icon = 'undo',
        job = Config.job.name,
        canInteract = isOnDutyEMS,
        action = storeVehicle,
    }

    QB.interact.addCircleZone(('qbambulance:garage:%s'):format(hospital.name), hospital.garage, 6.0, options, false)

    QB.interact.addCircleZone(('qbambulance:duty:%s'):format(hospital.name), hospital.duty, 2.0, {
        {
            label = 'Toggle Duty',
            icon = 'briefcase',
            job = Config.job.name,
            -- The real toggle is server/duty.lua's /ems-duty command (also
            -- reachable directly from chat) -- routed through here too so
            -- the world-space prompt doesn't duplicate its validation logic.
            action = function() ExecuteCommand('ems-duty') end,
        },
    }, false)
end
