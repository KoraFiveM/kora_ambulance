-- Billing smoke test -- calculateCost is pure; chargeForRespawn is the
-- side-effecting wrapper, exercised against the mock's in-memory money.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/billing.lua')

h.test('calculateCost is just baseCost with no wounds', function()
    h.assertEqual(Billing.calculateCost({}), Config.billing.baseCost)
    h.assertEqual(Billing.calculateCost(nil), Config.billing.baseCost)
end)

h.test('calculateCost adds perWoundCost[tier] for every open wound', function()
    local expected = Config.billing.baseCost
        + Config.billing.perWoundCost[3]
        + Config.billing.perWoundCost[1]

    h.assertEqual(Billing.calculateCost({ chest = 3, left_hand = 1 }), expected)
end)

h.test('calculateCost falls back to the highest tier bracket for an out-of-range tier', function()
    local maxTier = #Config.billing.perWoundCost
    local expected = Config.billing.baseCost + Config.billing.perWoundCost[maxTier]
    h.assertEqual(Billing.calculateCost({ chest = 99 }), expected)
end)

h.test('chargeForRespawn drains the primary account first, capped at what is available', function()
    handle.ensurePlayer(1)
    handle.players[1].money[Config.billing.account] = 10000
    handle.players[1].money[Config.billing.fallbackAccount] = 10000

    local cost = Billing.chargeForRespawn(1, {})
    h.assertEqual(cost, Config.billing.baseCost)
    h.assertEqual(handle.players[1].money[Config.billing.account], 10000 - cost)
    h.assertEqual(handle.players[1].money[Config.billing.fallbackAccount], 10000) -- untouched -- primary covered it all
end)

h.test('chargeForRespawn spills the remainder onto the fallback account when primary is short', function()
    handle.ensurePlayer(2)
    handle.players[2].money[Config.billing.account] = 100
    handle.players[2].money[Config.billing.fallbackAccount] = 5000

    local cost = Billing.chargeForRespawn(2, { chest = 4 }) -- baseCost + perWoundCost[4], comfortably > 100
    h.assertTrue(cost > 100)
    h.assertEqual(handle.players[2].money[Config.billing.account], 0) -- primary fully drained
    h.assertEqual(handle.players[2].money[Config.billing.fallbackAccount], 5000 - (cost - 100))
end)

h.test('chargeForRespawn is a no-op (charges nothing) when cost is somehow non-positive', function()
    handle.ensurePlayer(3)
    handle.players[3].money[Config.billing.account] = 500

    -- calculateCost can never actually return <= 0 given a positive
    -- baseCost, but chargeForRespawn's own early-return guard is still real
    -- branching logic worth locking down against a future baseCost of 0.
    local originalBase = Config.billing.baseCost
    Config.billing.baseCost = 0
    local cost = Billing.chargeForRespawn(3, {})
    Config.billing.baseCost = originalBase

    h.assertEqual(cost, 0)
    h.assertEqual(handle.players[3].money[Config.billing.account], 500)
end)

h.test('chargeForRespawn fires the legacy SendBillEmail client event with the charged amount', function()
    handle.ensurePlayer(4)
    handle.players[4].money[Config.billing.account] = 10000

    local cost = Billing.chargeForRespawn(4, {})
    local push = handle.lastClient('hospital:client:SendBillEmail')
    h.assertTrue(push ~= nil)
    h.assertEqual(push.target, 4)
    h.assertEqual(push.args[1], cost)
end)

h.test('charge is reusable for successful non-respawn care', function()
    handle.ensurePlayer(5)
    handle.players[5].money[Config.billing.account] = 300
    handle.players[5].money[Config.billing.fallbackAccount] = 1000

    local charged = Billing.charge(5, Config.billing.checkInCost, 'EMS check-in care')
    h.assertEqual(charged, Config.billing.checkInCost)
    h.assertEqual(handle.players[5].money[Config.billing.account], 300 - Config.billing.checkInCost)
end)

h.report('billing')
