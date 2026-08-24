-- Death smoke test -- the ALIVE/LASTSTAND/DEAD state machine (pure
-- transition table + the side-effecting wrappers) and the wound ledger's
-- bleeding/limping QB.status sync.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua') -- Death.respawnAtHospital calls Billing.chargeForRespawn

------------------------------------------------------------------------------
-- Pure FSM
------------------------------------------------------------------------------

h.test('transition: alive -> laststand on died, nothing else from alive', function()
    local next1, changed1 = Death.transition('alive', 'died')
    h.assertEqual(next1, 'laststand')
    h.assertTrue(changed1)

    local next2, changed2 = Death.transition('alive', 'revived')
    h.assertEqual(next2, 'alive')
    h.assertFalse(changed2)
end)

h.test('transition: laststand -> dead via bledOut or died, -> alive via revived', function()
    h.assertEqual((Death.transition('laststand', 'bledOut')), 'dead')
    h.assertEqual((Death.transition('laststand', 'died')), 'dead')
    h.assertEqual((Death.transition('laststand', 'revived')), 'alive')
end)

h.test('transition: dead -> alive via respawned or revived, nothing else', function()
    h.assertEqual((Death.transition('dead', 'respawned')), 'alive')
    h.assertEqual((Death.transition('dead', 'revived')), 'alive')
    local next3, changed3 = Death.transition('dead', 'died')
    h.assertEqual(next3, 'dead')
    h.assertFalse(changed3)
end)

------------------------------------------------------------------------------
-- Side-effecting wrappers
------------------------------------------------------------------------------

h.test('enterLaststand sets metadata, pushes the client event, and getState reflects it', function()
    handle.ensurePlayer(1)
    h.assertTrue(Death.enterLaststand(1, 'testing'))
    h.assertEqual(Death.getState(1), 'laststand')
    h.assertTrue(Death.isLaststand(1))

    local push = handle.lastClient('qbambulance:client:enterLaststand')
    h.assertTrue(push ~= nil)
    h.assertEqual(push.target, 1)
end)

h.test('enterLaststand is a no-op if already in laststand or dead', function()
    handle.ensurePlayer(2)
    h.assertTrue(Death.enterLaststand(2))
    h.assertFalse(Death.enterLaststand(2)) -- already laststand
end)

h.test('markDead transitions laststand -> dead and alive -> dead (skipping laststand)', function()
    handle.ensurePlayer(3)
    Death.enterLaststand(3)
    h.assertTrue(Death.markDead(3))
    h.assertTrue(Death.isDead(3))

    handle.ensurePlayer(4) -- starts alive
    h.assertTrue(Death.markDead(4))
    h.assertTrue(Death.isDead(4))
end)

h.test('reviveInField only works from laststand/dead, stops bleeding, does not clear wounds', function()
    handle.ensurePlayer(5)
    h.assertFalse(Death.reviveInField(5)) -- alive -- nothing to revive

    Death.enterLaststand(5)
    Death.recordWound(5, 'chest', 3)
    h.assertTrue(Wounds.isBleeding(Death.getWoundData(5)))

    h.assertTrue(Death.reviveInField(5, 30))
    h.assertTrue(Death.isAlive(5))
    h.assertFalse(handle.QB.status.isActive(5, 'bleeding'))
    -- Wound ledger itself is untouched -- only the visible bleeding status is cleared.
    h.assertEqual(Death.getWoundData(5).chest, 3)
end)

h.test('respawnAtHospital only works from dead, charges a bill, and fully clears wounds', function()
    handle.ensurePlayer(6)
    handle.players[6].money.cash = 1000

    h.assertFalse((Death.respawnAtHospital(6))) -- alive -- refused

    Death.markDead(6)
    Death.recordWound(6, 'chest', 2)

    local ok = Death.respawnAtHospital(6, Config.hospitals[1].name)
    h.assertTrue(ok)
    h.assertTrue(Death.isAlive(6))
    h.assertEqual(next(Death.getWoundData(6)), nil) -- wounds fully cleared
    h.assertTrue(handle.players[6].money.cash < 1000) -- billed

    local push = handle.lastClient('qbambulance:client:respawnedAtHospital')
    h.assertTrue(push ~= nil and push.target == 6)
end)

h.test('respawnAtHospital defaults to the first configured hospital for an unknown name', function()
    handle.ensurePlayer(7)
    Death.markDead(7)
    h.assertTrue(Death.respawnAtHospital(7, 'not-a-real-hospital'))
end)

------------------------------------------------------------------------------
-- Wound ledger -> QB.status sync
------------------------------------------------------------------------------

h.test('recordWound never downgrades an existing wound on the same body part', function()
    handle.ensurePlayer(8)
    Death.recordWound(8, 'chest', 3)
    Death.recordWound(8, 'chest', 1) -- weaker hit on the same part -- must not downgrade
    h.assertEqual(Death.getWoundData(8).chest, 3)

    Death.recordWound(8, 'chest', 4) -- worse hit -- must escalate
    h.assertEqual(Death.getWoundData(8).chest, 4)
end)

h.test('_syncStatus applies bleeding at the worst tier and limping only when that tier cannot walk', function()
    handle.ensurePlayer(9)
    Death.recordWound(9, 'left_hand', 1) -- tier 1: canWalk = true
    h.assertTrue(handle.QB.status.isActive(9, 'bleeding'))
    h.assertFalse(handle.QB.status.isActive(9, 'limping'))

    Death.recordWound(9, 'chest', 4) -- tier 4: canWalk = false
    h.assertTrue(handle.QB.status.isActive(9, 'limping'))
    h.assertEqual(handle.QB.status.applied[9].bleeding.severity, 4)
end)

h.test('clearWound / clearAllWounds remove the QB.status effects once no wound remains', function()
    handle.ensurePlayer(10)
    Death.recordWound(10, 'chest', 2)
    h.assertTrue(handle.QB.status.isActive(10, 'bleeding'))

    Death.clearWound(10, 'chest')
    h.assertFalse(handle.QB.status.isActive(10, 'bleeding'))

    Death.recordWound(10, 'chest', 4)
    Death.clearAllWounds(10)
    h.assertFalse(handle.QB.status.isActive(10, 'bleeding'))
    h.assertFalse(handle.QB.status.isActive(10, 'limping'))
    h.assertEqual(next(Death.getWoundData(10)), nil)
end)

------------------------------------------------------------------------------
-- baseevents wiring + bleed-out timeout
------------------------------------------------------------------------------

h.test('baseevents:onPlayerDied server-side transitions the reporting player into laststand', function()
    handle.ensurePlayer(11)
    handle.fireEvent('baseevents:onPlayerDied', 11, 1, { 0, 0, 0 })
    h.assertTrue(Death.isLaststand(11))
end)

h.test('qbambulance:server:reportWound validates body part/tier before recording', function()
    handle.ensurePlayer(12)
    local reportWound = handle.QB.events.registry['qbambulance:server:reportWound']
    h.assertTrue(reportWound ~= nil)

    reportWound(12, 'not_a_real_part', 2)
    h.assertEqual(next(Death.getWoundData(12)), nil)

    reportWound(12, 'chest', 99) -- out of range tier
    h.assertEqual(next(Death.getWoundData(12)), nil)

    reportWound(12, 'chest', 2)
    h.assertEqual(Death.getWoundData(12).chest, 2)
end)

h.report('death')
