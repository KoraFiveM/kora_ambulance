-- Client death smoke test -- kora_lib cache owns fatal-injury detection while
-- kora_ambulance immediately suppresses the native wasted flow and reports the
-- edge through a corroborating server callback without any baseevents
-- dependency.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

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
handle.QB.textui = {
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

handle.QB.cache = {
    onChange = function(key, handler)
        h.assertEqual(key, 'isDead')
        deathHandler = handler
    end,
    coords = function() return coords end,
    isDead = function() return fatal end,
}
handle.QB.callback.trigger = function(name, cause)
    h.assertEqual(name, 'qbambulance:server:reportDeath')
    reportedCause = cause
    reportAttempts = reportAttempts + 1
    return acceptReport
end
handle.QB.anim = {
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
_G.RegisterCommand = function() end
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
_G.EnableControlAction = function(_, control) enabledControls[control] = true end
_G.GetEntityMaxHealth = function() return 200 end
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
    handle.QB.callback.trigger = function()
        reportAttempts = reportAttempts + 1
        return reportAttempts > attemptsToRefuse
    end

    deathHandler(true, false)
    handle.step()

    h.assertEqual(reportAttempts, attemptsToRefuse + 1, 'slow retries must continue past the quick burst')
    h.assertTrue(ragdolled, 'the late corroboration must still resurrect the ped')
    handle.QB.callback.trigger = function(_, cause)
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
    h.assertEqual(health, 50)
    h.assertTrue(ragdolled)

end)

h.test('client death lifecycle never writes the server-owned emsDown state bag', function()
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    h.assertTrue(State.inLaststand)
    h.assertEqual(playedAnimations[#playedAnimations].clip, 'writhe_loop')
    h.assertEqual(clientStateWrites, 0)
end)

h.test('death screen effect retains and releases kora_lib handle identity', function()
    handle.fireEvent('qbambulance:client:markDead', 0, 1000)
    handle.fireEvent('qbambulance:client:markDead', 0, 1000)

    h.assertEqual(#handle.QB.fx.started, 1, 'repeated dead-state updates must not leak screen handles')
    h.assertEqual(playedAnimations[#playedAnimations].clip, 'dead_a')
    local startedHandle = handle.QB.fx.started[1].handle
    local activeDownedAnimation = playedAnimations[#playedAnimations]

    handle.fireEvent('qbambulance:client:revived', 0, 20)

    h.assertEqual(handle.QB.fx.stopped[1], startedHandle,
        'revive must release the opaque handle returned by screenEffect')
    h.assertEqual(stoppedAnimation, activeDownedAnimation,
        'revive must release the downed animation it started')
end)

h.test('downed controls block movement while allowing configured camera movement', function()
    disabledControls = {}
    playerFiringDisabled = false
    stopControlLoopAfterFrame = true

    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    h.assertFalse(disabledControls[1], 'horizontal camera look should remain enabled')
    h.assertFalse(disabledControls[2], 'vertical camera look should remain enabled')
    h.assertTrue(disabledControls[30], 'horizontal movement must remain disabled')
    h.assertTrue(disabledControls[31], 'vertical movement must remain disabled')
    h.assertTrue(playerFiringDisabled, 'weapon firing must remain disabled')
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('downed camera movement can be disabled in config', function()
    local allowCameraMovement = Config.death.allowCameraMovement
    Config.death.allowCameraMovement = false
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    Config.death.allowCameraMovement = allowCameraMovement
    h.assertTrue(disabledControls[1])
    h.assertTrue(disabledControls[2])
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('the fully dead state keeps camera look free and still blocks movement and weapons', function()
    disabledControls = {}
    playerFiringDisabled = false
    stopControlLoopAfterFrame = true

    handle.fireEvent('qbambulance:client:markDead', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    h.assertFalse(disabledControls[0], 'camera switching must stay enabled while dead')
    h.assertFalse(disabledControls[1], 'horizontal camera look must stay enabled while dead')
    h.assertFalse(disabledControls[2], 'vertical camera look must stay enabled while dead')
    h.assertTrue(disabledControls[30], 'horizontal movement must stay disabled while dead')
    h.assertTrue(disabledControls[24], 'attack must stay disabled while dead')
    h.assertTrue(playerFiringDisabled, 'weapon firing must stay disabled while dead')
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('laststand never blocks look, chat, voice or pause controls when camera movement is allowed', function()
    -- 245 chat, 249 push-to-talk, 199/200 pause menu -- none may ever be disabled.
    local mustStayFree = { 0, 1, 2, 199, 200, 245, 249 }
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    for _, control in ipairs(mustStayFree) do
        h.assertFalse(disabledControls[control], ('control %d must stay enabled'):format(control))
    end
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('the dead state honours the same option when camera movement is disabled', function()
    local allowCameraMovement = Config.death.allowCameraMovement
    Config.death.allowCameraMovement = false
    disabledControls = {}
    stopControlLoopAfterFrame = true

    handle.fireEvent('qbambulance:client:markDead', 0, 1000)
    handle.step()

    stopControlLoopAfterFrame = false
    Config.death.allowCameraMovement = allowCameraMovement
    h.assertTrue(disabledControls[1])
    h.assertTrue(disabledControls[2])
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

-- --- entry paths, prompt visibility and camera, one frame per step() ---------

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
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    h.assertTrue(resurrectedAt ~= nil, 'a natively dead ped keeps the frozen death camera until resurrected')
    h.assertEqual(health, 50)
    h.assertTrue(ragdolled)
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('laststand entered through normal damage leaves a living ped alone', function()
    resetWorld()
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 1000)
    h.assertEqual(resurrectedAt, nil)
    h.assertEqual(health, nil)
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('a direct dead push on a fatally injured ped resurrects it as well', function()
    resetWorld()
    fatal = true
    handle.fireEvent('qbambulance:client:markDead', 0, 1000)
    h.assertTrue(resurrectedAt ~= nil)
    handle.fireEvent('qbambulance:client:revived', 0, 20)
end)

h.test('the bleed-out timer shows through laststand, survives its own expiry and hands over to the dead prompt', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 3000)
    handle.step()
    h.assertTrue(visiblePrompt() ~= nil, 'timer must be on screen right after entering laststand')
    h.assertTrue(visiblePrompt().text:find('Bleeding out in', 1, true) ~= nil)

    for _ = 1, 400 do handle.step() end -- mock clock moves 16ms per call; run past the 3s deadline
    h.assertTrue(visiblePrompt() ~= nil, 'the prompt must not vanish when the clock runs out before markDead lands')
    h.assertEqual(visiblePrompt().text, 'Bleeding out...')

    handle.fireEvent('qbambulance:client:markDead', 0, 2000)
    handle.step()
    h.assertTrue(visiblePrompt().text:find('You can respawn in', 1, true) ~= nil)
    for _ = 1, 400 do handle.step() end
    h.assertEqual(visiblePrompt().text, 'Type /respawn to wake up at a hospital')

    handle.fireEvent('qbambulance:client:revived', 0, 20)
    h.assertEqual(visiblePrompt(), nil, 'revive clears the prompt')
    _G.Wait = realWait
end)

h.test('a prompt another resource stacks on top cannot hide the timer for good', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 60000)
    handle.step()
    local other = handle.QB.textui.show('Leave property', { key = 'E' })
    h.assertEqual(visiblePrompt().text, 'Leave property')

    -- the clock re-asserts itself on its next tick
    for _ = 1, 100 do handle.step() end
    h.assertTrue(visiblePrompt().text:find('Bleeding out in', 1, true) ~= nil)
    handle.QB.textui.hide(other)
    handle.fireEvent('qbambulance:client:revived', 0, 20)
    h.assertEqual(visiblePrompt(), nil)
    _G.Wait = realWait
end)

h.test('with camera movement allowed look is actively re-enabled every frame in both down states', function()
    resetWorld()
    _G.Wait = frameWait
    Config.death.allowCameraMovement = true
    for _, event in ipairs({ 'enterLaststand', 'markDead' }) do
        enabledControls, disabledControls = {}, {}
        handle.fireEvent('qbambulance:client:' .. event, 0, 60000)
        handle.step()
        h.assertTrue(enabledControls[1] and enabledControls[2], event .. ': look must be enabled')
        h.assertFalse(disabledControls[1] or disabledControls[2], event .. ': look must not be disabled')
        handle.fireEvent('qbambulance:client:revived', 0, 20)
    end
    _G.Wait = realWait
end)

h.test('the downed animation comes back after a ragdoll or resurrect cleared it, but not mid-ragdoll', function()
    resetWorld()
    _G.Wait = frameWait
    handle.fireEvent('qbambulance:client:enterLaststand', 0, 60000)
    playedAnimations = {}

    playingAnim, ragdolling = false, true
    for _ = 1, 100 do handle.step() end
    h.assertEqual(#playedAnimations, 0, 'must not fight an active ragdoll')

    ragdolling = false
    for _ = 1, 100 do handle.step() end
    h.assertTrue(#playedAnimations >= 1, 'writhe animation must be re-applied once the ragdoll ends')
    h.assertEqual(playedAnimations[1].clip, 'writhe_loop')
    handle.fireEvent('qbambulance:client:revived', 0, 20)
    _G.Wait = realWait
end)

h.report('death_client')
