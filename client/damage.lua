-- Damage (client realm) -- per-body-part wound LOCATION while alive.
-- baseevents only reports the alive->dead transition (see client/death.lua's
-- header); this is the separate, lightweight damage-source listener the
-- plan calls for, feeding Wounds' pure roll functions to decide whether a
-- hit becomes a tracked wound, then reporting it to the server (server/
-- death.lua's qbambulance:server:reportWound, which re-validates before
-- calling Death.recordWound).
--
-- CEventNetworkEntityDamage's exact argument layout is FiveM-build-dependent
-- (flagged as a known risk in the plan's open decisions) -- indexed
-- defensively via pcall rather than assumed exhaustive.

-- WEAPON_GROUP_* hashes classify a weapon without needing its exact name
-- (GetWeapontypeGroup is a stable native across builds, unlike parsing
-- CEventNetworkEntityDamage's own weapon field position).
local GROUP_CLASS = {
    [joaat('GROUP_UNARMED')] = 'unarmed',
    [joaat('GROUP_MELEE')] = 'melee',
    [joaat('GROUP_PISTOL')] = 'pistol',
    [joaat('GROUP_SMG')] = 'smg',
    [joaat('GROUP_MG')] = 'smg',
    [joaat('GROUP_RIFLE')] = 'rifle',
    [joaat('GROUP_SHOTGUN')] = 'shotgun',
    [joaat('GROUP_SNIPER')] = 'sniper',
    [joaat('GROUP_HEAVY')] = 'explosive',
    [joaat('GROUP_THROWN')] = 'explosive',
    [joaat('GROUP_STUNGUN')] = 'pistol',
}

local function classifyWeapon(weaponHash)
    local ok, group = pcall(GetWeapontypeGroup, weaponHash)
    if not ok then return 'unarmed' end
    return GROUP_CLASS[group] or 'unarmed'
end

local lastProcessedAt = 0

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not (State and State.isAlive and State.isAlive()) then return end

    local ok, victim, _attacker, victimDied, weaponHash = pcall(function()
        return args[1], args[2], args[3] == 1, args[4]
    end)
    if not ok or victim ~= QB.cache.ped() then return end
    if victimDied then return end -- baseevents/client/death.lua owns the death transition itself

    -- Coarse client-side rate limit -- a shotgun/explosive can fire several
    -- CEventNetworkEntityDamage entries for one visual hit; without this a
    -- single blast could report (and bill for) several wounds at once.
    local now = GetGameTimer()
    if now - lastProcessedAt < 300 then return end
    lastProcessedAt = now

    local weaponClass = classifyWeapon(weaponHash)
    if not Wounds.rollInjury(weaponClass) then return end

    local bodyPart = Wounds.pickBodyPart()
    local tier = Wounds.rollSeverity(weaponClass, bodyPart)

    if Wounds.rollBleed(weaponClass) then
        local ped = QB.cache.ped()
        pcall(function()
            QB.fx.playPtfx({ dict = 'blood', name = 'blood_bullet_impact_var2', entity = ped, looped = false })
        end)
    end

    QB.events.trigger('qbambulance:server:reportWound', bodyPart, tier)
end)
