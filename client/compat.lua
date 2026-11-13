-- Safe qb-ambulancejob compatibility presentation. Client events never
-- grant health, alter medical state or select a bed; meaningful actions are
-- requested through the validated server adapter.

if not Config.compat.enabled then return end

local lastKnownDoctorCount = 0
local painScreenHandle

-- Registered but inert. kora_dispatch renders every EMS call now, including the
-- ones raised from the legacy hospital:server:ambulanceAlert path -- it
-- registers that server event itself and turns it into a real call. Rendering
-- here as well would show the same incident twice, once as a proper dispatch
-- card and once as a stray toast with a blip that outlives it.
--
-- The registration is kept so a third-party resource firing this client event
-- directly still finds a listener rather than an error.
RegisterNetEvent('hospital:client:ambulanceAlert', function() end)

-- Admin /revive and the admin menu fire these after the player is already up,
-- so the CPR hint is opt-in (Config.compat.reviveNotice).
local function reviveNotice()
    if not Config.compat.reviveNotice then return end
    Kora.notify.send({ title = Kora.lang('title.ems'), message = Kora.lang('ui.cpr_required'), type = 'info' })
end

RegisterNetEvent('hospital:client:Revive', reviveNotice)
RegisterNetEvent('hospital:client:RevivePlayer', reviveNotice)

RegisterNetEvent('hospital:client:SetPain', function(level)
    if tonumber(level) and tonumber(level) > 0 then
        if not painScreenHandle then
            painScreenHandle = Kora.fx.screenEffect('DrugsMichaelAliensFightIn', 0, true)
        end
    elseif painScreenHandle then
        Kora.fx.stopScreenEffect(painScreenHandle)
        painScreenHandle = nil
    end
end)

-- Applies hospital:server:SetArmor (SetPedArmour is client-only). Reduce-only,
-- like the server adapter that forwards it.
RegisterNetEvent('kora_ambulance:client:setArmour', function(armour)
    armour = tonumber(armour)
    if not armour then return end
    local ped = PlayerPedId()
    if armour >= 0 and armour <= GetPedArmour(ped) then SetPedArmour(ped, math.floor(armour)) end
end)

RegisterNetEvent('hospital:client:KillPlayer', function()
    -- Intentionally inert: a locally-triggerable compatibility event cannot
    -- be an authority for changing a player's health.
end)

RegisterNetEvent('hospital:client:HealInjuries', function(_percent)
    Kora.notify.send({ title = Kora.lang('title.hospital'), message = Kora.lang('ui.use_treatment'), type = 'info' })
end)

RegisterNetEvent('hospital:client:SendToBed', function(_bedIndex)
    Kora.notify.send({ title = Kora.lang('title.hospital'), message = Kora.lang('ui.use_desk'), type = 'info' })
end)

RegisterNetEvent('hospital:client:leaveBed', function()
    TriggerServerEvent('hospital:server:LeaveBed')
end)

RegisterNetEvent('hospital:client:SetBed', function(bedIndex)
    Kora.notify.send({ title = Kora.lang('title.hospital'), message = Kora.lang('ui.assigned_bed', bedIndex), type = 'info' })
end)

RegisterNetEvent('hospital:client:SetBed2', function(bedIndex)
    Kora.notify.send({ title = Kora.lang('title.hospital'), message = Kora.lang('ui.assigned_bed', bedIndex), type = 'info' })
end)

RegisterNetEvent('hospital:client:RespawnAtHospital', function()
    TriggerServerEvent('hospital:server:RespawnAtHospital')
end)

RegisterNetEvent('hospital:client:SendBillEmail', function(amount)
    Kora.notify.send({ title = Kora.lang('title.hospital_bill'), message = Kora.lang('ui.billed', tonumber(amount) or 0), type = 'warning' })
end)

RegisterNetEvent('hospital:client:SetDoctorCount', function(count)
    lastKnownDoctorCount = tonumber(count) or 0
end)

RegisterNetEvent('hospital:client:adminHeal', function()
    Kora.notify.send({ title = Kora.lang('title.hospital'), message = Kora.lang('ui.admin_heal_disabled'), type = 'error' })
end)

RegisterNetEvent('hospital:client:CheckStatus', function()
    local status = Kora.callback.trigger('hospital:GetPlayerStatus')
    if type(status) ~= 'table' then return end

    local woundCount = 0
    for _ in pairs(status.woundData or {}) do woundCount = woundCount + 1 end

    Kora.notify.send({
        title = Kora.lang('title.status'),
        message = Kora.lang('ui.status_detail', tostring(status.isdead), tostring(status.inlaststand), woundCount),
        type = 'info',
    })
end)

RegisterNetEvent('hospital:client:TreatWounds', function()
    Kora.notify.send({ title = Kora.lang('title.ems'), message = Kora.lang('ui.target_patient'), type = 'info' })
end)

-- SetEscortingState/isEscorted map onto our own stretcher system rather than
-- a separate compat-only flag -- see client/stretcher.lua's header for why
-- dragging state has to live there (it owns the actual per-frame position
-- sync), and its Stretcher.isBeingDragged()/isDragging() getters exposed for
-- exactly this reason.
RegisterNetEvent('hospital:client:SetEscortingState', function(state)
    if not state then TriggerServerEvent('kora_ambulance:server:stretcherRelease') end
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
    Kora.notify.send({ title = Kora.lang('title.ems'), message = Kora.lang('ui.target_downed'), type = 'info' })
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

exports('PainKillerLoop', function() end)
