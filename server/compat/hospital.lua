-- Legacy qb-ambulancejob compat -- every hospital:server:*/hospital:client:*
-- event name and hospital:* callback the plan's checklist calls out, so an
-- off-the-shelf qb-ecosystem script/addon that hooks these keeps working
-- unmodified against this framework. Loaded LAST (see fxmanifest.lua) so
-- every handler below can call the real Death/Billing/Revive/Duty/Items
-- functions directly.
--
-- Ambiguous legacy names (this checklist has a few with no single canonical
-- real-world signature -- CanHelp/SetEscortingState in particular) are
-- mapped onto the closest real behaviour this resource already has rather
-- than left as no-ops, and documented inline where the mapping is a genuine
-- judgement call, not an obvious 1:1 translation.

local QBCore = exports.qbcore

------------------------------------------------------------------------------
-- hospital:server:* -- legacy scripts TriggerServerEvent these directly.
------------------------------------------------------------------------------

RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
    local src = source
    local ped = GetPlayerPed(src)
    if isDead == true and ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then Death.markDead(src) end
end)

RegisterNetEvent('hospital:server:SetLaststandStatus', function(inLaststand)
    local src = source
    local ped = GetPlayerPed(src)
    if inLaststand == true and ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then Death.enterLaststand(src, 'legacy') end
end)

-- Bidirectional compat with Core.dispatch.alert's own LEGACY_JOB_EVENTS
-- (which only fires hospital:client:ambulanceAlert outbound, see qbcore's
-- modules/dispatch/server.lua) -- this is the inbound leg, for a legacy
-- script that fires the OLD server event name directly instead of going
-- through our own /911e command.
--
-- The old payload is deliberately ignored. A compatibility event is still a
-- public client boundary, so it may select only one registered incident; its
-- wording and location come from the server.
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
    local ok, err = exports.qbdispatch:registerPlayerAlert(key, definition)
    if not ok then print(('^3[qbambulance]^7 could not register dispatch alert %s: %s'):format(key, err)) end
end

local function nearHospital(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)

    for _, hospital in ipairs(Config.hospitals) do
        local dx, dy, dz = coords.x - hospital.coords.x, coords.y - hospital.coords.y, coords.z - hospital.coords.z
        if (dx * dx + dy * dy + dz * dz) <= 225.0 then return true end
    end
    return false
end

RegisterNetEvent('hospital:server:ambulanceAlert', function()
    local src = source
    if Death.isAlive(src) then return end
    exports.qbdispatch:createPlayerCall(src, 'qbambulance:emergency')
end)

RegisterNetEvent('hospital:server:SendDoctorAlert', function()
    local src = source
    if not nearHospital(src) then return end
    exports.qbdispatch:createPlayerCall(src, 'qbambulance:doctor')
end)

-- Still the ONE code route into a respawn, our own /respawn command included.
-- Since Config.death.respawnTime is enforced server-side, the refusal has to
-- be spoken: a player who fires this event by hand would otherwise see the
-- respawn silently do nothing and read it as a broken script.
RegisterNetEvent('hospital:server:RespawnAtHospital', function(hospitalName)
    local src = source
    local ok, reason = Death.respawnAtHospital(src, hospitalName)
    if not ok and reason then
        QB.notify.send(src, { title = 'EMS', message = reason, type = 'error' })
    end
end)

RegisterNetEvent('hospital:server:SendToBed', function(bedIndex)
    TriggerClientEvent('hospital:client:SendToBed', source, bedIndex)
end)

RegisterNetEvent('hospital:server:LeaveBed', function()
    TriggerClientEvent('hospital:client:LeaveBed', source)
end)

-- A legacy client reporting its own locally-detected wound set (bodyPart ->
-- tier pairs) -- merged in via the same Death.recordWound path our own
-- damage.lua uses, so it participates in bleed ticking/billing identically.
RegisterNetEvent('hospital:server:SyncInjuries', function(injuries)
    if type(injuries) ~= 'table' then return end
    local src = source

    -- qb-ambulancejob's legacy payload is `{ limbs = ..., isBleeding = n }`.
    -- `isBleeding` is a bleed-tick counter, not a 1..4 wound tier; treating it
    -- as one was the source of invalid QB.status severities.  That payload's
    -- limb keys also do not match this resource's body-part names, so leave it
    -- to the legacy resource and only consume the documented bodyPart -> tier
    -- compatibility shape below.
    if injuries.limbs ~= nil or injuries.isBleeding ~= nil then return end

    for bodyPart, tier in pairs(injuries) do
        tier = math.floor(tonumber(tier) or 0)
        if type(bodyPart) == 'string' and Wounds.bodyPartDef(bodyPart)
            and tier >= 1 and tier <= Wounds.MAX_TIER then
            Death.recordWound(src, bodyPart, tier)
        end
    end
end)

-- Native weapon-damage-modifier natives are client-authoritative; forwarded
-- rather than reimplemented server-side.
RegisterNetEvent('hospital:server:SetWeaponDamage', function(weaponHash, modifier)
    TriggerClientEvent('hospital:client:SetWeaponDamage', source, weaponHash, modifier)
end)

RegisterNetEvent('hospital:server:RestoreWeaponDamage', function(weaponHash)
    TriggerClientEvent('hospital:client:RestoreWeaponDamage', source, weaponHash)
end)

RegisterNetEvent('hospital:server:SetArmor', function(armor)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local requested = math.max(0, math.min(100, math.floor(tonumber(armor) or 0)))
    if requested <= GetPedArmour(ped) then SetPedArmour(ped, requested) end
end)

RegisterNetEvent('hospital:server:resetHungerThirst', function()
    -- Kept as an inert compatibility endpoint. Native hospital respawn resets
    -- needs inside Death.respawnAtHospital; no public event should grant a
    -- free refill independently of that server-authoritative transition.
end)

RegisterNetEvent('hospital:server:AddDoctor', function()
    Duty.setDuty(source, true)
end)

RegisterNetEvent('hospital:server:RemoveDoctor', function()
    Duty.setDuty(source, false)
end)

-- Trusted-caller revive/treat: unlike Revive.complete (which gates on the
-- reviver actually holding a defibrillator, for our own CPR flow), these
-- legacy names are historically called by the ambulance job's OWN already-
-- validated client code, so the only check kept here is on-duty EMS.
local function isOnDutyEMS(src)
    local job = QBCore:getJob(src)
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

RegisterNetEvent('hospital:server:RevivePlayer', function(targetSrc)
    QB.notify.send(source, { title = 'EMS', message = 'Use the validated CPR interaction to revive this patient.', type = 'error' })
end)

RegisterNetEvent('hospital:server:TreatWounds', function(targetSrc)
    local src = source
    if not isOnDutyEMS(src) then return end
    local who = tonumber(targetSrc) or src
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(who) then return end
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(who)
    if not ped or ped == 0 or not targetPed or targetPed == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.death.reviveRange then return end
    local bodyPart, tier = Wounds.pickTreatableWound(Death.getWoundData(who), Wounds.MAX_TIER)
    if bodyPart then
        local removed = QBCore:removeItem(src, 'bandage', 1, nil, 'legacy-treat-wounds')
        if removed then Death.clearWound(who, bodyPart) end
    end
end)

RegisterNetEvent('hospital:server:UseFirstAid', function()
    QBCore:useItem(source, 'bandage')
end)

-- UseIfaks/UsePainkillers aren't in the plan's server-name checklist
-- verbatim (only UseFirstAid/CanHelp are), but the client checklist DOES
-- list UseIfaks/UseBandage/UsePainkillers -- client/compat.lua's handlers
-- for those need a matching server-side item-use path, so these two exist
-- to complete that pair rather than leaving IFAK/painkillers as the only
-- pharmacy items with no legacy trigger at all.
RegisterNetEvent('hospital:server:UseIfaks', function()
    QBCore:useItem(source, 'ifak')
end)

RegisterNetEvent('hospital:server:UsePainkillers', function()
    QBCore:useItem(source, 'painkillers')
end)

-- CanHelp has no single canonical real-world signature (the plan flags this
-- ambiguity) -- interpreted here as "did this player just perform a help
-- action", a fire-and-forget acknowledgement rather than a query (a query
-- would need to be QB.callback, like hospital:GetPlayerStatus below, and
-- this name is explicitly listed alongside the plain events, not the
-- callback-style ones).
RegisterNetEvent('hospital:server:CanHelp', function() end)

RegisterNetEvent('hospital:server:removeBandage', function()
    QBCore:removeItem(source, 'bandage', 1)
end)

RegisterNetEvent('hospital:server:removeIfaks', function()
    QBCore:removeItem(source, 'ifak', 1)
end)

RegisterNetEvent('hospital:server:removePainkillers', function()
    QBCore:removeItem(source, 'painkillers', 1)
end)

------------------------------------------------------------------------------
-- hospital:* callback-style -- registered via QB.callback.register so a
-- legacy QBCore.Functions.CreateCallback/TriggerCallback caller reaches
-- these through qbcore's own compat layer (see qbcore/AGENTS.md's compat
-- section) without this resource doing anything QBCore-specific itself.
------------------------------------------------------------------------------

QB.callback.register('hospital:GetDoctors', function(_src)
    return QBCore:getPlayersByJob(Config.job.name, true)
end)

QB.callback.register('hospital:GetPlayerStatus', function(_src, targetSrc)
    local who = tonumber(targetSrc) or _src
    return {
        isdead = Death.isDead(who),
        inlaststand = Death.isLaststand(who),
        woundData = Death.getWoundData(who),
    }
end)

QB.callback.register('hospital:GetPlayerBleeding', function(_src, targetSrc)
    local who = tonumber(targetSrc) or _src
    return Wounds.isBleeding(Death.getWoundData(who))
end)
