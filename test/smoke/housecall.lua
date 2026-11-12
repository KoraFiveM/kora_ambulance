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

h.test('buildAlertPayload targets the EMS job TYPE and defaults a message', function()
    local payload = HouseCall.buildAlertPayload(42, { x = 1, y = 2, z = 3 }, nil)

    -- The TYPE, not this resource's job name: a server with a fire department
    -- or a second hospital registered as type='ems' is reached by the same call.
    h.assertEqual(payload.jobTypes[1], Config.job.type)
    h.assertEqual(payload.jobs, nil, 'no hard-coded job name')
    h.assertTrue(payload.message:find('42') ~= nil, 'the caller is identified')
    h.assertEqual(payload.code, '911e')
    h.assertEqual(payload.priority, 1, 'a 911 call is critical')

    local withMessage = HouseCall.buildAlertPayload(42, nil, 'custom text')
    h.assertEqual(withMessage.message, 'custom text')
end)

h.test('buildQueuePayload is a low-priority call carrying the accept hook', function()
    local payload = HouseCall.buildQueuePayload({ id = 7, src = 42, coords = { x = 1, y = 2, z = 3 }, note = 'sore arm' })

    h.assertEqual(payload.priority, 3,
        'a house call must not outrank a patient who is actually bleeding out')
    h.assertEqual(payload.message, 'sore arm', 'the caller note becomes the message')
    -- kora_dispatch knows nothing about house calls: it fires whatever event name
    -- it was handed when a paramedic first attaches. That is what keeps
    -- job-specific behaviour out of the dispatch resource.
    h.assertEqual(payload.onAccept, 'kora_ambulance:server:housecallAccepted', 'the generic accept hook')
    h.assertEqual(payload.data.requestId, 7, 'and enough data to find the request again')
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

h.test('prune removes expired calls and pending is keyed to stable citizen identity', function()
    local now = 1000
    local queue = {
        { id = 1, citizenid = 'CID0001', createdAt = now - 901 },
        { id = 2, citizenid = 'CID0002', createdAt = now - 10 },
    }

    local active, expired = HouseCall.prune(queue, now, 900)
    h.assertEqual(#active, 1)
    h.assertEqual(active[1].id, 2)
    h.assertEqual(#expired, 1)
    h.assertTrue(HouseCall.hasPending(active, 'CID0002'))
    h.assertFalse(HouseCall.hasPending(active, 'CID0001'))
end)

h.test('a 911 call reaches on-duty EMS and reports how many heard it', function()
    handle.ensurePlayer(1); handle.players[1].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.ensurePlayer(2) -- civilian caller
    handle.ensurePlayer(3); handle.players[3].job = { name = Config.job.name, onduty = false, grade = { level = 1 } }

    local _, count = handle.kora_dispatch:createCall(HouseCall.buildAlertPayload(2, nil, 'help'))

    -- The count is what /911e uses to tell the caller "help is coming" versus
    -- "nobody is on duty" -- two very different things to hear while bleeding.
    h.assertEqual(count, 1, 'the on-duty paramedic only, never the off-duty one')
end)

h.report('housecall')
