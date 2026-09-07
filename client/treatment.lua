-- Treatment (client realm) -- qblib-powered patient assessment and one-wound
-- treatment actions. All authority stays in server/treatment.lua.

local function isOnDutyEMS()
    local job = exports.qbcore:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

---@param entity number
---@return integer|nil
local function targetServerId(entity)
    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end
    return GetPlayerServerId(playerIndex)
end

local function assessPatient(entity)
    local patientSrc = targetServerId(entity)
    if not patientSrc then return end

    local report, reason = QB.callback.trigger('qbambulance:server:assessPatient', patientSrc)
    if not report then
        QB.notify.send({ title = 'Patient Assessment', message = reason or 'Unable to assess patient.', type = 'error' })
        return
    end

    if #report.wounds == 0 then
        QB.notify.send({ title = 'Patient Assessment', message = ('State: %s. No open wounds.'):format(report.state), type = 'success' })
        return
    end

    local findings = {}
    for _, wound in ipairs(report.wounds) do
        findings[#findings + 1] = ('%s: %s'):format(wound.bodyPartLabel, wound.severityLabel)
    end
    QB.notify.send({
        title = ('Patient Assessment (%s)'):format(report.state),
        message = table.concat(findings, ' | '),
        type = 'warning',
    })
end

local function treatPatient(entity)
    local patientSrc = targetServerId(entity)
    if not patientSrc then return end

    local started, outcome = QB.actions.run({
        label = 'Treating patient',
        duration = Config.treatment.duration,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
        begin = function(targetSrc)
            return QB.callback.trigger('qbambulance:server:beginTreatment', targetSrc)
        end,
        complete = function(result, targetSrc)
            local treated, completeErr = QB.callback.trigger('qbambulance:server:completeTreatment',
                targetSrc, result.token, result.completed)
            return { treated = treated == true, reason = completeErr }
        end,
    }, patientSrc)

    if not started then
        QB.notify.send({ title = 'Patient Treatment', message = outcome or 'Unable to begin treatment.', type = 'error' })
        return
    end

    if outcome and outcome.treated then
        QB.notify.send({ title = 'Patient Treatment', message = 'One wound has been treated.', type = 'success' })
    else
        QB.notify.send({
            title = 'Patient Treatment',
            message = (outcome and outcome.reason) or 'Treatment was not completed.',
            type = 'warning',
        })
    end
end

local function registerTargets()
    exports.qbtarget:addGlobalType('player', {
        {
            label = 'Assess Patient',
            icon = 'stethoscope',
            canInteract = function() return isOnDutyEMS() end,
            onSelect = assessPatient,
        },
        {
            label = 'Treat Wound',
            icon = 'bandage',
            canInteract = function() return isOnDutyEMS() end,
            onSelect = treatPatient,
        },
    }, Config.treatment.range)
end

registerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerTargets() end
end)
