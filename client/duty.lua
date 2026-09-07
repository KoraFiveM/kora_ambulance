-- Duty (client realm) -- duty toggle prompt and duty-fleet vehicle
-- spawn/store at each hospital's garage point. The server owns the ephemeral
-- duty vehicle lifecycle; this file only
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

    TaskLeaveVehicle(QB.cache.ped(), veh, 0)
    Wait(1500)
    QB.events.trigger('qbambulance:server:storeDutyVehicle')
end

local function registerDutyTargets()
for _, hospital in ipairs(Config.hospitals) do
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

    exports.qbtarget:addSphereZone({
        coords = hospital.garage,
        radius = 6.0,
        options = options,
    })

    exports.qbtarget:addSphereZone({
        coords = hospital.duty,
        radius = 2.0,
        options = {
            {
                label = 'Toggle Duty',
                icon = 'briefcase',
                canInteract = function()
                    local job = exports.qbcore:getJob()
                    return job ~= nil and job.name == Config.job.name
                end,
                -- The real toggle is server/duty.lua's /ems-duty command (also
                -- reachable directly from chat) -- routed through here too so
                -- the world-space prompt doesn't duplicate its validation logic.
                onSelect = function() ExecuteCommand('ems-duty') end,
            },
        },
    })
end
end

registerDutyTargets()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'qbtarget' then registerDutyTargets() end
end)


-- EMS red for this player's dispatch UI. Client-side because it is per-player:
-- a paramedic and an officer on the same server see different accents at the
-- same moment, so it can never be a server setting.
CreateThread(function()
    Wait(1500) -- let qbdispatch's own frame mount before pushing tokens at it
    exports.qbdispatch:setTheme(Config.dispatch.accent)
end)
