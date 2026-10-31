-- Stretcher (server realm) -- owns both the lightweight emergency-carry
-- relationship and physical stretchers deployed from tracked duty vehicles.
-- Clients choose an entity/target only; models, offsets and every resulting
-- relationship are resolved and validated here.

Stretcher = Stretcher or {}

local QBCore = exports.kora_core

local draggerOf = {} -- patientSrc -> medicSrc (emergency carry)
local targetOf = {} -- medicSrc -> patientSrc (emergency carry)
local carryHeartbeatAt = {}

local stretchers = {} -- stretcherNetworkId -> record
local stretcherByVehicle = {} -- vehicleNetworkId -> stretcherNetworkId
local stretcherByOperator = {} -- medicSrc -> stretcherNetworkId
local stretcherByPatient = {} -- patientSrc -> stretcherNetworkId

---@param value any
---@return integer|nil
local function networkId(value)
    value = tonumber(value)
    if not value or value < 1 or value % 1 ~= 0 then return nil end
    return value
end

---@param src integer
---@return boolean
local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param src integer
---@param entity integer
---@param range number
---@return boolean
local function isNearEntity(src, entity, range)
    if not QBCore:getPlayerData(src) or not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= range
end

---@param networkIdValue integer
---@param expectedType integer
---@return integer|nil
local function resolveNetworkEntity(networkIdValue, expectedType)
    local entity = NetworkGetEntityFromNetworkId(networkIdValue)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityType(entity) ~= expectedType then return nil end
    return entity
end

---@param vehicleNetworkId integer
---@return table|nil dutyRecord
---@return table|nil vehicleDef
---@return integer|nil vehicle
local function resolveDutyVehicle(vehicleNetworkId)
    local dutyRecord = Duty.vehicleRecord(vehicleNetworkId)
    if not dutyRecord then return nil, nil, nil end

    local vehicleDef = Config.dutyVehicles[dutyRecord.vehicleIndex]
    if not vehicleDef or not vehicleDef.stretcher then return nil, nil, nil end

    local vehicle = resolveNetworkEntity(vehicleNetworkId, 2)
    if not vehicle or GetEntityModel(vehicle) ~= dutyRecord.model
        or dutyRecord.model ~= joaat(vehicleDef.model) then
        return nil, nil, nil
    end

    return dutyRecord, vehicleDef, vehicle
end

---@param record table
---@return table
local function snapshot(record)
    return {
        networkId = record.networkId,
        vehicleNetworkId = record.vehicleNetworkId,
        mode = record.mode,
        operator = record.operator,
        patient = record.patient,
    }
end

---@param record table
local function publish(record)
    local state = snapshot(record)
    Entity(record.entity).state:set('qbambulanceStretcher', state, true)
    TriggerClientEvent('qbambulance:client:stretcherStateChanged', -1, state)
end

---@param src integer
---@param reason string
local function notifyFailure(src, reason)
    Kora.notify.send(src, { title = 'Patient Transport', message = reason, type = 'error' })
end

---@param record table
local function clearOperator(record)
    if not record.operator then return end
    if stretcherByOperator[record.operator] == record.networkId then stretcherByOperator[record.operator] = nil end
    record.operator = nil
    record.operatorHeartbeatAt = nil
end

---@param record table
---@param reason? string
local function clearPatient(record, reason)
    local patient = record.patient
    if not patient then return end
    if stretcherByPatient[patient] == record.networkId then stretcherByPatient[patient] = nil end
    record.patient = nil
    TriggerClientEvent('qbambulance:client:stretcherPatientReleased', patient, reason or 'released')
end

---@param record table
---@param reason string
local function removePhysical(record, reason)
    local removedSnapshot = snapshot(record)
    removedSnapshot.removed = true
    removedSnapshot.reason = reason

    clearOperator(record)
    clearPatient(record, reason)
    stretchers[record.networkId] = nil
    if stretcherByVehicle[record.vehicleNetworkId] == record.networkId then
        stretcherByVehicle[record.vehicleNetworkId] = nil
    end

    TriggerClientEvent('qbambulance:client:stretcherStateChanged', -1, removedSnapshot)
    if record.entity and DoesEntityExist(record.entity) then DeleteEntity(record.entity) end
end

---@param record table
---@return integer|nil
local function actionEntity(record)
    if record.mode == 'vehicle' then return resolveNetworkEntity(record.vehicleNetworkId, 2) end
    return record.entity
end

---@param src integer
---@param stretcherNetworkId any
---@return table|nil record
---@return string|nil reason
local function validateStretcher(src, stretcherNetworkId)
    stretcherNetworkId = networkId(stretcherNetworkId)
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if not record then return nil, 'Unknown stretcher.' end
    if not isOnDutyEMS(src) then return nil, 'You must be on duty.' end

    local entity = resolveNetworkEntity(record.networkId, 3)
    if not entity or entity ~= record.entity or GetEntityModel(entity) ~= joaat(Config.transport.model) then
        removePhysical(record, 'stretcher entity lost')
        return nil, 'That stretcher is no longer available.'
    end

    local anchor = actionEntity(record)
    if not anchor or not isNearEntity(src, anchor, Config.transport.interactionRange) then
        return nil, 'Move closer to the stretcher.'
    end
    return record, nil
end

local VALID_TRANSITIONS = {
    world = { push = 'pushed', stow = 'vehicle' },
    pushed = { release = 'world', stow = 'vehicle' },
    vehicle = { unstow = 'world' },
}

---@param mode string
---@param action string
---@return string|nil nextMode
function Stretcher.transition(mode, action)
    local row = VALID_TRANSITIONS[mode]
    return row and row[action] or nil
end

---@param targetState "alive"|"laststand"|"dead"
---@param targetAlreadyMoved boolean
---@param medicAlreadyMoving boolean
---@return boolean eligible
---@return string|nil reason
function Stretcher.canPickup(targetState, targetAlreadyMoved, medicAlreadyMoving)
    if targetState == 'alive' then return false, 'patient is not down' end
    if targetAlreadyMoved then return false, 'someone is already moving this patient' end
    if medicAlreadyMoving then return false, 'you are already moving a patient' end
    return true, nil
end

---@param src integer
---@return integer|nil
function Stretcher.draggingTarget(src)
    return targetOf[src]
end

---@param targetSrc integer
---@return integer|nil
function Stretcher.draggedBy(targetSrc)
    return draggerOf[targetSrc]
end

---@param targetSrc integer
---@return integer|nil
function Stretcher.patientStretcher(targetSrc)
    return stretcherByPatient[targetSrc]
end

---@param vehicleNetworkId integer
---@return integer|nil
function Stretcher.vehicleStretcher(vehicleNetworkId)
    return stretcherByVehicle[vehicleNetworkId]
end

---@param stretcherNetworkId integer
---@return table|nil
function Stretcher.state(stretcherNetworkId)
    local record = stretchers[stretcherNetworkId]
    return record and snapshot(record) or nil
end

local function releaseCarry(medicSrc, silent)
    local targetSrc = targetOf[medicSrc]
    if not targetSrc then return end

    targetOf[medicSrc] = nil
    draggerOf[targetSrc] = nil
    carryHeartbeatAt[medicSrc] = nil

    if not silent then
        TriggerClientEvent('qbambulance:client:stretcherEnd', medicSrc)
        TriggerClientEvent('qbambulance:client:stretcherEnd', targetSrc)
    end
end

---@param src integer
---@param vehicleNetworkId any
---@return integer|nil stretcherNetworkId
---@return string|nil reason
function Stretcher.deploy(src, vehicleNetworkId)
    vehicleNetworkId = networkId(vehicleNetworkId)
    if not vehicleNetworkId then return nil, 'Invalid duty vehicle.' end
    if not isOnDutyEMS(src) then return nil, 'You must be on duty.' end
    if stretcherByVehicle[vehicleNetworkId] then return nil, 'This vehicle already has a stretcher deployed.' end

    local _, vehicleDef, vehicle = resolveDutyVehicle(vehicleNetworkId)
    if not vehicle then return nil, 'This is not a stretcher-equipped duty vehicle.' end
    if not isNearEntity(src, vehicle, Config.transport.interactionRange) then return nil, 'Move closer to the duty vehicle.' end

    local offset = vehicleDef.stretcher.offset
    local origin, rotation = GetEntityCoords(vehicle), GetEntityRotation(vehicle)
    -- Server rotations use ZXY order; the offset native is client-only.
    local sx, cx = math.sin(math.rad(rotation.x)), math.cos(math.rad(rotation.x))
    local sy, cy = math.sin(math.rad(rotation.y)), math.cos(math.rad(rotation.y))
    local sz, cz = math.sin(math.rad(rotation.z)), math.cos(math.rad(rotation.z))
    local coords = vector3(
        origin.x + offset.x * (cz * cy - sz * sx * sy) - offset.y * sz * cx + offset.z * (cz * sy + sz * sx * cy),
        origin.y + offset.x * (sz * cy + cz * sx * sy) + offset.y * cz * cx + offset.z * (sz * sy - cz * sx * cy),
        origin.z - offset.x * cx * sy + offset.y * sx + offset.z * cx * cy
    )
    local entity = CreateObjectNoOffset(joaat(Config.transport.model), coords.x, coords.y, coords.z, true, true, false)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil, 'Could not deploy the stretcher.' end

    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    if GetEntityHeading and SetEntityHeading then SetEntityHeading(entity, GetEntityHeading(vehicle)) end
    FreezeEntityPosition(entity, true)

    local stretcherNetworkId = NetworkGetNetworkIdFromEntity(entity)
    if not stretcherNetworkId or stretcherNetworkId == 0 then
        DeleteEntity(entity)
        return nil, 'Could not network the stretcher.'
    end

    local record = {
        entity = entity,
        networkId = stretcherNetworkId,
        vehicleNetworkId = vehicleNetworkId,
        mode = 'world',
    }
    stretchers[stretcherNetworkId] = record
    stretcherByVehicle[vehicleNetworkId] = stretcherNetworkId
    publish(record)
    return stretcherNetworkId, nil
end

---@param src integer
---@param stretcherNetworkId any
---@return boolean
---@return string|nil
function Stretcher.beginPush(src, stretcherNetworkId)
    if stretcherByOperator[src] or targetOf[src] then return false, 'You are already moving a patient.' end
    local record, reason = validateStretcher(src, stretcherNetworkId)
    if not record then return false, reason end
    if record.operator then return false, 'Another medic is already moving this stretcher.' end

    local nextMode = Stretcher.transition(record.mode, 'push')
    if not nextMode then return false, 'Unstow the stretcher before moving it.' end

    FreezeEntityPosition(record.entity, false)
    record.mode = nextMode
    record.operator = src
    record.operatorHeartbeatAt = GetGameTimer()
    stretcherByOperator[src] = record.networkId
    publish(record)
    return true, nil
end

---@param src integer
---@param stretcherNetworkId any
---@return boolean
---@return string|nil
function Stretcher.stopPush(src, stretcherNetworkId)
    stretcherNetworkId = networkId(stretcherNetworkId)
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if not record or record.operator ~= src then return false, 'You are not moving that stretcher.' end

    local nextMode = Stretcher.transition(record.mode, 'release')
    if not nextMode then return false, 'The stretcher cannot be released right now.' end

    clearOperator(record)
    record.mode = nextMode
    FreezeEntityPosition(record.entity, true)
    publish(record)
    return true, nil
end

---@param src integer
---@param stretcherNetworkId any
---@param targetSrc any
---@return boolean
---@return string|nil
function Stretcher.loadPatient(src, stretcherNetworkId, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc % 1 ~= 0 or targetSrc == src then return false, 'Invalid patient.' end

    local record, reason = validateStretcher(src, stretcherNetworkId)
    if not record then return false, reason end
    if record.mode == 'vehicle' then return false, 'Unstow the stretcher before loading a patient.' end
    if record.operator and record.operator ~= src then return false, 'Another medic is moving that stretcher.' end
    if record.patient then return false, 'The stretcher is already occupied.' end
    if not QBCore:getPlayerData(targetSrc) then return false, 'Patient is unavailable.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return false, 'Patient is unavailable.' end

    local targetPed = GetPlayerPed(targetSrc)
    if not targetPed or targetPed == 0
        or not isNearEntity(src, targetPed, Config.transport.interactionRange)
        or #(GetEntityCoords(targetPed) - GetEntityCoords(actionEntity(record))) > Config.transport.interactionRange then
        return false, 'Move the patient closer to the stretcher.'
    end

    local eligible, eligibilityReason = Stretcher.canPickup(
        Death.getState(targetSrc),
        draggerOf[targetSrc] ~= nil or stretcherByPatient[targetSrc] ~= nil,
        targetOf[src] ~= nil
    )
    if not eligible then return false, eligibilityReason end

    record.patient = targetSrc
    stretcherByPatient[targetSrc] = record.networkId
    publish(record)
    TriggerClientEvent('qbambulance:client:stretcherPatientLoaded', targetSrc, snapshot(record))
    return true, nil
end

---@param src integer
---@param stretcherNetworkId any
---@return boolean
---@return string|nil
function Stretcher.unloadPatient(src, stretcherNetworkId)
    local record, reason = validateStretcher(src, stretcherNetworkId)
    if not record then return false, reason end
    if record.mode == 'vehicle' then return false, 'Unstow the stretcher before unloading the patient.' end
    if record.operator and record.operator ~= src then return false, 'Another medic is moving that stretcher.' end
    if not record.patient then return false, 'The stretcher is empty.' end

    clearPatient(record, 'unloaded')
    publish(record)
    return true, nil
end

---@param src integer
---@param stretcherNetworkId any
---@param vehicleNetworkId any
---@return boolean
---@return string|nil
function Stretcher.stow(src, stretcherNetworkId, vehicleNetworkId)
    vehicleNetworkId = networkId(vehicleNetworkId)
    local record, reason = validateStretcher(src, stretcherNetworkId)
    if not record then return false, reason end
    if record.vehicleNetworkId ~= vehicleNetworkId then return false, 'This stretcher belongs to another duty vehicle.' end
    if record.operator and record.operator ~= src then return false, 'Another medic is moving that stretcher.' end

    local _, _, vehicle = resolveDutyVehicle(vehicleNetworkId)
    if not vehicle then return false, 'The duty vehicle is no longer available.' end
    if not isNearEntity(src, vehicle, Config.transport.interactionRange) then return false, 'Move closer to the duty vehicle.' end

    local nextMode = Stretcher.transition(record.mode, 'stow')
    if not nextMode then return false, 'The stretcher is already stowed.' end

    clearOperator(record)
    record.mode = nextMode
    FreezeEntityPosition(record.entity, false)
    publish(record)
    return true, nil
end

---@param src integer
---@param vehicleNetworkId any
---@return boolean
---@return string|nil
function Stretcher.unstow(src, vehicleNetworkId)
    vehicleNetworkId = networkId(vehicleNetworkId)
    if not vehicleNetworkId then return false, 'Invalid duty vehicle.' end
    if not isOnDutyEMS(src) then return false, 'You must be on duty.' end

    local stretcherNetworkId = stretcherByVehicle[vehicleNetworkId]
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if not record then return false, 'This vehicle has no deployed stretcher.' end

    local _, _, vehicle = resolveDutyVehicle(vehicleNetworkId)
    if not vehicle or not isNearEntity(src, vehicle, Config.transport.interactionRange) then
        return false, 'Move closer to the duty vehicle.'
    end

    local nextMode = Stretcher.transition(record.mode, 'unstow')
    if not nextMode then return false, 'The stretcher is already outside the vehicle.' end

    record.mode = nextMode
    FreezeEntityPosition(record.entity, true)
    publish(record)
    return true, nil
end

---@param vehicleNetworkId integer
---@param reason? string
function Stretcher.removeForVehicle(vehicleNetworkId, reason)
    local stretcherNetworkId = stretcherByVehicle[vehicleNetworkId]
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if record then removePhysical(record, reason or 'vehicle removed') end
end

Kora.callback.register('qbambulance:server:stretcherDeployRequested', function(src, vehicleNetworkId)
    return Stretcher.deploy(src, vehicleNetworkId)
end, { rateLimit = { max = 3, window = 10000 } })

local function registerAction(name, action)
    Kora.events.register(name, function(src, ...)
        local ok, reason = action(src, ...)
        if not ok and reason then notifyFailure(src, reason) end
    end)
end

registerAction('qbambulance:server:stretcherPushRequested', Stretcher.beginPush)
registerAction('qbambulance:server:stretcherReleased', Stretcher.stopPush)
registerAction('qbambulance:server:patientLoadedOnStretcher', Stretcher.loadPatient)
registerAction('qbambulance:server:patientUnloadedFromStretcher', Stretcher.unloadPatient)
registerAction('qbambulance:server:stretcherStowed', Stretcher.stow)
registerAction('qbambulance:server:stretcherUnstowed', Stretcher.unstow)

Kora.events.register('qbambulance:server:stretcherHeartbeatReceived', function(src, stretcherNetworkId)
    stretcherNetworkId = networkId(stretcherNetworkId)
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if not record or record.operator ~= src or record.mode ~= 'pushed' then return end
    if not isOnDutyEMS(src) or not isNearEntity(src, record.entity, Config.transport.interactionRange * 2.0) then
        Stretcher.stopPush(src, stretcherNetworkId)
        return
    end
    record.operatorHeartbeatAt = GetGameTimer()
end)

-- Emergency carry remains available when a physical stretcher is impractical.
Kora.events.register('qbambulance:server:stretcherPickup', function(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc % 1 ~= 0 or targetSrc == src then return end
    if not isOnDutyEMS(src) or not QBCore:getPlayerData(targetSrc) then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return end

    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not ped or ped == 0 or not targetPed or targetPed == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.death.reviveRange then return end

    local eligible, reason = Stretcher.canPickup(
        Death.getState(targetSrc),
        draggerOf[targetSrc] ~= nil or stretcherByPatient[targetSrc] ~= nil,
        targetOf[src] ~= nil or stretcherByOperator[src] ~= nil
    )
    if not eligible then
        notifyFailure(src, reason)
        return
    end

    draggerOf[targetSrc] = src
    targetOf[src] = targetSrc
    carryHeartbeatAt[src] = GetGameTimer()
    TriggerClientEvent('qbambulance:client:stretcherBegin', src, targetSrc, true)
    TriggerClientEvent('qbambulance:client:stretcherBegin', targetSrc, src, false)
end)

Kora.events.register('qbambulance:server:stretcherRelease', function(src)
    releaseCarry(src, false)
end)

Kora.events.register('qbambulance:server:stretcherHeartbeat', function(src)
    local targetSrc = targetOf[src]
    if not targetSrc then return end
    local now = GetGameTimer()
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    local invalid = not isOnDutyEMS(src)
        or not QBCore:getPlayerData(targetSrc)
        or GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc)
        or not ped or ped == 0 or not targetPed or targetPed == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.death.reviveRange * 2.0
    if invalid then
        releaseCarry(src, false)
        return
    end

    local previous = carryHeartbeatAt[src]
    if previous and now - previous < 500 then return end
    carryHeartbeatAt[src] = now
end)

local function releasePatient(src, reason)
    local medicSrc = draggerOf[src]
    if medicSrc then releaseCarry(medicSrc, false) end

    local stretcherNetworkId = stretcherByPatient[src]
    local record = stretcherNetworkId and stretchers[stretcherNetworkId]
    if record then
        clearPatient(record, reason)
        publish(record)
    end
end

AddEventHandler('qbambulance:server:onPlayerRevived', function(src)
    releasePatient(src, 'patient revived')
end)

AddEventHandler('qbambulance:server:onPlayerRespawned', function(src)
    releasePatient(src, 'patient respawned')
end)

---@param now integer GetGameTimer value
function Stretcher.sweep(now)
    for medicSrc, patientSrc in pairs(targetOf) do
        local medicPed = GetPlayerPed(medicSrc)
        local patientPed = GetPlayerPed(patientSrc)
        local invalid = not isOnDutyEMS(medicSrc)
            or not QBCore:getPlayerData(patientSrc)
            or GetPlayerRoutingBucket(medicSrc) ~= GetPlayerRoutingBucket(patientSrc)
            or not medicPed or medicPed == 0 or not patientPed or patientPed == 0
            or Death.getState(patientSrc) == 'alive'
            or #(GetEntityCoords(medicPed) - GetEntityCoords(patientPed)) > Config.death.reviveRange * 2.0
            or now - (carryHeartbeatAt[medicSrc] or 0) > Config.transport.heartbeatTtl
        if invalid then releaseCarry(medicSrc, false) end
    end

    for _, record in pairs(stretchers) do
        local vehicle = resolveNetworkEntity(record.vehicleNetworkId, 2)
        local entity = resolveNetworkEntity(record.networkId, 3)
        if not vehicle or not entity then
            removePhysical(record, 'transport entity lost')
        else
            if record.operator and (not isOnDutyEMS(record.operator)
                or not isNearEntity(record.operator, record.entity, Config.transport.interactionRange * 2.0)
                or now - (record.operatorHeartbeatAt or 0) > Config.transport.heartbeatTtl) then
                clearOperator(record)
                record.mode = 'world'
                FreezeEntityPosition(record.entity, true)
                publish(record)
            end

            local patientPed = record.patient and GetPlayerPed(record.patient)
            local patientInvalid = record.patient and (not QBCore:getPlayerData(record.patient)
                or Death.getState(record.patient) == 'alive'
                or not patientPed or patientPed == 0
                or GetPlayerRoutingBucket(record.patient) ~= GetEntityRoutingBucket(record.entity)
                or (record.mode ~= 'vehicle'
                    and #(GetEntityCoords(patientPed) - GetEntityCoords(record.entity))
                        > Config.transport.interactionRange * 3.0))
            if patientInvalid then
                clearPatient(record, 'patient unavailable')
                publish(record)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.transport.heartbeatInterval)
        Stretcher.sweep(GetGameTimer())
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    -- Notify the surviving patient as well as clearing server ownership. If
    -- the dropped player was the medic, suppressing this event would leave
    -- the patient's carry loop running with ragdoll disabled indefinitely.
    releaseCarry(src, false)

    local medicSrc = draggerOf[src]
    if medicSrc then releaseCarry(medicSrc, false) end

    local stretcherNetworkId = stretcherByOperator[src]
    local operated = stretcherNetworkId and stretchers[stretcherNetworkId]
    if operated then
        clearOperator(operated)
        operated.mode = 'world'
        FreezeEntityPosition(operated.entity, true)
        publish(operated)
    end

    releasePatient(src, 'patient disconnected')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, record in pairs(stretchers) do removePhysical(record, 'resource stopped') end
end)
