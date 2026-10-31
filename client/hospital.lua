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

local function registerHospitalTargets()
    for _, hospital in ipairs(Config.hospitals) do
        exports.kora_target:addSphereZone({
            coords = hospital.checkIn or hospital.coords,
            radius = Config.hospitalCare.interactionRange,
            options = {
                {
                    label = 'Check In for Care', icon = 'bed',
                    onSelect = function() requestCheckIn(hospital) end,
                },
            },
        })

        if hospital.pharmacy then
            exports.kora_target:addSphereZone({
                coords = hospital.pharmacy,
                radius = 3.0,
                options = {
                    {
                        label = 'Browse Pharmacy', icon = 'pill',
                        onSelect = function()
                            exports.kora_inventory:openInventory('shop', ('ambulance_pharmacy_%s'):format(hospital.name))
                        end,
                    },
                },
            })
        end

        if hospital.stash and hospital.stash.coords then
            exports.kora_target:addSphereZone({
                coords = hospital.stash.coords,
                radius = 3.0,
                options = {
                    {
                        label = 'EMS Stash', icon = 'box',
                        canInteract = function()
                            local job = exports.kora_core:getJob()
                            return job ~= nil and job.name == Config.job.name
                        end,
                        onSelect = function()
                            exports.kora_inventory:openInventory('stash', ('ambulance_stash_%s'):format(hospital.name))
                        end,
                    },
                },
            })
        end

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
end

registerHospitalTargets()

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_target' then registerHospitalTargets() end
end)
