-- server/duty.lua hospital-fixture registration smoke test -- the pharmacy
-- shop + EMS stash per hospital, registered against qbinventory. Proves
-- registerHospitals() re-runs not only at load but also on a qbinventory
-- restart mid-session (a `dependency 'qbinventory'` declaration only
-- guarantees start ORDER on a fresh boot, not survival of a later restart,
-- which wipes qbinventory's own shop/stash tables).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/duty.lua')

local hospitalCount = #Config.hospitals

h.test('registerHospitals runs once per hospital at load time', function()
    h.assertEqual(#handle.qbinventory.calls, hospitalCount * 2, 'each hospital should register exactly one shop and one stash at load')
end)

h.test('a qbinventory restart re-registers every hospital shop and stash', function()
    local before = #handle.qbinventory.calls

    handle.fireEvent('onResourceStart', nil, 'qbinventory')

    local after = #handle.qbinventory.calls
    h.assertEqual(after, before + hospitalCount * 2, 'registerHospitals must re-run on a qbinventory restart, not just at load')
end)

h.test('an unrelated resource starting does not re-trigger hospital registration', function()
    local before = #handle.qbinventory.calls

    handle.fireEvent('onResourceStart', nil, 'some_other_resource')

    h.assertEqual(#handle.qbinventory.calls, before, 'only a qbinventory restart should re-trigger registerHospitals')
end)

h.report('duty')
