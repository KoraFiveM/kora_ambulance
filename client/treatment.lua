-- Treatment (client realm) -- kora_lib-powered patient assessment and one-wound
-- treatment actions. All authority stays in server/treatment.lua.

local function isOnDutyEMS()
    local job = exports.kora_core:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param entity number
---@return integer|nil
local function targetServerId(entity)
    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end
    return GetPlayerServerId(playerIndex)
end

---@param patientSrc integer
local function assessPatientById(patientSrc)
    patientSrc = tonumber(patientSrc)
    if not patientSrc or patientSrc < 1 or patientSrc % 1 ~= 0 then return end

    local report, reason = Kora.callback.trigger('qbambulance:server:assessPatient', patientSrc)
    if not report then
        Kora.notify.send({ title = 'Patient Assessment', message = reason or 'Unable to assess patient.', type = 'error' })
        return
    end

    if #report.wounds == 0 then
        Kora.notify.send({ title = 'Patient Assessment', message = ('State: %s. No open wounds.'):format(report.state), type = 'success' })
        return
    end

    local findings = {}
    for _, wound in ipairs(report.wounds) do
        findings[#findings + 1] = ('%s: %s'):format(wound.bodyPartLabel, wound.severityLabel)
    end
    Kora.notify.send({
        title = ('Patient Assessment (%s)'):format(report.state),
        message = table.concat(findings, ' | '),
        type = 'warning',
    })
end

---@param patientSrc integer
local function treatPatientById(patientSrc)
    patientSrc = tonumber(patientSrc)
    if not patientSrc or patientSrc < 1 or patientSrc % 1 ~= 0 then return end

    local started, outcome = Kora.actions.run({
        label = 'Treating patient',
        duration = Config.treatment.duration,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
        begin = function(targetSrc)
            return Kora.callback.trigger('qbambulance:server:beginTreatment', targetSrc)
        end,
        complete = function(result, targetSrc)
            local treated, completeErr = Kora.callback.trigger('qbambulance:server:completeTreatment',
                targetSrc, result.token, result.completed)
            return { treated = treated == true, reason = completeErr }
        end,
    }, patientSrc)

    if not started then
        Kora.notify.send({ title = 'Patient Treatment', message = outcome or 'Unable to begin treatment.', type = 'error' })
        return
    end

    if outcome and outcome.treated then
        Kora.notify.send({ title = 'Patient Treatment', message = 'One wound has been treated.', type = 'success' })
    else
        Kora.notify.send({
            title = 'Patient Treatment',
            message = (outcome and outcome.reason) or 'Treatment was not completed.',
            type = 'warning',
        })
    end
end

local function assessPatient(entity)
    local patientSrc = targetServerId(entity)
    if patientSrc then assessPatientById(patientSrc) end
end

local function treatPatient(entity)
    local patientSrc = targetServerId(entity)
    if patientSrc then treatPatientById(patientSrc) end
end

-- Legacy integrations enter the same kora_lib action as the native target
-- option. All authority remains in server/treatment.lua.
RegisterNetEvent('qbambulance:client:treatmentRequested', treatPatientById)

local function registerTargets()
    exports.kora_target:addGlobalType('player', {
        {
            label = 'Assess Patient',
            icon = 'stethoscope',
            canInteract = isOnDutyEMS,
            onSelect = assessPatient,
        },
        {
            label = 'Treat Wound',
            icon = 'bandage',
            canInteract = isOnDutyEMS,
            onSelect = treatPatient,
        },
    }, Config.treatment.range)
end

registerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTargets() end
end)
