-- Pharmacy client smoke test -- the painkiller benefit the server sends is
-- applied client-side (SetEntityHealth is client-only), capped at max health,
-- and never touches a downed ped.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/downed.lua')

local health, maxHealth = 150, 200
_G.PlayerPedId = function() return 1 end
_G.GetEntityHealth = function() return health end
_G.GetEntityMaxHealth = function() return maxHealth end
_G.SetEntityHealth = function(_, value) health = value end
_G.State = { isAlive = function() return true end }

dofile('client/pharmacy.lua')

local function boost(amount) handle.fireEvent('qbambulance:client:painkillerBenefit', 0, amount) end

h.test('the boost raises health by the configured amount', function()
    health = 150
    boost(Config.painkillers.healthAmount)
    h.assertEqual(health, 150 + Config.painkillers.healthAmount)
end)

h.test('max health is respected', function()
    health = 195
    boost(15)
    h.assertEqual(health, 200)
    boost(15) -- already full: unchanged
    h.assertEqual(health, 200)
end)

h.test('a fatally injured ped, a downed player, or a bad amount is left alone', function()
    health = 100
    boost(15)
    h.assertEqual(health, 100)

    health = 150
    _G.State = { isAlive = function() return false end }
    boost(15)
    h.assertEqual(health, 150)

    _G.State = { isAlive = function() return true end }
    boost(0); boost(-10); boost('x'); boost(nil)
    h.assertEqual(health, 150)
end)

h.report('pharmacy_client')
