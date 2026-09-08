-- Patient-action target registration smoke test. Physical transport adds a
-- stretcher-model registration and vehicle operations alongside the existing
-- player interactions; every registration must survive a qbtarget restart.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

dofile('client/stretcher.lua')
dofile('client/revive.lua')
dofile('client/treatment.lua')

h.test('patient, physical stretcher, and vehicle targets register at load', function()
    h.assertEqual(#handle.qbtarget.calls, 5)

    local kinds = {}
    for _, call in ipairs(handle.qbtarget.calls) do kinds[call.kind] = (kinds[call.kind] or 0) + 1 end
    h.assertEqual(kinds.player, 3, 'carry, revive and treatment register player targets')
    h.assertEqual(kinds.model, 1, 'the physical stretcher model is targetable')
    h.assertEqual(kinds.vehicle, 1, 'duty-vehicle transport operations are targetable')
end)

h.test('a qbtarget restart re-registers every patient-action global type', function()
    local before = #handle.qbtarget.calls

    handle.fireEvent('onClientResourceStart', nil, 'qbtarget')

    local after = #handle.qbtarget.calls
    h.assertEqual(after, before + 5,
        'all five patient/transport target registrations must be restored')
end)

h.test('an unrelated resource restarting does not re-trigger anything', function()
    local before = #handle.qbtarget.calls

    handle.fireEvent('onClientResourceStart', nil, 'some_other_resource')

    h.assertEqual(#handle.qbtarget.calls, before, 'only a qbtarget restart should re-trigger addGlobalType')
end)

h.report('client_targets')
