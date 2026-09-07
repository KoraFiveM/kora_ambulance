-- Single flat Config table, per-area sub-tables, a trailing comment on every
-- value -- matches qblib/qbcore's own config.lua convention.

Config = Config or {}

Config.job = {
    name = 'ambulance',              -- must match the job record qbcore's shared/jobs.lua already seeds
    onDutyDoctorGrade = 1,            -- minimum grade (1-based) counted as an "on-duty doctor" for Core.doctors' self-heal gate

    -- The qbcore job TYPE this resource dispatches to. Calls target the type,
    -- not the job name, so a server adding a fire department or a second
    -- hospital with `type = 'ems'` gets them on the same radio with no change
    -- here.
    type = 'ems',
}

Config.death = {
    deathTime = 300000,               -- ms a player can stay in laststand before bleeding out to full death
    respawnTime = 60000,              -- ms a fully dead player waits before /respawn is accepted (enforced in Death.respawnAtHospital, not just counted down on screen)
    reportRetryInterval = 100,         -- ms a dead client waits before retrying server ped-state corroboration
    reportRetryAttempts = 5,           -- bounded retries for OneSync health replication before leaving the native death state intact
    minimumRevive = 20,               -- % of max health a successful revive restores the patient to
    reviveInterval = 5000,            -- ms cooldown between CPR attempts on the same patient (prevents minigame-spam revives)
    reviveRange = 3.0,                -- metres the reviver must stay within the patient to keep the CPR session valid
    reviveActionTtl = 20000,          -- ms a server-issued CPR action remains valid
}

Config.doctors = {
    minimalDoctors = 1,               -- on-duty EMS (grade >= Config.job.onDutyDoctorGrade) below which the self-heal AI kicks in
    docCooldown = 600000,             -- ms cooldown before the self-heal AI will revive the SAME player again
    selfHealDelay = 90000,            -- ms a laststand player waits (with no on-duty EMS) before the AI auto-revives them
}

Config.billing = {
    baseCost = 500,                   -- flat hospital bill charged on every respawn-at-hospital
    perWoundCost = { 150, 350, 650, 1200 }, -- extra cost per still-open wound, indexed by its severity tier (1..4)
    account = 'cash',                 -- Core.money account billed first (capped at what's available -- cash can't go negative)
    fallbackAccount = 'bank',         -- account billed for whatever `account` couldn't cover (allowed to go negative, so this always fully succeeds)
}

Config.painkillers = {
    interval = 300000,                -- ms cooldown between painkiller uses (metadata.lastPainkillerAt-gated)
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
        beds = {
            vector4(295.5, -595.6, 43.3, 90.0),
            vector4(295.5, -597.9, 43.3, 90.0),
            vector4(295.5, -600.2, 43.3, 90.0),
        },
        pharmacy = vector4(316.4, -594.7, 43.3, 340.0),
        stash = { coords = vector4(308.6, -598.8, 43.3, 160.0), slots = 50, maxWeight = 4000000 },
        duty = vector4(308.0, -595.0, 43.2, 340.0),
        garage = vector4(294.5, -583.5, 43.2, 250.0),
        blip = { sprite = 61, color = 1, scale = 0.8, label = 'Pillbox Hill Medical' },
    },
    {
        name = 'sandy',
        label = 'Sandy Shores Medical Center',
        coords = vector4(1839.5, 3672.9, 34.3, 130.0),
        beds = {
            vector4(1838.9, 3670.6, 34.3, 40.0),
            vector4(1836.9, 3669.0, 34.3, 40.0),
        },
        pharmacy = vector4(1836.9, 3674.4, 34.6, 320.0),
        stash = { coords = vector4(1839.9, 3675.0, 34.3, 40.0), slots = 30, maxWeight = 2000000 },
        duty = vector4(1835.8, 3672.9, 34.6, 320.0),
        garage = vector4(1849.8, 3686.5, 34.2, 145.0),
        blip = { sprite = 61, color = 1, scale = 0.8, label = 'Sandy Shores Medical' },
    },
}

Config.dutyVehicles = {
    { label = 'Ambulance', model = 'ambulance' },
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
    { name = 'head',           label = 'Head',            weight = 3,  vital = true },
    { name = 'neck',           label = 'Neck',            weight = 2,  vital = true },
    { name = 'chest',          label = 'Chest',           weight = 10, vital = true },
    { name = 'abdomen',        label = 'Abdomen',         weight = 8,  vital = true },
    { name = 'spine',          label = 'Spine',           weight = 3,  vital = true },
    { name = 'left_shoulder',  label = 'Left Shoulder',   weight = 5,  vital = false },
    { name = 'right_shoulder', label = 'Right Shoulder',  weight = 5,  vital = false },
    { name = 'left_arm',       label = 'Left Arm',        weight = 8,  vital = false },
    { name = 'right_arm',      label = 'Right Arm',       weight = 8,  vital = false },
    { name = 'left_hand',      label = 'Left Hand',       weight = 4,  vital = false },
    { name = 'right_hand',     label = 'Right Hand',      weight = 4,  vital = false },
    { name = 'left_leg',       label = 'Left Leg',        weight = 10, vital = false },
    { name = 'right_leg',      label = 'Right Leg',       weight = 10, vital = false },
    { name = 'left_foot',      label = 'Left Foot',       weight = 4,  vital = false },
    { name = 'right_foot',     label = 'Right Foot',      weight = 4,  vital = false },
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
