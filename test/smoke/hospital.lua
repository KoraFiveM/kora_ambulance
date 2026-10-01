-- Hospital check-in smoke test -- beds, session tokens, proximity, cleanup,
-- and the successful-care-only billing boundary.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/hospital.lua')

local hospital = Config.hospitals[1]
SetEntityHealth = nil -- unavailable on the server

local function placeAtCheckIn(src)
    handle.ensurePlayer(src)
    local point = hospital.checkIn or hospital.coords
    handle.setCoords(src, point.x, point.y, point.z)
end

local function placeAtBed(src, index)
    local bed = hospital.beds[index]
    handle.setCoords(src, bed.x, bed.y, bed.z)
end

local function injure(src)
    Death.recordWound(src, 'chest', 2)
end

h.test('check-in reserves the lowest available bed through its callback', function()
    placeAtCheckIn(1); injure(1)
    local care = handle.QB.callback.registry['qbambulance:server:checkInRequested'](1, hospital.name)
    h.assertEqual(care.bedIndex, 1)
    h.assertEqual(care.hospital, hospital.name)
    h.assertTrue(type(care.token) == 'string')
    h.assertEqual(Hospital.getSession(1).token, care.token)
    handle.QB.events.registry['qbambulance:server:bedLeft'](1, care.token)
end)

h.test('check-in rejects remote, healthy, dead, duplicate, and full requests', function()
    handle.ensurePlayer(2); injure(2)
    local remote = Hospital.requestCheckIn(2, hospital.name)
    h.assertFalse(remote)

    placeAtCheckIn(3)
    local healthy = Hospital.requestCheckIn(3, hospital.name)
    h.assertFalse(healthy)

    placeAtCheckIn(4); injure(4); Death.markDead(4)
    local dead = Hospital.requestCheckIn(4, hospital.name)
    h.assertFalse(dead)

    placeAtCheckIn(5); injure(5)
    local first = Hospital.requestCheckIn(5, hospital.name)
    local duplicate = Hospital.requestCheckIn(5, hospital.name)
    h.assertTrue(first ~= false)
    h.assertFalse(duplicate)
    Hospital.leaveBed(5, first.token)

    local sessions = {}
    for src = 6, 8 do
        placeAtCheckIn(src); injure(src)
        sessions[#sessions + 1] = Hospital.requestCheckIn(src, hospital.name)
    end
    placeAtCheckIn(9); injure(9)
    h.assertFalse(Hospital.requestCheckIn(9, hospital.name))
    for src = 6, 8 do Hospital.leaveBed(src, sessions[src - 5].token) end
end)

h.test('completion requires the source-bound token, duration, and assigned-bed proximity', function()
    placeAtCheckIn(10); injure(10)
    local care = Hospital.requestCheckIn(10, hospital.name)
    placeAtBed(10, care.bedIndex)

    h.assertFalse(Hospital.completeBedCare(10, 'forged'))
    h.assertFalse(Hospital.completeBedCare(10, care.token))
    handle.advanceTime(Config.hospitalCare.duration + 1)
    handle.setCoords(10, 0, 0, 0)
    h.assertFalse(Hospital.completeBedCare(10, care.token))
    h.assertEqual(Hospital.getSession(10), nil)
end)

h.test('successful care revives laststand, requests client healing, clears wounds and charges once', function()
    placeAtCheckIn(11); injure(11)
    handle.players[11].money.cash = 1000
    handle.setHealth(11, 40)
    Death.enterLaststand(11)

    local completedHook, releasedHook = false, false
    AddEventHandler('qbambulance:server:onBedCareCompleted', function(src, name, index, cost)
        completedHook = src == 11 and name == hospital.name and index == 1 and cost == Config.billing.checkInCost
    end)
    AddEventHandler('qbambulance:server:onBedReleased', function(src, _, _, reason)
        releasedHook = src == 11 and reason == 'completed'
    end)

    local care = Hospital.requestCheckIn(11, hospital.name)
    placeAtBed(11, care.bedIndex)
    handle.advanceTime(Config.hospitalCare.duration + 1)
    h.assertTrue(Hospital.completeBedCare(11, care.token))
    h.assertTrue(Death.isAlive(11))
    local release = handle.lastClient('qbambulance:client:bedReleased')
    h.assertEqual(release.target, 11)
    h.assertEqual(release.args[1], 'completed')
    h.assertEqual(next(Death.getWoundData(11)), nil)
    h.assertEqual(handle.players[11].money.cash, 1000 - Config.billing.checkInCost)
    h.assertTrue(completedHook)
    h.assertTrue(releasedHook)
    h.assertFalse(Hospital.completeBedCare(11, care.token))
end)

h.test('expired sessions and disconnects release their beds without charging', function()
    placeAtCheckIn(12); injure(12)
    handle.players[12].money.cash = 1000
    local care = Hospital.requestCheckIn(12, hospital.name)
    placeAtBed(12, care.bedIndex)
    handle.advanceTime(Config.hospitalCare.actionTtl + 1)
    h.assertFalse(Hospital.completeBedCare(12, care.token))
    h.assertEqual(handle.players[12].money.cash, 1000)

    placeAtCheckIn(13); injure(13)
    local disconnectCare = Hospital.requestCheckIn(13, hospital.name)
    handle.fireEvent('playerDropped', 13)
    h.assertEqual(Hospital.getSession(13), nil)
    placeAtCheckIn(14); injure(14)
    local replacement = Hospital.requestCheckIn(14, hospital.name)
    h.assertEqual(replacement.bedIndex, disconnectCare.bedIndex)
    Hospital.leaveBed(14, replacement.token)
end)

h.report('hospital')
