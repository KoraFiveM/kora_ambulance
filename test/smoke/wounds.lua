-- Wounds smoke test -- pure wound-severity/weapon-class/treatment logic,
-- no natives and no qbcore/qblib mocks needed beyond QB.status.registerEffect
-- (called at shared/wounds.lua's own load time).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')

h.test('pickBodyPart respects weight and is deterministic given a fixed rand', function()
    -- rand() == 0 always selects the first cumulative-weight bucket to clear,
    -- i.e. the first body part in Config.bodyParts.
    local part = Wounds.pickBodyPart(function() return 0 end)
    h.assertEqual(part, Config.bodyParts[1].name)

    -- rand() == 1 (the top of the range) should resolve to the last part.
    local lastPart = Wounds.pickBodyPart(function() return 0.999999 end)
    h.assertEqual(lastPart, Config.bodyParts[#Config.bodyParts].name)
end)

h.test('bodyPartFromBone maps every configured bone and rejects missing or malformed IDs', function()
    for _, part in ipairs(Config.bodyParts) do
        for _, bone in ipairs(part.bones) do h.assertEqual(Wounds.bodyPartFromBone(bone), part.name) end
    end
    h.assertEqual(Wounds.bodyPartFromBone(65535), nil)
    h.assertEqual(Wounds.bodyPartFromBone(false), nil)
    h.assertEqual(Wounds.bodyPartFromBone(31086.5), nil)
end)

h.test('severityFromDamage uses configured thresholds, adds vital bump, and clamps', function()
    h.assertEqual(Wounds.severityFromDamage(3, 'left_hand'), 1)
    h.assertEqual(Wounds.severityFromDamage(7, 'left_hand'), 1)
    h.assertEqual(Wounds.severityFromDamage(8, 'left_hand'), 2)
    h.assertEqual(Wounds.severityFromDamage(20, 'left_hand'), 3)
    h.assertEqual(Wounds.severityFromDamage(40, 'left_hand'), 4)

    h.assertEqual(Wounds.severityFromDamage(3, 'head'), 2)
    h.assertEqual(Wounds.severityFromDamage(20, 'chest'), 4)
    h.assertEqual(Wounds.severityFromDamage(100, 'head'), Wounds.MAX_TIER)
end)

h.test('resolveWeaponClass classifies common weapon names', function()
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_PISTOL'), 'pistol')
    h.assertEqual(Wounds.resolveWeaponClass('weapon_pumpshotgun'), 'shotgun')
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_KNIFE'), 'melee')
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_SNIPERRIFLE'), 'sniper')
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_CARBINERIFLE'), 'rifle')
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_STICKYBOMB'), 'explosive')
    h.assertEqual(Wounds.resolveWeaponClass('WEAPON_UNARMED'), 'unarmed')
    h.assertEqual(Wounds.resolveWeaponClass(nil), 'unarmed')
    -- Unknown but weapon_-shaped names fall back to 'pistol', not 'unarmed'.
    h.assertEqual(Wounds.resolveWeaponClass('weapon_totally_made_up'), 'pistol')
end)

h.test('rollInjury/rollBleed respect the configured class chances via injected rand', function()
    h.assertTrue(Wounds.rollInjury('rifle', function() return 0.0 end))
    h.assertFalse(Wounds.rollInjury('rifle', function() return 0.999999 end))

    h.assertTrue(Wounds.rollBleed('shotgun', function() return 0.0 end))
    h.assertFalse(Wounds.rollBleed('unarmed', function() return 0.999999 end))
end)

h.test('rollSeverity clamps into 1..MAX_TIER regardless of class bias/vital bump', function()
    -- melee has severityBias = -1; base roll floor (rand=0) is tier 1, so
    -- 1 + (-1) = 0 must clamp up to 1.
    local tier = Wounds.rollSeverity('melee', 'left_hand', function() return 0.0 end)
    h.assertTrue(tier >= 1 and tier <= Wounds.MAX_TIER)
    h.assertEqual(tier, 1)

    -- explosive has severityBias = +2, and 'head' is a vital part (+1 more);
    -- base roll ceiling (rand just under 1) is tier MAX_TIER, so it must
    -- clamp DOWN to MAX_TIER, not overflow past it.
    local maxTier = Wounds.rollSeverity('explosive', 'head', function() return 0.999999 end)
    h.assertEqual(maxTier, Wounds.MAX_TIER)
end)

h.test('rollSeverity gives a vital body part a strictly higher-or-equal tier than a non-vital one, same roll', function()
    local rand = function() return 0.5 end
    local vitalTier = Wounds.rollSeverity('pistol', 'chest', rand)   -- vital = true
    local limbTier = Wounds.rollSeverity('pistol', 'left_hand', rand) -- vital = false
    h.assertTrue(vitalTier >= limbTier)
end)

h.test('worstTier/worstOpenTier take the maximum, never average or latest', function()
    h.assertEqual(Wounds.worstTier({ 1, 3, 2 }), 3)
    h.assertEqual(Wounds.worstTier({}), nil)

    h.assertEqual(Wounds.worstOpenTier({ chest = 2, left_arm = 4, head = 1 }), 4)
    h.assertEqual(Wounds.worstOpenTier({}), nil)
end)

h.test('movementMultiplier reflects the worst open wound, and 1.0 when unhurt', function()
    h.assertEqual(Wounds.movementMultiplier({}), 1.0)

    local mult = Wounds.movementMultiplier({ chest = 4 })
    h.assertEqual(mult, Config.woundLevels[4].movementMultiplier)

    -- A minor tier-1 hand wound alongside a critical tier-4 chest wound must
    -- still report the tier-4 multiplier, not an average of the two.
    local mixedMult = Wounds.movementMultiplier({ chest = 4, left_hand = 1 })
    h.assertEqual(mixedMult, Config.woundLevels[4].movementMultiplier)
end)

h.test('bleedTickDamage indexes Config.bleed.damagePerSeverity by tier', function()
    for tier = 1, Wounds.MAX_TIER do
        h.assertEqual(Wounds.bleedTickDamage(tier), Config.bleed.damagePerSeverity[tier])
    end
end)

h.test('isBleeding is true iff there is at least one open wound', function()
    h.assertFalse(Wounds.isBleeding({}))
    h.assertTrue(Wounds.isBleeding({ chest = 1 }))
end)

h.test('canTreatWithTier: a tier requiring an IFAK cannot be closed by a bandage-level item', function()
    -- tier 3/4 have ifakRequired = true in Config.woundLevels
    h.assertFalse(Wounds.canTreatWithTier(3, 2))
    h.assertFalse(Wounds.canTreatWithTier(4, 2))
    h.assertTrue(Wounds.canTreatWithTier(3, 4))
    h.assertTrue(Wounds.canTreatWithTier(1, 2))
    h.assertTrue(Wounds.canTreatWithTier(2, 2))
end)

h.test('pickTreatableWound picks the MOST SEVERE wound the item can actually treat', function()
    -- A bandage (maxTier 2) can't touch the tier-4 wound, so it should pick
    -- the tier-2 one over the tier-1 one.
    local bodyPart, tier = Wounds.pickTreatableWound({ chest = 4, left_arm = 2, left_hand = 1 }, 2)
    h.assertEqual(bodyPart, 'left_arm')
    h.assertEqual(tier, 2)

    -- An IFAK (maxTier 4) can treat everything, so it should go straight for
    -- the worst wound.
    local ifakPart, ifakTier = Wounds.pickTreatableWound({ chest = 4, left_arm = 2, left_hand = 1 }, Wounds.MAX_TIER)
    h.assertEqual(ifakPart, 'chest')
    h.assertEqual(ifakTier, 4)

    local noPart, noTier = Wounds.pickTreatableWound({}, Wounds.MAX_TIER)
    h.assertEqual(noPart, nil)
    h.assertEqual(noTier, nil)
end)

h.report('wounds')
