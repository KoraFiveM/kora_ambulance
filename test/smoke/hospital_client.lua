-- Hospital client targets are facility-only and must survive kora_target reloads
-- even when a deployment omits optional pharmacy/stash fields.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('shared/config.lua')
dofile('shared/hospital_menu.lua')

local locale = dofile('locales/en.lua')
Kora.lang = function(key)
    local section, name = key:match('^([^.]+)%.(.+)$')
    return locale[section][name]
end

Config.hospitals[1].pharmacy = nil
Config.hospitals[1].stash = nil
local hospitalBlips = {}
Kora.blips.create = function(_, options)
    hospitalBlips[#hospitalBlips + 1] = options
    return #hospitalBlips
end
local removedBlips = {}
Kora.blips.remove = function(blip) removedBlips[#removedBlips + 1] = blip end
local keybinds = {}
Kora.keybind = { add = function(definition)
    local bind = { definition = definition, disabled = definition.disabled == true }
    bind.disable = function(toggle) bind.disabled = toggle ~= false end
    keybinds[definition.name] = bind
    return bind
end }
dofile('client/hospital.lua')

h.test('hospital check-in targets tolerate optional facility points being absent', function()
    local checkIns = 0
    for _, call in ipairs(handle.kora_target.calls) do
        h.assertEqual(call.kind, 'sphere')
        if call.definition.options[1].label == 'Check In for Care' then checkIns = checkIns + 1 end
    end
    h.assertEqual(checkIns, #Config.hospitals)
end)

h.test('hospital markers use canonical category and facility names', function()
    h.assertEqual(#hospitalBlips, #Config.hospitals)
    h.assertEqual(hospitalBlips[1].category, 'Hospital')
    h.assertEqual(hospitalBlips[1].name, 'Pillbox Hill Medical')
    h.assertEqual(hospitalBlips[1].label, nil, 'kora_lib composes the map label')
end)

h.test('hospital check-in targets register again after kora_target restarts', function()
    local before = #handle.kora_target.calls
    handle.fireEvent('onClientResourceStart', nil, 'kora_target')
    h.assertEqual(#handle.kora_target.calls, before * 2)
end)

h.test('re-registering after a kora_target restart replaces the hospital blips instead of stacking them', function()
    h.assertEqual(#removedBlips, #Config.hospitals)
    h.assertEqual(#hospitalBlips, #Config.hospitals * 2)
end)

h.test('completed server care heals locally; cancelled and inactive care do not', function()
    handle.ensurePlayer(1)
    handle.setHealth(1, 40)
    PlayerPedId = function() return 1 end
    SetEntityHealth = function(ped, value) handle.setHealth(ped, value) end -- client-only native
    SetEntityCoords = function() end
    ClearPedTasks = function() end
    local heading
    SetEntityHeading = function(_, value) heading = value end
    local animations = {}
    local dictLoaded = true
    RequestAnimDict = function() end
    HasAnimDictLoaded = function() return dictLoaded end
    RemoveAnimDict = function() end
    TaskPlayAnim = function(_, dict, clip, _, _, _, flag)
        animations[#animations + 1] = { dict = dict, clip = clip, flag = flag }
    end
    TaskStartScenarioAtPosition = function() error('check-in must play the bed animation') end
    local care = { token = 'care-test', bed = { x = 1, y = 2, z = 3, w = 90.0 }, duration = 5000 }
    handle.fireEvent('kora_ambulance:client:checkInAccepted', 65535, care)
    h.assertEqual(heading, 90.0)
    local realWait = Wait
    Wait = coroutine.yield
    handle.step()
    h.assertEqual(#animations, 1)
    h.assertEqual(animations[1].dict, 'anim@gangops@morgue@table@')
    h.assertEqual(animations[1].clip, 'body_search')
    h.assertEqual(animations[1].flag, 1, 'animation loops on the bed')
    handle.fireEvent('kora_ambulance:client:bedReleased', 65535, 'left-bed')
    h.assertEqual(handle.players[1].health, 40)
    handle.fireEvent('kora_ambulance:client:bedReleased', 65535, 'completed')
    h.assertEqual(handle.players[1].health, 40)
    dictLoaded = false
    care = { token = 'care-delayed', bed = care.bed, duration = care.duration }
    handle.fireEvent('kora_ambulance:client:checkInAccepted', 65535, care)
    handle.step()
    handle.fireEvent('kora_ambulance:client:bedReleased', 65535, 'completed')
    h.assertEqual(handle.players[1].health, 200)
    dictLoaded = true
    handle.step()
    h.assertEqual(#animations, 1, 'a released patient stays off the bed when the dictionary finishes loading')
    Wait = realWait
end)

h.test('leaving the bed is a keybind enabled only while a bed is reserved, with no per-frame loop', function()
    local bind = keybinds.kora_ambulance_leave_bed
    h.assertTrue(bind ~= nil, 'leave-bed keybind registered')
    h.assertEqual(bind.definition.defaultKey, 'E')
    h.assertTrue(bind.disabled, 'disabled with no bed reserved')

    PlayerPedId = function() return 1 end
    SetEntityCoords = function() end
    ClearPedTasks = function() end
    local care = { token = 'care-key', bed = { x = 1, y = 2, z = 3 }, duration = 5000 }
    local waits = {}
    local realWait = Wait
    Wait = function(ms) waits[#waits + 1] = ms end
    local triggered = {}
    Kora.events.trigger = function(name, ...) triggered[#triggered + 1] = { name = name, args = { ... } } end
    local completions = 0
    Kora.callback.trigger = function(name) if name == 'kora_ambulance:server:bedCareCompleted' then completions = completions + 1 end return true end

    bind.definition.onPressed() -- no bed: ignored
    h.assertEqual(#triggered, 0)

    handle.fireEvent('kora_ambulance:client:checkInAccepted', 65535, care)
    h.assertFalse(bind.disabled, 'enabled while resting')
    bind.definition.onPressed()
    h.assertEqual(#triggered, 1)
    h.assertEqual(triggered[1].name, 'kora_ambulance:server:bedLeft')
    h.assertEqual(triggered[1].args[1], 'care-key')
    h.assertTrue(bind.disabled, 'disabled once the leave request is sent')

    handle.fireEvent('kora_ambulance:client:bedReleased', 65535, 'left-bed')
    handle.step() -- the care timer wakes after the bed was released: must not complete it
    h.assertEqual(completions, 0)
    h.assertEqual(waits[#waits], 5000, 'one sleep for the whole duration')

    handle.fireEvent('kora_ambulance:client:checkInAccepted', 65535, { token = 'care-done', bed = care.bed, duration = 5000 })
    handle.step()
    h.assertEqual(completions, 1)
    h.assertTrue(bind.disabled, 'disabled once care is completing')
    handle.fireEvent('kora_ambulance:client:bedReleased', 65535, 'completed')
    Wait = realWait
end)

h.report('hospital_client')
