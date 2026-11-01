-- Revive/status smoke test -- every revive path against the wound ledger, the
-- bleeding/limping Kora.status pills and the client sync push, under both
-- Config.revive options.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/hospital.lua')
dofile('server/doctors.lua')
dofile('server/revive.lua')

local status = handle.Kora.status
local nextSrc = 100

---A downed player with a tier-4 chest wound (bleeding AND limping).
local function downedPatient()
    nextSrc = nextSrc + 1
    local src = nextSrc
    handle.ensurePlayer(src)
    Death.recordWound(src, 'chest', 4)
    Death.enterLaststand(src)
    return src
end

local function lastSync(src)
    for i = #handle.clientEvents, 1, -1 do
        local event = handle.clientEvents[i]
        if event.name == 'qbambulance:client:syncStatus' and event.target == src then return event.args end
    end
end

local function withRevive(options, fn)
    local saved = { clearBleeding = Config.revive.clearBleeding, clearWounds = Config.revive.clearWounds }
    for key, value in pairs(options) do Config.revive[key] = value end
    local ok, err = pcall(fn)
    Config.revive.clearBleeding, Config.revive.clearWounds = saved.clearBleeding, saved.clearWounds
    if not ok then error(err, 0) end
end

local function makeMedic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.players[src].items.defibrillator = 1
end

h.test('config ships bleeding cleared and wounds kept, and validates both as booleans', function()
    h.assertTrue(Config.revive.clearBleeding)
    h.assertFalse(Config.revive.clearWounds)
    h.assertTrue(Config.validate())
    withRevive({ clearBleeding = 'yes' }, function() h.assertThrows(Config.validate) end)
    withRevive({ clearWounds = 1 }, function() h.assertThrows(Config.validate) end)
end)

h.test('default revive stops the bleeding pill and bleed gate but keeps the wound and limp', function()
    local src = downedPatient()
    h.assertTrue(status.isActive(src, 'bleeding'))
    h.assertTrue(Death.isBleeding(src))

    h.assertTrue(Death.reviveInField(src, 20))

    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertFalse(Death.isBleeding(src))
    h.assertEqual(Death.getWoundData(src).chest, 4)
    h.assertTrue(status.isActive(src, 'limping'))
    local sync = lastSync(src)
    h.assertEqual(sync[1], false, 'client is told bleeding ended')
    h.assertEqual(sync[2], 4, 'client is told the limp remains')
end)

h.test('a revive that stopped the bleeding does not revive it on later wound-ledger changes', function()
    local src = downedPatient()
    Death.recordWound(src, 'left_leg', 2)
    Death.reviveInField(src, 20)

    Death.clearWound(src, 'left_leg') -- _syncStatus runs again
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertFalse(Death.isBleeding(src))
end)

h.test('a new or worse wound after the revive bleeds again', function()
    local src = downedPatient()
    Death.reviveInField(src, 20)
    h.assertFalse(Death.isBleeding(src))

    Death.recordWound(src, 'head', 1)
    h.assertTrue(Death.isBleeding(src))
    h.assertTrue(status.isActive(src, 'bleeding'))
    h.assertEqual(lastSync(src)[1], 4)
end)

h.test('clearWounds closes every wound and ends both pills', function()
    withRevive({ clearWounds = true }, function()
        local src = downedPatient()
        h.assertTrue(Death.reviveInField(src, 20))
        h.assertEqual(next(Death.getWoundData(src)), nil)
        h.assertFalse(status.isActive(src, 'bleeding'))
        h.assertFalse(status.isActive(src, 'limping'))
        h.assertFalse(Death.isBleeding(src))
        h.assertEqual(lastSync(src)[1], false)
        h.assertEqual(lastSync(src)[2], false)
    end)
end)

h.test('clearBleeding=false leaves bleeding in place but still pushes the real state', function()
    withRevive({ clearBleeding = false }, function()
        local src = downedPatient()
        h.assertTrue(Death.reviveInField(src, 20))
        h.assertTrue(status.isActive(src, 'bleeding'))
        h.assertTrue(Death.isBleeding(src))
        h.assertEqual(lastSync(src)[1], 4)
    end)
end)

h.test('clearWounds wins over clearBleeding=false', function()
    withRevive({ clearBleeding = false, clearWounds = true }, function()
        local src = downedPatient()
        Death.reviveInField(src, 20)
        h.assertEqual(next(Death.getWoundData(src)), nil)
        h.assertFalse(status.isActive(src, 'bleeding'))
    end)
end)

h.test('a revive from the dead state clears bleeding the same way', function()
    local src = downedPatient()
    Death.markDead(src)
    h.assertTrue(Death.reviveInField(src, 20))
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertTrue(Death.isAlive(src))
end)

h.test('CPR/defibrillator revive honours both options', function()
    local medic = 200; makeMedic(medic)
    local patient = downedPatient()
    local ok = Revive.complete(medic, patient, true)
    h.assertTrue(ok)
    h.assertFalse(status.isActive(patient, 'bleeding'))
    h.assertEqual(Death.getWoundData(patient).chest, 4)

    withRevive({ clearWounds = true }, function()
        local medic2 = 201; makeMedic(medic2)
        local patient2 = downedPatient()
        h.assertTrue(Revive.complete(medic2, patient2, true))
        h.assertEqual(next(Death.getWoundData(patient2)), nil)
        h.assertFalse(status.isActive(patient2, 'limping'))
    end)
end)

h.test('self-heal AI revive honours both options', function()
    local src = downedPatient()
    handle.advanceTime(0)
    local saved = Config.doctors.selfHealDelay
    Config.doctors.selfHealEnabled = true
    Config.doctors.selfHealDelay = 0
    h.assertTrue(Doctors.trySelfHeal(src))
    Config.doctors.selfHealDelay = saved
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertTrue(status.isActive(src, 'limping'))

    withRevive({ clearWounds = true }, function()
        local other = downedPatient()
        Config.doctors.selfHealDelay = 0
        h.assertTrue(Doctors.trySelfHeal(other))
        Config.doctors.selfHealDelay = saved
        h.assertFalse(status.isActive(other, 'limping'))
        h.assertEqual(next(Death.getWoundData(other)), nil)
    end)
    Config.doctors.selfHealEnabled = false
end)

h.test('hospital check-in revive clears everything even with both options off', function()
    withRevive({ clearBleeding = false, clearWounds = false }, function()
        local hospital = Config.hospitals[1]
        local src = downedPatient()
        local point = hospital.checkIn or hospital.coords
        handle.setCoords(src, point.x, point.y, point.z)
        handle.players[src].money.cash = 1000
        local care = Hospital.requestCheckIn(src, hospital.name)
        h.assertTrue(care ~= nil and care ~= false, 'check-in must be accepted')
        local bed = hospital.beds[care.bedIndex]
        handle.setCoords(src, bed.x, bed.y, bed.z)
        handle.advanceTime(Config.hospitalCare.duration + 1)

        h.assertTrue(Hospital.completeBedCare(src, care.token))
        h.assertTrue(Death.isAlive(src))
        h.assertEqual(next(Death.getWoundData(src)), nil)
        h.assertFalse(status.isActive(src, 'bleeding'))
        h.assertFalse(status.isActive(src, 'limping'))
        h.assertEqual(lastSync(src)[1], false)
        h.assertEqual(lastSync(src)[2], false)
    end)
end)

h.test('respawn at a hospital clears wounds, pills and a stopped-bleed flag', function()
    local src = downedPatient()
    Death.reviveInField(src, 20) -- bleeding stopped, wound kept
    Death.recordWound(src, 'head', 2)
    Death.enterLaststand(src)
    Death.markDead(src)
    local saved = Config.death.respawnTime
    Config.death.respawnTime = 0
    handle.players[src].money.cash = 1000
    local ok = Death.respawnAtHospital(src)
    Config.death.respawnTime = saved

    h.assertTrue(ok)
    h.assertEqual(next(Death.getWoundData(src)), nil)
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertFalse(status.isActive(src, 'limping'))
    h.assertEqual(lastSync(src)[1], false)
end)

h.test('fullRevive (admin) ignores Config.revive and clears every wound', function()
    local src = downedPatient()
    h.assertTrue(Death.fullRevive(src))
    h.assertTrue(Death.isAlive(src))
    h.assertEqual(next(Death.getWoundData(src)), nil)
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertFalse(status.isActive(src, 'limping'))
    h.assertEqual(handle.lastClient('qbambulance:client:revived').target, src)
end)

h.test('fullRevive is exported for admin tools', function()
    h.assertTrue(type(handle.exports.fullRevive) == 'function')
    local src = downedPatient()
    h.assertTrue(handle.exports.fullRevive(src))
    h.assertEqual(next(Death.getWoundData(src)), nil)
end)

h.test('an external revive that only flips the metadata is reconciled by the sweep', function()
    local src = downedPatient()
    -- What kora_admin /revive does server-side: metadata only.
    handle.players[src].metadata.isdead = false
    handle.players[src].metadata.inlaststand = false
    h.assertTrue(status.isActive(src, 'bleeding'), 'stale until reconciled')

    Death._sweep()

    h.assertEqual(next(Death.getWoundData(src)), nil)
    h.assertFalse(status.isActive(src, 'bleeding'))
    h.assertFalse(status.isActive(src, 'limping'))
    h.assertEqual(lastSync(src)[1], false)
    -- ...and the bleed-out clock must no longer be able to kill them.
    local saved = Config.death.deathTime
    Config.death.deathTime = 0
    Death._sweep()
    Config.death.deathTime = saved
    h.assertTrue(Death.isAlive(src))
end)

h.test('a stopped bleed survives a relog and a rewound ledger does not resurrect the pill', function()
    local src = downedPatient()
    Death.reviveInField(src, 20)
    local saved = handle.players[src].metadata.qbambulanceMedical
    h.assertTrue(saved.bleedStopped)

    handle.fireEvent('playerDropped', src)
    handle.fireEvent('qbcore:server:playerLoaded', src, src)

    h.assertEqual(Death.getWoundData(src).chest, 4)
    h.assertFalse(Death.isBleeding(src))
    h.assertFalse(status.isActive(src, 'bleeding'))
end)

h.test('the bleed gate and the bare wound ledger disagree after a bleed-stopping revive', function()
    local src = downedPatient()
    Death.reviveInField(src, 20)
    h.assertFalse(Death.isBleeding(src))
    h.assertTrue(Wounds.isBleeding(Death.getWoundData(src)), 'ledger still has the open wound')
end)

h.report('revive_status')
