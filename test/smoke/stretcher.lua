-- Stretcher smoke test -- the pure canPickup eligibility check and the
-- server-side pickup/release relationship tracking (the other genuine new
-- differentiator, per the plan). Position sync itself is client-only/
-- native-heavy and is not exercised here -- see client/stretcher.lua's own
-- header for that design.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/stretcher.lua')

h.test('canPickup refuses an alive patient', function()
    local ok, reason = Stretcher.canPickup('alive', false, false)
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)
end)

h.test('canPickup refuses a patient already being dragged by someone else', function()
    local ok = Stretcher.canPickup('laststand', true, false)
    h.assertFalse(ok)
end)

h.test('canPickup refuses a dragger who is already carrying someone', function()
    local ok = Stretcher.canPickup('dead', false, true)
    h.assertFalse(ok)
end)

h.test('canPickup allows a free EMS dragging a free laststand/dead patient', function()
    h.assertTrue((Stretcher.canPickup('laststand', false, false)))
    h.assertTrue((Stretcher.canPickup('dead', false, false)))
end)

local function makeMedic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
end

h.test('stretcherPickup registers the relationship and pushes begin to both sides', function()
    makeMedic(1)
    handle.ensurePlayer(2)
    Death.enterLaststand(2)

    local pickup = handle.QB.events.registry['qbambulance:server:stretcherPickup']
    pickup(1, 2)

    h.assertEqual(Stretcher.draggingTarget(1), 2)
    h.assertEqual(Stretcher.draggedBy(2), 1)

    local draggerPush = handle.lastClient('qbambulance:client:stretcherBegin')
    h.assertTrue(draggerPush ~= nil)
end)

h.test('stretcherPickup refuses a non-EMS dragger (relationship stays empty)', function()
    handle.ensurePlayer(3) -- not EMS
    handle.ensurePlayer(4)
    Death.enterLaststand(4)

    local pickup = handle.QB.events.registry['qbambulance:server:stretcherPickup']
    pickup(3, 4)

    h.assertEqual(Stretcher.draggingTarget(3), nil)
    h.assertEqual(Stretcher.draggedBy(4), nil)
end)

h.test('stretcherPickup refuses a second dragger on an already-carried patient', function()
    makeMedic(5)
    makeMedic(6)
    handle.ensurePlayer(7)
    Death.enterLaststand(7)

    local pickup = handle.QB.events.registry['qbambulance:server:stretcherPickup']
    pickup(5, 7)
    pickup(6, 7) -- should be refused -- 7 is already being dragged by 5

    h.assertEqual(Stretcher.draggedBy(7), 5)
    h.assertEqual(Stretcher.draggingTarget(6), nil)
end)

h.test('stretcherRelease clears the relationship and notifies both sides', function()
    makeMedic(8)
    handle.ensurePlayer(9)
    Death.enterLaststand(9)

    local pickup = handle.QB.events.registry['qbambulance:server:stretcherPickup']
    local release = handle.QB.events.registry['qbambulance:server:stretcherRelease']

    pickup(8, 9)
    release(8)

    h.assertEqual(Stretcher.draggingTarget(8), nil)
    h.assertEqual(Stretcher.draggedBy(9), nil)
end)

h.test('a playerDropped for the dragger also releases their patient', function()
    makeMedic(10)
    handle.ensurePlayer(11)
    Death.enterLaststand(11)

    handle.QB.events.registry['qbambulance:server:stretcherPickup'](10, 11)
    h.assertEqual(Stretcher.draggedBy(11), 10)

    handle.fireEvent('playerDropped', 10)
    h.assertEqual(Stretcher.draggedBy(11), nil)
end)

h.test('heartbeat releases a relationship that is no longer nearby', function()
    makeMedic(12)
    handle.ensurePlayer(13)
    Death.enterLaststand(13)
    handle.QB.events.registry['qbambulance:server:stretcherPickup'](12, 13)
    handle.setCoords(13, 100, 0, 0)

    handle.QB.events.registry['qbambulance:server:stretcherHeartbeat'](12)

    h.assertEqual(Stretcher.draggingTarget(12), nil)
    h.assertEqual(Stretcher.draggedBy(13), nil)
end)

h.report('stretcher')
