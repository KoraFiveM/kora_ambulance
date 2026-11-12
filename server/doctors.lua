-- Doctors (server realm) -- on-duty EMS headcount and the self-heal AI that
-- kicks in when too few (or zero) doctors are on duty, so a laststand player
-- isn't stuck waiting forever for a human EMS response. shouldSelfHeal is
-- pure (test/smoke/doctors.lua); the sweep thread below is the only
-- side-effecting part.

Doctors = Doctors or {}

-- kora_core has no Kora proxy; calls cross the exports boundary directly.
local QBCore = exports.kora_core

local lastSelfHealAt = {} -- src -> os.time() of the last AI self-heal on this player

---@return integer count On-duty EMS at grade >= Config.job.onDutyDoctorGrade.
function Doctors.onDutyCount()
    local count = 0
    for _, src in ipairs(QBCore:getPlayersByJob(Config.job.name, true)) do
        local job = QBCore:getJob(src)
        if job and job.grade and (job.grade.level or 1) >= Config.job.onDutyDoctorGrade then
            count = count + 1
        end
    end
    return count
end

---@param onDutyCount integer
---@return boolean
function Doctors.shouldSelfHeal(onDutyCount)
    return onDutyCount < Config.doctors.minimalDoctors
end

---@param now integer os.time()
---@param lastHealAt integer|nil
---@return boolean eligible False if still within Config.doctors.docCooldown of the last AI heal on this player.
function Doctors.cooldownElapsed(now, lastHealAt)
    if not lastHealAt then return true end
    return (now - lastHealAt) >= math.floor(Config.doctors.docCooldown / 1000)
end

---@param src integer
---@return integer|nil
function Doctors.lastSelfHealAt(src)
    return lastSelfHealAt[src]
end

---Runs the self-heal AI pass for one laststand player: revives in the field
---(no bill -- an AI paramedic doesn't invoice) if enough time has both
---elapsed since they went down (Config.doctors.selfHealDelay) and since
---their last AI heal (Config.doctors.docCooldown). Does nothing unless
---Config.doctors.selfHealEnabled is true (default false; nil counts as off).
---@param src integer
---@return boolean healed
function Doctors.trySelfHeal(src)
    if Config.doctors.selfHealEnabled ~= true then return false end -- off by default; nil counts as off
    if not Death.isLaststand(src) then return false end
    if Death.laststandElapsed(src) < math.floor(Config.doctors.selfHealDelay / 1000) then return false end

    local now = os.time()
    if not Doctors.cooldownElapsed(now, lastSelfHealAt[src]) then return false end

    lastSelfHealAt[src] = now
    Death.reviveInField(src, Config.death.minimumRevive)
    Kora.notify.send(src, { title = 'EMS', message = 'No paramedics were available -- you stabilised on your own.', type = 'info' })

    return true
end

CreateThread(function()
    while true do
        Wait(10000)
        if Doctors.shouldSelfHeal(Doctors.onDutyCount()) then
            for _, src in ipairs(QBCore:getPlayers()) do
                if Death.isLaststand(src) then Doctors.trySelfHeal(src) end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastSelfHealAt[source] = nil
end)
