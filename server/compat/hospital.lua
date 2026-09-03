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
-- Raised through qbdispatch, so a legacy caller produces a real call with a
-- feed entry, a map marker and a response state -- not a notification that
-- vanishes. qbdispatch can register these same names itself
-- (Config.compat.legacyInbound), but ships with that OFF precisely so this
-- handler -- which knows the job, the wording and the coordinates -- owns them.
--
-- The legacy signature is not stable across the ecosystem: real qb-policejob
-- fires its equivalent as (coords, text) while qbcore's compat table fires
-- (message, coords). Both orders are sniffed rather than assumed, since getting
-- it wrong silently swaps a call's description with its location.
local function sniff(a, b)
    if type(a) == 'string' then return a, b end
    if type(a) == 'table' then return type(b) == 'string' and b or nil, a end
    return nil, nil
end

RegisterNetEvent('hospital:server:ambulanceAlert', function(a, b)
    local src = source
    local message, coords = sniff(a, b)

    if not coords then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local position = GetEntityCoords(ped)
            coords = { x = position.x, y = position.y, z = position.z }
        end
    end

    Ambulance.dispatch.call({
        code = '10-52',
        title = 'Ambulance Alert',
        message = message or 'A medical emergency was reported.',
        priority = 1,
        coords = coords,
        icon = 'heart-pulse',
        data = { legacy = 'hospital:server:ambulanceAlert', requester = src },
    })
end)

RegisterNetEvent('hospital:server:SendDoctorAlert', function()
    Ambulance.dispatch.call({
        code = '10-51',
        title = 'Doctor Requested',
        message = 'A doctor is needed at the hospital.',
        priority = 3,
        icon = 'stethoscope',
        data = { legacy = 'hospital:server:SendDoctorAlert' },
    })
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
    for bodyPart, tier in pairs(injuries) do
        if type(bodyPart) == 'string' and type(tier) == 'number' then
            Death.recordWound(src, bodyPart, math.floor(tier))
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
    QBCore:reset(source)
end)

RegisterNetEvent('hospital:server:AddDoctor', function()
    QBCore:setJobDuty(source, true)
end)

RegisterNetEvent('hospital:server:RemoveDoctor', function()
    QBCore:setJobDuty(source, false)
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
