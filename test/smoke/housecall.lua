-- HouseCall smoke test -- cooldown gate, alert payload construction, and the
-- pure submitToQueue/acceptFromQueue queue transforms (the genuine new
-- differentiator, per the plan -- so its actual mechanics are worth locking
-- down independent of the /housecall*/accepthousecall command wiring).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/housecall.lua')

h.test('cooldownElapsed: nil lastAt is always eligible; otherwise gated by cooldownMs', function()
    h.assertTrue(HouseCall.cooldownElapsed(nil, os.time(), 60000))

    local now = os.time()
    h.assertFalse(HouseCall.cooldownElapsed(now, now, 60000))
    h.assertTrue(HouseCall.cooldownElapsed(now, now + 61, 60000))
end)

h.test('buildAlertPayload targets the ambulance job and defaults a message', function()
    local payload = HouseCall.buildAlertPayload(42, { x = 1, y = 2, z = 3 }, nil)
    h.assertEqual(payload.jobs[1], Config.job.name)
    h.assertTrue(payload.message:find('42') ~= nil)
    h.assertEqual(payload.code, '911e')

    local withMessage = HouseCall.buildAlertPayload(42, nil, 'custom text')
    h.assertEqual(withMessage.message, 'custom text')
end)

h.test('submitToQueue appends without mutating the original array', function()
    local original = {}
    local afterOne = HouseCall.submitToQueue(original, { id = 1 })
    h.assertEqual(#original, 0) -- original untouched
    h.assertEqual(#afterOne, 1)
    h.assertEqual(afterOne[1].id, 1)

    local afterTwo = HouseCall.submitToQueue(afterOne, { id = 2 })
    h.assertEqual(#afterOne, 1) -- still untouched
    h.assertEqual(#afterTwo, 2)
end)

h.test('acceptFromQueue removes exactly the matching id and returns it, leaving the rest in order', function()
    local queue = HouseCall.submitToQueue(HouseCall.submitToQueue(HouseCall.submitToQueue({}, { id = 1 }), { id = 2 }), { id = 3 })

    local newQueue, accepted = HouseCall.acceptFromQueue(queue, 2)
    h.assertEqual(accepted.id, 2)
    h.assertEqual(#newQueue, 2)
    h.assertEqual(newQueue[1].id, 1)
    h.assertEqual(newQueue[2].id, 3)
    h.assertEqual(#queue, 3) -- original untouched
end)

h.test('acceptFromQueue returns nil for an id that is not queued', function()
    local queue = HouseCall.submitToQueue({}, { id = 1 })
    local newQueue, accepted = HouseCall.acceptFromQueue(queue, 999)
    h.assertEqual(accepted, nil)
    h.assertEqual(#newQueue, 1)
end)

h.test('/911e respects Core.dispatch.alert routing and reports how many EMS were reached', function()
    handle.ensurePlayer(1); handle.players[1].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.ensurePlayer(2) -- civilian caller

    -- alert() in the mock counts on-duty players by job, mirroring
    -- Core.dispatch.alert's own O(1) getPlayersByJob-based fan-out.
    local count = handle.qbcore:alert(HouseCall.buildAlertPayload(2, nil, 'help'))
    h.assertEqual(count, 1)
end)

h.report('housecall')
