-- Items smoke test -- painkillerEligible (pure) and the full pharmacy
-- createUseable flow: eligibility gate -> server-asks-client progress bar
-- (QB.callback.trigger's server->client direction) -> real wound treatment
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
handle.QB.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return true end

h.test('bandage: no wound at all -> refused, item not consumed', function()
    handle.ensurePlayer(1)
    handle.players[1].items.bandage = 1

    handle.qbcore:useItem(1, 'bandage')
    h.assertEqual(handle.players[1].items.bandage, 1)
end)

h.test('bandage: treats a tier-2-or-lower wound and consumes exactly one bandage', function()
    handle.ensurePlayer(2)
    handle.players[2].items.bandage = 2
    Death.recordWound(2, 'left_hand', 2)

    handle.qbcore:useItem(2, 'bandage')

    h.assertEqual(Death.getWoundData(2).left_hand, nil) -- treated
    h.assertEqual(handle.players[2].items.bandage, 1) -- exactly one consumed
end)

h.test('bandage cannot treat a tier-3+ wound (needs an IFAK) and does not consume the item', function()
    handle.ensurePlayer(3)
    handle.players[3].items.bandage = 1
    Death.recordWound(3, 'chest', 4)

    handle.qbcore:useItem(3, 'bandage')

    h.assertEqual(Death.getWoundData(3).chest, 4) -- untouched
    h.assertEqual(handle.players[3].items.bandage, 1) -- not consumed
end)

h.test('bandage refuses to be used while dead', function()
    handle.ensurePlayer(4)
    handle.players[4].items.bandage = 1
    Death.markDead(4)

    handle.qbcore:useItem(4, 'bandage')
    h.assertEqual(handle.players[4].items.bandage, 1)
end)

h.test('ifak treats any tier, including one a bandage could not', function()
    handle.ensurePlayer(5)
    handle.players[5].items.ifak = 1
    Death.recordWound(5, 'chest', 4)

    handle.qbcore:useItem(5, 'ifak')

    h.assertEqual(Death.getWoundData(5).chest, nil)
    h.assertEqual(handle.players[5].items.ifak, 0)
end)

h.test('a cancelled progress bar (client reports false) treats nothing and consumes nothing', function()
    handle.ensurePlayer(6)
    handle.players[6].items.bandage = 1
    Death.recordWound(6, 'left_hand', 1)

    handle.QB.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return false end
    handle.qbcore:useItem(6, 'bandage')
    handle.QB.callback.clientHandlers['qbambulance:client:pharmacyProgress'] = function(_payload) return true end

    h.assertEqual(Death.getWoundData(6).left_hand, 1) -- untreated
    h.assertEqual(handle.players[6].items.bandage, 1) -- not consumed
end)

h.test('painkillers: respects the cooldown and consumes exactly one on success', function()
    handle.ensurePlayer(7)
    handle.players[7].items.painkillers = 2

    handle.qbcore:useItem(7, 'painkillers')
    h.assertEqual(handle.players[7].items.painkillers, 1)

    handle.qbcore:useItem(7, 'painkillers') -- immediately again -- cooldown blocks it
    h.assertEqual(handle.players[7].items.painkillers, 1)
end)

h.report('items')
