local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

h.test('the shipped hospital, injury and transport configuration is valid', function()
    h.assertTrue(Config.validate())
end)

h.test('validation rejects a non-boolean downed camera option', function()
    local allowCameraMovement = Config.death.allowCameraMovement
    Config.death.allowCameraMovement = 'yes'
    h.assertThrows(Config.validate)
    Config.death.allowCameraMovement = allowCameraMovement
end)

h.test('validation rejects a negative report retry window', function()
    local window = Config.death.reportRetryWindow
    Config.death.reportRetryWindow = -1
    h.assertThrows(Config.validate)
    Config.death.reportRetryWindow = window
end)

h.test('the death screen ships disabled, with dim and hints on', function()
    h.assertEqual(Config.death.screen.enabled, false)
    h.assertEqual(Config.death.screen.dim, true)
    h.assertEqual(Config.death.screen.showHints, true)
end)

h.test('validation rejects non-boolean death screen options', function()
    for _, key in ipairs({ 'enabled', 'dim', 'showHints' }) do
        local value = Config.death.screen[key]
        Config.death.screen[key] = 'yes'
        h.assertThrows(Config.validate)
        Config.death.screen[key] = value
    end
    local screen = Config.death.screen
    Config.death.screen = nil
    h.assertThrows(Config.validate)
    Config.death.screen = screen
end)

h.test('validation rejects an empty hospital list', function()
    local hospitals = Config.hospitals
    Config.hospitals = {}
    h.assertThrows(Config.validate)
    Config.hospitals = hospitals
end)

h.test('validation rejects malformed injury ranges', function()
    local maxDamage = Config.injuries.maxDamage
    Config.injuries.maxDamage = Config.injuries.minDamage - 1
    h.assertThrows(Config.validate)
    Config.injuries.maxDamage = maxDamage
end)

h.report('config')
