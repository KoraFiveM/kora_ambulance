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

    local report, reason = Kora.callback.trigger('kora_ambulance:server:assessPatient', patientSrc)
    if not report then
        Kora.notify.send({ title = Kora.lang('title.assessment'), message = reason or Kora.lang('ui.unable_assess'), type = 'error' })
        return
    end

    if #report.wounds == 0 then
        Kora.notify.send({ title = Kora.lang('title.assessment'), message = Kora.lang('ui.woundless_assessment', report.state), type = 'success' })
        return
    end

    local findings = {}
    for _, wound in ipairs(report.wounds) do
        findings[#findings + 1] = Kora.lang('ui.finding', wound.bodyPartLabel, wound.severityLabel)
    end
    Kora.notify.send({
        title = Kora.lang('ui.assessment_title', report.state),
        message = table.concat(findings, Kora.lang('ui.finding_separator')),
        type = 'warning',
    })
end

---@param patientSrc integer
local function treatPatientById(patientSrc)
    patientSrc = tonumber(patientSrc)
    if not patientSrc or patientSrc < 1 or patientSrc % 1 ~= 0 then return end

    local started, outcome = Kora.actions.run({
        label = Kora.lang('ui.treating_patient'),
        duration = Config.treatment.duration,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
        begin = function(targetSrc)
            return Kora.callback.trigger('kora_ambulance:server:beginTreatment', targetSrc)
        end,
        complete = function(result, targetSrc)
            local treated, completeErr = Kora.callback.trigger('kora_ambulance:server:completeTreatment',
                targetSrc, result.token, result.completed)
            return { treated = treated == true, reason = completeErr }
        end,
    }, patientSrc)

    if not started then
        Kora.notify.send({ title = Kora.lang('title.treatment'), message = outcome or Kora.lang('ui.unable_treat'), type = 'error' })
        return
    end

    if outcome and outcome.treated then
        Kora.notify.send({ title = Kora.lang('title.treatment'), message = Kora.lang('ui.one_wound_treated'), type = 'success' })
    else
        Kora.notify.send({
            title = Kora.lang('title.treatment'),
            message = (outcome and outcome.reason) or Kora.lang('ui.treatment_incomplete'),
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
RegisterNetEvent('kora_ambulance:client:treatmentRequested', treatPatientById)

local function useFirstAid(entity)
    local patientSrc = targetServerId(entity)
    if patientSrc then TriggerServerEvent('kora_ambulance:server:firstAidTarget', patientSrc) end
end

local function registerTargets()
    local options = {
        {
            label = Kora.lang('ui.assess_patient'),
            icon = 'stethoscope',
            canInteract = isOnDutyEMS,
            onSelect = assessPatient,
        },
        {
            label = Kora.lang('ui.treat_wound'),
            icon = 'bandage',
            canInteract = isOnDutyEMS,
            onSelect = treatPatient,
        },
    }
    if Config.firstaid and Config.firstaid.enabled and Config.firstaid.targetEnabled then
        options[#options + 1] = {
            label = Kora.lang('ui.use_first_aid'),
            icon = 'kit-medical',
            canInteract = isOnDutyEMS,
            onSelect = useFirstAid,
        }
    end
    exports.kora_target:addGlobalType('player', options, Config.treatment.range)
end

registerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTargets() end
end)
