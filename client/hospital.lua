-- Hospital (client realm) -- facility presentation only. The server chooses
-- and reserves beds; this file cannot select one or make care succeed early.

local activeCare

local function stopCare(token)
    if not activeCare or (token and activeCare.token ~= token) then return end
    ClearPedTasks(PlayerPedId())
    activeCare = nil
end

local function startCare(care)
    if type(care) ~= 'table' or type(care.token) ~= 'string' or activeCare then return end
    activeCare = care

    local bed = care.bed
    local ped = PlayerPedId()
    SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
    TaskStartScenarioAtPosition(ped, 'PROP_HUMAN_BUM_BIN', bed.x, bed.y, bed.z, bed.w or 0.0, 0, true, false)
    Kora.notify.send({ title = 'Hospital Check-in', message = 'Resting in your assigned bed.', type = 'info' })

    CreateThread(function()
        local token = care.token
        local startedAt = GetGameTimer()
        while activeCare and activeCare.token == token do
            if IsControlJustPressed(0, 38) then
                Kora.events.trigger('qbambulance:server:bedLeft', token)
                return
            end
            if GetGameTimer() - startedAt >= care.duration then
                local completed, reason = Kora.callback.trigger('qbambulance:server:bedCareCompleted', token)
                if not completed then
                    Kora.notify.send({ title = 'Hospital Check-in', message = reason or 'Care was not completed.', type = 'warning' })
                end
                return
            end
            Wait(0)
        end
    end)
end

local function requestCheckIn(hospital)
    if not hospital.beds or #hospital.beds == 0 then
        Kora.notify.send({ title = 'Hospital Check-in', message = 'This hospital has no beds available.', type = 'warning' })
        return
    end
    if activeCare then
        Kora.notify.send({ title = 'Hospital Check-in', message = 'You already have a bed reserved.', type = 'warning' })
        return
    end
    local care, reason = Kora.callback.trigger('qbambulance:server:checkInRequested', hospital.name)
    if not care then
        Kora.notify.send({ title = 'Hospital Check-in', message = reason or 'Check-in is unavailable.', type = 'error' })
        return
    end
    startCare(care)
end

RegisterNetEvent('qbambulance:client:checkInAccepted', function(care)
    startCare(care)
end)

RegisterNetEvent('qbambulance:client:bedReleased', function(reason)
    if not activeCare then return end
    stopCare(activeCare.token)
    if reason == 'completed' then
        local ped = PlayerPedId()
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        Kora.notify.send({ title = 'Hospital Check-in', message = 'Care completed.', type = 'success' })
    elseif reason ~= 'left-bed' then
        Kora.notify.send({ title = 'Hospital Check-in', message = 'Your bed reservation was released.', type = 'warning' })
    end
end)

local function isEMS()
    local job = exports.kora_core:getJob()
    return job ~= nil and job.name == Config.job.name
end

local hospitalHandlers = {
    isEMS = isEMS,
    checkIn = requestCheckIn,
    pharmacy = function(hospital)
        exports.kora_inventory:openInventory('shop', ('ambulance_pharmacy_%s'):format(hospital.name))
    end,
    stash = function(hospital)
        exports.kora_inventory:openInventory('stash', ('ambulance_stash_%s'):format(hospital.name))
    end,
}

local facilityKinds = { checkIn = true, pharmacy = true, stash = true }

local zoneIds = {} -- hospital name -> ids of the zones registered for it, replaced on re-registration

local function registerHospital(hospital)
    if Config.Debug then
        print(('[kora_ambulance] registering targets for hospital %s (beds: %d)'):format(hospital.name, #(hospital.beds or {})))
    end

    zoneIds[hospital.name] = zoneIds[hospital.name] or {}
    HospitalMenu.register(zoneIds[hospital.name], HospitalMenu.build(hospital, hospitalHandlers), facilityKinds,
        function(definition) return exports.kora_target:addSphereZone(definition) end,
        function(id) exports.kora_target:removeZone(id) end)

    if hospital.blip then
        local blip = Kora.blips.create(hospital.coords, hospital.blip)
        if blip and not hospital.blip.info then
            Kora.blips.setInfo(blip, {
                title = hospital.label,
                rows = { { kind = 'wrappedText', value = 'Medical services and EMS facilities are available here.' } },
            })
        end
    end
end

local function registerHospitalTargets()
    for _, hospital in ipairs(Config.hospitals) do
        if Config.hospitalMenu.isolateErrors then
            local ok, err = pcall(registerHospital, hospital)
            if not ok then
                print(('[kora_ambulance] could not register targets for hospital %s: %s'):format(tostring(hospital.name), tostring(err)))
            end
        else
            registerHospital(hospital)
        end
    end
end

registerHospitalTargets()

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_target' then registerHospitalTargets() end
end)
