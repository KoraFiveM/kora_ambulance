-- Stretcher smoke test -- the pure canPickup eligibility check and the
-- server-side pickup/release relationship tracking (the other genuine new
-- differentiator, per the plan). Position sync itself is client-only/
-- native-heavy and is not exercised here -- see client/stretcher.lua's own
-- header for that design.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/duty.lua')
dofile('server/stretcher.lua')

h.test('canPickup refuses an alive patient', function()
    local ok, reason = Stretcher.canPickup('alive', false, false)
    h.assertFalse(ok)
    h.assertTrue(reason ~= nil)
end)

h.test('canPickup refuses a patient already being dragged by someone else', function()
    local ok = Stretcher.canPickup('laststand', true, false)
    h.assertFalse(ok)
end)

h.test('canPickup refuses a dragger who is already carrying someone', function()
    local ok = Stretcher.canPickup('dead', false, true)
    h.assertFalse(ok)
end)

h.test('canPickup allows a free EMS dragging a free laststand/dead patient', function()
    h.assertTrue((Stretcher.canPickup('laststand', false, false)))
    h.assertTrue((Stretcher.canPickup('dead', false, false)))
end)

local function makeMedic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
end

h.test('stretcherPickup registers the relationship and pushes begin to both sides', function()
    makeMedic(1)
    handle.ensurePlayer(2)
    Death.enterLaststand(2)

    local pickup = handle.Kora.events.registry['qbambulance:server:stretcherPickup']
    pickup(1, 2)

    h.assertEqual(Stretcher.draggingTarget(1), 2)
    h.assertEqual(Stretcher.draggedBy(2), 1)

    local draggerPush = handle.lastClient('qbambulance:client:stretcherBegin')
    h.assertTrue(draggerPush ~= nil)
end)

h.test('stretcherPickup refuses a non-EMS dragger (relationship stays empty)', function()
    handle.ensurePlayer(3) -- not EMS
    handle.ensurePlayer(4)
    Death.enterLaststand(4)

    local pickup = handle.Kora.events.registry['qbambulance:server:stretcherPickup']
    pickup(3, 4)

    h.assertEqual(Stretcher.draggingTarget(3), nil)
    h.assertEqual(Stretcher.draggedBy(4), nil)
end)

h.test('stretcherPickup refuses a second dragger on an already-carried patient', function()
    makeMedic(5)
    makeMedic(6)
    handle.ensurePlayer(7)
    Death.enterLaststand(7)

    local pickup = handle.Kora.events.registry['qbambulance:server:stretcherPickup']
    pickup(5, 7)
    pickup(6, 7) -- should be refused -- 7 is already being dragged by 5

    h.assertEqual(Stretcher.draggedBy(7), 5)
    h.assertEqual(Stretcher.draggingTarget(6), nil)
end)

h.test('stretcherRelease clears the relationship and notifies both sides', function()
    makeMedic(8)
    handle.ensurePlayer(9)
    Death.enterLaststand(9)

    local pickup = handle.Kora.events.registry['qbambulance:server:stretcherPickup']
    local release = handle.Kora.events.registry['qbambulance:server:stretcherRelease']

    pickup(8, 9)
    release(8)

    h.assertEqual(Stretcher.draggingTarget(8), nil)
    h.assertEqual(Stretcher.draggedBy(9), nil)
end)

h.test('a playerDropped for the dragger also releases their patient', function()
    makeMedic(10)
    handle.ensurePlayer(11)
    Death.enterLaststand(11)

    handle.Kora.events.registry['qbambulance:server:stretcherPickup'](10, 11)
    h.assertEqual(Stretcher.draggedBy(11), 10)

    handle.fireEvent('playerDropped', 10)
    h.assertEqual(Stretcher.draggedBy(11), nil)
    local released = handle.lastClient('qbambulance:client:stretcherEnd')
    h.assertEqual(released.target, 11, 'the surviving patient must be told to stop the carry presentation')
end)

h.test('heartbeat releases a relationship that is no longer nearby', function()
    makeMedic(12)
    handle.ensurePlayer(13)
    Death.enterLaststand(13)
    handle.Kora.events.registry['qbambulance:server:stretcherPickup'](12, 13)
    handle.setCoords(13, 100, 0, 0)

    handle.Kora.events.registry['qbambulance:server:stretcherHeartbeat'](12)

    h.assertEqual(Stretcher.draggingTarget(12), nil)
    h.assertEqual(Stretcher.draggedBy(13), nil)
end)

h.test('a missing carry heartbeat expires ownership so another medic can help', function()
    makeMedic(14)
    makeMedic(15)
    handle.ensurePlayer(16)
    Death.enterLaststand(16)

    local pickup = handle.Kora.events.registry['qbambulance:server:stretcherPickup']
    pickup(14, 16)
    h.assertEqual(Stretcher.draggedBy(16), 14)

    handle.advanceTime(Config.transport.heartbeatTtl + 1)
    Stretcher.sweep(GetGameTimer())
    h.assertEqual(Stretcher.draggedBy(16), nil)
    h.assertEqual(Stretcher.draggingTarget(14), nil)

    pickup(15, 16)
    h.assertEqual(Stretcher.draggedBy(16), 15, 'expired ownership must not block a replacement medic')
end)

h.test('physical transport mode transitions are explicit and reject illegal edges', function()
    h.assertEqual(Stretcher.transition('world', 'push'), 'pushed')
    h.assertEqual(Stretcher.transition('pushed', 'release'), 'world')
    h.assertEqual(Stretcher.transition('world', 'stow'), 'vehicle')
    h.assertEqual(Stretcher.transition('vehicle', 'unstow'), 'world')
    h.assertEqual(Stretcher.transition('vehicle', 'push'), nil)
    h.assertEqual(Stretcher.transition('world', 'unstow'), nil)
end)

local function checkoutTransportVehicle(src, vehicleIndex)
    local hospital = Config.hospitals[1]
    makeMedic(src)
    handle.setCoords(src, hospital.garage.x, hospital.garage.y, hospital.garage.z)
    return handle.Kora.callback.registry['qbambulance:server:spawnDutyVehicle'](src, hospital.name, vehicleIndex or 1)
end

local function deployTransport(src)
    local vehicleNetworkId = checkoutTransportVehicle(src, 1)
    local stretcherNetworkId, reason = Stretcher.deploy(src, vehicleNetworkId)
    h.assertTrue(stretcherNetworkId ~= nil, reason)
    return vehicleNetworkId, stretcherNetworkId
end

h.test('deployment requires an on-duty medic and a tracked compatible duty vehicle', function()
    handle.ensurePlayer(20)
    local untracked = CreateVehicle(joaat('ambulance'), 0, 0, 0, 0, true, false)
    h.assertEqual((Stretcher.deploy(20, untracked)), nil, 'a civilian cannot deploy')

    makeMedic(20)
    h.assertEqual((Stretcher.deploy(20, untracked)), nil, 'an arbitrary ambulance is not a duty vehicle')

    local unsupported = checkoutTransportVehicle(21, 2)
    h.assertEqual((Stretcher.deploy(21, unsupported)), nil, 'a configured vehicle without stretcher support is refused')
end)

h.test('one server-created stretcher is tied to one compatible duty vehicle', function()
    local vehicleNetworkId, stretcherNetworkId = deployTransport(22)
    h.assertEqual(Stretcher.vehicleStretcher(vehicleNetworkId), stretcherNetworkId)
    h.assertEqual(Stretcher.state(stretcherNetworkId).mode, 'world')
    h.assertEqual(handle.entities[stretcherNetworkId].type, 3)
    h.assertEqual(handle.entities[stretcherNetworkId].model, joaat(Config.transport.model))
    h.assertEqual(handle.entityStates[stretcherNetworkId].qbambulanceStretcher.networkId, stretcherNetworkId)
    h.assertEqual((Stretcher.deploy(22, vehicleNetworkId)), nil, 'a second stretcher cannot be deployed')
end)

h.test('a downed patient can be loaded, transported in the linked vehicle, and unloaded', function()
    local vehicleNetworkId, stretcherNetworkId = deployTransport(23)
    local stretcher = handle.entities[stretcherNetworkId]
    handle.setCoords(23, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)

    h.assertTrue((Stretcher.beginPush(23, stretcherNetworkId)))
    h.assertEqual(Stretcher.state(stretcherNetworkId).mode, 'pushed')

    handle.ensurePlayer(24)
    handle.setCoords(24, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)
    Death.enterLaststand(24)
    h.assertTrue((Stretcher.loadPatient(23, stretcherNetworkId, 24)))
    h.assertEqual(Stretcher.patientStretcher(24), stretcherNetworkId)

    local vehicle = handle.entities[vehicleNetworkId]
    stretcher.coords = vehicle.coords -- simulate the client-owned push movement
    handle.setCoords(23, vehicle.coords.x, vehicle.coords.y, vehicle.coords.z)
    h.assertTrue((Stretcher.stow(23, stretcherNetworkId, vehicleNetworkId)))
    local stowed = Stretcher.state(stretcherNetworkId)
    h.assertEqual(stowed.mode, 'vehicle')
    h.assertEqual(stowed.patient, 24, 'the patient remains loaded for transport')

    h.assertTrue((Stretcher.unstow(23, vehicleNetworkId)))
    handle.setCoords(23, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)
    handle.setCoords(24, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)
    h.assertTrue((Stretcher.unloadPatient(23, stretcherNetworkId)))
    h.assertEqual(Stretcher.patientStretcher(24), nil)
end)

h.test('alive patients and competing patient relationships are refused', function()
    local _, stretcherNetworkId = deployTransport(25)
    local coords = handle.entities[stretcherNetworkId].coords
    handle.setCoords(25, coords.x, coords.y, coords.z)
    handle.ensurePlayer(26)
    handle.setCoords(26, coords.x, coords.y, coords.z)

    h.assertFalse((Stretcher.loadPatient(25, stretcherNetworkId, 26)), 'an alive patient cannot be loaded')
    Death.enterLaststand(26)
    handle.Kora.events.registry['qbambulance:server:stretcherPickup'](25, 26)
    h.assertFalse((Stretcher.loadPatient(25, stretcherNetworkId, 26)), 'a carried patient cannot also be loaded')
end)

h.test('heartbeat expiry releases an operator without deleting the stretcher', function()
    local _, stretcherNetworkId = deployTransport(27)
    local coords = handle.entities[stretcherNetworkId].coords
    handle.setCoords(27, coords.x, coords.y, coords.z)
    h.assertTrue((Stretcher.beginPush(27, stretcherNetworkId)))

    handle.advanceTime(Config.transport.heartbeatTtl + 1)
    Stretcher.sweep(GetGameTimer())
    h.assertEqual(Stretcher.state(stretcherNetworkId).mode, 'world')
    h.assertEqual(Stretcher.state(stretcherNetworkId).operator, nil)
    h.assertTrue(handle.entities[stretcherNetworkId] ~= nil)
end)

h.test('returning a duty vehicle removes its stretcher and releases its patient', function()
    local vehicleNetworkId, stretcherNetworkId = deployTransport(28)
    local stretcher = handle.entities[stretcherNetworkId]
    handle.setCoords(28, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)
    handle.ensurePlayer(29)
    handle.setCoords(29, stretcher.coords.x, stretcher.coords.y, stretcher.coords.z)
    Death.enterLaststand(29)
    h.assertTrue((Stretcher.loadPatient(28, stretcherNetworkId, 29)))

    local garage = Config.hospitals[1].garage
    handle.setCoords(28, garage.x, garage.y, garage.z)
    handle.advanceTime(Config.dutyGarage.actionCooldown)
    handle.Kora.events.registry['qbambulance:server:storeDutyVehicle'](28)

    h.assertEqual(Stretcher.vehicleStretcher(vehicleNetworkId), nil)
    h.assertEqual(Stretcher.patientStretcher(29), nil)
    h.assertEqual(handle.entities[stretcherNetworkId], nil)
end)

h.test('lost physical entities are swept and cannot leave stale relationships', function()
    local vehicleNetworkId, stretcherNetworkId = deployTransport(30)
    DeleteEntity(stretcherNetworkId)
    Stretcher.sweep(GetGameTimer())
    h.assertEqual(Stretcher.vehicleStretcher(vehicleNetworkId), nil)
    h.assertEqual(Stretcher.state(stretcherNetworkId), nil)
end)

h.test('deployment transforms offsets with server ZXY rotations', function()
    local vehicleId = checkoutTransportVehicle(31, 1)
    local vehicle = handle.entities[vehicleId]
    local origin = vehicle.coords
    local offset = Config.dutyVehicles[1].stretcher.offset
    local function check(rotation, x, y, z)
        vehicle.rotation = vector3(rotation[1], rotation[2], rotation[3])
        local id, reason = Stretcher.deploy(31, vehicleId)
        h.assertTrue(id ~= nil, reason)
        local coords = handle.entities[id].coords
        h.assertTrue(math.abs(coords.x - origin.x - x) < 0.000001)
        h.assertTrue(math.abs(coords.y - origin.y - y) < 0.000001)
        h.assertTrue(math.abs(coords.z - origin.z - z) < 0.000001)
        DeleteEntity(id)
        Stretcher.sweep(GetGameTimer())
    end
    check({ 0, 0, 0 }, offset.x, offset.y, offset.z)
    check({ 0, 0, 90 }, -offset.y, offset.x, offset.z)
    check({ 90, 0, 0 }, offset.x, -offset.z, offset.y)
    check({ 0, 90, 0 }, offset.z, offset.y, -offset.x)
    check({ 90, 90, 90 }, -offset.x, offset.z, offset.y)
end)

h.report('stretcher')
