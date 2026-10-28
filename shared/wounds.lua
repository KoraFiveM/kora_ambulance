-- Wounds -- pure, native-free logic over Config.bodyParts/weaponClassMap/
-- woundLevels/bleed. Shared realm so client/damage.lua (per-hit wound
-- location while alive) and server/death.lua (bleed ticking, billing,
-- SyncInjuries compat) call the exact same math. Every function here is a
-- plain value in, value out transform -- no natives, no Core/QB calls -- so
-- it's fully exercised by test/smoke/wounds.lua under plain lua5.4.

Wounds = Wounds or {}

local bodyPartByName = {}
local bodyPartByBone = {}
for _, part in ipairs(Config.bodyParts) do
    bodyPartByName[part.name] = part
    for _, bone in ipairs(part.bones or {}) do bodyPartByBone[bone] = part.name end
end

local woundLevelByTier = {}
for _, level in ipairs(Config.woundLevels) do woundLevelByTier[level.tier] = level end

local MAX_TIER = #Config.woundLevels

---@return {name: string, label: string}[]
function Wounds.bodyPartNames()
    local out = {}
    for i, part in ipairs(Config.bodyParts) do out[i] = part.name end
    return out
end

---@param name string
---@return table|nil
function Wounds.bodyPartDef(name)
    return bodyPartByName[name]
end

---Maps a GTA ped bone ID to this resource's configured body-part name.
---@param bone number|nil
---@return string|nil bodyPart
function Wounds.bodyPartFromBone(bone)
    if type(bone) ~= 'number' or bone ~= bone or bone % 1 ~= 0 then return nil end
    return bodyPartByBone[bone]
end

---Derives a wound tier from observed health loss. The configured thresholds
---are the lower bounds for tiers 2..N; vital locations add one tier after
---classification. The final tier is always clamped to the configured wound
---level range.
---@param damage number
---@param bodyPart string
---@return integer tier
function Wounds.severityFromDamage(damage, bodyPart)
    damage = tonumber(damage) or 0

    local tier = 1
    for _, threshold in ipairs(Config.injuries.severityThresholds) do
        if damage < threshold then break end
        tier = tier + 1
    end

    local part = bodyPartByName[bodyPart]
    if part and part.vital then tier = tier + 1 end

    if tier < 1 then return 1 end
    if tier > MAX_TIER then return MAX_TIER end
    return tier
end

---@param tier integer
---@return table|nil
function Wounds.woundLevelDef(tier)
    return woundLevelByTier[tier]
end

---Picks a body part using each part's configured `weight` as a relative
---roll -- `rand` is injectable (defaults to `math.random`) so this is
---deterministic and testable without relying on global RNG state.
---@param rand? fun(): number 0..1
---@return string bodyPart
function Wounds.pickBodyPart(rand)
    rand = rand or math.random

    local total = 0
    for _, part in ipairs(Config.bodyParts) do total = total + part.weight end

    local roll = rand() * total
    local cursor = 0
    for _, part in ipairs(Config.bodyParts) do
        cursor = cursor + part.weight
        if roll <= cursor then return part.name end
    end

    return Config.bodyParts[#Config.bodyParts].name
end

-- Native GTA weapon hashes are build-dependent to enumerate exhaustively, so
-- classification goes by name substring against the standard weapon_* naming
-- convention (matches kora_core/shared/weapons.lua's own item-name scheme) --
-- callers pass GetWeaponNameFromHash-style names, not raw hashes.
local WEAPON_CLASS_PATTERNS = {
    { pattern = 'melee',  class = 'melee' },
    { pattern = 'unarmed', class = 'unarmed' },
    { pattern = 'knife', class = 'melee' },
    { pattern = 'bat', class = 'melee' },
    { pattern = 'machete', class = 'melee' },
    { pattern = 'hatchet', class = 'melee' },
    { pattern = 'knuckle', class = 'melee' },
    { pattern = 'shotgun', class = 'shotgun' },
    { pattern = 'sniper', class = 'sniper' },
    { pattern = 'marksman', class = 'sniper' },
    { pattern = 'heavysniper', class = 'sniper' },
    { pattern = 'smg', class = 'smg' },
    { pattern = 'mg', class = 'smg' },
    { pattern = 'rifle', class = 'rifle' },
    { pattern = 'carbine', class = 'rifle' },
    { pattern = 'pistol', class = 'pistol' },
    { pattern = 'revolver', class = 'pistol' },
    { pattern = 'grenade', class = 'explosive' },
    { pattern = 'rpg', class = 'explosive' },
    { pattern = 'stickybomb', class = 'explosive' },
    { pattern = 'pipebomb', class = 'explosive' },
    { pattern = 'molotov', class = 'explosive' },
    { pattern = 'proxmine', class = 'explosive' },
}

---Resolves a native weapon name (e.g. "WEAPON_PISTOL", "weapon_pistol") to
---one of Config.weaponClassMap's keys. Falls back to 'pistol' for an
---unrecognised firearm-shaped name and 'unarmed' for nil/"unarmed"/"none",
---since an unmapped class would otherwise silently skip injury/bleed rolls.
---@param weaponName string|nil
---@return string weaponClass
function Wounds.resolveWeaponClass(weaponName)
    if not weaponName then return 'unarmed' end

    local lowered = weaponName:lower()
    if lowered == 'unarmed' or lowered == 'none' or lowered == '' then return 'unarmed' end

    for _, entry in ipairs(WEAPON_CLASS_PATTERNS) do
        if lowered:find(entry.pattern, 1, true) then return entry.class end
    end

    if lowered:find('weapon_', 1, true) then return 'pistol' end
    return 'unarmed'
end

---@param weaponClass string
---@return table {injuryChance, bleedChance, severityBias}
function Wounds.classDef(weaponClass)
    return Config.weaponClassMap[weaponClass] or Config.weaponClassMap.unarmed
end

---Rolls whether a hit from `weaponClass` causes a tracked injury at all.
---@param weaponClass string
---@param rand? fun(): number 0..1
---@return boolean injured
function Wounds.rollInjury(weaponClass, rand)
    rand = rand or math.random
    return (rand()) <= Wounds.classDef(weaponClass).injuryChance
end

---Rolls whether an injury from `weaponClass` bleeds.
---@param weaponClass string
---@param rand? fun(): number 0..1
---@return boolean bleeds
function Wounds.rollBleed(weaponClass, rand)
    rand = rand or math.random
    return (rand()) <= Wounds.classDef(weaponClass).bleedChance
end

---Rolls a 1..MAX_TIER severity for a new wound: a flat random base tier,
---nudged by the weapon class's `severityBias` and pushed up one tier for a
---vital body part, then clamped into range. Deterministic given `rand`.
---@param weaponClass string
---@param bodyPart string
---@param rand? fun(): number 0..1
---@return integer tier 1..MAX_TIER
function Wounds.rollSeverity(weaponClass, bodyPart, rand)
    rand = rand or math.random

    local base = 1 + math.floor(rand() * MAX_TIER)
    local bias = Wounds.classDef(weaponClass).severityBias or 0
    local part = bodyPartByName[bodyPart]
    local vitalBump = (part and part.vital) and 1 or 0

    local tier = base + bias + vitalBump
    if tier < 1 then tier = 1 end
    if tier > MAX_TIER then tier = MAX_TIER end
    return tier
end

---Combines any number of open wound tiers on the same body part into one
---effective tier -- worst tier wins, never averaged, so a fresh minor graze
---on an already-critical limb doesn't dilute the existing severity.
---@param tiers integer[]
---@return integer|nil tier nil if `tiers` is empty
function Wounds.worstTier(tiers)
    local worst = nil
    for _, tier in ipairs(tiers) do
        if not worst or tier > worst then worst = tier end
    end
    return worst
end

---@param woundData table<string, integer> bodyPart -> open wound tier
---@return integer|nil tier The single worst tier across every wound, or nil if woundData is empty
function Wounds.worstOpenTier(woundData)
    local tiers = {}
    for _, tier in pairs(woundData or {}) do tiers[#tiers + 1] = tier end
    return Wounds.worstTier(tiers)
end

---@param woundData table<string, integer>
---@return number multiplier 1.0 (unhurt) down to the worst open wound's movementMultiplier
function Wounds.movementMultiplier(woundData)
    local worst = Wounds.worstOpenTier(woundData)
    if not worst then return 1.0 end
    local level = woundLevelByTier[worst]
    return level and level.movementMultiplier or 1.0
end

---@param tier integer
---@return number damage HP lost per bleed tick at this tier
function Wounds.bleedTickDamage(tier)
    return Config.bleed.damagePerSeverity[tier] or Config.bleed.damagePerSeverity[MAX_TIER]
end

---@param woundData table<string, integer>
---@return boolean bleeding True if any wound is open at all (every tracked tier bleeds to some degree).
function Wounds.isBleeding(woundData)
    return Wounds.worstOpenTier(woundData) ~= nil
end

---Whether an item that only handles up to `maxTier` (a bandage, typically 2)
---can fully close a wound of `tier` severity, vs. only needing an IFAK.
---@param tier integer
---@param maxTier integer
---@return boolean
function Wounds.canTreatWithTier(tier, maxTier)
    local level = woundLevelByTier[tier]
    if level and level.ifakRequired and maxTier < 3 then return false end
    return tier <= maxTier
end

---Picks the single best wound for a bandage/IFAK application: the most
---severe OPEN wound this item is actually capable of treating (per
---Wounds.canTreatWithTier), so using a limited item always addresses the
---worst thing it can fix rather than an arbitrary/first one.
---@param woundData table<string, integer>
---@param maxTier integer The item's treatment ceiling (2 for a bandage, 4 for an IFAK).
---@return string|nil bodyPart
---@return integer|nil tier
function Wounds.pickTreatableWound(woundData, maxTier)
    local bestPart, bestTier = nil, nil

    for bodyPart, tier in pairs(woundData or {}) do
        if Wounds.canTreatWithTier(tier, maxTier) and (not bestTier or tier > bestTier) then
            bestPart, bestTier = bodyPart, tier
        end
    end

    return bestPart, bestTier
end

Wounds.MAX_TIER = MAX_TIER

-- The two durable QB.status conditions the wound system drives. Registered
-- here (shared realm) rather than in shared/items.lua -- these are wound
-- states, not item-consumption cosmetics, even though they use the same
-- QB.status mechanism. `bleeding`'s fx is a fixed vignette/ptfx regardless of
-- severity (QB.status has no per-severity fx); `limping` intentionally
-- carries NO fx/anim/movement of its own -- its per-tier movement penalty
-- varies with Wounds.woundLevelDef(severity).movementMultiplier, which
-- QB.status's single static `movement.speedMultiplier` can't express, so
-- client/damage.lua applies it directly via QB.status.onChange instead (see
-- that file's header comment and QB.status's own movement-field caveat).
QB.status.registerEffect('bleeding', {
    stacking = 'replace',
    severityLevels = MAX_TIER,
    fx = {
        ptfx = { dict = 'blood', name = 'blood_stab' },
    },
})

QB.status.registerEffect('limping', {
    stacking = 'replace',
    severityLevels = MAX_TIER,
})
