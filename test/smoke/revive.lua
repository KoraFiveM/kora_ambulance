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

h.test('network revive requires the proof authorization issued for that action', function()
    makeMedic(16)
    handle.ensurePlayer(17)
    Death.enterLaststand(17)

    local token, _, authorization = handle.QB.callback.registry['qbambulance:server:beginRevive'](16, 17)
    local wrongProof = handle.issueMinigameProof(16, 'mash', 'wrong-authorization')
    handle.QB.events.registry['qbambulance:server:completeRevive'](16, 17, token, wrongProof)
    h.assertTrue(Death.isLaststand(17), 'a proof from another authorization is rejected')

    makeMedic(18)
    handle.ensurePlayer(19)
    Death.enterLaststand(19)
    local validToken, _, validAuthorization = handle.QB.callback.registry['qbambulance:server:beginRevive'](18, 19)
    local validProof = handle.issueMinigameProof(18, 'mash', validAuthorization)
    handle.QB.events.registry['qbambulance:server:completeRevive'](18, 19, validToken, validProof)
    h.assertTrue(Death.isAlive(19), 'the matching action proof revives the patient')
end)

local beginRevive = handle.QB.callback.registry['qbambulance:server:beginRevive']
local completeRevive = handle.QB.events.registry['qbambulance:server:completeRevive']
local originalTimer = GetGameTimer
local clock = 1000000
GetGameTimer = function() return clock end

h.test('expired patient reservations admit another medic without accepting the old action', function()
    makeMedic(20)
    makeMedic(21)
    handle.ensurePlayer(22)
    Death.enterLaststand(22)
    local oldToken, _, oldAuthorization = beginRevive(20, 22)
    h.assertTrue(oldToken)
    h.assertFalse(beginRevive(21, 22), 'an active patient reservation still blocks another medic')
    clock = clock + Config.death.reviveActionTtl
    h.assertFalse(beginRevive(21, 22), 'preserve completion eligibility at the exact TTL boundary')
    clock = clock + 1
    local token, _, authorization = beginRevive(21, 22)
    h.assertTrue(token, 'a disconnected minigame must not lock the patient indefinitely')
    local oldProof = handle.issueMinigameProof(20, 'mash', oldAuthorization)
    completeRevive(20, 22, oldToken, oldProof)
    h.assertTrue(Death.isLaststand(22), 'expired action cannot revive the patient')
    h.assertEqual(handle.players[20].items.defibrillator, 1, 'expired action consumes no item')
    h.assertFalse(beginRevive(20, 22), 'old completion must not release the new medic reservation')
    local proof = handle.issueMinigameProof(21, 'mash', authorization)
    completeRevive(21, 22, token, proof)
    h.assertTrue(Death.isAlive(22), 'the new action still completes normally')
    h.assertEqual(handle.players[21].items.defibrillator, 0)
end)

h.test('expired medic reservations release the previous patient before starting another action', function()
    makeMedic(24)
    makeMedic(27)
    makeMedic(28)
    handle.ensurePlayer(25)
    handle.ensurePlayer(26)
    Death.enterLaststand(25)
    Death.enterLaststand(26)
    local oldToken, _, oldAuthorization = beginRevive(24, 25)
    h.assertTrue(oldToken)
    h.assertFalse(beginRevive(24, 26), 'an active medic cannot begin two actions')
    clock = clock + Config.death.reviveActionTtl + 1
    local token, _, authorization = beginRevive(24, 26)
    h.assertTrue(token, 'the same medic can retry after the action expires')
    h.assertTrue(beginRevive(27, 25), 'the old patient reservation is also released')
    completeRevive(24, 25, oldToken, handle.issueMinigameProof(24, 'mash', oldAuthorization))
    h.assertFalse(beginRevive(28, 26), 'a late old token cannot clear the newer medic action')
    h.assertTrue(Death.isLaststand(25))
    h.assertEqual(handle.players[24].items.defibrillator, 1)
    completeRevive(24, 26, token, handle.issueMinigameProof(24, 'mash', authorization))
    h.assertTrue(Death.isAlive(26))
    h.assertEqual(handle.players[24].items.defibrillator, 0)
end)

GetGameTimer = originalTimer
h.report('revive')
