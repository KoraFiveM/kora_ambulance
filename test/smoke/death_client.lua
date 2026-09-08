-- Client death smoke test -- qblib cache owns fatal-injury detection while
-- qbambulance immediately suppresses the native wasted flow and reports the
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

local clientStateWrites = 0
_G.LocalPlayer = { state = { set = function() clientStateWrites = clientStateWrites + 1 end } }
_G.RegisterCommand = function() end
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
    h.assertEqual(clientStateWrites, 0)
end)

h.test('death screen effect retains and releases qblib handle identity', function()
    handle.fireEvent('qbambulance:client:markDead', 0, 1000)
    handle.fireEvent('qbambulance:client:markDead', 0, 1000)

    h.assertEqual(#handle.QB.fx.started, 1, 'repeated dead-state updates must not leak screen handles')
    local startedHandle = handle.QB.fx.started[1].handle

    handle.fireEvent('qbambulance:client:revived', 0, 20)

    h.assertEqual(handle.QB.fx.stopped[1], startedHandle,
        'revive must release the opaque handle returned by screenEffect')
end)

h.report('death_client')
