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

handle.QB.cache = {
    onChange = function(key, handler)
        h.assertEqual(key, 'isDead')
        deathHandler = handler
    end,
    coords = function() return coords end,
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

    deathHandler(true, false)
    handle.step()

    h.assertEqual(reportAttempts, Config.death.reportRetryAttempts)
    h.assertEqual(health, nil)
    h.assertFalse(ragdolled)
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

h.report('death_client')
