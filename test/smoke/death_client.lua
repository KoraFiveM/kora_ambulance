-- Client death smoke test -- qblib cache owns fatal-injury detection while
-- qbambulance immediately suppresses the native wasted flow and reports the
-- edge through QB.events without any baseevents dependency.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()

local deathHandler
local coords = { x = 10.0, y = 20.0, z = 30.0 }
local resurrectedAt
local health
local ragdolled = false
local reportedCause

handle.QB.cache = {
    onChange = function(key, handler)
        h.assertEqual(key, 'isDead')
        deathHandler = handler
    end,
    coords = function() return coords end,
}
handle.QB.events.trigger = function(name, cause)
    h.assertEqual(name, 'qbambulance:server:reportDeath')
    reportedCause = cause
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

h.test('qblib cache fatal-injury edge suppresses native wasted and reports death', function()
    h.assertTrue(deathHandler ~= nil)

    deathHandler(true, false)

    h.assertEqual(resurrectedAt.x, 10.0)
    h.assertEqual(resurrectedAt.y, 20.0)
    h.assertEqual(resurrectedAt.z, 30.0)
    h.assertEqual(resurrectedAt.heading, 90.0)
    h.assertEqual(health, 50)
    h.assertTrue(ragdolled)

    handle.step() -- runs the one-shot secure-event report thread
    h.assertEqual(reportedCause, 'died')
end)

h.report('death_client')
