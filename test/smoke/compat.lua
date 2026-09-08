-- Secure legacy adapter smoke tests. Compatibility may start the modern UX,
-- but it must not bypass treatment, revive, bed, inventory or privacy gates.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/billing.lua')
dofile('server/duty.lua')
dofile('server/hospital.lua')
dofile('server/revive.lua')
dofile('server/treatment.lua')

Config.compat.enabled = false
dofile('server/compat/hospital.lua')

h.test('compatibility endpoints are not registered when disabled', function()
    h.assertEqual(handle.QB.callback.registry['hospital:GetDoctors'], nil)
    h.assertEqual(handle.QB.callback.registry['hospital:GetPlayerStatus'], nil)
end)

Config.compat.enabled = true
dofile('server/compat/hospital.lua')

local function makeMedic(src)
    handle.ensurePlayer(src)
    handle.players[src].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }
end

h.test('GetDoctors returns a count rather than disclosing the player list', function()
    makeMedic(1)
    makeMedic(2)
    local count = handle.QB.callback.registry['hospital:GetDoctors'](50)
    h.assertEqual(type(count), 'number')
    h.assertTrue(count >= 2)
end)

h.test('cross-player medical status is private except to nearby on-duty EMS', function()
    handle.ensurePlayer(3)
    handle.ensurePlayer(4)
    Death.recordWound(4, 'chest', 2)

    local callback = handle.QB.callback.registry['hospital:GetPlayerStatus']
    h.assertEqual(callback(3, 4), nil, 'a civilian cannot inspect another patient')

    local selfStatus = callback(4, 4)
    h.assertEqual(selfStatus.woundData.chest, 2)
    selfStatus.woundData.chest = nil
    h.assertEqual(Death.getWoundData(4).chest, 2, 'compat returns a detached wound table')

    makeMedic(5)
    handle.setCoords(5, 0, 0, 0)
    handle.setCoords(4, 100, 0, 0)
    h.assertEqual(callback(5, 4), nil, 'distant EMS is still refused')
    handle.setCoords(4, 0, 0, 0)
    h.assertEqual(callback(5, 4).woundData.chest, 2)
end)

h.test('legacy injury sync and destructive item removal are inert by default', function()
    handle.ensurePlayer(6)
    handle.players[6].items.bandage = 2
    handle.fireEvent('hospital:server:SyncInjuries', 6, { head = 4 })
    handle.fireEvent('hospital:server:removeBandage', 6)

    h.assertEqual(next(Death.getWoundData(6)), nil)
    h.assertEqual(handle.players[6].items.bandage, 2)
end)

h.test('legacy armor and weapon modifiers remain reduce-only', function()
    handle.ensurePlayer(7)
    handle.players[7].armour = 50
    handle.fireEvent('hospital:server:SetArmor', 7, 90)
    h.assertEqual(handle.players[7].armour, 50)
    handle.fireEvent('hospital:server:SetArmor', 7, 20)
    h.assertEqual(handle.players[7].armour, 20)

    handle.fireEvent('hospital:server:SetWeaponDamage', 7, 12345, 9.0)
    local event = handle.lastClient('hospital:client:SetWeaponDamage')
    h.assertEqual(event.target, 7)
    h.assertEqual(event.args[2], 1.0)
end)

h.test('legacy revive starts modern CPR UX without reviving or consuming an item', function()
    makeMedic(8)
    handle.players[8].items.defibrillator = 1
    handle.ensurePlayer(9)
    Death.enterLaststand(9)

    handle.fireEvent('hospital:server:RevivePlayer', 8, 9)
    local event = handle.lastClient('qbambulance:client:reviveRequested')
    h.assertTrue(event ~= nil)
    h.assertEqual(event.target, 8)
    h.assertEqual(event.args[1], 9)
    h.assertTrue(Death.isLaststand(9))
    h.assertEqual(handle.players[8].items.defibrillator, 1)
end)

h.test('legacy treatment starts modern treatment UX without clearing or consuming', function()
    makeMedic(10)
    handle.players[10].items.bandage = 1
    handle.ensurePlayer(11)
    Death.recordWound(11, 'left_arm', 2)

    handle.fireEvent('hospital:server:TreatWounds', 10, 11)
    local event = handle.lastClient('qbambulance:client:treatmentRequested')
    h.assertTrue(event ~= nil)
    h.assertEqual(event.target, 10)
    h.assertEqual(event.args[1], 11)
    h.assertEqual(Death.getWoundData(11).left_arm, 2)
    h.assertEqual(handle.players[10].items.bandage, 1)
end)

h.test('legacy SendToBed ignores the claimed index and uses Hospital allocation', function()
    local src = 12
    local hospital = Config.hospitals[1]
    handle.ensurePlayer(src)
    handle.setHealth(src, 150)
    handle.setCoords(src, hospital.checkIn.x, hospital.checkIn.y, hospital.checkIn.z)

    handle.fireEvent('hospital:server:SendToBed', src, 999)
    local session = Hospital.getSession(src)
    h.assertTrue(session ~= nil)
    h.assertEqual(session.hospital, hospital.name)
    h.assertEqual(session.bedIndex, 1)

    handle.fireEvent('hospital:server:LeaveBed', src)
    h.assertEqual(Hospital.getSession(src), nil)
end)

h.report('compat')
