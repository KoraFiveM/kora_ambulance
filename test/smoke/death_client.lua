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

_G.LocalPlayer = { state = { set = function() end } }
_G.RegisterCommand = function() end
_G.PlayerPedId = function() return 77 end
_G.GetEntityHeading = function() return 90.0 end
_G.NetworkResurrectLocalPlayer = function(x, y, z, heading)
    resurrectedAt = { x = x, y = y, z = z, heading = heading }
end
_G.SetEntityHealth = function(_, value) health = value end
_G.SetPedToRagdoll = function() ragdolled = true end

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

h.report('death_client')
