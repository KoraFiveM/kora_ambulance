local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()
dofile('config.lua')

dofile('client/compat.lua')

h.test('legacy pain effect retains and releases kora_lib handle identity', function()
    handle.fireEvent('hospital:client:SetPain', 0, 2)
    handle.fireEvent('hospital:client:SetPain', 0, 3)

    h.assertEqual(#handle.Kora.fx.started, 1, 'repeated pain updates must not leak screen handles')
    local startedHandle = handle.Kora.fx.started[1].handle

    handle.fireEvent('hospital:client:SetPain', 0, 0)

    h.assertEqual(handle.Kora.fx.stopped[1], startedHandle,
        'clearing pain must release the opaque handle returned by screenEffect')
end)

h.test('PainKillerLoop export exists and is inert', function()
    h.assertEqual(type(handle.exports.PainKillerLoop), 'function')
    h.assertEqual(handle.exports.PainKillerLoop(), nil)
end)

h.test('setArmour only ever lowers armour', function()
    local armour = 50
    _G.PlayerPedId = function() return 1 end
    _G.GetPedArmour = function() return armour end
    _G.SetPedArmour = function(_, value) armour = value end
    handle.fireEvent('kora_ambulance:client:setArmour', 0, 90)
    h.assertEqual(armour, 50)
    handle.fireEvent('kora_ambulance:client:setArmour', 0, 20)
    h.assertEqual(armour, 20)
end)

h.report('compat_client')
