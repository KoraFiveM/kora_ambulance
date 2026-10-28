-- Client damage capture: a native hit is only reported after kora_lib observes
-- a matching local health decrease within the configured window.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')

local healthHandler
local ped = 77
local damageBoneFound = true
local damageBone = 31086
local reports = {}

State = { isAlive = function() return true end }
handle.QB.cache = {
    ped = function() return ped end,
    onChange = function(key, handler)
        h.assertEqual(key, 'health')
        healthHandler = handler
    end,
}
handle.QB.events.trigger = function(name, payload)
    reports[#reports + 1] = { name = name, payload = payload }
end
GetPedLastDamageBone = function(target)
    h.assertEqual(target, ped)
    return damageBoneFound, damageBone
end

dofile('client/damage.lua')

local function nativeHit(options)
    options = options or {}
    handle.fireEvent('gameEventTriggered', 0, 'CEventNetworkEntityDamage', {
        options.victim or ped,
        88,
        0,
        options.fatal and 1 or 0,
    })
end

h.test('a mapped local hit reports measurements only after an actual health decrease', function()
    local before = #reports
    damageBoneFound = true
    damageBone = 31086
    nativeHit()
    h.assertEqual(#reports, before)

    healthHandler(180, 200)
    h.assertEqual(#reports, before + 1)
    local report = reports[#reports]
    h.assertEqual(report.name, 'qbambulance:server:hitObserved')
    h.assertEqual(report.payload.bone, 31086)
    h.assertEqual(report.payload.bodyPart, 'head')
    h.assertEqual(report.payload.damage, 20)
    h.assertEqual(report.payload.healthAfter, 180)
    h.assertFalse(report.payload.fallback)
    h.assertEqual(report.payload.tier, nil)
    h.assertEqual(report.payload.target, nil)
end)

h.test('remote victims and fatal damage events are ignored', function()
    local before = #reports
    nativeHit({ victim = 999 })
    healthHandler(170, 180)
    nativeHit({ fatal = true })
    healthHandler(160, 170)
    h.assertEqual(#reports, before)
end)

h.test('an armour-only hit with no health decrease emits nothing', function()
    local before = #reports
    nativeHit()
    h.assertEqual(#reports, before)
    handle.advanceTime(Config.injuries.captureWindow + 1)
    healthHandler(180, 180)
    h.assertEqual(#reports, before)
end)

h.test('tiny losses and health increases are ignored without leaking their bone', function()
    local before = #reports
    nativeHit()
    healthHandler(198, 200)
    healthHandler(180, 198)
    h.assertEqual(#reports, before)

    nativeHit()
    healthHandler(200, 180)
    healthHandler(170, 200)
    h.assertEqual(#reports, before)
end)

h.test('missing and unmapped bones use a legal weighted fallback', function()
    local before = #reports
    damageBoneFound = false
    damageBone = nil
    nativeHit()
    healthHandler(190, 200)
    local missing = reports[#reports].payload
    h.assertEqual(#reports, before + 1)
    h.assertEqual(missing.bone, false)
    h.assertTrue(missing.fallback)
    h.assertTrue(Wounds.bodyPartDef(missing.bodyPart) ~= nil)

    damageBoneFound = true
    damageBone = 65535
    nativeHit()
    healthHandler(180, 190)
    local unmapped = reports[#reports].payload
    h.assertEqual(unmapped.bone, 65535)
    h.assertTrue(unmapped.fallback)
    h.assertTrue(Wounds.bodyPartDef(unmapped.bodyPart) ~= nil)
end)

h.test('an expired correlation window and oversized losses are ignored', function()
    local before = #reports
    damageBoneFound = true
    damageBone = 18905
    nativeHit()
    handle.advanceTime(Config.injuries.captureWindow + 1)
    healthHandler(190, 200)
    h.assertEqual(#reports, before)

    nativeHit()
    healthHandler(50, 200)
    h.assertEqual(#reports, before)
end)

h.report('damage')
