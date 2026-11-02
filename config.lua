-- Single flat Config table, per-area sub-tables, a trailing comment on every
-- value -- matches kora_lib/qbcore's own config.lua convention.

Config = Config or {}

Config.Debug = false                  -- print hospital setup diagnostics (skipped/bedless hospitals) to the console

Config.job = {
    name = 'ambulance',              -- must match the job record kora_core's shared/jobs.lua already seeds
    onDutyDoctorGrade = 1,            -- minimum grade (1-based) counted as an "on-duty doctor" for Core.doctors' self-heal gate

    -- The kora_core job TYPE this resource dispatches to. Calls target the type,
    -- not the job name, so a server adding a fire department or a second
    -- hospital with `type = 'ems'` gets them on the same radio with no change
    -- here.
    type = 'ems',
}

Config.death = {
    deathTime = 300000,               -- ms a player can stay in laststand before bleeding out to full death
    respawnTime = 60000,              -- ms a fully dead player waits before /respawn is accepted; 0 = immediately. The death screen counts it down, and the server enforces it in Death.respawnAtHospital (an early hospital:server:RespawnAtHospital is refused)
    allowCameraMovement = true,        -- legacy switch: false locks the downed camera (same as cameraMode = 'fixed'); true defers to cameraMode
    cameraMode = 'free',               -- 'free' = downed/dead players look around with the mouse; 'fixed' = camera look locked (old behaviour). Read at use time
    holdDownedHealth = true,           -- true keeps a downed ped above the fatal health line (checked every half second): a fall or bleed tick taking it to 100 or less re-kills the ped (thrown up, timer lost, death camera freezes look); false leaves health alone
    downedHealth = 101,                -- health a downed ped is held at; must stay above 100 or GTA treats the ped as dead again (frozen death camera, no look input)
    respawnHoldTime = 1500,            -- ms [E] must be held to respawn once the respawn timer has ended; 0 = a single press
    reportRetryInterval = 100,         -- ms a dead client waits before retrying server ped-state corroboration
    reportRetryAttempts = 5,           -- quick retries (reportRetryInterval apart) for OneSync health replication
    reportRetryWindow = 15000,         -- ms the client then keeps retrying slowly while still fatally injured (vehicle crashes replicate health late); 0 gives up after reportRetryAttempts as before
    -- Optional death screen, drawn while downed (laststand) and dead. Off by
    -- default: the plain bleed-out / respawn countdown prompt is used. Neither
    -- mode takes NUI focus, so camera look is never affected. Read at use time.
    screen = {
        enabled = false,               -- true replaces the plain countdown with a Downed / Dead prompt (state, countdown) at the top of the screen
        dim = true,                    -- dim the screen while downed (lighter) and dead (darker); only used when enabled
        showHints = true,              -- append the key hints (/911e to call EMS, the alert key, /respawn once allowed); only used when enabled
    },
    -- While fully dead the player can press a key to send an EMS call with their
    -- location (raised through kora_dispatch to on-duty EMS). The key is a real
    -- key mapping, so players can rebind it in FiveM settings. The prompt shows
    -- the hint; the server enforces enabled, dead-only and the cooldown.
    alertEms = {
        enabled = true,                -- false removes the key and the hint
        key = 'G',                     -- default key (kora_lib keybind / RegisterKeyMapping)
        cooldown = 60000,              -- ms between alerts from the same player
    },
    -- What /respawn (respawn at hospital) does besides the hospital bill.
    respawn = {
        clearInventory = false,        -- true wipes the player inventory server-side on /respawn (kora_inventory clearInventory)
        keepItems = {},                -- item names that survive the wipe, e.g. { 'phone', 'id_card' }; only used when clearInventory = true
        -- Refuse /respawn while enough medics are on duty, so a dead player waits for a
        -- real revive. Counted server-side (on-duty players of `jobs`, the dead player
        -- excluded) and re-checked on every attempt; the death screen says so and
        -- re-enables by itself when the count drops below minOnDuty.
        blockWhenMedics = {
            enabled = false,           -- default off: /respawn is only gated by respawnTime
            minOnDuty = 3,             -- respawn is disabled while this many (or more) medics are on duty
            jobs = { 'ambulance' },    -- job names counted as medics
        },
    },
    minimumRevive = 20,               -- % of max health a successful revive restores the patient to
    reviveInterval = 5000,            -- ms cooldown between CPR attempts on the same patient (prevents minigame-spam revives)
    reviveRange = 3.0,                -- metres the reviver must stay within the patient to keep the CPR session valid
    reviveActionTtl = 20000,          -- ms a server-issued CPR action remains valid
}

-- What a revive (CPR/defibrillator, the self-heal AI, hospital laststand care)
-- does to injuries. Read at use time by Death.reviveInField. Admin/full revives
-- (Death.fullRevive, the fullRevive export) and hospital check-in care always
-- clear everything regardless of these two.
Config.revive = {
    clearBleeding = true,             -- a revive stops the bleeding: the Bleeding status ends and bleed damage stops, while wounds stay on the ledger
    clearWounds = false,              -- a revive also closes every wound (limping ends, nothing left to treat or bill); false keeps non-bleeding injuries such as limping, as before
}

Config.doctors = {
    minimalDoctors = 1,               -- on-duty EMS (grade >= Config.job.onDutyDoctorGrade) below which the self-heal AI kicks in (only when selfHealEnabled = true)
    docCooldown = 600000,             -- ms cooldown before the self-heal AI will revive the SAME player again
    selfHealEnabled = false,          -- default false (nil counts as false): a laststand player stays down with the bleed-out timer running until a real medic revives them or the timer runs out. Set true to let an AI doctor revive players when not enough EMS are on duty (see minimalDoctors / selfHealDelay)
    selfHealDelay = 90000,            -- ms a laststand player waits (with no on-duty EMS) before the AI auto-revives them
}

Config.billing = {
    baseCost = 500,                   -- flat hospital bill charged on every respawn-at-hospital
    checkInCost = 250,                -- flat fee charged only after a successful non-death check-in treatment
    perWoundCost = { 150, 350, 650, 1200 }, -- extra cost per still-open wound, indexed by its severity tier (1..4)
    account = 'cash',                 -- Core.money account billed first (capped at what's available -- cash can't go negative)
    fallbackAccount = 'bank',         -- account billed for whatever `account` couldn't cover (allowed to go negative, so this always fully succeeds)
}

Config.hospitalCare = {
    interactionRange = 3.0,           -- metres a patient must be from a hospital check-in point
    bedRange = 2.5,                   -- metres a patient must remain from their assigned bed to finish care
    duration = 15000,                 -- ms a check-in treatment takes once the server has reserved a bed
    actionTtl = 45000,                -- ms a reserved care action can remain unfinished before its bed is released
    requireInjury = true,             -- healthy players cannot occupy a treatment bed
    allowBedless = true,              -- true: a hospital with no beds still gets its pharmacy/stash/duty/garage options and check-in shows a notice; false: config load fails (strict)
}

-- Hospital interaction menu (see shared/hospital_menu.lua). Each hospital entry
-- builds its own zones from whichever fields it has; a missing field only drops
-- that feature. A hospital entry may carry its own `radius = { checkIn = n, duty = n, ... }`
-- (same keys as below) to widen its zones, e.g. so a two-door entrance is covered
-- from both doors; it overrides `radius` below for that hospital only.
Config.hospitalMenu = {
    isolateErrors = true,             -- true: a hospital whose targets fail to register is skipped (and logged) without stopping the remaining hospitals; false: the error propagates
    radius = {                        -- metres around each hospital point in which its options show; checkIn defaults to Config.hospitalCare.interactionRange
        checkIn = nil,
        pharmacy = 3.0,
        stash = 3.0,
        duty = 2.0,
        garage = 6.0,
    },
}

Config.injuries = {
    captureWindow = 500,              -- ms client damage observations may be correlated before reporting a wound
    reportCooldown = 300,             -- ms between client injury reports for one observed hit
    healthTolerance = 5,              -- HP below max that still counts as healthy for hospital check-in
    minDamage = 3,                    -- smallest health loss considered an injury report
    maxDamage = 100,                  -- largest single health loss accepted by the client injury classifier
    severityThresholds = { 8, 20, 40 }, -- dense ascending damage cutoffs for wound severity tiers
    clearWhenHealthy = true,          -- true: an alive player whose health is back at max (admin /heal, regen, any healing outside this resource) has every wound closed, so the Bleeding/Limping pills go away; false keeps wounds until treated, revived or checked in
    healthyMargin = 0,                -- HP below max that still counts as fully healthy for clearWhenHealthy (0 = must be exactly at max)
}

Config.transport = {
    model = 'v_med_emptybed',         -- GTA hospital-bed prop used by patient transport integrations
    interactionRange = 3.0,           -- metres from a transport bed allowed for its interaction
    heartbeatInterval = 2000,         -- ms between transport ownership heartbeats
    heartbeatTtl = 6500,              -- ms without a heartbeat before transport ownership expires
    patientOffset = vector3(0.0, 0.0, 0.55), -- patient attachment offset on the bed prop
    patientRotation = vector3(0.0, 0.0, 180.0), -- patient attachment rotation on the bed prop
    pushOffset = vector3(0.0, -1.15, 0.15), -- pusher attachment offset on the bed prop
    pushRotation = vector3(0.0, 0.0, 0.0), -- pusher attachment rotation on the bed prop
}

Config.compat = {
    enabled = true,                   -- enables legacy qb-ambulancejob compatibility endpoints
    acceptClientInjurySync = false,   -- legacy injury sync remains opt-in; server-owned injury reports are preferred
    allowDestructiveItemEvents = false, -- legacy item-removal events never remove inventory without explicit opt-in
}

Config.painkillers = {
    interval = 300000,                -- ms cooldown between painkiller uses (per player, in memory)
    animDict = 'mp_suicide',          -- pill-taking animation dictionary
    animClip = 'pill',                -- pill-taking animation clip
    animDuration = 3400,              -- ms the animation plays AND the "Using Painkillers" progress bar runs; both end together
    healthAmount = 15,                -- HP restored on a completed use (capped at the ped's max health); 0 = no health benefit
    stopBleeding = false,             -- true: a completed use also stops the bleeding of open wounds (wounds stay on the ledger, like a field revive); false = health only
}

Config.defibrillator = {
    useable = true,                   -- true: the defibrillator inventory item is a registered usable that starts CPR on the nearest downed patient within Config.death.reviveRange (on-duty EMS only); false: item use is left to your own handler
}

Config.treatment = {
    duration = 5000,                  -- ms an on-duty medic must spend treating one wound
    range = 3.0,                      -- metres the medic must remain from the patient throughout treatment
    actionTtl = 15000,                -- ms before an unfinished server-issued treatment action expires
}

Config.dispatch = {
    alertCooldown = 30000,            -- ms cooldown per player on the /911e emergency alert command
    housecallCooldown = 60000,        -- ms cooldown per player on submitting a new house-call request
    housecallTtl = 900000,             -- ms an unclaimed house-call request remains available
    maxHousecalls = 50,                -- maximum live house-call requests retained server-wide

    accent = '#EF4444',               -- EMS red, applied to this player's dispatch UI

    -- Automatic calls when a player goes down or dies. Real qb-ambulancejob had
    -- these; the rewrite dropped all three, leaving a bleeding-out player with
    -- no way to reach EMS except typing a command.
    autoCall = true,
    autoCallCooldown = 45000,         -- ms per player, so one messy firefight is one call, not ten
}

-- Multiple check-in/bed hospitals. `beds` are local offsets from `coords`
-- (bed 1 is also where a respawn-at-hospital lands the player).
Config.hospitals = {
    {
        name = 'pillbox',
        label = 'Pillbox Hill Medical Center',
        coords = vector4(298.7, -584.7, 43.3, 90.0),
        checkIn = vector4(307.1, -595.1, 43.3, 70.0),
        beds = {
            vector4(295.5, -595.6, 43.3, 90.0),
            vector4(295.5, -597.9, 43.3, 90.0),
            vector4(295.5, -600.2, 43.3, 90.0),
        },
        pharmacy = vector4(316.4, -594.7, 43.3, 340.0),
        stash = { coords = vector4(308.6, -598.8, 43.3, 160.0), slots = 50, maxWeight = 4000000 },
        duty = vector4(308.0, -595.0, 43.2, 340.0),
        garage = vector4(294.5, -583.5, 43.2, 250.0),
        blip = { sprite = 61, color = 1, scale = 0.8, category = 'Hospital', name = 'Pillbox Hill Medical' },
    },
    {
        name = 'sandy',
        label = 'Sandy Shores Medical Center',
        coords = vector4(1839.5, 3672.9, 34.3, 130.0),
        checkIn = vector4(1839.5, 3672.9, 34.3, 130.0),
        radius = { checkIn = 5.5, duty = 5.5 }, -- wide enough to reach both front doors
        beds = {
            vector4(1838.9, 3670.6, 34.3, 40.0),
            vector4(1836.9, 3669.0, 34.3, 40.0),
        },
        pharmacy = vector4(1836.9, 3674.4, 34.6, 320.0),
        stash = { coords = vector4(1839.9, 3675.0, 34.3, 40.0), slots = 30, maxWeight = 2000000 },
        duty = vector4(1835.8, 3672.9, 34.6, 320.0),
        garage = vector4(1849.8, 3686.5, 34.2, 145.0),
        blip = { sprite = 61, color = 1, scale = 0.8, category = 'Hospital', name = 'Sandy Shores Medical' },
    },
}

Config.dutyVehicles = {
    {
        label = 'Ambulance', model = 'ambulance',
        stretcher = {
            offset = vector3(0.0, -3.5, 0.25),
            rotation = vector3(0.0, 0.0, 0.0),
        },
    },
    { label = 'Ambulance (Lifeguard)', model = 'lguard' },
    { label = 'Response Bike', model = 'faggio2' },
}

Config.dutyGarage = {
    interactionRange = 8.0,            -- metres from a configured garage allowed for checkout or return
    actionCooldown = 3000,             -- ms between checkout/return requests from one player
}

-- 15 body parts, each with a relative hit-weight (used by Wounds.pickBodyPart's
-- weighted roll -- torso/chest are hit more often than hands/feet) and a
-- `vital` flag (a tier-4 wound to a vital part shortens the blackout timer,
-- see Wounds.blackoutTimer).
Config.bodyParts = {
    { name = 'head',           label = 'Head',            weight = 3,  vital = true,  bones = { 31086 } },
    { name = 'neck',           label = 'Neck',            weight = 2,  vital = true,  bones = { 39317 } },
    { name = 'chest',          label = 'Chest',           weight = 10, vital = true,  bones = { 24816, 24817 } },
    { name = 'abdomen',        label = 'Abdomen',         weight = 8,  vital = true,  bones = { 11816 } },
    { name = 'spine',          label = 'Spine',           weight = 3,  vital = true,  bones = { 23553 } },
    { name = 'left_shoulder',  label = 'Left Shoulder',   weight = 5,  vital = false, bones = { 64729 } },
    { name = 'right_shoulder', label = 'Right Shoulder',  weight = 5,  vital = false, bones = { 10706 } },
    { name = 'left_arm',       label = 'Left Arm',        weight = 8,  vital = false, bones = { 61163 } },
    { name = 'right_arm',      label = 'Right Arm',       weight = 8,  vital = false, bones = { 28252 } },
    { name = 'left_hand',      label = 'Left Hand',       weight = 4,  vital = false, bones = { 18905 } },
    { name = 'right_hand',     label = 'Right Hand',      weight = 4,  vital = false, bones = { 57005 } },
    { name = 'left_leg',       label = 'Left Leg',        weight = 10, vital = false, bones = { 58271 } },
    { name = 'right_leg',      label = 'Right Leg',       weight = 10, vital = false, bones = { 63931 } },
    { name = 'left_foot',      label = 'Left Foot',       weight = 4,  vital = false, bones = { 14201 } },
    { name = 'right_foot',     label = 'Right Foot',      weight = 4,  vital = false, bones = { 52301 } },
}

-- 4-tier bleed severity, qbx_medical-style: escalating tick damage and
-- movement penalty, and only tiers >= ifakRequiredAt can't be closed by a
-- plain bandage (needs an IFAK). Tuned as a playtest-adjustable starting
-- point per the plan's open decision, not a fixed spec.
Config.woundLevels = {
    { tier = 1, label = 'Minor',    movementMultiplier = 1.00, canWalk = true,  ifakRequired = false },
    { tier = 2, label = 'Moderate', movementMultiplier = 0.85, canWalk = true,  ifakRequired = false },
    { tier = 3, label = 'Severe',   movementMultiplier = 0.65, canWalk = true,  ifakRequired = true },
    { tier = 4, label = 'Critical', movementMultiplier = 0.40, canWalk = false, ifakRequired = true },
}

Config.bleed = {
    tickRate = 15000,                  -- ms between bleed damage ticks while any wound is open
    damagePerSeverity = { 1, 2, 4, 7 }, -- HP lost per tick, indexed by wound tier (1..4)
}

Config.blackoutTimer = 20000           -- ms of sustained tier-4 bleeding before the screen starts fading to black
Config.fadeOutTimer = 8000             -- ms the fade-to-black takes once triggered, before forced laststand

local function isPositiveNumber(value)
    return type(value) == 'number' and value > 0
end

local function isVector3(value)
    local kind = type(value)
    return (kind == 'table' or kind == 'vector3' or kind == 'vector4')
        and type(value.x) == 'number' and type(value.y) == 'number' and type(value.z) == 'number'
end

---Validates the structural configuration required by hospital and transport flows.
---Kept Lua-table based so test/mocks.lua can load this file outside FiveM.
---@return boolean
function Config.validate()
    local hospitalNames, beds, bones = {}, {}, {}
    assert(type(Config.death.allowCameraMovement) == 'boolean', 'death allowCameraMovement must be boolean')
    assert(Config.death.cameraMode == 'free' or Config.death.cameraMode == 'fixed', "death cameraMode must be 'free' or 'fixed'")
    assert(type(Config.death.holdDownedHealth) == 'boolean', 'death holdDownedHealth must be boolean')
    assert(Config.doctors.selfHealEnabled == nil or type(Config.doctors.selfHealEnabled) == 'boolean', 'doctors selfHealEnabled must be boolean')
    assert(type(Config.death.downedHealth) == 'number' and Config.death.downedHealth > 100,
        'death downedHealth must be a number above 100')
    assert(type(Config.death.respawnHoldTime) == 'number' and Config.death.respawnHoldTime >= 0,
        'death respawnHoldTime must be a non-negative number')
    assert(type(Config.death.reportRetryWindow) == 'number' and Config.death.reportRetryWindow >= 0,
        'death reportRetryWindow must be a non-negative number')
    assert(type(Config.death.screen) == 'table' and type(Config.death.screen.enabled) == 'boolean'
        and type(Config.death.screen.dim) == 'boolean' and type(Config.death.screen.showHints) == 'boolean',
        'death screen enabled, dim and showHints must be boolean')
    local alertEms, respawn = Config.death.alertEms, Config.death.respawn
    assert(type(alertEms) == 'table' and type(alertEms.enabled) == 'boolean'
        and type(alertEms.key) == 'string' and alertEms.key ~= ''
        and type(alertEms.cooldown) == 'number' and alertEms.cooldown >= 0,
        'death alertEms needs boolean enabled, a key and a non-negative cooldown')
    assert(type(respawn) == 'table' and type(respawn.clearInventory) == 'boolean' and type(respawn.keepItems) == 'table',
        'death respawn needs boolean clearInventory and a keepItems list')
    local block = respawn.blockWhenMedics
    assert(type(block) == 'table' and type(block.enabled) == 'boolean'
        and type(block.minOnDuty) == 'number' and block.minOnDuty >= 1 and type(block.jobs) == 'table',
        'death respawn blockWhenMedics needs boolean enabled, minOnDuty >= 1 and a jobs list')
    assert(type(Config.death.respawnTime) == 'number' and Config.death.respawnTime >= 0,
        'death respawnTime must be a non-negative number')
    assert(type(Config.revive.clearBleeding) == 'boolean' and type(Config.revive.clearWounds) == 'boolean',
        'revive clearBleeding and clearWounds must be boolean')
    assert(type(Config.injuries.clearWhenHealthy) == 'boolean', 'injuries clearWhenHealthy must be boolean')
    assert(type(Config.injuries.healthyMargin) == 'number' and Config.injuries.healthyMargin >= 0,
        'injuries healthyMargin must be a non-negative number')
    assert(type(Config.hospitals) == 'table' and #Config.hospitals > 0, 'at least one hospital is required')
    for _, hospital in ipairs(Config.hospitals) do
        assert(type(hospital.name) == 'string' and hospital.name ~= '' and not hospitalNames[hospital.name], 'hospital names must be unique')
        hospitalNames[hospital.name] = true
        assert(isVector3(hospital.coords), 'hospital coords must be vectors')
        assert(isVector3(hospital.checkIn or hospital.coords), 'hospital check-in must be a vector')
        if type(hospital.beds) ~= 'table' or #hospital.beds == 0 then
            assert(Config.hospitalCare.allowBedless == true, 'each hospital requires at least one bed')
            hospital.beds = {}
            if Config.Debug then print(('[kora_ambulance] hospital %s has no beds configured; check-in disabled there'):format(hospital.name)) end
        end
        for _, bed in ipairs(hospital.beds) do
            assert(isVector3(bed), 'hospital beds must be vectors')
            local key = ('%.3f:%.3f:%.3f'):format(bed.x, bed.y, bed.z)
            assert(not beds[key], 'hospital beds must be unique')
            beds[key] = true
        end
    end

    assert(isPositiveNumber(Config.hospitalCare.interactionRange)
        and isPositiveNumber(Config.hospitalCare.bedRange)
        and isPositiveNumber(Config.hospitalCare.duration)
        and isPositiveNumber(Config.hospitalCare.actionTtl), 'hospital care ranges and durations must be positive')
    assert(type(Config.hospitalCare.requireInjury) == 'boolean', 'hospital care requireInjury must be boolean')
    assert(isPositiveNumber(Config.injuries.captureWindow)
        and isPositiveNumber(Config.injuries.reportCooldown)
        and type(Config.injuries.healthTolerance) == 'number' and Config.injuries.healthTolerance >= 0
        and isPositiveNumber(Config.injuries.minDamage)
        and isPositiveNumber(Config.injuries.maxDamage)
        and Config.injuries.minDamage <= Config.injuries.maxDamage,
        'injury capture values must be valid positive ranges')
    assert(type(Config.transport.model) == 'string' or type(Config.transport.model) == 'number', 'transport model must be a string or hash')
    assert(isPositiveNumber(Config.transport.interactionRange) and isPositiveNumber(Config.transport.heartbeatInterval)
        and isPositiveNumber(Config.transport.heartbeatTtl), 'transport ranges and durations must be positive')
    assert(Config.transport.heartbeatTtl > Config.transport.heartbeatInterval, 'transport heartbeat ttl must exceed its interval')
    assert(isVector3(Config.transport.patientOffset) and isVector3(Config.transport.patientRotation)
        and isVector3(Config.transport.pushOffset) and isVector3(Config.transport.pushRotation), 'transport attachments must be vector3 values')

    local lastThreshold, thresholdCount = 0, 0
    for index, threshold in pairs(Config.injuries.severityThresholds) do
        assert(type(index) == 'number' and index >= 1 and index == math.floor(index), 'injury thresholds must be dense and ascending')
        thresholdCount = thresholdCount + 1
    end
    for index = 1, thresholdCount do
        local threshold = Config.injuries.severityThresholds[index]
        assert(isPositiveNumber(threshold) and threshold > lastThreshold, 'injury thresholds must be dense and ascending')
        lastThreshold = threshold
    end
    assert(thresholdCount > 0, 'injury thresholds must not be empty')

    local bodyPartNames = {}
    assert(type(Config.bodyParts) == 'table' and #Config.bodyParts > 0, 'at least one body part is required')
    for _, part in ipairs(Config.bodyParts) do
        assert(type(part.name) == 'string' and part.name ~= '' and not bodyPartNames[part.name], 'body-part names must be unique')
        bodyPartNames[part.name] = true
        assert(isPositiveNumber(part.weight) and type(part.vital) == 'boolean', 'body parts require a positive weight and vital flag')
        assert(type(part.bones) == 'table' and #part.bones > 0, 'body parts require bones')
        for _, bone in ipairs(part.bones) do
            assert(type(bone) == 'number' and bone % 1 == 0 and bone >= 0 and bone <= 65535
                and not bones[bone], 'body-part bones must be unique valid IDs')
            bones[bone] = true
        end
    end
    assert(type(Config.compat.enabled) == 'boolean'
        and type(Config.compat.acceptClientInjurySync) == 'boolean'
        and type(Config.compat.allowDestructiveItemEvents) == 'boolean', 'compatibility flags must be boolean')
    assert(type(Config.dutyVehicles) == 'table' and #Config.dutyVehicles > 0, 'at least one duty vehicle is required')
    for _, vehicle in ipairs(Config.dutyVehicles) do
        assert(type(vehicle.model) == 'string' or type(vehicle.model) == 'number', 'duty vehicle models must be strings or hashes')
        if vehicle.stretcher then
            assert(isVector3(vehicle.stretcher.offset) and isVector3(vehicle.stretcher.rotation), 'stretcher attachments require offset and rotation vector3 values')
        end
    end
    return true
end

Config.validate()

-- Weapon class -> {injuryChance, bleedChance, severityBias}. `severityBias`
-- is added to the 1..4 tier roll before clamping (see Wounds.rollSeverity) --
-- a shotgun blast skews toward tier 3/4, a melee bruise skews toward tier 1.
Config.weaponClassMap = {
    melee     = { injuryChance = 0.35, bleedChance = 0.30, severityBias = -1 },
    unarmed   = { injuryChance = 0.10, bleedChance = 0.05, severityBias = -2 },
    pistol    = { injuryChance = 0.85, bleedChance = 0.70, severityBias = 0 },
    smg       = { injuryChance = 0.85, bleedChance = 0.70, severityBias = 0 },
    rifle     = { injuryChance = 0.95, bleedChance = 0.85, severityBias = 1 },
    shotgun   = { injuryChance = 0.95, bleedChance = 0.90, severityBias = 2 },
    sniper    = { injuryChance = 1.00, bleedChance = 1.00, severityBias = 2 },
    explosive = { injuryChance = 1.00, bleedChance = 0.90, severityBias = 2 },
    fall      = { injuryChance = 0.50, bleedChance = 0.20, severityBias = 0 },
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then Config = Kora.config.adopt(Config) end
