-- Safe qb-ambulancejob compatibility presentation. Client events never
-- grant health, alter medical state or select a bed; meaningful actions are
-- requested through the validated server adapter.

if not Config.compat.enabled then return end

local lastKnownDoctorCount = 0
local painScreenHandle

-- Registered but inert. qbdispatch renders every EMS call now, including the
-- ones raised from the legacy hospital:server:ambulanceAlert path -- it
-- registers that server event itself and turns it into a real call. Rendering
-- here as well would show the same incident twice, once as a proper dispatch
-- card and once as a stray toast with a blip that outlives it.
--
-- The registration is kept so a third-party resource firing this client event
-- directly still finds a listener rather than an error.
RegisterNetEvent('hospital:client:ambulanceAlert', function() end)

RegisterNetEvent('hospital:client:Revive', function()
    QB.notify.send({ title = 'EMS', message = 'A server-authorized medic must perform CPR.', type = 'info' })
end)

RegisterNetEvent('hospital:client:RevivePlayer', function()
    QB.notify.send({ title = 'EMS', message = 'A server-authorized medic must perform CPR.', type = 'info' })
end)

RegisterNetEvent('hospital:client:SetPain', function(level)
    if tonumber(level) and tonumber(level) > 0 then
        if not painScreenHandle then
            painScreenHandle = QB.fx.screenEffect('DrugsMichaelAliensFightIn', 0, true)
        end
    else
        if painScreenHandle then
            QB.fx.stopScreenEffect(painScreenHandle)
            painScreenHandle = nil
        end
    end
end)

RegisterNetEvent('hospital:client:KillPlayer', function()
    -- Intentionally inert: a locally-triggerable compatibility event cannot
    -- be an authority for changing a player's health.
end)

RegisterNetEvent('hospital:client:HealInjuries', function(_percent)
    QB.notify.send({ title = 'Hospital', message = 'Use patient treatment or hospital check-in.', type = 'info' })
end)

RegisterNetEvent('hospital:client:SendToBed', function(_bedIndex)
    QB.notify.send({ title = 'Hospital', message = 'Use a check-in desk for a server-assigned bed.', type = 'info' })
end)

RegisterNetEvent('hospital:client:leaveBed', function()
    TriggerServerEvent('hospital:server:leaveBed')
end)

RegisterNetEvent('hospital:client:SetBed', function(bedIndex)
    QB.notify.send({ title = 'Hospital', message = ('Assigned to bed %s.'):format(tostring(bedIndex)), type = 'info' })
end)

RegisterNetEvent('hospital:client:SetBed2', function(bedIndex)
    QB.notify.send({ title = 'Hospital', message = ('Assigned to bed %s.'):format(tostring(bedIndex)), type = 'info' })
end)

RegisterNetEvent('hospital:client:RespawnAtHospital', function()
    TriggerServerEvent('hospital:server:RespawnAtHospital')
end)

RegisterNetEvent('hospital:client:SendBillEmail', function(amount)
    QB.notify.send({ title = 'Hospital Bill', message = ('You were billed $%d.'):format(tonumber(amount) or 0), type = 'warning' })
end)

RegisterNetEvent('hospital:client:SetDoctorCount', function(count)
    lastKnownDoctorCount = tonumber(count) or 0
end)

RegisterNetEvent('hospital:client:adminHeal', function()
    QB.notify.send({ title = 'Hospital', message = 'Client-side admin healing is disabled.', type = 'error' })
end)

RegisterNetEvent('hospital:client:CheckStatus', function()
    local status = QB.callback.trigger('hospital:GetPlayerStatus')
    if type(status) ~= 'table' then return end

    local woundCount = 0
    for _ in pairs(status.woundData or {}) do woundCount = woundCount + 1 end

    QB.notify.send({
        title = 'status',
        message = ('Dead: %s | Laststand: %s | Open wounds: %d'):format(tostring(status.isdead), tostring(status.inlaststand), woundCount),
        type = 'info',
    })
end)

RegisterNetEvent('hospital:client:TreatWounds', function()
    QB.notify.send({ title = 'EMS', message = 'Target a patient to start validated treatment.', type = 'info' })
end)

-- SetEscortingState/isEscorted map onto our own stretcher system rather than
-- a separate compat-only flag -- see client/stretcher.lua's header for why
-- dragging state has to live there (it owns the actual per-frame position
-- sync), and its Stretcher.isBeingDragged()/isDragging() getters exposed for
-- exactly this reason.
RegisterNetEvent('hospital:client:SetEscortingState', function(state)
    if not state then TriggerServerEvent('qbambulance:server:stretcherRelease') end
end)

exports('isEscorted', function()
    return Stretcher and Stretcher.isBeingDragged and Stretcher.isBeingDragged() or false
end)

exports('CanHelp', function()
    local alive = State and State.isAlive and State.isAlive()
    local escorted = Stretcher and Stretcher.isBeingDragged and Stretcher.isBeingDragged()
    return alive == true and escorted ~= true
end)

RegisterNetEvent('hospital:client:HelpPerson', function()
    QB.notify.send({ title = 'EMS', message = 'Target a downed player to perform CPR or apply first aid.', type = 'info' })
end)

RegisterNetEvent('hospital:client:UseFirstAid', function()
    TriggerServerEvent('hospital:server:UseFirstAid')
end)

RegisterNetEvent('hospital:client:UseBandage', function()
    TriggerServerEvent('hospital:server:UseFirstAid')
end)

RegisterNetEvent('hospital:client:UseIfaks', function()
    TriggerServerEvent('hospital:server:UseIfaks')
end)

RegisterNetEvent('hospital:client:UsePainkillers', function()
    TriggerServerEvent('hospital:server:UsePainkillers')
end)
