-- Death smoke test -- the ALIVE/LASTSTAND/DEAD state machine (pure
-- transition table + the side-effecting wrappers) and the wound ledger's
-- bleeding/limping Kora.status sync.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua') -- Death.respawnAtHospital calls Billing.chargeForRespawn
dofile('server/duty.lua') -- compatibility duty aliases share its location policy
dofile('server/compat/hospital.lua')

-- Death's respawn gate is measured in os.time() SECONDS, so the only way to
-- test "after the wait" without actually sleeping a minute is to own the clock.
local now = 1000
os.time = function() return now end

local respawnWaitSeconds = math.floor(Config.death.respawnTime / 1000)

---Skips past Config.death.respawnTime so a respawn is no longer gated.
local function waitOutRespawn()
    now = now + respawnWaitSeconds
end

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

h.test('enterLaststand sets metadata, pushes the client event, and getState reflects it', function()
    handle.ensurePlayer(1)
    h.assertTrue(Death.enterLaststand(1, 'testing'))
    h.assertEqual(Death.getState(1), 'laststand')
    h.assertTrue(Death.isLaststand(1))

    local push = handle.lastClient('kora_ambulance:client:enterLaststand')
    h.assertTrue(push ~= nil)
    h.assertEqual(push.target, 1)
    h.assertEqual(handle.playerStates[1].emsDown, 'laststand')
    h.assertEqual(handle.players[1].metadata.kora_ambulanceMedical.laststandAt, now)
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
    h.assertEqual(handle.playerStates[3].emsDown, 'dead')

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
    h.assertEqual(handle.playerStates[5].emsDown, false)
    h.assertFalse(handle.Kora.status.isActive(5, 'bleeding'))
    -- Wound ledger itself is untouched -- only the visible bleeding status is cleared.
    h.assertEqual(Death.getWoundData(5).chest, 3)
end)

h.test('respawnAtHospital only works from dead, charges a bill, and fully clears wounds', function()
    handle.ensurePlayer(6)
    handle.players[6].money.cash = 1000
    handle.players[6].metadata.hunger = 10
    handle.players[6].metadata.thirst = 20

    h.assertFalse((Death.respawnAtHospital(6))) -- alive -- refused

    Death.markDead(6)
    Death.recordWound(6, 'chest', 2)
    waitOutRespawn()

    local ok = Death.respawnAtHospital(6, Config.hospitals[1].name)
    h.assertTrue(ok)
    h.assertTrue(Death.isAlive(6))
    h.assertEqual(next(Death.getWoundData(6)), nil) -- wounds fully cleared
    h.assertTrue(handle.players[6].money.cash < 1000) -- billed
    h.assertEqual(handle.players[6].metadata.hunger, 100)
    h.assertEqual(handle.players[6].metadata.thirst, 100)

    local push = handle.lastClient('kora_ambulance:client:respawnedAtHospital')
    h.assertTrue(push ~= nil and push.target == 6)
end)

h.test('respawnAtHospital defaults to the first configured hospital for an unknown name', function()
    handle.ensurePlayer(7)
    Death.markDead(7)
    waitOutRespawn()
    h.assertTrue(Death.respawnAtHospital(7, 'not-a-real-hospital'))
end)

-- Server-enforced respawn wait. The client countdown is display only, so
-- everything a bypassing player could skip has to be refused here.

h.test('respawnAtHospital refuses a freshly dead player and says how long is left', function()
    handle.ensurePlayer(20)
    handle.players[20].money.cash = 1000
    Death.markDead(20)

    local ok, reason = Death.respawnAtHospital(20)
    h.assertFalse(ok)
    h.assertEqual(reason, ('You cannot respawn for another %ds.'):format(respawnWaitSeconds))

    -- Refused BEFORE any of the respawn's side effects run -- a rejected
    -- attempt must not bill the player or quietly bring them back to life.
    h.assertTrue(Death.isDead(20))
    h.assertEqual(handle.players[20].money.cash, 1000)
end)

h.test('respawnAtHospital counts the wait down as the clock advances', function()
    handle.ensurePlayer(21)
    Death.markDead(21)
    h.assertEqual(Death.respawnWaitRemaining(21), respawnWaitSeconds)

    now = now + 10
    h.assertEqual(Death.respawnWaitRemaining(21), respawnWaitSeconds - 10)

    local _, reason = Death.respawnAtHospital(21)
    h.assertEqual(reason, ('You cannot respawn for another %ds.'):format(respawnWaitSeconds - 10))
end)

h.test('respawnAtHospital allows the respawn once the wait has elapsed', function()
    handle.ensurePlayer(22)
    Death.markDead(22)
    waitOutRespawn()

    h.assertEqual(Death.respawnWaitRemaining(22), 0)
    h.assertTrue((Death.respawnAtHospital(22)))
    h.assertTrue(Death.isAlive(22))
end)

h.test('respawnAtHospital refuses a laststand player outright -- the wait never even applies', function()
    handle.ensurePlayer(23)
    Death.enterLaststand(23)
    waitOutRespawn() -- plenty of time passes; still not a respawn candidate

    local ok, reason = Death.respawnAtHospital(23)
    h.assertFalse(ok)
    h.assertEqual(reason, 'You are not dead.')
    h.assertTrue(Death.isLaststand(23))
end)

h.test('legacy dead metadata without a medical timestamp remains immediately respawnable', function()
    handle.ensurePlayer(24)
    handle.players[24].metadata.isdead = true -- rejoined dead; the in-memory timestamp did not survive

    h.assertEqual(Death.respawnWaitRemaining(24), 0)
    h.assertTrue((Death.respawnAtHospital(24)))
end)

h.test('persisted dead timestamps survive a relog and continue the respawn deadline', function()
    local src = 26
    handle.ensurePlayer(src)
    Death.markDead(src)
    local persistedAt = handle.players[src].metadata.kora_ambulanceMedical.deadAt
    handle.fireEvent('playerDropped', src)

    now = now + 10
    handle.fireEvent('kora_core:server:playerLoaded', src, src)
    h.assertEqual(Death.respawnWaitRemaining(src), respawnWaitSeconds - 10)
    h.assertEqual(handle.players[src].metadata.kora_ambulanceMedical.deadAt, persistedAt)
    h.assertEqual(handle.playerStates[src].emsDown, 'dead')
end)

h.test('persisted wounds round-trip and exported snapshots are detached copies', function()
    local src = 27
    handle.ensurePlayer(src)
    Death.recordWound(src, 'left_arm', 3)
    local persisted = handle.players[src].metadata.kora_ambulanceMedical
    h.assertEqual(persisted.version, 1)
    h.assertEqual(persisted.wounds.left_arm, 3)

    handle.fireEvent('playerDropped', src)
    handle.fireEvent('kora_core:server:playerLoaded', src, src)
    h.assertEqual(Death.getWoundData(src).left_arm, 3)

    local snapshot = handle.exports.getPatientStatus(src)
    h.assertEqual(snapshot.state, 'alive')
    h.assertEqual(snapshot.wounds.left_arm, 3)
    snapshot.wounds.left_arm = 1
    h.assertEqual(Death.getWoundData(src).left_arm, 3)
end)

h.test('player load sanitizes malformed medical data and promotes elapsed laststand', function()
    local src = 28
    local player = handle.ensurePlayer(src)
    player.metadata.inlaststand = true
    local deathSeconds = math.floor(Config.death.deathTime / 1000)
    local startedAt = now - deathSeconds - 10
    player.metadata.kora_ambulanceMedical = {
        version = 1,
        wounds = { chest = 3, invented = 4, left_hand = 1.5 },
        laststandAt = startedAt,
        deadAt = now + 100,
        injected = true,
    }

    handle.fireEvent('kora_core:server:playerLoaded', src, src)
    h.assertTrue(Death.isDead(src))
    h.assertEqual(Death.getWoundData(src).chest, 3)
    h.assertEqual(Death.getWoundData(src).invented, nil)
    local clean = player.metadata.kora_ambulanceMedical
    h.assertEqual(clean.version, 1)
    h.assertEqual(clean.laststandAt, nil)
    h.assertEqual(clean.deadAt, startedAt + deathSeconds)
    h.assertEqual(clean.injected, nil)
    h.assertEqual(handle.playerStates[src].emsDown, 'dead')
    h.assertEqual(Death.respawnWaitRemaining(src), respawnWaitSeconds - 10)
end)

h.test('a revive clears the death timestamp so a later death starts a fresh wait', function()
    handle.ensurePlayer(25)
    Death.markDead(25)
    Death.reviveInField(25)
    h.assertEqual(Death.respawnWaitRemaining(25), 0)

    Death.markDead(25)
    h.assertEqual(Death.respawnWaitRemaining(25), respawnWaitSeconds)
end)

h.test('recordWound never downgrades an existing wound on the same body part', function()
    handle.ensurePlayer(8)
    Death.recordWound(8, 'chest', 3)
    Death.recordWound(8, 'chest', 1) -- weaker hit on the same part -- must not downgrade
    h.assertEqual(Death.getWoundData(8).chest, 3)

    Death.recordWound(8, 'chest', 4) -- worse hit -- must escalate
    h.assertEqual(Death.getWoundData(8).chest, 4)
end)

h.test('recordWound rejects invalid compatibility input before status sync', function()
    handle.ensurePlayer(13)
    Death.recordWound(13, 'chest', 99)
    Death.recordWound(13, 'not_a_real_part', 2)
    h.assertEqual(next(Death.getWoundData(13)), nil)
    h.assertFalse(handle.Kora.status.isActive(13, 'bleeding'))
end)

h.test('_syncStatus applies bleeding at the worst tier and limping only when that tier cannot walk', function()
    handle.ensurePlayer(9)
    Death.recordWound(9, 'left_hand', 1) -- tier 1: canWalk = true
    h.assertTrue(handle.Kora.status.isActive(9, 'bleeding'))
    h.assertFalse(handle.Kora.status.isActive(9, 'limping'))

    Death.recordWound(9, 'chest', 4) -- tier 4: canWalk = false
    h.assertTrue(handle.Kora.status.isActive(9, 'limping'))
    h.assertEqual(handle.Kora.status.applied[9].bleeding.severity, 4)
end)

h.test('clearWound / clearAllWounds remove the Kora.status effects once no wound remains', function()
    handle.ensurePlayer(10)
    Death.recordWound(10, 'chest', 2)
    h.assertTrue(handle.Kora.status.isActive(10, 'bleeding'))

    Death.clearWound(10, 'chest')
    h.assertFalse(handle.Kora.status.isActive(10, 'bleeding'))

    Death.recordWound(10, 'chest', 4)
    Death.clearAllWounds(10)
    h.assertFalse(handle.Kora.status.isActive(10, 'bleeding'))
    h.assertFalse(handle.Kora.status.isActive(10, 'limping'))
    h.assertEqual(next(Death.getWoundData(10)), nil)
end)

h.test('kora_ambulance:server:reportDeath rejects an alive server ped', function()
    handle.ensurePlayer(11)
    local reportDeath = handle.Kora.callback.registry['kora_ambulance:server:reportDeath']
    h.assertTrue(reportDeath ~= nil)
    h.assertFalse(reportDeath(11, 'died'))
    h.assertTrue(Death.isAlive(11))
end)

h.test('kora_ambulance:server:reportDeath transitions a corroborated dead ped into laststand', function()
    handle.ensurePlayer(14)
    handle.setHealth(14, 0)
    local reportDeath = handle.Kora.callback.registry['kora_ambulance:server:reportDeath']
    h.assertTrue(reportDeath(14, 'died'))
    h.assertTrue(Death.isLaststand(14))
    handle.setHealth(14, 200)
    h.assertTrue(reportDeath(14, 'duplicate')) -- acknowledgement is idempotent once accepted
end)

h.test('public resetHungerThirst compatibility event cannot refill needs', function()
    handle.ensurePlayer(15)
    handle.players[15].metadata.hunger = 17
    handle.players[15].metadata.thirst = 23

    handle.fireEvent('hospital:server:resetHungerThirst', 15)

    h.assertEqual(handle.players[15].metadata.hunger, 17)
    h.assertEqual(handle.players[15].metadata.thirst, 23)
end)

h.test('legacy doctor duty aliases require the EMS job and a hospital duty point', function()
    local src = 18
    handle.ensurePlayer(src)
    local duty = Config.hospitals[1].duty
    handle.setCoords(src, duty.x, duty.y, duty.z)
    handle.fireEvent('hospital:server:AddDoctor', src)
    h.assertFalse(handle.players[src].job.onduty, 'a civilian cannot use the doctor alias')

    handle.players[src].job = { name = Config.job.name, onduty = false, grade = { level = 1 } }
    handle.setCoords(src, 0, 0, 0)
    handle.fireEvent('hospital:server:AddDoctor', src)
    h.assertFalse(handle.players[src].job.onduty, 'remote EMS cannot use the doctor alias')

    handle.setCoords(src, duty.x, duty.y, duty.z)
    handle.fireEvent('hospital:server:AddDoctor', src)
    h.assertTrue(handle.players[src].job.onduty)

    handle.setCoords(src, 0, 0, 0)
    handle.fireEvent('hospital:server:RemoveDoctor', src)
    h.assertTrue(handle.players[src].job.onduty, 'remote off-duty requests are denied too')
end)

h.test('legacy ambulance alert requires a downed reporter and ignores its payload', function()
    handle.ensurePlayer(16)
    local before = #handle.dispatchCalls
    handle.fireEvent('hospital:server:ambulanceAlert', 16, 'forged emergency', { x = 9999, y = 9999, z = 0 })
    h.assertEqual(#handle.dispatchCalls, before, 'an alive player cannot create the call')

    Death.markDead(16)
    handle.setCoords(16, 123.0, 456.0, 20.0)
    handle.fireEvent('hospital:server:ambulanceAlert', 16, 'forged emergency', { x = 9999, y = 9999, z = 0 })

    local call = handle.lastDispatchCall()
    h.assertEqual(call.title, 'Medical Emergency', 'registered presentation wins')
    h.assertEqual(call.coords.x, 123.0, 'coordinates come from the reporter ped')
end)

h.test('legacy doctor alert is accepted only at a configured hospital', function()
    handle.ensurePlayer(17)
    handle.setCoords(17, 0.0, 0.0, 0.0)
    local before = #handle.dispatchCalls
    handle.fireEvent('hospital:server:SendDoctorAlert', 17)
    h.assertEqual(#handle.dispatchCalls, before, 'a remote caller is refused')

    local hospital = Config.hospitals[1]
    handle.setCoords(17, hospital.coords.x, hospital.coords.y, hospital.coords.z)
    handle.fireEvent('hospital:server:SendDoctorAlert', 17)
    h.assertEqual(handle.lastDispatchCall().title, 'Doctor Requested', 'a nearby caller raises the fixed alert')
end)

h.test('the legacy client-selected wound tier route is inaccessible', function()
    h.assertEqual(handle.Kora.events.registry['kora_ambulance:server:reportWound'], nil)
end)

h.test('hitObserved validates measurements, remaps known bones, and derives severity', function()
    local src = 12
    handle.ensurePlayer(src)
    handle.setHealth(src, 180)
    local observed = handle.Kora.events.registry['kora_ambulance:server:hitObserved']
    h.assertTrue(observed ~= nil)

    observed(src, nil)
    observed(src, { sequence = 1, bone = 31086, bodyPart = 'head', damage = 0 / 0, healthAfter = 180, fallback = false })
    observed(src, { sequence = 1, bone = 31086, bodyPart = 'head', damage = 8, healthAfter = 150, fallback = false })
    h.assertEqual(next(Death.getWoundData(src)), nil)

    -- The claimed bodyPart is not authoritative for a recognized bone.
    observed(src, { sequence = 1, bone = 31086, bodyPart = 'right_foot', damage = 8, healthAfter = 175, fallback = false })
    h.assertEqual(Death.getWoundData(src).head, 3)
    h.assertEqual(Death.getWoundData(src).right_foot, nil)
end)

h.test('hitObserved accepts fallback only for a missing or unmapped bone', function()
    local observed = handle.Kora.events.registry['kora_ambulance:server:hitObserved']

    handle.ensurePlayer(29)
    handle.setHealth(29, 190)
    observed(29, { sequence = 1, bone = false, bodyPart = 'left_leg', damage = 10, healthAfter = 190, fallback = true })
    h.assertEqual(Death.getWoundData(29).left_leg, 2)

    handle.ensurePlayer(30)
    handle.setHealth(30, 190)
    observed(30, { sequence = 1, bone = 65535, bodyPart = 'right_arm', damage = 10, healthAfter = 190, fallback = false })
    h.assertEqual(next(Death.getWoundData(30)), nil)
    observed(30, { sequence = 2, bone = 31086, bodyPart = 'right_arm', damage = 10, healthAfter = 190, fallback = true })
    h.assertEqual(next(Death.getWoundData(30)), nil)
    observed(30, { sequence = 3, bone = 65535, bodyPart = 'right_arm', damage = 10, healthAfter = 190, fallback = true })
    h.assertEqual(Death.getWoundData(30).right_arm, 2)
end)

h.test('hitObserved burns replayed and cooldown-rejected sequences', function()
    local src = 31
    handle.ensurePlayer(src)
    handle.setHealth(src, 180)
    local observed = handle.Kora.events.registry['kora_ambulance:server:hitObserved']

    observed(src, { sequence = 10, bone = 18905, bodyPart = 'left_hand', damage = 20, healthAfter = 180, fallback = false })
    h.assertEqual(Death.getWoundData(src).left_hand, 3)
    handle.advanceTime(Config.injuries.reportCooldown + 1)
    observed(src, { sequence = 10, bone = 31086, bodyPart = 'head', damage = 40, healthAfter = 180, fallback = false })
    h.assertEqual(Death.getWoundData(src).head, nil)

    observed(src, { sequence = 11, bone = 57005, bodyPart = 'right_hand', damage = 40, healthAfter = 180, fallback = false })
    h.assertEqual(Death.getWoundData(src).right_hand, 4)
    observed(src, { sequence = 12, bone = 52301, bodyPart = 'right_foot', damage = 40, healthAfter = 180, fallback = false })
    h.assertEqual(Death.getWoundData(src).right_foot, nil)
    handle.advanceTime(Config.injuries.reportCooldown + 1)
    observed(src, { sequence = 12, bone = 52301, bodyPart = 'right_foot', damage = 40, healthAfter = 180, fallback = false })
    h.assertEqual(Death.getWoundData(src).right_foot, nil)
end)

-- Config.death.respawn: inventory wipe and the medic gate (both default off).
local blockPushes = {} -- src -> last kora_ambulance:client:respawnBlock value
local baseTriggerClientEvent = _G.TriggerClientEvent
_G.TriggerClientEvent = function(name, target, ...)
    if name == 'kora_ambulance:client:respawnBlock' then blockPushes[target] = (...) end
    return baseTriggerClientEvent(name, target, ...)
end

local function medic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = 'ambulance', onduty = true, grade = { level = 1 } }
end

h.test('respawn leaves the inventory alone by default and wipes it, keeping the keep-list, when configured', function()
    local calls = {}
    handle.kora_inventory.clearInventory = function(_, src, keep) calls[#calls + 1] = { src = src, keep = keep }; return true end

    handle.ensurePlayer(30); Death.markDead(30); waitOutRespawn()
    h.assertTrue(Death.respawnAtHospital(30))
    h.assertEqual(#calls, 0, 'default off')

    Config.death.respawn.clearInventory = true
    Config.death.respawn.keepItems = { 'phone' }
    handle.ensurePlayer(31); Death.markDead(31); waitOutRespawn()
    h.assertTrue(Death.respawnAtHospital(31))
    h.assertEqual(#calls, 1)
    h.assertEqual(calls[1].src, 31)
    h.assertEqual(calls[1].keep[1], 'phone')

    handle.ensurePlayer(32)
    h.assertFalse((Death.respawnAtHospital(32)), 'a living player is refused before anything is wiped')
    h.assertEqual(#calls, 1)
    Config.death.respawn.clearInventory = false
    Config.death.respawn.keepItems = {}
end)

h.test('respawnTime = 0 allows an immediate respawn', function()
    local saved = Config.death.respawnTime
    Config.death.respawnTime = 0
    handle.ensurePlayer(33); Death.markDead(33)
    h.assertEqual(Death.respawnWaitRemaining(33), 0)
    h.assertTrue(Death.respawnAtHospital(33))
    Config.death.respawnTime = saved
end)

h.test('blockWhenMedics is off by default and never refuses', function()
    h.assertFalse(Config.death.respawn.blockWhenMedics.enabled)
    for i = 40, 45 do medic(i) end
    handle.ensurePlayer(46); Death.markDead(46); waitOutRespawn()
    h.assertTrue(Death.respawnAtHospital(46))
    for i = 40, 45 do handle.players[i].job.onduty = false end
end)

h.test('blockWhenMedics refuses /respawn while minOnDuty medics are on duty and re-enables when they drop', function()
    local block = Config.death.respawn.blockWhenMedics
    for _, player in pairs(handle.players) do player.job.onduty = false end -- earlier tests leave medics on duty
    block.enabled = true; block.minOnDuty = 2
    medic(50); medic(51)
    handle.ensurePlayer(52); Death.markDead(52); waitOutRespawn()

    h.assertEqual(blockPushes[52], 2, 'client told respawn is disabled')

    local ok, reason = Death.respawnAtHospital(52)
    h.assertFalse(ok)
    h.assertEqual(reason, 'Respawn is disabled while 2 or more medics are on duty.')
    h.assertTrue(Death.isDead(52), 'still dead')

    handle.players[51].job.onduty = false
    Death._sweep()
    h.assertEqual(blockPushes[52], false, 'sweep re-enables the client prompt')
    h.assertTrue(Death.respawnAtHospital(52))

    -- an off-duty or other-job player does not count, and neither does the dead player
    handle.players[50].job.onduty = true; handle.players[51].job.onduty = false
    handle.ensurePlayer(53); handle.players[53].job = { name = 'police', onduty = true, grade = { level = 1 } }
    h.assertEqual(Death.medicsOnDuty(50), 0)
    h.assertEqual(Death.medicsOnDuty(99), 1)
    block.enabled = false; block.minOnDuty = 3
    handle.players[50].job.onduty = false
end)

h.report('death')
