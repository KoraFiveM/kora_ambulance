-- Client death smoke test -- kora_lib cache owns fatal-injury detection while
-- kora_ambulance immediately suppresses the native wasted flow and reports the
-- edge through a corroborating server callback without any baseevents
-- dependency.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/downed.lua')

local deathHandler
local coords = { x = 10.0, y = 20.0, z = 30.0 }
local resurrectedAt
local health
local ragdolled = false
local reportedCause
local acceptReport = false
local reportAttempts = 0
local playedAnimations = {}
local stoppedAnimation
local disabledControls = {}
local playerFiringDisabled = false
local stopControlLoopAfterFrame = false
local fatal = true
local ragdolling = false
local playingAnim = false
local enabledControls = {}

-- Minimal kora_lib textui: a stack where only the newest entry is visible.
local textui = { entries = {}, order = {} }
handle.Kora.textui = {
    show = function(text, opts)
        textui.n = (textui.n or 0) + 1
        local id = 1000 + textui.n
        textui.entries[id] = { text = text, opts = opts }
        textui.order[#textui.order + 1] = id
        return id
    end,
    update = function(id, text, opts)
        if not textui.entries[id] then return false end
        textui.entries[id] = { text = text, opts = opts }
        return true
    end,
    hide = function(id)
        if not textui.entries[id] then return false end
        textui.entries[id] = nil
        for i, v in ipairs(textui.order) do if v == id then table.remove(textui.order, i) break end end
        return true
    end,
    isVisible = function(id) return textui.entries[id] ~= nil and textui.order[#textui.order] == id end,
}
local function visiblePrompt()
    local id = textui.order[#textui.order]
    return id and textui.entries[id] or nil
end

handle.Kora.cache = {
    onChange = function(key, handler)
        h.assertEqual(key, 'isDead')
        deathHandler = handler
    end,
    coords = function() return coords end,
    isDead = function() return fatal end,
}
handle.Kora.callback.trigger = function(name, cause)
    h.assertEqual(name, 'kora_ambulance:server:reportDeath')
    reportedCause = cause
    reportAttempts = reportAttempts + 1
    return acceptReport
end
handle.Kora.anim = {
    play = function(entity, dict, clip, options)
        local animation = { entity = entity, dict = dict, clip = clip, options = options }
        playedAnimations[#playedAnimations + 1] = animation
        return animation
    end,
    stopHandle = function(handleToStop)
        stoppedAnimation = handleToStop
        return true
    end,
}

local clientStateWrites = 0
_G.LocalPlayer = { state = { set = function() clientStateWrites = clientStateWrites + 1 end } }
local commands = {}
_G.RegisterCommand = function(name, handler) commands[name] = handler end
local serverEvents = {}
_G.TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end
local keybinds = {}
handle.Kora.keybind = { add = function(definition) keybinds[definition.name] = definition end }
handle.Kora.world = { getStreetNames = function() return 'Alta Street', 'Strawberry Ave' end }
_G.PlayerId = function() return 1 end
_G.PlayerPedId = function() return 77 end
_G.GetEntityHeading = function() return 90.0 end
_G.NetworkResurrectLocalPlayer = function(x, y, z, heading)
    resurrectedAt = { x = x, y = y, z = z, heading = heading }
end
_G.SetEntityHealth = function(_, value) health = value end
_G.SetPedToRagdoll = function() ragdolled = true end
_G.IsPedFatallyInjured = function() return fatal end
_G.GetEntityCoords = function() return coords end
_G.IsPedRagdoll = function() return ragdolling end
_G.IsPedInAnyVehicle = function() return false end
_G.IsEntityPlayingAnim = function() return playingAnim end
local dimAlphas = {}
_G.DrawRect = function(_, _, _, _, _, _, _, alpha) dimAlphas[#dimAlphas + 1] = alpha end
_G.EnableControlAction = function(_, control) enabledControls[control] = true end
_G.GetEntityMaxHealth = function() return 200 end
local groundZ = false
_G.GetGroundZFor_3dCoord = function() return groundZ ~= false, groundZ or 0.0 end
_G.GetEntityHealth = function() return health or 200 end
_G.ClearPedTasksImmediately = function() end
_G.SetPedCanRagdoll = function() end
_G.DisableControlAction = function(_, control)
    disabledControls[control] = true
end
_G.DisablePlayerFiring = function(_, disabled)
    playerFiringDisabled = disabled
    if stopControlLoopAfterFrame then
        State.inLaststand = false
        State.isDead = false
    end
end

dofile('client/death.lua')

h.test('an uncorroborated death report does not resurrect the local ped', function()
    h.assertTrue(deathHandler ~= nil)
    Config.death.reportRetryWindow = 0

    deathHandler(true, false)
    handle.step()

    h.assertEqual(reportAttempts, Config.death.reportRetryAttempts)
    h.assertEqual(health, nil)
    h.assertFalse(ragdolled)
    Config.death.reportRetryWindow = 15000
end)

h.test('a death report the server only corroborates late keeps being retried instead of abandoned', function()
    acceptReport = false
    reportAttempts = 0
    ragdolled = false
    local attemptsToRefuse = Config.death.reportRetryAttempts + 2
    handle.Kora.callback.trigger = function()
        reportAttempts = reportAttempts + 1
        return reportAttempts > attemptsToRefuse
    end

    deathHandler(true, false)
    handle.step()

    h.assertEqual(reportAttempts, attemptsToRefuse + 1, 'slow retries must continue past the quick burst')
    h.assertTrue(ragdolled, 'the late corroboration must still resurrect the ped')
    handle.Kora.callback.trigger = function(_, cause)
        reportedCause = cause
        reportAttempts = reportAttempts + 1
        return acceptReport
    end
end)

h.test('a corroborated death report suppresses native wasted after server acceptance', function()
    acceptReport = true
    reportAttempts = 0

    deathHandler(true, false)

    handle.step()
    h.assertEqual(reportAttempts, 1)
    h.assertEqual(reportedCause, 'died')
    h.assertEqual(resurrectedAt.x, 10.0)
    h.assertEqual(resurrectedAt.y, 20.0)
    h.assertEqual(resurrectedAt.z, 30.0)
    h.assertEqual(resurrectedAt.heading, 90.0)
    h.assertEqual(health, 101, 'downed health stays above the fatal line (<=100 is dead to GTA)')
    h.assertTrue(ragdolled)

end)

h.test('client death lifecycle never writes the server-owned emsDown state bag', function()
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    h.assertTrue(State.inLaststand)
    h.assertEqual(playedAnimations[#playedAnimations].clip, 'writhe_loop')
    h.assertEqual(clientStateWrites, 0)
end)

h.test('death screen effect retains and releases kora_lib handle identity', function()
    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)
    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)

    h.assertEqual(#handle.Kora.fx.started, 1, 'repeated dead-state updates must not leak screen handles')
    h.assertEqual(playedAnimations[#playedAnimations].clip, 'dead_a')
    local startedHandle = handle.Kora.fx.started[1].handle
    local activeDownedAnimation = playedAnimations[#playedAnimations]

    handle.fireEvent('kora_ambulance:client:revived', 0, 20)

    h.assertEqual(handle.Kora.fx.stopped[1], startedHandle,
        'revive must release the opaque handle returned by screenEffect')
    h.assertEqual(stoppedAnimation, activeDownedAnimation,
        'revive must release the downed animation it started')
end)

h.test('downed controls block movement while allowing configured camera movement', function()
    disabledControls = {}
    playerFiringDisabled = false
    stopControlLoopAfterFrame = true

    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    h.assertFalse(disabledControls[1], 'horizontal camera look should remain enabled')
    h.assertFalse(disabledControls[2], 'vertical camera look should remain enabled')
    h.assertTrue(disabledControls[30], 'horizontal movement must remain disabled')
    h.assertTrue(disabledControls[31], 'vertical movement must remain disabled')
    h.assertTrue(playerFiringDisabled, 'weapon firing must remain disabled')
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('downed camera movement can be disabled in config', function()
    local allowCameraMovement = Config.death.allowCameraMovement
    Config.death.allowCameraMovement = false
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    Config.death.allowCameraMovement = allowCameraMovement
    h.assertTrue(disabledControls[1])
    h.assertTrue(disabledControls[2])
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('the fully dead state keeps camera look free and still blocks movement and weapons', function()
    disabledControls = {}
    playerFiringDisabled = false
    stopControlLoopAfterFrame = true

    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    h.assertFalse(disabledControls[0], 'camera switching must stay enabled while dead')
    h.assertFalse(disabledControls[1], 'horizontal camera look must stay enabled while dead')
    h.assertFalse(disabledControls[2], 'vertical camera look must stay enabled while dead')
    h.assertTrue(disabledControls[30], 'horizontal movement must stay disabled while dead')
    h.assertTrue(disabledControls[24], 'attack must stay disabled while dead')
    h.assertTrue(playerFiringDisabled, 'weapon firing must stay disabled while dead')
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('laststand never blocks look, chat, voice or pause controls when camera movement is allowed', function()
    -- 245 chat, 249 push-to-talk, 199/200 pause menu -- none may ever be disabled.
    local mustStayFree = { 0, 1, 2, 199, 200, 245, 249 }
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    for _, control in ipairs(mustStayFree) do
        h.assertFalse(disabledControls[control], ('control %d must stay enabled'):format(control))
    end
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('the dead state honours the same option when camera movement is disabled', function()
    local allowCameraMovement = Config.death.allowCameraMovement
    Config.death.allowCameraMovement = false
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    Config.death.allowCameraMovement = allowCameraMovement
    h.assertTrue(disabledControls[1])
    h.assertTrue(disabledControls[2])
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

local realWait = _G.Wait
local function frameWait() if coroutine.isyieldable() then coroutine.yield() end end

local function resetWorld()
    resurrectedAt, health, ragdolled = nil, nil, false
    fatal, ragdolling, playingAnim = false, false, true
    playedAnimations = {}
    disabledControls, enabledControls = {}, {}
end

h.test('laststand entered on a still fatally injured ped (vehicle crash, legacy event, restore) resurrects it', function()
    -- No cache edge involved: only the server push arrives.
    resetWorld()
    fatal = true
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    h.assertTrue(resurrectedAt ~= nil, 'a natively dead ped keeps the frozen death camera until resurrected')
    h.assertEqual(health, 101)
    h.assertTrue(ragdolled)
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('laststand entered through normal damage leaves a living ped alone', function()
    resetWorld()
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 1000)
    h.assertEqual(resurrectedAt, nil)
    h.assertEqual(health, nil)
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('a direct dead push on a fatally injured ped resurrects it as well', function()
    resetWorld()
    fatal = true
    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)
    h.assertTrue(resurrectedAt ~= nil)
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('the bleed-out timer shows through laststand, survives its own expiry and hands over to the dead prompt', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 3000)
    handle.step()
    h.assertTrue(visiblePrompt() ~= nil, 'timer must be on screen right after entering laststand')
    h.assertTrue(visiblePrompt().text:find('Bleeding out in', 1, true) ~= nil)

    for _ = 1, 400 do handle.step() end -- mock clock moves 16ms per call; run past the 3s deadline
    h.assertTrue(visiblePrompt() ~= nil, 'the prompt must not vanish when the clock runs out before markDead lands')
    h.assertEqual(visiblePrompt().text, 'Bleeding out...')

    handle.fireEvent('kora_ambulance:client:markDead', 0, 2000)
    handle.step()
    h.assertTrue(visiblePrompt().text:find('You can respawn in', 1, true) ~= nil)
    for _ = 1, 400 do handle.step() end
    h.assertEqual(visiblePrompt().text, 'Type /respawn to wake up at a hospital · [G] Alert EMS')

    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    h.assertEqual(visiblePrompt(), nil, 'revive clears the prompt')
    _G.Wait = realWait
end)

h.test('a prompt another resource stacks on top cannot hide the timer for good', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 60000)
    handle.step()
    local other = handle.Kora.textui.show('Leave property', { key = 'E' })
    h.assertEqual(visiblePrompt().text, 'Leave property')

    -- the clock re-asserts itself on its next tick
    for _ = 1, 100 do handle.step() end
    h.assertTrue(visiblePrompt().text:find('Bleeding out in', 1, true) ~= nil)
    handle.Kora.textui.hide(other)
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    h.assertEqual(visiblePrompt(), nil)
    _G.Wait = realWait
end)

h.test('with camera movement allowed look is actively re-enabled every frame in both down states', function()
    resetWorld()
    _G.Wait = frameWait
    Config.death.allowCameraMovement = true
    for _, event in ipairs({ 'enterLaststand', 'markDead' }) do
        enabledControls, disabledControls = {}, {}
        handle.fireEvent('kora_ambulance:client:' .. event, 0, 60000)
        handle.step()
        h.assertTrue(enabledControls[1] and enabledControls[2], event .. ': look must be enabled')
        h.assertFalse(disabledControls[1] or disabledControls[2], event .. ': look must not be disabled')
        handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    end
    _G.Wait = realWait
end)

h.test('the downed animation comes back after a ragdoll or resurrect cleared it, but not mid-ragdoll', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 60000)
    playedAnimations = {}

    playingAnim, ragdolling = false, true
    for _ = 1, 100 do handle.step() end
    h.assertEqual(#playedAnimations, 0, 'must not fight an active ragdoll')

    ragdolling = false
    for _ = 1, 100 do handle.step() end
    h.assertTrue(#playedAnimations >= 1, 'writhe animation must be re-applied once the ragdoll ends')
    h.assertEqual(playedAnimations[1].clip, 'writhe_loop')
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    _G.Wait = realWait
end)

h.test('death screen off: plain countdown prompt, no dim, no title or hints', function()
    resetWorld()
    dimAlphas = {}
    _G.Wait = frameWait
    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 60000)
    for _ = 1, 5 do handle.step() end
    local prompt = visiblePrompt()
    h.assertTrue(prompt.text:find('^Bleeding out in %d%d:%d%d$') ~= nil, 'unchanged prompt text: ' .. prompt.text)
    h.assertEqual(prompt.opts.position, nil)
    h.assertEqual(#dimAlphas, 0)
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    _G.Wait = realWait
end)

h.test('death screen on: Downed then Dead prompts with hints, dimming, and no mouse focus taken', function()
    resetWorld()
    dimAlphas = {}
    local focusCalls = 0
    _G.SetNuiFocus = function() focusCalls = focusCalls + 1 end
    _G.Wait = frameWait
    Config.death.screen.enabled = true

    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 60000)
    for _ = 1, 5 do handle.step() end
    local prompt = visiblePrompt()
    h.assertTrue(prompt.text:find('^%*%*Downed%*%* · Bleeding out in %d%d:%d%d · /911e to call EMS$') ~= nil, prompt.text)
    h.assertEqual(prompt.opts.position, 'top-center')
    h.assertTrue(#dimAlphas > 0 and dimAlphas[#dimAlphas] == 70, 'downed dim')

    handle.fireEvent('kora_ambulance:client:markDead', 0, 60000)
    dimAlphas = {}
    for _ = 1, 5 do handle.step() end
    prompt = visiblePrompt()
    h.assertTrue(prompt.text:find('^%*%*Dead%*%* · You can respawn in %d%d:%d%d · %[G%] Alert EMS · /respawn once the timer ends$') ~= nil, prompt.text)
    h.assertEqual(dimAlphas[#dimAlphas], 150, 'dead dim is darker')

    for _ = 1, 8000 do handle.step() end
    h.assertEqual(visiblePrompt().text, '**Dead** · Type /respawn to wake up at a hospital · [G] Alert EMS')
    h.assertEqual(focusCalls, 0, 'the death screen must never take NUI focus')

    h.assertFalse(disabledControls[1] or disabledControls[2], 'camera look stays free with the screen on')
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    h.assertEqual(visiblePrompt(), nil)
    Config.death.screen.enabled = false
    _G.Wait = realWait
end)

h.test('death screen options dim=false and showHints=false are honoured', function()
    resetWorld()
    dimAlphas = {}
    _G.Wait = frameWait
    Config.death.screen.enabled = true
    Config.death.screen.dim = false
    Config.death.screen.showHints = false

    handle.fireEvent('kora_ambulance:client:enterLaststand', 0, 60000)
    for _ = 1, 5 do handle.step() end
    h.assertTrue(visiblePrompt().text:find('^%*%*Downed%*%* · Bleeding out in %d%d:%d%d$') ~= nil, visiblePrompt().text)
    h.assertEqual(#dimAlphas, 0)

    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    Config.death.screen.enabled, Config.death.screen.dim, Config.death.screen.showHints = false, true, true
    _G.Wait = realWait
end)

h.test('alert key: registered from Config.death.alertEms, sends the street only while dead', function()
    local bind = keybinds.kora_ambulance_alert_ems
    h.assertTrue(bind ~= nil, 'keybind registered')
    h.assertEqual(bind.defaultKey, Config.death.alertEms.key)

    resetWorld()
    serverEvents = {}
    bind.onPressed()
    h.assertEqual(#serverEvents, 0, 'alive players send nothing')

    handle.fireEvent('kora_ambulance:client:markDead', 0, 1000)
    bind.onPressed()
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'kora_ambulance:server:alertEms')
    h.assertEqual(serverEvents[1].args[1], 'Alta Street')
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
end)

h.test('respawn disabled while medics are on duty: prompt says so, /respawn refuses, and it clears on its own', function()
    resetWorld()
    serverEvents = {}
    _G.Wait = frameWait
    handle.fireEvent('kora_ambulance:client:markDead', 0, 0)
    handle.fireEvent('kora_ambulance:client:respawnBlock', 0, 3)
    for _ = 1, 100 do handle.step() end
    h.assertEqual(visiblePrompt().text, 'Respawn is disabled while 3 medics are on duty · [G] Alert EMS')

    commands.respawn()
    h.assertEqual(#serverEvents, 0, 'no round-trip while blocked')

    handle.fireEvent('kora_ambulance:client:respawnBlock', 0, false)
    for _ = 1, 100 do handle.step() end
    h.assertEqual(visiblePrompt().text, 'Type /respawn to wake up at a hospital · [G] Alert EMS')
    commands.respawn()
    h.assertEqual(serverEvents[1].name, 'hospital:server:RespawnAtHospital')

    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    _G.Wait = realWait
end)

h.test('a kora_lib restart re-registers the death edge and reports a death it missed', function()
    deathHandler = nil
    _G.TriggerEvent('onClientResourceStart', 'kora_target')
    h.assertEqual(deathHandler, nil, 'other resources starting do not re-register')

    fatal = true
    acceptReport = true
    reportAttempts = 0
    _G.TriggerEvent('onClientResourceStart', 'kora_lib')
    h.assertTrue(deathHandler ~= nil, 'the isDead listener is registered again')
    handle.step()
    h.assertEqual(reportAttempts, 1, 'a player already fatally injured is seeded once')

    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    fatal = false
    reportAttempts = 0
    _G.TriggerEvent('onClientResourceStart', 'kora_lib')
    handle.step()
    h.assertEqual(reportAttempts, 0, 'an alive player is not reported on restart')
end)

h.report('death_client')

h.test('a ped below the ground probe is lifted, one resting on uneven ground is not moved', function()
    h.assertEqual(Downed.groundedZ(30.0, 40.0), 41.0)
    h.assertEqual(Downed.groundedZ(30.0, 29.0), 30.0)
    h.assertEqual(Downed.groundedZ(30.0, nil), 30.0)
    h.assertEqual(Downed.groundedZ(30.0, false), 30.0)
end)

h.test('revive health is above the fatal line so the revived ped is not re-killed', function()
    h.assertTrue(Downed.revivedHealth(20, 200) > 100)
    h.assertTrue(Downed.revivedHealth(0, 200) > 100)
end)

h.test('revive resurrects a still fatally injured ped and restores survivable health', function()
    fatal = true
    resurrectedAt = nil
    health = nil
    handle.fireEvent('kora_ambulance:client:revived', 0, 20)
    h.assertTrue(resurrectedAt ~= nil, 'a fatally injured ped must be resurrected first')
    h.assertTrue(health > 100)
    h.assertEqual(resurrectedAt.z, 30.0)
    fatal = false
end)
