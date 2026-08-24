-- Revive smoke test -- the eligibility gate (pure) and the full
-- Revive.complete integration (job/duty, item, target-state, cooldown).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/revive.lua')

h.test('eligibility refuses an alive patient regardless of cooldown', function()
    local ok, reason = Revive.eligibility('alive', nil, os.time())
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)
end)

h.test('eligibility allows laststand/dead with no prior attempt', function()
    h.assertTrue((Revive.eligibility('laststand', nil, os.time())))
    h.assertTrue((Revive.eligibility('dead', nil, os.time())))
end)

h.test('eligibility enforces Config.death.reviveInterval between attempts on the same patient', function()
    local now = os.time()
    local ok, reason = Revive.eligibility('laststand', now, now)
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)

    local later = now + math.ceil(Config.death.reviveInterval / 1000) + 1
    h.assertTrue((Revive.eligibility('laststand', now, later)))
end)

local function makeMedic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.players[src].items.defibrillator = 1
end

h.test('complete refuses a reviver who is not on-duty EMS', function()
    handle.ensurePlayer(1)
    handle.ensurePlayer(2)
    Death.enterLaststand(2)

    local ok, reason = Revive.complete(1, 2, true)
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)
end)

h.test('complete refuses a reviver with no defibrillator', function()
    handle.ensurePlayer(3)
    handle.players[3].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.ensurePlayer(4)
    Death.enterLaststand(4)

    local ok = Revive.complete(3, 4, true)
    h.assertFalse(ok)
end)

h.test('complete refuses reviving an alive target', function()
    makeMedic(5)
    handle.ensurePlayer(6) -- stays alive

    local ok = Revive.complete(5, 6, true)
    h.assertFalse(ok)
end)

h.test('complete on a failed minigame does not revive and does not consume the defibrillator', function()
    makeMedic(7)
    handle.ensurePlayer(8)
    Death.enterLaststand(8)

    local ok = Revive.complete(7, 8, false)
    h.assertFalse(ok)
    h.assertTrue(Death.isLaststand(8))
    h.assertEqual(handle.players[7].items.defibrillator, 1) -- not consumed on failure
end)

h.test('complete on a successful minigame revives the target and consumes exactly one defibrillator', function()
    makeMedic(9)
    handle.ensurePlayer(10)
    Death.enterLaststand(10)

    local ok = Revive.complete(9, 10, true)
    h.assertTrue(ok)
    h.assertTrue(Death.isAlive(10))
    h.assertEqual(handle.players[9].items.defibrillator, 0)
end)

h.test('complete enforces the per-target cooldown across separate revivers', function()
    makeMedic(11)
    makeMedic(12)
    handle.ensurePlayer(13)
    Death.enterLaststand(13)

    h.assertTrue(Revive.complete(11, 13, true))

    -- Immediately re-down and try again with a DIFFERENT reviver -- cooldown
    -- is tracked per TARGET, not per reviver, so this must still be refused.
    Death.enterLaststand(13)
    local ok, reason = Revive.complete(12, 13, true)
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)
end)

h.test('a successful revive fires qbambulance:server:onPlayerRevivedBy', function()
    makeMedic(14)
    handle.ensurePlayer(15)
    Death.enterLaststand(15)

    local fired = false
    local originalTriggerEvent = _G.TriggerEvent
    _G.TriggerEvent = function(name, ...)
        if name == 'qbambulance:server:onPlayerRevivedBy' then fired = true end
        return originalTriggerEvent(name, ...)
    end

    Revive.complete(14, 15, true)
    _G.TriggerEvent = originalTriggerEvent

    h.assertTrue(fired)
end)

h.report('revive')
