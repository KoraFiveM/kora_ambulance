-- Downed (shared) -- pure helpers for the laststand / dead presentation. No
-- natives, so test/smoke/downed.lua runs them outside FiveM.
--
-- GTA treats a player ped at or below 100 health as fatally injured. Setting a
-- downed ped to a lower value (the old fixed 50, or 20% of max health = 40 on
-- revive) kept it fatally injured: GTA's death camera ignored mouse look and the
-- ped never recovered after a revive. Every health value we apply goes through
-- here so it stays above that line.

Downed = Downed or {}

Downed.FATAL_HEALTH = 100

---@param max? number GetEntityMaxHealth of the ped.
---@return number
local function ceiling(max)
    max = tonumber(max) or 200
    return math.max(Downed.FATAL_HEALTH + 1, max)
end

---Health a downed (laststand/dead) ped is held at: Config.death.downedHealth,
---clamped into the survivable range.
---@param configured? number
---@param max? number
---@return integer
function Downed.downedHealth(configured, max)
    local value = tonumber(configured) or Downed.FATAL_HEALTH + 1
    return math.floor(math.min(math.max(value, Downed.FATAL_HEALTH + 1), ceiling(max)))
end

---Health after a revive: pct of the survivable range (100..max), never fatal.
---@param pct? number 0..100
---@param max? number
---@return integer
function Downed.revivedHealth(pct, max)
    pct = math.min(math.max(tonumber(pct) or 20, 0), 100)
    local top = ceiling(max)
    local value = Downed.FATAL_HEALTH + (top - Downed.FATAL_HEALTH) * pct / 100
    return math.floor(math.min(math.max(value, Downed.FATAL_HEALTH + 1), top))
end

---Whether mouse look stays free while down. cameraMode 'fixed' or the legacy
---allowCameraMovement = false lock it; anything else (default 'free') frees it.
---@param death table Config.death
---@return boolean
function Downed.cameraFree(death)
    if type(death) ~= 'table' then return true end
    if death.allowCameraMovement == false then return false end
    return death.cameraMode ~= 'fixed'
end

---@param heldMs number
---@param needMs number
---@return boolean complete
---@return number fraction 0..1
function Downed.holdProgress(heldMs, needMs)
    needMs = tonumber(needMs) or 0
    if needMs <= 0 then return true, 1 end
    local fraction = math.min(math.max((tonumber(heldMs) or 0) / needMs, 0), 1)
    return fraction >= 1, fraction
end
