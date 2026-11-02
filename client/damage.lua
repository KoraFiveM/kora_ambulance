-- Damage (client realm) -- correlates the local victim's native damage event
-- with kora_lib's next observed health decrease. The client reports measurements
-- only; server/death.lua owns validation, body-part remapping, and severity.

local pendingHit
local sequence = math.max(0, GetGameTimer())

local function nextSequence()
    sequence = math.max(sequence + 1, GetGameTimer())
    return sequence
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
    if now - hit.at > Config.injuries.captureWindow then
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
