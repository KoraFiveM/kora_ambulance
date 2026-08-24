-- Death (client realm) -- reacts to the server-authoritative ALIVE/
-- LASTSTAND/DEAD transitions (server/death.lua) and to baseevents' own
-- client-side events directly, for an immediate local reaction that doesn't
-- wait on the network round-trip.
--
-- baseevents (already installed, see deathevents.lua) is what detects the
-- alive->dead transition; this file's job is entirely about PRESENTATION
-- once that transition happens (suppressing the vanilla wasted screen,
-- laststand crawl/ragdoll, the death fade, respawn) -- it does not
-- reimplement death DETECTION.

State = State or {}
State.inLaststand = false
State.isDead = false

local laststandGeneration = 0

---@return boolean
function State.isAlive()
    return not State.inLaststand and not State.isDead
end

-- qbcore's PlayerData replication is 1:1 (server -> the owning client only)
-- -- another client can never read a remote player's PlayerData.metadata.
-- isdead directly. A replicated player state bag is the correct, idiomatic
-- FiveM mechanism for "is this OTHER player currently down" -- client/
-- revive.lua and client/stretcher.lua's qbtarget canInteract checks read
-- this off the target's Player(serverId).state, not off any qbcore data.
local function setDownState(value)
    LocalPlayer.state:set('emsDown', value, true)
end

-- Immediately keeps the ped from actually going through the native wasted
-- flow the instant baseevents reports a death, ahead of the server's own
-- qbambulance:client:enterLaststand push landing a moment later -- without
-- this, the vanilla wasted screen can flash on screen first.
local function suppressVanillaWasted(coords)
    local ped = PlayerPedId()
    local heading = GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    SetEntityHealth(ped, 50)
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
end

RegisterNetEvent('baseevents:onPlayerDied', function(_killertype, coords)
    if not State.inLaststand and not State.isDead then
        suppressVanillaWasted({ x = coords[1], y = coords[2], z = coords[3] })
    end
end)

RegisterNetEvent('baseevents:onPlayerKilled', function(_killerid, payload)
    if not State.inLaststand and not State.isDead and payload and payload.killerpos then
        suppressVanillaWasted({ x = payload.killerpos[1], y = payload.killerpos[2], z = payload.killerpos[3] })
    end
end)

RegisterNetEvent('qbambulance:client:enterLaststand', function(deathTimeMs)
    State.inLaststand = true
    State.isDead = false
    setDownState('laststand')

    laststandGeneration = laststandGeneration + 1
    local myGeneration = laststandGeneration

    QB.notify.send({ title = 'EMS', message = 'You are critically injured. Wait for help or you will bleed out.', type = 'error' })

    CreateThread(function()
        local ped = PlayerPedId()
        local endsAt = GetGameTimer() + deathTimeMs

        while State.inLaststand and laststandGeneration == myGeneration and GetGameTimer() < endsAt do
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 47, true)  -- weapon wheel
            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            SetPedCanRagdoll(ped, true)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('qbambulance:client:markDead', function()
    State.inLaststand = false
    State.isDead = true
    setDownState('dead')
    laststandGeneration = laststandGeneration + 1

    QB.fx.screenEffect('DeathFailOut', 0, true)
    QB.notify.send({ title = 'EMS', message = 'You have died. Use /respawn to wake up at a hospital.', type = 'error' })
end)

RegisterNetEvent('qbambulance:client:revived', function(healthPct)
    local wasDead = State.isDead
    State.inLaststand = false
    State.isDead = false
    setDownState(false)
    laststandGeneration = laststandGeneration + 1

    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, math.floor(GetEntityMaxHealth(ped) * ((tonumber(healthPct) or 20) / 100)))
    SetPedCanRagdoll(ped, true)

    if wasDead then QB.fx.stopScreenEffect({ name = 'DeathFailOut' }) end

    QB.notify.send({ title = 'EMS', message = 'You have been stabilised.', type = 'success' })
end)

RegisterNetEvent('qbambulance:client:respawnedAtHospital', function(coords)
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    Wait(600)

    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or 0.0, true, false)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)

    State.isDead = false
    State.inLaststand = false
    setDownState(false)
    QB.fx.stopScreenEffect({ name = 'DeathFailOut' })

    Wait(200)
    DoScreenFadeIn(800)
end)

-- /respawn re-triggers the exact legacy RespawnAtHospital path (compat/
-- hospital.lua) even for our own new system -- one code path either way.
RegisterCommand('respawn', function()
    if not State.isDead then return end
    TriggerServerEvent('hospital:server:RespawnAtHospital')
end, false)
