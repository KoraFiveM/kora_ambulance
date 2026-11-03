-- Damage (client realm) -- correlates the local victim's native damage event
-- with kora_lib's next observed health decrease. The client reports measurements
-- only; server/death.lua owns validation, body-part remapping, and severity.

Damage = Damage or {}

local pendingHit
local sequence = math.max(0, GetGameTimer())
local ignoreUntil = 0

local function nextSequence()
    sequence = math.max(sequence + 1, GetGameTimer())
    return sequence
end

---Drops the pending hit and ignores every hit until `ms` have passed. Called
---when health changes for a reason that is not an injury: a heal or revive
---(Config.injuries.healGraceMs) and starvation damage from kora_core's needs
---(Config.injuries.needsDamageWindowMs). Event driven, nothing polls.
---@param ms number
function Damage.suppressFor(ms)
    if type(ms) ~= 'number' or ms <= 0 then return end
    pendingHit = nil
    ignoreUntil = math.max(ignoreUntil, GetGameTimer() + ms)
end

---@param bone any
---@return number|false
local function normalizeBone(bone)
    if type(bone) ~= 'number' or bone ~= bone or bone % 1 ~= 0 then return false end
    return bone
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not (State and State.isAlive and State.isAlive()) then return end
    if GetGameTimer() < ignoreUntil then return end
    if type(args) ~= 'table' or args[1] ~= Kora.cache.ped() then return end

    local victimDied = args[4] == true or args[4] == 1
    if victimDied then return end

    -- GetPedLastDamageBone is edge-sensitive: delaying this until the cache's
    -- health tick risks observing a later hit instead of this event.
    local ok, found, bone = pcall(GetPedLastDamageBone, args[1])
    if not ok or not found then bone = false end

    pendingHit = {
        at = GetGameTimer(),
        bone = normalizeBone(bone),
    }
end)

local function onHealthChange(health, previousHealth)
    local hit = pendingHit
    if not hit then return end

    local now = GetGameTimer()
    if now < ignoreUntil or now - hit.at > Config.injuries.captureWindow then
        pendingHit = nil
        return
    end

    if type(health) ~= 'number' or type(previousHealth) ~= 'number' then return end
    if health > previousHealth then
        pendingHit = nil
        return
    end
    if health == previousHealth then return end

    -- A health decrease consumes the correlated hit even if it is too small
    -- to report. This prevents a later unrelated decrease reusing its bone.
    pendingHit = nil
    local damage = previousHealth - health
    if damage < Config.injuries.minDamage or damage > Config.injuries.maxDamage then return end

    local bodyPart = Wounds.bodyPartFromBone(hit.bone)
    local fallback = bodyPart == nil
    if fallback then bodyPart = Wounds.pickBodyPart() end

    Kora.events.trigger('qbambulance:server:hitObserved', {
        sequence = nextSequence(),
        bone = hit.bone,
        bodyPart = bodyPart,
        damage = damage,
        healthAfter = health,
        fallback = fallback,
    })
end

-- kora_lib drops every onChange registration when it restarts; re-register on
-- its restart. No seeding: this correlates health decreases, not a state.
Kora.cache.onChange('health', onHealthChange)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then Kora.cache.onChange('health', onHealthChange) end
end)

-- kora_core hurts a starving or dehydrated ped (ApplyDamageToPed) on every
-- server update while hunger or thirst is 0. That raises the same native damage
-- event as a hit, so each needs tick opened a bleeding wound (5 damage = tier 1,
-- both needs empty = tier 2). The same replicated update that makes kora_core
-- deal the damage opens an ignore window here, before the native event lands.
local function watchNeeds()
    if not Config.injuries.ignoreNeedsDamage then return end
    for _, need in ipairs({ 'hunger', 'thirst' }) do
        pcall(function()
            exports.kora_core:onPlayerDataChange({ 'metadata', need }, function(_, value)
                if (tonumber(value) or 1) <= 0 then Damage.suppressFor(Config.injuries.needsDamageWindowMs) end
            end)
        end)
    end
end

watchNeeds()

-- kora_core forgets its subscribers when it restarts.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_core' then watchNeeds() end
end)
