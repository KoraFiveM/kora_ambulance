-- Items smoke test -- painkillerEligible (pure) and the full pharmacy
-- createUseable flow: eligibility gate -> server-asks-client progress bar
-- (Kora.callback.trigger's server->client direction) -> real wound treatment
-- -> item consumption, exercised end-to-end against the mock's captured
-- useable handlers and a stubbed client-side progress-bar response.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/items.lua')

h.test('painkillerEligible: nil lastUsedAt is always eligible; otherwise gated by the interval', function()
    h.assertTrue(Items.painkillerEligible(os.time(), nil))

    local now = os.time()
    h.assertFalse(Items.painkillerEligible(now, now))
    local intervalSeconds = math.floor(Config.painkillers.interval / 1000)
    h.assertTrue(Items.painkillerEligible(now + intervalSeconds + 1, now))
end)

-- Stub the client's progress-bar response for every test below: "completed"
-- unless a test overrides it to simulate a cancel.
handle.Kora.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return true end

h.test('bandage: no wound at all -> refused, item not consumed', function()
    handle.ensurePlayer(1)
    handle.players[1].items.bandage = 1

    handle.kora_core:useItem(1, 'bandage')
    h.assertEqual(handle.players[1].items.bandage, 1)
end)

h.test('bandage: treats a tier-2-or-lower wound and consumes exactly one bandage', function()
    handle.ensurePlayer(2)
    handle.players[2].items.bandage = 2
    Death.recordWound(2, 'left_hand', 2)

    handle.kora_core:useItem(2, 'bandage')

    h.assertEqual(Death.getWoundData(2).left_hand, nil) -- treated
    h.assertEqual(handle.players[2].items.bandage, 1) -- exactly one consumed
end)

h.test('bandage cannot treat a tier-3+ wound (needs an IFAK) and does not consume the item', function()
    handle.ensurePlayer(3)
    handle.players[3].items.bandage = 1
    Death.recordWound(3, 'chest', 4)

    handle.kora_core:useItem(3, 'bandage')

    h.assertEqual(Death.getWoundData(3).chest, 4) -- untouched
    h.assertEqual(handle.players[3].items.bandage, 1) -- not consumed
end)

h.test('bandage refuses to be used while dead', function()
    handle.ensurePlayer(4)
    handle.players[4].items.bandage = 1
    Death.markDead(4)

    handle.kora_core:useItem(4, 'bandage')
    h.assertEqual(handle.players[4].items.bandage, 1)
end)

h.test('ifak treats any tier, including one a bandage could not', function()
    handle.ensurePlayer(5)
    handle.players[5].items.ifak = 1
    Death.recordWound(5, 'chest', 4)

    handle.kora_core:useItem(5, 'ifak')

    h.assertEqual(Death.getWoundData(5).chest, nil)
    h.assertEqual(handle.players[5].items.ifak, 0)
end)

h.test('ifaks is an alias of the ifak handler and consumes its own item', function()
    handle.ensurePlayer(30)
    handle.players[30].items.ifaks = 1
    Death.recordWound(30, 'chest', 4)

    handle.kora_core:useItem(30, 'ifaks')

    h.assertEqual(Death.getWoundData(30).chest, nil)
    h.assertEqual(handle.players[30].items.ifaks, 0)
end)

h.test('a cancelled progress bar (client reports false) treats nothing and consumes nothing', function()
    handle.ensurePlayer(6)
    handle.players[6].items.bandage = 1
    Death.recordWound(6, 'left_hand', 1)

    handle.Kora.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return false end
    handle.kora_core:useItem(6, 'bandage')
    handle.Kora.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return true end

    h.assertEqual(Death.getWoundData(6).left_hand, 1) -- untreated
    h.assertEqual(handle.players[6].items.bandage, 1) -- not consumed
end)

h.test('painkillers: respects the cooldown and consumes exactly one on success', function()
    handle.ensurePlayer(7)
    handle.players[7].items.painkillers = 2

    handle.kora_core:useItem(7, 'painkillers')
    h.assertEqual(handle.players[7].items.painkillers, 1)

    handle.kora_core:useItem(7, 'painkillers') -- immediately again -- cooldown blocks it
    h.assertEqual(handle.players[7].items.painkillers, 1)
end)

h.test('painkillers: a promise-returning trigger (same-VM) is awaited; health boost applied; cancel consumes nothing', function()
    handle.ensurePlayer(30)
    handle.players[30].items.painkillers = 2
    handle.players[30].health = 150
    local calls = {}
    local result = true
    _G.Citizen = _G.Citizen or {}
    _G.Citizen.Await = function(p) return p.value end
    local realTrigger = handle.Kora.callback.trigger
    handle.Kora.callback.trigger = function(_, _, payload)
        calls[#calls + 1] = payload
        return { next = function() end, value = result }
    end

    result = false -- cancelled
    handle.kora_core:useItem(30, 'painkillers')
    h.assertEqual(handle.players[30].items.painkillers, 2)
    h.assertEqual(handle.players[30].health, 150)

    result = true
    handle.kora_core:useItem(30, 'painkillers')
    handle.Kora.callback.trigger = realTrigger
    h.assertEqual(handle.players[30].items.painkillers, 1)
    -- Server never writes health (SetEntityHealth is client-only): it tells the client.
    h.assertEqual(handle.players[30].health, 150)
    local benefit = handle.lastClient('qbambulance:client:painkillerBenefit')
    h.assertEqual(benefit.target, 30)
    h.assertEqual(benefit.args[1], Config.painkillers.healthAmount)
    h.assertEqual(calls[2].duration, Config.painkillers.animDuration)
    h.assertEqual(calls[2].anim.dict, Config.painkillers.animDict)
    h.assertEqual(calls[2].anim.clip, Config.painkillers.animClip)
end)

h.test('painkillers: success never raises a script error (no client-only natives on the server)', function()
    h.assertEqual(SetEntityHealth, nil)
    h.assertEqual(SetPedArmour, nil)
    handle.ensurePlayer(31)
    handle.players[31].items.painkillers = 1
    local ok, err = pcall(function() handle.kora_core:useItem(31, 'painkillers') end)
    h.assertTrue(ok, tostring(err))
    h.assertEqual(handle.players[31].items.painkillers, 0)
    h.assertEqual(handle.lastClient('qbambulance:client:painkillerBenefit').target, 31)
end)

h.test('painkillers: healthAmount 0 sends no boost; a downed player gets none', function()
    local amount = Config.painkillers.healthAmount
    handle.ensurePlayer(32)
    local before = #handle.clientEvents
    Config.painkillers.healthAmount = 0
    Items.applyPainkillerBenefit(32)
    h.assertEqual(#handle.clientEvents, before)

    Config.painkillers.healthAmount = amount
    Death.enterLaststand(32, 'test')
    before = #handle.clientEvents
    Items.applyPainkillerBenefit(32)
    for i = before + 1, #handle.clientEvents do
        h.assertTrue(handle.clientEvents[i].name ~= 'qbambulance:client:painkillerBenefit', 'downed player was boosted')
    end
end)

h.test('painkillers: stopBleeding option stops the bleed server-side', function()
    handle.ensurePlayer(33)
    Death.recordWound(33, 'left_hand', 2)
    local stop = Config.painkillers.stopBleeding
    Config.painkillers.stopBleeding = true
    Items.applyPainkillerBenefit(33)
    Config.painkillers.stopBleeding = stop
    h.assertFalse(Death.isBleeding(33))
end)

h.report('items')
