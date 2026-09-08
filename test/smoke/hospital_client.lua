-- Hospital client targets are facility-only and must survive qbtarget reloads
-- even when a deployment omits optional pharmacy/stash fields.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

Config.hospitals[1].pharmacy = nil
Config.hospitals[1].stash = nil
local hospitalBlips = {}
QB.blips.create = function(_, options)
    hospitalBlips[#hospitalBlips + 1] = options
    return #hospitalBlips
end
dofile('client/hospital.lua')

h.test('hospital check-in targets tolerate optional facility points being absent', function()
    local checkIns = 0
    for _, call in ipairs(handle.qbtarget.calls) do
        h.assertEqual(call.kind, 'sphere')
        if call.definition.options[1].label == 'Check In for Care' then checkIns = checkIns + 1 end
    end
    h.assertEqual(checkIns, #Config.hospitals)
end)

h.test('hospital markers use canonical category and facility names', function()
    h.assertEqual(#hospitalBlips, #Config.hospitals)
    h.assertEqual(hospitalBlips[1].category, 'Hospital')
    h.assertEqual(hospitalBlips[1].name, 'Pillbox Hill Medical')
    h.assertEqual(hospitalBlips[1].label, nil, 'qblib composes the map label')
end)

h.test('hospital check-in targets register again after qbtarget restarts', function()
    local before = #handle.qbtarget.calls
    handle.fireEvent('onClientResourceStart', nil, 'qbtarget')
    h.assertEqual(#handle.qbtarget.calls, before * 2)
end)

h.report('hospital_client')
