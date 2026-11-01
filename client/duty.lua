-- Duty (client realm) -- duty toggle prompt and duty-fleet vehicle
-- spawn/store at each hospital's garage point. The server owns the ephemeral
-- duty vehicle lifecycle; this file only
-- resolves the spawned network id into a real local entity handle and warps
-- the player into it.

local function isOnDutyEMS()
    local job = exports.kora_core:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

local function resolveNetworkEntity(networkId)
    Kora.loops.controlled(function() return NetworkDoesEntityExistWithNetworkId(networkId) end, 50, 2500, 50)
    return NetworkGetEntityFromNetworkId(networkId)
end

local function spawnVehicle(hospital, vehicleIndex)
    local result = Kora.callback.trigger('qbambulance:server:spawnDutyVehicle', hospital.name, vehicleIndex)
    if not result then
        Kora.notify.send({ title = 'EMS Garage', message = 'Could not check out a vehicle.', type = 'error' })
        return
    end

    local veh = resolveNetworkEntity(result)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    TaskWarpPedIntoVehicle(Kora.cache.ped(), veh, -1)
    Kora.notify.send({ title = 'EMS Garage', message = 'Vehicle checked out.', type = 'success' })
end

local function storeVehicle()
    local veh = Kora.cache.vehicle()
    if not veh then
        Kora.notify.send({ title = 'EMS Garage', message = 'Get in the vehicle first.', type = 'error' })
        return
    end

    TaskLeaveVehicle(Kora.cache.ped(), veh, 0)
    Wait(1500)
    Kora.events.trigger('qbambulance:server:storeDutyVehicle')
end

local function garageOptions(hospital)
    local options = {}

    for index, vehicleDef in ipairs(Config.dutyVehicles) do
        options[#options + 1] = {
            label = ('Check out %s'):format(vehicleDef.label),
            icon = 'car',
            canInteract = isOnDutyEMS,
            onSelect = function() spawnVehicle(hospital, index) end,
        }
    end

    options[#options + 1] = {
        label = 'Return Vehicle',
        icon = 'undo',
        canInteract = isOnDutyEMS,
        onSelect = storeVehicle,
    }

    return options
end

local dutyHandlers = {
    isEMS = function()
        local job = exports.kora_core:getJob()
        return job ~= nil and job.name == Config.job.name
    end,
    -- The command and target share the same server-side location and
    -- employment validation.
    duty = function() ExecuteCommand('ems-duty') end,
    garageOptions = garageOptions,
}

local dutyKinds = { duty = true, garage = true }

local function registerDutyTarget(hospital)
    for _, zone in ipairs(HospitalMenu.build(hospital, dutyHandlers)) do
        if dutyKinds[zone.kind] then
            exports.kora_target:addSphereZone({ coords = zone.coords, radius = zone.radius, options = zone.options })
        end
    end
end

local function registerDutyTargets()
    for _, hospital in ipairs(Config.hospitals) do
        if Config.hospitalMenu.isolateErrors then
            local ok, err = pcall(registerDutyTarget, hospital)
            if not ok then
                print(('[kora_ambulance] could not register duty targets for hospital %s: %s'):format(tostring(hospital.name), tostring(err)))
            end
        else
            registerDutyTarget(hospital)
        end
    end
end

registerDutyTargets()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_target' then registerDutyTargets() end
end)

-- EMS red for this player's dispatch UI. Client-side because it is per-player:
-- a paramedic and an officer on the same server see different accents at the
-- same moment, so it can never be a server setting.
CreateThread(function()
    Wait(1500) -- let kora_dispatch's own frame mount before pushing tokens at it
    exports.kora_dispatch:setTheme(Config.dispatch.accent)
end)
