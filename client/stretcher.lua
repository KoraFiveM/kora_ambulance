-- Stretcher (client realm) -- presents server-owned emergency-carry and
-- physical-stretcher state. Every attachment offset comes from Config; no
-- position, model or relationship is sent to the server by this client.

Stretcher = Stretcher or {}

local carryDragging -- { targetSrc }
local carryDragged -- { draggerSrc }
local stretcherStates = {} -- networkId -> replicated server snapshot
local pushingNetworkId
local loadedNetworkId

-- Fireman's-carry shoulder position for the nm/firemans_carry clip, relative to
-- the carrier. Config.carry.patientOffset/patientRotation override these.
local CARRY_OFFSET = { x = 0.27, y = 0.15, z = 0.63 }
local CARRY_ROTATION = { x = 0.5, y = 0.5, z = 180.0 }

---@param value any
---@param fallback table
---@return table
local function vec3Config(value, fallback)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then return fallback end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return fallback end
    return { x = x, y = y, z = z }
end
local PUSH_ANIM = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 }
local PATIENT_ANIM = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 }

local function localServerId()
    return GetPlayerServerId(PlayerId())
end

---@return boolean
function Stretcher.isBeingDragged()
    return carryDragged ~= nil or loadedNetworkId ~= nil
end

---@return boolean
function Stretcher.isDragging()
    return carryDragging ~= nil or pushingNetworkId ~= nil
end

---@return boolean
function Stretcher.isPatientLoaded()
    return loadedNetworkId ~= nil
end

local function isOnDutyEMS()
    local job = exports.kora_core:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param entity integer
---@return integer|nil
local function entityNetworkId(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local id = NetworkGetNetworkIdFromEntity(entity)
    return id and id ~= 0 and id or nil
end

---@param entity integer
---@return integer|nil
local function targetServerId(entity)
    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end
    return GetPlayerServerId(playerIndex)
end

---@param entity integer
---@return boolean
local function isDowned(entity)
    local serverId = targetServerId(entity)
    if not serverId then return false end
    local state = Player(serverId).state.emsDown
    return state == 'laststand' or state == 'dead'
end

---@param networkId integer
---@return integer|nil
local function resolveEntity(networkId)
    Kora.loops.controlled(function()
        return NetworkDoesEntityExistWithNetworkId(networkId)
    end, 50, 2500, 50)

    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    return entity
end

---@param vehicle integer
---@return table|nil
local function vehicleStretcherDef(vehicle)
    local model = GetEntityModel(vehicle)
    for _, vehicleDef in ipairs(Config.dutyVehicles) do
        if vehicleDef.stretcher and joaat(vehicleDef.model) == model then return vehicleDef.stretcher end
    end
    return nil
end

local function stopPushingPresentation()
    if not pushingNetworkId then return end
    pushingNetworkId = nil
    Kora.anim.stop(PlayerPedId())
end

local function stopPatientPresentation()
    if not loadedNetworkId then return end
    loadedNetworkId = nil
    local ped = PlayerPedId()
    DetachEntity(ped, true, true)
    SetPedCanRagdoll(ped, true)
    Kora.anim.stop(ped)
end

---@param state table
local function applyState(state)
    if type(state) ~= 'table' or type(state.networkId) ~= 'number' then return end
    if state.removed then
        stretcherStates[state.networkId] = nil
        if pushingNetworkId == state.networkId then stopPushingPresentation() end
        if loadedNetworkId == state.networkId then stopPatientPresentation() end
        return
    end

    stretcherStates[state.networkId] = state
    CreateThread(function()
        local stretcher = resolveEntity(state.networkId)
        if not stretcher then return end
        Kora.entities.requestControl(stretcher, 500)

        if state.mode == 'vehicle' then
            local vehicle = resolveEntity(state.vehicleNetworkId)
            local attachment = vehicle and vehicleStretcherDef(vehicle)
            if vehicle and attachment then
                DetachEntity(stretcher, true, true)
                AttachEntityToEntity(stretcher, vehicle, 0,
                    attachment.offset.x, attachment.offset.y, attachment.offset.z,
                    attachment.rotation.x, attachment.rotation.y, attachment.rotation.z,
                    false, false, false, false, 2, true)
            end
        elseif state.mode == 'pushed' and state.operator then
            local player = GetPlayerFromServerId(state.operator)
            local operatorPed = player ~= -1 and GetPlayerPed(player) or 0
            if operatorPed ~= 0 and state.operator == localServerId() then
                DetachEntity(stretcher, true, true)
                AttachEntityToEntity(stretcher, operatorPed, GetPedBoneIndex(operatorPed, 28422),
                    Config.transport.pushOffset.x, Config.transport.pushOffset.y, Config.transport.pushOffset.z,
                    Config.transport.pushRotation.x, Config.transport.pushRotation.y, Config.transport.pushRotation.z,
                    false, false, false, false, 2, true)

                if pushingNetworkId ~= state.networkId then
                    pushingNetworkId = state.networkId
                    Kora.anim.play(operatorPed, PUSH_ANIM.dict, PUSH_ANIM.clip, { flag = PUSH_ANIM.flag })
                    CreateThread(function()
                        while pushingNetworkId == state.networkId do
                            Kora.events.trigger('kora_ambulance:server:stretcherHeartbeatReceived', state.networkId)
                            Wait(Config.transport.heartbeatInterval)
                        end
                    end)
                end
            end
        else
            DetachEntity(stretcher, true, true)
            FreezeEntityPosition(stretcher, true)
        end

        if state.operator ~= localServerId() and pushingNetworkId == state.networkId then
            stopPushingPresentation()
        end

        if state.patient == localServerId() then
            local ped = PlayerPedId()
            loadedNetworkId = state.networkId
            SetPedCanRagdoll(ped, false)
            Kora.anim.play(ped, PATIENT_ANIM.dict, PATIENT_ANIM.clip, { flag = PATIENT_ANIM.flag })
            AttachEntityToEntity(ped, stretcher, 0,
                Config.transport.patientOffset.x, Config.transport.patientOffset.y, Config.transport.patientOffset.z,
                Config.transport.patientRotation.x, Config.transport.patientRotation.y, Config.transport.patientRotation.z,
                false, false, false, false, 2, true)
        elseif loadedNetworkId == state.networkId then
            stopPatientPresentation()
        end
    end)
end

RegisterNetEvent('kora_ambulance:client:stretcherStateChanged', applyState)
RegisterNetEvent('kora_ambulance:client:stretcherPatientLoaded', applyState)
RegisterNetEvent('kora_ambulance:client:stretcherPatientReleased', function()
    stopPatientPresentation()
end)

if AddStateBagChangeHandler then
    AddStateBagChangeHandler('kora_ambulanceStretcher', nil, function(bagName, _, value)
        if type(value) ~= 'table' then return end
        local entity = GetEntityFromStateBagName(bagName)
        if entity == 0 then return end
        local id = entityNetworkId(entity)
        if id then
            value.networkId = id
            applyState(value)
        end
    end)
end

local function startCarryDragger(targetSrc)
    carryDragging = { targetSrc = targetSrc }
    local anim = Config.carry.dragger
    Kora.anim.play(PlayerPedId(), anim.dict, anim.clip, { flag = anim.flag })

    CreateThread(function()
        while carryDragging and carryDragging.targetSrc == targetSrc do
            Kora.events.trigger('kora_ambulance:server:stretcherHeartbeat')
            Wait(2000)
        end
    end)

    -- A way to put the patient down without ALT-targeting a ped that is now
    -- on the medic's shoulder. The server's release handler already only
    -- releases the sender's own carry.
    if Config.carry.stopPrompt == false then return end
    local control = tonumber(Config.carry.stopControl) or 38
    CreateThread(function()
        local promptId = Kora.textui.show('Stop Carrying', { key = 'E', icon = 'hand' })
        while carryDragging and carryDragging.targetSrc == targetSrc do
            -- kora_target confirms its menu with the same key: picking another
            -- option (CPR, assess) while carrying must not also drop the patient.
            local targeting = false
            local ok, state = pcall(function() return exports.kora_target:getState() end)
            if ok and type(state) == 'table' then targeting = state.active == true end
            if not targeting and IsControlJustPressed(0, control) then
                Kora.events.trigger('kora_ambulance:server:stretcherRelease')
                Wait(500)
            end
            Wait(0)
        end
        Kora.textui.hide(promptId)
    end)
end

local function stopCarryDragging()
    if not carryDragging then return end
    carryDragging = nil
    Kora.anim.stop(PlayerPedId())
end

-- The patient's client owns its ped, so attaching it to the carrier replicates
-- to every player. Teleporting it each frame only moved it locally. Re-checked
-- every 250ms: a resurrect (new ped) or a ragdoll drops the attachment/anim.
local function startCarryPatient(draggerSrc)
    carryDragged = { draggerSrc = draggerSrc }
    local anim = Config.carry.patient
    local offset = vec3Config(Config.carry.patientOffset, CARRY_OFFSET)
    local rotation = vec3Config(Config.carry.patientRotation, CARRY_ROTATION)

    CreateThread(function()
        while carryDragged and carryDragged.draggerSrc == draggerSrc do
            local draggerPlayer = GetPlayerFromServerId(draggerSrc)
            local draggerPed = draggerPlayer ~= -1 and GetPlayerPed(draggerPlayer) or 0
            if draggerPed ~= 0 and DoesEntityExist(draggerPed) then
                local ped = PlayerPedId()
                SetPedCanRagdoll(ped, false)
                if IsPedRagdoll(ped) then ClearPedTasksImmediately(ped) end
                -- Clip first, then attach (the usual fireman's-carry order): the
                -- offset is authored for the firemans_carry pose, not the downed one.
                if not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
                    -- The downed writhe/dead clip is a primary task that outranks the flag-33
                    -- carry clip, leaving the body in the downed pose instead of over the shoulder.
                    ClearPedTasks(ped)
                    Kora.anim.play(ped, anim.dict, anim.clip, { flag = anim.flag })
                    -- play yields while the dict streams; don't leave the clip on after a release.
                    if not carryDragged or carryDragged.draggerSrc ~= draggerSrc then
                        Kora.anim.stop(ped)
                        return
                    end
                    -- A resurrect while streaming hands back a new ped.
                    ped = PlayerPedId()
                end
                if not IsEntityAttachedToEntity(ped, draggerPed) then
                    DetachEntity(ped, true, false)
                    AttachEntityToEntity(ped, draggerPed, 0,
                        offset.x, offset.y, offset.z,
                        rotation.x, rotation.y, rotation.z,
                        false, false, false, false, 2, false)
                end
            end
            Wait(250)
        end
    end)
end

local function stopCarryPatient()
    if not carryDragged then return end
    carryDragged = nil
    local ped = PlayerPedId()
    DetachEntity(ped, true, false)
    SetPedCanRagdoll(ped, true)
    Kora.anim.stop(ped)
end

RegisterNetEvent('kora_ambulance:client:stretcherBegin', function(otherSrc, iAmDragger)
    if iAmDragger then
        startCarryDragger(otherSrc)
        Kora.notify.send({ title = 'EMS', message = 'Emergency carry started.', type = 'info' })
    else
        startCarryPatient(otherSrc)
        Kora.notify.send({ title = 'EMS', message = 'You are being carried.', type = 'info' })
    end
end)

RegisterNetEvent('kora_ambulance:client:stretcherEnd', function()
    stopCarryDragging()
    stopCarryPatient()
end)

---@param coords vector3|table
---@param vehicleNetworkId? integer
---@return table|nil
local function nearestStretcher(coords, vehicleNetworkId)
    local closest, closestDistance
    for id, state in pairs(stretcherStates) do
        if not vehicleNetworkId or state.vehicleNetworkId == vehicleNetworkId then
            local entity = NetworkGetEntityFromNetworkId(id)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                local distance = #(GetEntityCoords(entity) - coords)
                if distance <= Config.transport.interactionRange and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = state, distance
                end
            end
        end
    end
    return closest
end

local function deployStretcher(vehicle)
    local vehicleNetworkId = entityNetworkId(vehicle)
    if not vehicleNetworkId then return end
    local stretcherNetworkId, reason = Kora.callback.trigger(
        'kora_ambulance:server:stretcherDeployRequested', vehicleNetworkId)
    Kora.notify.send({
        title = 'Patient Transport',
        message = stretcherNetworkId and 'Stretcher deployed.' or (reason or 'Unable to deploy stretcher.'),
        type = stretcherNetworkId and 'success' or 'error',
    })
end

local function registerTargets()
    exports.kora_target:addGlobalType('player', {
        {
            label = 'Emergency Carry',
            icon = 'move',
            canInteract = function(entity)
                return isOnDutyEMS() and isDowned(entity) and not Stretcher.isDragging()
                    and not Stretcher.isBeingDragged()
            end,
            onSelect = function(entity)
                local targetSrc = targetServerId(entity)
                if targetSrc then Kora.events.trigger('kora_ambulance:server:stretcherPickup', targetSrc) end
            end,
        },
        {
            label = 'Release Carried Patient',
            icon = 'x',
            canInteract = function(entity)
                return carryDragging ~= nil and targetServerId(entity) == carryDragging.targetSrc
            end,
            onSelect = function() Kora.events.trigger('kora_ambulance:server:stretcherRelease') end,
        },
        {
            label = 'Load onto Stretcher',
            icon = 'bed',
            canInteract = function(entity)
                if not isOnDutyEMS() or not isDowned(entity) or Stretcher.isDragging() then return false end
                local state = nearestStretcher(GetEntityCoords(entity))
                return state ~= nil and state.mode ~= 'vehicle' and state.patient == nil
            end,
            onSelect = function(entity)
                local state = nearestStretcher(GetEntityCoords(entity))
                local targetSrc = targetServerId(entity)
                if state and targetSrc then
                    Kora.events.trigger('kora_ambulance:server:patientLoadedOnStretcher', state.networkId, targetSrc)
                end
            end,
        },
    }, Config.transport.interactionRange)

    exports.kora_target:addModel(Config.transport.model, {
        {
            label = 'Push Stretcher',
            icon = 'hand',
            canInteract = function(entity)
                local state = stretcherStates[entityNetworkId(entity)]
                return isOnDutyEMS() and state ~= nil and state.mode == 'world' and not Stretcher.isDragging()
            end,
            onSelect = function(entity)
                Kora.events.trigger('kora_ambulance:server:stretcherPushRequested', entityNetworkId(entity))
            end,
        },
        {
            label = 'Stop Pushing',
            icon = 'hand',
            canInteract = function(entity)
                local state = stretcherStates[entityNetworkId(entity)]
                return state ~= nil and state.mode == 'pushed' and state.operator == localServerId()
            end,
            onSelect = function(entity)
                Kora.events.trigger('kora_ambulance:server:stretcherReleased', entityNetworkId(entity))
            end,
        },
        {
            label = 'Unload Patient',
            icon = 'person-walking',
            canInteract = function(entity)
                local state = stretcherStates[entityNetworkId(entity)]
                return isOnDutyEMS() and state ~= nil and state.mode ~= 'vehicle' and state.patient ~= nil
            end,
            onSelect = function(entity)
                Kora.events.trigger('kora_ambulance:server:patientUnloadedFromStretcher', entityNetworkId(entity))
            end,
        },
    }, Config.transport.interactionRange)

    exports.kora_target:addGlobalType('vehicle', {
        {
            label = 'Deploy Stretcher',
            icon = 'bed',
            canInteract = function(entity)
                if not isOnDutyEMS() or not vehicleStretcherDef(entity) then return false end
                return nearestStretcher(GetEntityCoords(entity), entityNetworkId(entity)) == nil
            end,
            onSelect = deployStretcher,
        },
        {
            label = 'Stow Stretcher',
            icon = 'truck-medical',
            canInteract = function(entity)
                if not isOnDutyEMS() or not vehicleStretcherDef(entity) then return false end
                local state = nearestStretcher(GetEntityCoords(entity), entityNetworkId(entity))
                return state ~= nil and state.mode ~= 'vehicle'
                    and (state.operator == nil or state.operator == localServerId())
            end,
            onSelect = function(entity)
                local vehicleNetworkId = entityNetworkId(entity)
                local state = nearestStretcher(GetEntityCoords(entity), vehicleNetworkId)
                if state then
                    Kora.events.trigger('kora_ambulance:server:stretcherStowed', state.networkId, vehicleNetworkId)
                end
            end,
        },
        {
            label = 'Unstow Stretcher',
            icon = 'truck-medical',
            canInteract = function(entity)
                local id = entityNetworkId(entity)
                for _, state in pairs(stretcherStates) do
                    if state.vehicleNetworkId == id and state.mode == 'vehicle' then return isOnDutyEMS() end
                end
                return false
            end,
            onSelect = function(entity)
                Kora.events.trigger('kora_ambulance:server:stretcherUnstowed', entityNetworkId(entity))
            end,
        },
    }, Config.transport.interactionRange)
end

registerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTargets() end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    stopCarryDragging()
    stopCarryPatient()
    stopPushingPresentation()
    stopPatientPresentation()
end)
