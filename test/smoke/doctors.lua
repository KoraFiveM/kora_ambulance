-- Doctors smoke test -- onDutyCount, the shouldSelfHeal/cooldownElapsed gates,
-- and the trySelfHeal integration against Death's laststand timer.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/doctors.lua')

h.test('onDutyCount only counts on-duty ambulance employees at or above onDutyDoctorGrade', function()
    handle.ensurePlayer(1); handle.players[1].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.ensurePlayer(2); handle.players[2].job = { name = Config.job.name, onduty = false, grade = { level = 3 } } -- off duty
    handle.ensurePlayer(3); handle.players[3].job = { name = 'police', onduty = true, grade = { level = 1 } } -- wrong job
    handle.ensurePlayer(4); handle.players[4].job = { name = Config.job.name, onduty = true, grade = { level = Config.job.onDutyDoctorGrade } }

    h.assertEqual(Doctors.onDutyCount(), 2) -- players 1 and 4
end)

h.test('shouldSelfHeal is true only below the configured minimum', function()
    h.assertTrue(Doctors.shouldSelfHeal(Config.doctors.minimalDoctors - 1))
    h.assertFalse(Doctors.shouldSelfHeal(Config.doctors.minimalDoctors))
    h.assertFalse(Doctors.shouldSelfHeal(Config.doctors.minimalDoctors + 5))
end)

h.test('cooldownElapsed: nil lastHealAt is always eligible; otherwise gated by docCooldown', function()
    h.assertTrue(Doctors.cooldownElapsed(1000, nil))

    local cooldownSeconds = math.floor(Config.doctors.docCooldown / 1000)
    h.assertFalse(Doctors.cooldownElapsed(1000, 1000 - 1)) -- essentially "just healed"
    h.assertTrue(Doctors.cooldownElapsed(1000 + cooldownSeconds, 1000))
end)

h.test('trySelfHeal refuses a player who is not in laststand', function()
    handle.ensurePlayer(10)
    h.assertFalse(Doctors.trySelfHeal(10))
end)

h.test('trySelfHeal refuses before selfHealDelay has elapsed since going down', function()
    handle.ensurePlayer(11)
    Death.enterLaststand(11)
    h.assertFalse(Doctors.trySelfHeal(11)) -- laststandElapsed() is ~0, selfHealDelay has not passed
end)

h.test('trySelfHeal revives once selfHealDelay has elapsed, and re-applies its own docCooldown', function()
    handle.ensurePlayer(12)

    local fakeNow = os.time()
    local realTime = os.time
    os.time = function() return fakeNow end

    Death.enterLaststand(12) -- records laststandAt at fakeNow

    fakeNow = fakeNow + math.floor(Config.doctors.selfHealDelay / 1000) + 1
    h.assertTrue(Doctors.trySelfHeal(12))
    h.assertTrue(Death.isAlive(12))

    -- Immediately trying again on a (newly re-downed) player within
    -- docCooldown of the last AI heal must be refused by the cooldown gate.
    Death.enterLaststand(12)
    fakeNow = fakeNow + math.floor(Config.doctors.selfHealDelay / 1000) + 1
    h.assertFalse(Doctors.trySelfHeal(12))

    os.time = realTime
end)

h.report('doctors')
