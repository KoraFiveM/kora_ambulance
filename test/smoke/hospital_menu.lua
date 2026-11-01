-- Every configured hospital must build a non-empty menu, and a hospital entry
-- with only a subset of features must still show the options it does have.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/hospital_menu.lua')

local handlers = {
    isEMS = function() return true end,
    checkIn = function() end, pharmacy = function() end, stash = function() end, duty = function() end,
    garageOptions = function() return { { label = 'Check out', onSelect = function() end } } end,
}

local function kinds(zones)
    local set = {}
    for _, zone in ipairs(zones) do set[zone.kind] = true end
    return set
end

h.test('every configured hospital builds a non-empty menu', function()
    for _, hospital in ipairs(Config.hospitals) do
        local zones = HospitalMenu.build(hospital, handlers)
        h.assertTrue(#zones > 0, hospital.name .. ' menu is empty')
        for _, zone in ipairs(zones) do
            h.assertTrue(#zone.options > 0, hospital.name .. ' ' .. zone.kind .. ' has no options')
            h.assertTrue(zone.radius > 0)
        end
    end
end)

h.test('every configured hospital shows all of the features it configures', function()
    for _, hospital in ipairs(Config.hospitals) do
        local set = kinds(HospitalMenu.build(hospital, handlers))
        h.assertTrue(set.checkIn, hospital.name .. ' check-in')
        h.assertEqual(set.pharmacy == true, hospital.pharmacy ~= nil)
        h.assertEqual(set.stash == true, hospital.stash ~= nil)
        h.assertEqual(set.duty == true, hospital.duty ~= nil)
        h.assertEqual(set.garage == true, hospital.garage ~= nil)
    end
end)

h.test('the sandy hospital builds the same feature set as pillbox', function()
    local byName = {}
    for _, hospital in ipairs(Config.hospitals) do byName[hospital.name] = hospital end
    h.assertTrue(byName.sandy and byName.pillbox)
    local sandy, pillbox = kinds(HospitalMenu.build(byName.sandy, handlers)), kinds(HospitalMenu.build(byName.pillbox, handlers))
    for kind in pairs(pillbox) do h.assertTrue(sandy[kind], 'sandy is missing ' .. kind) end
end)

h.test('a hospital with only coords still gets a check-in option', function()
    local zones = HospitalMenu.build({ name = 'bare', coords = vector4(1.0, 2.0, 3.0, 0.0) }, handlers)
    h.assertEqual(#zones, 1)
    h.assertEqual(zones[1].kind, 'checkIn')
    h.assertEqual(zones[1].coords.x, 1.0)
end)

h.test('a malformed optional field drops only that feature', function()
    local zones = HospitalMenu.build({
        name = 'odd', coords = vector4(1.0, 2.0, 3.0, 0.0), pharmacy = 'nowhere',
        stash = { slots = 5 }, duty = vector4(4.0, 5.0, 6.0, 0.0),
    }, handlers)
    local set = kinds(zones)
    h.assertTrue(set.checkIn and set.duty)
    h.assertTrue(not set.pharmacy and not set.stash and not set.garage)
end)

h.test('configured radii override the defaults', function()
    local original = Config.hospitalMenu.radius.duty
    Config.hospitalMenu.radius.duty = 4.5
    local zones = HospitalMenu.build(Config.hospitals[1], handlers)
    Config.hospitalMenu.radius.duty = original
    for _, zone in ipairs(zones) do
        if zone.kind == 'duty' then h.assertEqual(zone.radius, 4.5) end
    end
end)

h.report('hospital_menu')
