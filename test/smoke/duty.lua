-- server/duty.lua hospital-fixture registration smoke test -- the pharmacy
-- shop + EMS stash per hospital, registered against kora_inventory. Proves
-- registerHospitals() re-runs not only at load but also on a kora_inventory
-- restart mid-session (a `dependency 'kora_inventory'` declaration only
-- guarantees start ORDER on a fresh boot, not survival of a later restart,
-- which wipes kora_inventory's own shop/stash tables).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/duty.lua')

local hospitalCount = #Config.hospitals

h.test('registerHospitals runs once per hospital at load time', function()
    h.assertEqual(#handle.kora_inventory.calls, hospitalCount * 2, 'each hospital should register exactly one shop and one stash at load')
end)

h.test('a kora_inventory restart re-registers every hospital shop and stash', function()
    local before = #handle.kora_inventory.calls

    handle.fireEvent('onResourceStart', nil, 'kora_inventory')

    local after = #handle.kora_inventory.calls
    h.assertEqual(after, before + hospitalCount * 2, 'registerHospitals must re-run on a kora_inventory restart, not just at load')
end)

h.test('an unrelated resource starting does not re-trigger hospital registration', function()
    local before = #handle.kora_inventory.calls

    handle.fireEvent('onResourceStart', nil, 'some_other_resource')

    h.assertEqual(#handle.kora_inventory.calls, before, 'only a kora_inventory restart should re-trigger registerHospitals')
end)

h.test('optional pharmacy and stash points can be omitted independently', function()
    local hospital = Config.hospitals[1]
    local pharmacy, stash = hospital.pharmacy, hospital.stash
    hospital.pharmacy, hospital.stash = nil, nil
    local before = #handle.kora_inventory.calls

    handle.fireEvent('onResourceStart', nil, 'kora_inventory')

    hospital.pharmacy, hospital.stash = pharmacy, stash
    h.assertEqual(#handle.kora_inventory.calls, before + (hospitalCount - 1) * 2,
        'only configured inventory points should be registered')
end)

local function makeMedicAtGarage(src, hospital)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
    handle.setCoords(src, hospital.garage.x, hospital.garage.y, hospital.garage.z)
end

h.test('duty checkout creates one ephemeral server-owned vehicle without a garage row', function()
    local hospital = Config.hospitals[1]
    makeMedicAtGarage(20, hospital)

    local networkId = handle.Kora.callback.registry['kora_ambulance:server:spawnDutyVehicle'](20, hospital.name, 1)

    h.assertTrue(type(networkId) == 'number' and networkId > 0)
    h.assertTrue(handle.entities[networkId] ~= nil, 'the shared vehicle exists server-side')
    h.assertTrue(Duty.currentVehiclePlate(20) ~= nil, 'the checkout is tracked by source')
    h.assertEqual(Duty.currentVehicleNetworkId(20), networkId)
    local record, owner = Duty.vehicleRecord(networkId)
    h.assertEqual(owner, 20)
    h.assertEqual(record.vehicleIndex, 1)
    h.assertEqual(record.model, joaat(Config.dutyVehicles[1].model))
end)

h.test('duty checkout refuses remote callers and return deletes the ephemeral entity', function()
    local hospital = Config.hospitals[1]
    makeMedicAtGarage(21, hospital)
    handle.setCoords(21, 0, 0, 0)
    local remote = handle.Kora.callback.registry['kora_ambulance:server:spawnDutyVehicle'](21, hospital.name, 1)
    h.assertFalse(remote)

    makeMedicAtGarage(22, hospital)
    local networkId = handle.Kora.callback.registry['kora_ambulance:server:spawnDutyVehicle'](22, hospital.name, 1)
    handle.advanceTime(Config.dutyGarage.actionCooldown)
    handle.Kora.events.registry['kora_ambulance:server:storeDutyVehicle'](22)

    h.assertEqual(handle.entities[networkId], nil, 'return deletes the live entity')
    h.assertEqual(Duty.currentVehiclePlate(22), nil, 'return clears the checkout guard')
end)

h.test('disconnect deletes a checked-out duty vehicle', function()
    local hospital = Config.hospitals[1]
    makeMedicAtGarage(23, hospital)
    local networkId = handle.Kora.callback.registry['kora_ambulance:server:spawnDutyVehicle'](23, hospital.name, 1)

    handle.fireEvent('playerDropped', 23)

    h.assertEqual(handle.entities[networkId], nil)
    h.assertEqual(Duty.currentVehiclePlate(23), nil)
end)

h.test('EMS duty command requires a configured hospital duty point', function()
    local src = 24
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = false, grade = { level = 1 } }
    local command = handle.Kora.commands.registry['ems-duty']
    h.assertTrue(type(command) == 'function')

    command(src)
    h.assertFalse(handle.players[src].job.onduty, 'remote command must not toggle duty')

    local duty = Config.hospitals[1].duty
    handle.setCoords(src, duty.x, duty.y, duty.z)
    command(src)
    h.assertTrue(handle.players[src].job.onduty)
end)

h.report('duty')
