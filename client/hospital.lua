-- Hospital (client realm) -- facility presentation only. The server chooses
-- and reserves beds; this file cannot select one or make care succeed early.

local activeCare
local leaveBinding

local function stopCare(token)
    if not activeCare or (token and activeCare.token ~= token) then return end
    if leaveBinding then leaveBinding.disable(true) end
    ClearPedTasks(PlayerPedId())
    activeCare = nil
end

-- Leaving the bed is a rebindable key mapping that is only enabled while a bed
-- is reserved, so nothing polls the control every frame for the whole stay.
do
    local key = Config.hospitalCare.leaveKey
    if key == nil then key = 'E' end
    if type(key) == 'string' and key ~= '' then
        leaveBinding = Kora.keybind.add({
            name = 'kora_ambulance_leave_bed',
            description = Kora.lang('ui.leave_bed_description'),
            defaultKey = key,
            disabled = true,
            onPressed = function()
                if not activeCare then return end
                local token = activeCare.token
                leaveBinding.disable(true)
                Kora.events.trigger('kora_ambulance:server:bedLeft', token)
            end,
        })
    end
end

local function startCare(care)
    if type(care) ~= 'table' or type(care.token) ~= 'string' or activeCare then return end
    activeCare = care

    local bed = care.bed
    local ped = PlayerPedId()
    SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
    SetEntityHeading(ped, bed.w or 0.0)
    TaskStartScenarioAtPosition(ped, 'PROP_HUMAN_BUM_BIN', bed.x, bed.y, bed.z, bed.w or 0.0, 0, true, false)
    Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = Kora.lang('ui.resting_bed'), type = 'info' })
    if leaveBinding then leaveBinding.disable(false) end

    local anim = Config.hospitalCare.bedAnim
    if type(anim) == 'table' and type(anim.dict) == 'string' and type(anim.clip) == 'string' then
        CreateThread(function()
            if activeCare ~= care then return end
            RequestAnimDict(anim.dict)
            local deadline = GetGameTimer() + 5000
            while activeCare == care and not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do
                Wait(10)
            end

            if activeCare == care then
                if HasAnimDictLoaded(anim.dict) then
                    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 8.0, -8.0, -1, anim.flag or 1, 0.0, false, false, false)
                else
                    Kora.logging.warn(
                        'hospital.bed_anim_timeout',
                        'Could not load the hospital bed animation',
                        { dict = anim.dict }
                    )
                end
            end
            RemoveAnimDict(anim.dict)
        end)
    end

    -- One sleep for the whole care duration instead of a per-frame tick.
    CreateThread(function()
        local token = care.token
        Wait(care.duration)
        if not activeCare or activeCare.token ~= token then return end
        if leaveBinding then leaveBinding.disable(true) end
        local completed, reason = Kora.callback.trigger('kora_ambulance:server:bedCareCompleted', token)
        if not completed then
            Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = reason or Kora.lang('ui.care_incomplete'), type = 'warning' })
        end
    end)
end

local function requestCheckIn(hospital)
    if not hospital.beds or #hospital.beds == 0 then
        Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = Kora.lang('ui.no_beds'), type = 'warning' })
        return
    end
    if activeCare then
        Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = Kora.lang('ui.bed_reserved'), type = 'warning' })
        return
    end
    local care, reason = Kora.callback.trigger('kora_ambulance:server:checkInRequested', hospital.name)
    if not care then
        Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = reason or Kora.lang('ui.checkin_unavailable'), type = 'error' })
        return
    end
    startCare(care)
end

RegisterNetEvent('kora_ambulance:client:checkInAccepted', function(care)
    startCare(care)
end)

RegisterNetEvent('kora_ambulance:client:bedReleased', function(reason)
    if not activeCare then return end
    stopCare(activeCare.token)
    if reason == 'completed' then
        local ped = PlayerPedId()
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = Kora.lang('ui.care_complete'), type = 'success' })
    elseif reason ~= 'left-bed' then
        Kora.bridge.sendNotify({ title = Kora.lang('title.hospital_checkin'), message = Kora.lang('ui.bed_released'), type = 'warning' })
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
local hospitalBlips = {} -- hospital name -> map blip, removed before re-registration so a kora_target restart never stacks a second one

local function registerHospital(hospital)
    if Config.Debug then
        Kora.logging.debug('hospital.registering_targets', 'Registering targets for hospital', { hospital = tostring(hospital.name), beds = #(hospital.beds or {}) })
    end

    zoneIds[hospital.name] = zoneIds[hospital.name] or {}
    HospitalMenu.register(zoneIds[hospital.name], HospitalMenu.build(hospital, hospitalHandlers), facilityKinds,
        function(definition) return exports.kora_target:addSphereZone(definition) end,
        function(id) exports.kora_target:removeZone(id) end)

    if hospital.blip then
        if hospitalBlips[hospital.name] then Kora.blips.remove(hospitalBlips[hospital.name]) end
        local blip = Kora.blips.create(hospital.coords, hospital.blip)
        hospitalBlips[hospital.name] = blip
        if blip and not hospital.blip.info then
            Kora.blips.setInfo(blip, {
                title = hospital.label,
                rows = { { kind = 'wrappedText', value = Kora.lang('ui.hospital_services') } },
            })
        end
    end
end

local function registerHospitalTargets()
    for _, hospital in ipairs(Config.hospitals) do
        if Config.hospitalMenu.isolateErrors then
            local ok, err = pcall(registerHospital, hospital)
            if not ok then
                Kora.logging.error('hospital.register_targets_failed', 'Could not register targets for hospital', { hospital = tostring(hospital.name), error = tostring(err) })
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
