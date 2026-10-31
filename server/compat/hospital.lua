-- Safe qb-ambulancejob compatibility adapter. Legacy names remain available,
-- but every meaningful mutation delegates to the native validated workflow.
-- Insecure historical shortcuts are intentionally inert by default.

if not Config.compat.enabled then return end

local QBCore = exports.kora_core

local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

local function nearbyPlayers(a, b, range)
    if not QBCore:getPlayerData(a) or not QBCore:getPlayerData(b) then return false end
    return Kora.world.resolveNearbyPlayer(a, b, { maxDistance = range }) ~= nil
end

local function nearbyHospital(src, checkInOnly)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)

    for _, hospital in ipairs(Config.hospitals) do
        local point = checkInOnly and (hospital.checkIn or hospital.coords) or hospital.coords
        local range = checkInOnly and Config.hospitalCare.interactionRange or 15.0
        if #(coords - vector3(point.x, point.y, point.z)) <= range then return hospital end
    end
    return nil
end

local function mayReadPatient(src, targetSrc)
    if src == targetSrc then return true end
    return isOnDutyEMS(src) and nearbyPlayers(src, targetSrc, Config.treatment.range)
end

local function copyWounds(src)
    local copy = {}
    for bodyPart, tier in pairs(Death.getWoundData(src)) do copy[bodyPart] = tier end
    return copy
end

RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
    local src = source
    local ped = GetPlayerPed(src)
    if isDead == true and ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then Death.markDead(src) end
end)

RegisterNetEvent('hospital:server:SetLaststandStatus', function(inLaststand)
    local src = source
    local ped = GetPlayerPed(src)
    if inLaststand == true and ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then
        Death.enterLaststand(src, 'legacy')
    end
end)

local playerAlerts = {
    ['qbambulance:emergency'] = {
        jobTypes = { Config.job.type }, code = '10-52', title = 'Medical Emergency',
        message = 'A patient requires medical assistance.', priority = 1, icon = 'heart-pulse',
        cooldown = Config.dispatch.autoCallCooldown,
    },
    ['qbambulance:doctor'] = {
        jobTypes = { Config.job.type }, code = '10-51', title = 'Doctor Requested',
        message = 'A doctor is needed at the hospital.', priority = 3, icon = 'stethoscope',
        cooldown = Config.dispatch.autoCallCooldown,
    },
}

for key, definition in pairs(playerAlerts) do
    local ok, err = exports.kora_dispatch:registerPlayerAlert(key, definition)
    if not ok then print(('^3[qbambulance]^7 could not register dispatch alert %s: %s'):format(key, err)) end
end

RegisterNetEvent('hospital:server:ambulanceAlert', function()
    local src = source
    if Death.isAlive(src) then return end
    exports.kora_dispatch:createPlayerCall(src, 'qbambulance:emergency')
end)

RegisterNetEvent('hospital:server:SendDoctorAlert', function()
    local src = source
    if not nearbyHospital(src) then return end
    exports.kora_dispatch:createPlayerCall(src, 'qbambulance:doctor')
end)

RegisterNetEvent('hospital:server:RespawnAtHospital', function(hospitalName)
    local ok, reason = Death.respawnAtHospital(source, hospitalName)
    if not ok and reason then Kora.notify.send(source, { title = 'EMS', message = reason, type = 'error' }) end
end)

-- A legacy bed index is never trusted. The closest configured check-in picks
-- the facility and Hospital atomically picks the first free bed.
RegisterNetEvent('hospital:server:SendToBed', function(_bedIndex)
    local src = source
    local hospital = nearbyHospital(src, true)
    if not hospital then
        Kora.notify.send(src, { title = 'Hospital', message = 'Use a hospital check-in desk.', type = 'error' })
        return
    end
    local _, reason = Hospital.requestCheckIn(src, hospital.name)
    if reason then Kora.notify.send(src, { title = 'Hospital', message = reason, type = 'error' }) end
end)

RegisterNetEvent('hospital:server:LeaveBed', function()
    Hospital.leaveBed(source)
end)

RegisterNetEvent('hospital:server:SyncInjuries', function(injuries)
    if not Config.compat.acceptClientInjurySync or type(injuries) ~= 'table' then return end
    if injuries.limbs ~= nil or injuries.isBleeding ~= nil then return end

    local src = source
    for bodyPart, tier in pairs(injuries) do
        tier = math.floor(tonumber(tier) or 0)
        if type(bodyPart) == 'string' and Wounds.bodyPartDef(bodyPart)
            and tier >= 1 and tier <= Wounds.MAX_TIER then
            Death.recordWound(src, bodyPart, tier)
        end
    end
end)

-- Weapon modifier compatibility is reduce-only. A public legacy event must
-- never let its caller increase weapon damage.
RegisterNetEvent('hospital:server:SetWeaponDamage', function(weaponHash, modifier)
    modifier = tonumber(modifier)
    if type(weaponHash) ~= 'number' or not modifier then return end
    modifier = math.max(0.0, math.min(1.0, modifier))
    TriggerClientEvent('hospital:client:SetWeaponDamage', source, weaponHash, modifier)
end)

RegisterNetEvent('hospital:server:RestoreWeaponDamage', function(weaponHash)
    if type(weaponHash) ~= 'number' then return end
    TriggerClientEvent('hospital:client:RestoreWeaponDamage', source, weaponHash)
end)

RegisterNetEvent('hospital:server:SetArmor', function(armor)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local requested = math.max(0, math.min(100, math.floor(tonumber(armor) or 0)))
    if requested <= GetPedArmour(ped) then SetPedArmour(ped, requested) end
end)

RegisterNetEvent('hospital:server:resetHungerThirst', function()
    -- Needs are reset only by the server-authoritative hospital respawn.
end)

RegisterNetEvent('hospital:server:AddDoctor', function()
    Duty.setDuty(source, true)
end)

RegisterNetEvent('hospital:server:RemoveDoctor', function()
    Duty.setDuty(source, false)
end)

RegisterNetEvent('hospital:server:RevivePlayer', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not isOnDutyEMS(src)
        or not nearbyPlayers(src, targetSrc, Config.death.reviveRange)
        or Death.isAlive(targetSrc) then return end

    TriggerClientEvent('qbambulance:client:reviveRequested', src, targetSrc)
end)

RegisterNetEvent('hospital:server:TreatWounds', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not isOnDutyEMS(src)
        or not nearbyPlayers(src, targetSrc, Config.treatment.range) then return end

    TriggerClientEvent('qbambulance:client:treatmentRequested', src, targetSrc)
end)

RegisterNetEvent('hospital:server:UseFirstAid', function()
    QBCore:useItem(source, 'bandage')
end)

RegisterNetEvent('hospital:server:UseIfaks', function()
    QBCore:useItem(source, 'ifak')
end)

RegisterNetEvent('hospital:server:UsePainkillers', function()
    QBCore:useItem(source, 'painkillers')
end)

RegisterNetEvent('hospital:server:CanHelp', function()
    -- UX hint only; modern server actions perform the actual authorization.
end)

local function registerDestructiveRemoval(eventName, itemName)
    RegisterNetEvent(eventName, function()
        if Config.compat.allowDestructiveItemEvents then QBCore:removeItem(source, itemName, 1) end
    end)
end

registerDestructiveRemoval('hospital:server:removeBandage', 'bandage')
registerDestructiveRemoval('hospital:server:removeIfaks', 'ifak')
registerDestructiveRemoval('hospital:server:removePainkillers', 'painkillers')

Kora.callback.register('hospital:GetDoctors', function()
    return #QBCore:getPlayersByJob(Config.job.name, true)
end)

Kora.callback.register('hospital:GetPlayerStatus', function(src, targetSrc)
    local who = tonumber(targetSrc) or src
    if not mayReadPatient(src, who) then return nil, 'not authorized' end
    return {
        isdead = Death.isDead(who),
        inlaststand = Death.isLaststand(who),
        woundData = copyWounds(who),
    }
end)

Kora.callback.register('hospital:GetPlayerBleeding', function(src, targetSrc)
    local who = tonumber(targetSrc) or src
    if not mayReadPatient(src, who) then return nil, 'not authorized' end
    return Death.isBleeding(who)
end)
