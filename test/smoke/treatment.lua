-- EMS patient assessment/treatment smoke tests: server-authoritative job,
-- proximity, supply selection, action timing and wound mutation.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/treatment.lua')

local function makeMedic(src, supplies)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    for item, count in pairs(supplies or {}) do handle.players[src].items[item] = count end
end

h.test('assessment returns a stable head-to-toe wound summary', function()
    makeMedic(1)
    handle.ensurePlayer(2)
    Death.recordWound(2, 'right_leg', 2)
    Death.recordWound(2, 'head', 4)

    local report = handle.QB.callback.registry['qbambulance:server:assessPatient'](1, 2)
    h.assertEqual(report.state, 'alive')
    h.assertEqual(#report.wounds, 2)
    h.assertEqual(report.wounds[1].bodyPart, 'head')
    h.assertEqual(report.wounds[1].severityLabel, 'Critical')
    h.assertEqual(report.wounds[2].bodyPart, 'right_leg')
end)

h.test('assessment requires an on-duty nearby medic', function()
    handle.ensurePlayer(3)
    handle.ensurePlayer(4)
    local report, reason = handle.QB.callback.registry['qbambulance:server:assessPatient'](3, 4)
    h.assertTrue(report == nil)
    h.assertTrue(reason ~= nil)

    makeMedic(5)
    handle.ensurePlayer(6)
    handle.setCoords(6, Config.treatment.range + 1, 0, 0)
    report, reason = handle.QB.callback.registry['qbambulance:server:assessPatient'](5, 6)
    h.assertTrue(report == nil)
    h.assertTrue(reason ~= nil)
end)

h.test('minor treatment prefers a bandage and consumes exactly one', function()
    makeMedic(7, { bandage = 2, ifak = 1 })
    handle.ensurePlayer(8)
    Death.recordWound(8, 'left_arm', 2)

    local token = Treatment.begin(7, 8)
    h.assertTrue(token ~= nil)
    handle.advanceTime(Config.treatment.duration)
    local treated = Treatment.complete(7, 8, token, true)

    h.assertTrue(treated)
    h.assertTrue(Death.getWoundData(8).left_arm == nil)
    h.assertEqual(handle.players[7].items.bandage, 1)
    h.assertEqual(handle.players[7].items.ifak, 1)
end)

h.test('critical treatment chooses an IFAK before lesser bandage work', function()
    makeMedic(9, { bandage = 1, ifak = 1 })
    handle.ensurePlayer(10)
    Death.recordWound(10, 'left_hand', 1)
    Death.recordWound(10, 'chest', 4)

    local token = Treatment.begin(9, 10)
    handle.advanceTime(Config.treatment.duration)
    h.assertTrue(Treatment.complete(9, 10, token, true))
    h.assertTrue(Death.getWoundData(10).chest == nil)
    h.assertEqual(Death.getWoundData(10).left_hand, 1)
    h.assertEqual(handle.players[9].items.ifak, 0)
    h.assertEqual(handle.players[9].items.bandage, 1)
end)

h.test('a cancelled treatment releases the patient and consumes nothing', function()
    makeMedic(11, { bandage = 1 })
    makeMedic(12, { bandage = 1 })
    handle.ensurePlayer(13)
    Death.recordWound(13, 'right_arm', 1)

    local token = Treatment.begin(11, 13)
    h.assertTrue(token ~= nil)
    h.assertFalse(Treatment.complete(11, 13, token, false))
    h.assertEqual(handle.players[11].items.bandage, 1)

    local secondToken = Treatment.begin(12, 13)
    h.assertTrue(secondToken ~= nil, 'the patient lock should be released on cancellation')
end)

h.test('treatment cannot be completed before its kora_lib action duration', function()
    makeMedic(14, { bandage = 1 })
    handle.ensurePlayer(15)
    Death.recordWound(15, 'left_foot', 1)

    local token = Treatment.begin(14, 15)
    local treated, reason = Treatment.complete(14, 15, token, true)
    h.assertFalse(treated)
    h.assertTrue(reason ~= nil)
    h.assertEqual(handle.players[14].items.bandage, 1)
    h.assertEqual(Death.getWoundData(15).left_foot, 1)
end)

h.test('treatment revalidates distance before consuming supplies', function()
    makeMedic(16, { ifak = 1 })
    handle.ensurePlayer(17)
    Death.recordWound(17, 'abdomen', 3)

    local token = Treatment.begin(16, 17)
    handle.advanceTime(Config.treatment.duration)
    handle.setCoords(17, Config.treatment.range + 1, 0, 0)
    local treated = Treatment.complete(16, 17, token, true)
    h.assertFalse(treated)
    h.assertEqual(handle.players[16].items.ifak, 1)
    h.assertEqual(Death.getWoundData(17).abdomen, 3)
end)

h.report('treatment')
