-- Legacy qb-ambulancejob compat (client realm) -- the client-side half of
-- the checklist; server/compat/hospital.lua is the other half. Where a
-- legacy name has real state consequences, the handler bounces to the
-- matching hospital:server:* event (already implemented in server/compat/
-- hospital.lua) rather than re-implementing the same logic twice; purely
-- local/cosmetic names are handled directly here.

local lastKnownDoctorCount = 0

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
    TriggerServerEvent('hospital:server:RevivePlayer')
end)

RegisterNetEvent('hospital:client:RevivePlayer', function()
    TriggerServerEvent('hospital:server:RevivePlayer')
end)

RegisterNetEvent('hospital:client:SetPain', function(level)
    if tonumber(level) and tonumber(level) > 0 then
        QB.fx.screenEffect('DrugsMichaelAliensFightIn', 0, true)
    else
        QB.fx.stopScreenEffect({ name = 'DrugsMichaelAliensFightIn' })
    end
end)

RegisterNetEvent('hospital:client:KillPlayer', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('hospital:client:HealInjuries', function(_percent)
    TriggerServerEvent('hospital:server:TreatWounds')
end)

RegisterNetEvent('hospital:client:SendToBed', function(bedIndex)
    local hospital = Config.hospitals[1]
    local bed = hospital.beds[tonumber(bedIndex) or 1] or hospital.beds[1]
    if not bed then return end

    TaskStartScenarioAtCoords(PlayerPedId(), 'PROP_HUMAN_BUM_BIN', bed.x, bed.y, bed.z, bed.w, 0, true, false)
end)

RegisterNetEvent('hospital:client:LeaveBed', function()
    ClearPedTasks(PlayerPedId())
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
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    TriggerServerEvent('hospital:server:TreatWounds')
end)

RegisterNetEvent('hospital:client:CheckStatus', function()
    local ok, status = pcall(QB.callback.trigger, 'hospital:GetPlayerStatus')
    if not ok or type(status) ~= 'table' then return end

    local woundCount = 0
    for _ in pairs(status.woundData or {}) do woundCount = woundCount + 1 end

    QB.notify.send({
        title = 'Status',
        message = ('Dead: %s | Laststand: %s | Open wounds: %d'):format(tostring(status.isdead), tostring(status.inlaststand), woundCount),
        type = 'info',
    })
end)

RegisterNetEvent('hospital:client:TreatWounds', function()
    TriggerServerEvent('hospital:server:TreatWounds')
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

-- CanHelp has no single canonical real-world signature (see server/compat/
-- hospital.lua's own note on the same name) -- a client-side inventory
-- check would need a qbinventory client export this codebase doesn't
-- currently expose, so this is deliberately permissive rather than
-- guessing at item state it can't actually verify.
exports('CanHelp', function()
    return true
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
