-- Death (client realm) -- reacts to the server-authoritative ALIVE/
-- LASTSTAND/DEAD transitions (server/death.lua) and qblib cache's fatal-
-- injury edge, for an immediate local reaction that doesn't wait on the
-- network round-trip.
--
-- QB.cache owns the shared 200ms IsPedFatallyInjured poll. This file presents
-- the transition (suppresses the vanilla wasted screen, then handles
-- laststand crawl/ragdoll, death fade, and respawn) and reports it securely
-- to the server; it does not start another detection loop.

State = State or {}
State.inLaststand = false
State.isDead = false

-- Bumped by every down-state transition below. Threads that outlive their
-- transition (the control-disable loop, the countdown clock) fence themselves
-- on the value they were started with, so a revive mid-bleed-out retires them
-- instead of leaving a stale timer ticking on screen.
local downGeneration = 0
local respawnAvailableAt = 0
local deathScreenHandle

local function stopDeathScreen()
    if not deathScreenHandle then return end
    QB.fx.stopScreenEffect(deathScreenHandle)
    deathScreenHandle = nil
end

---@return boolean
function State.isAlive()
    return not State.inLaststand and not State.isDead
end

-- Immediately keeps the ped from actually going through the native wasted
-- flow the instant the cache reports a death, ahead of the server's own
-- qbambulance:client:enterLaststand push landing a moment later -- without
-- this, the vanilla wasted screen can flash on screen first.
local function suppressVanillaWasted(coords)
    local ped = PlayerPedId()
    local heading = GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    SetEntityHealth(ped, 50)
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
end

-- Bleed-out / respawn countdown. Its own once-a-second thread rather than a
-- line inside the laststand loop below: that loop has to run at Wait(0) to
-- keep controls disabled every frame, and formatting a clock string sixty
-- times a second to change it once a second is pure waste.
--
-- One reused textui handle across both states -- laststand hands the clock
-- straight over to death, and a second handle would stack a dead timer
-- underneath the live one.
local countdown

local function stopCountdown()
    if not countdown then return end
    QB.textui.hide(countdown)
    countdown = nil
end

---@param text string
---@param icon string
local function showCountdown(text, icon)
    if countdown and QB.textui.update(countdown, text, { icon = icon }) then return end
    countdown = QB.textui.show(text, { icon = icon })
end

---@param ms number
---@return string mmss
local function clockText(ms)
    local seconds = math.max(0, math.ceil(ms / 1000))
    return ('%02d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

---Ticks `label mm:ss` down to `endsAt`, then leaves `finalText` on screen (or
---clears the prompt when there is nothing left to say). Display only -- the
---server owns both the bleed-out sweep and the respawn gate.
---@param generation integer The downGeneration this clock belongs to; it retires the moment that moves on.
---@param endsAt integer GetGameTimer() value the clock runs out at.
---@param label string Prefixed to the clock, e.g. 'Bleeding out in'.
---@param finalText? string Replaces the clock once it hits zero.
local function runCountdown(generation, endsAt, label, finalText)
    CreateThread(function()
        while downGeneration == generation and GetGameTimer() < endsAt do
            showCountdown(('%s %s'):format(label, clockText(endsAt - GetGameTimer())), 'Clock')
            Wait(1000)
        end

        -- Another transition already owns the prompt -- leave its text alone.
        if downGeneration ~= generation then return end

        if finalText then
            showCountdown(finalText, 'Heart')
        else
            stopCountdown()
        end
    end)
end

QB.cache.onChange('isDead', function(isDead, wasDead)
    if not isDead or wasDead or State.inLaststand or State.isDead then return end

    local coords = QB.cache.coords()

    -- Keep the ped fatally injured until the server has observed that state.
    -- OneSync health can trail the client's cache edge briefly, so retry the
    -- authenticated callback for a bounded window. Only after acceptance
    -- do we resurrect locally to suppress GTA's wasted flow; otherwise a
    -- forged report can no longer manufacture laststand from a healthy ped.
    CreateThread(function()
        for attempt = 1, Config.death.reportRetryAttempts do
            if QB.callback.trigger('qbambulance:server:reportDeath', 'died') then
                suppressVanillaWasted(coords)
                return
            end
            if attempt < Config.death.reportRetryAttempts then Wait(Config.death.reportRetryInterval) end
        end
    end)
end)

RegisterNetEvent('qbambulance:client:enterLaststand', function(deathTimeMs)
    State.inLaststand = true
    State.isDead = false

    downGeneration = downGeneration + 1
    local myGeneration = downGeneration

    QB.notify.send({ title = 'EMS', message = 'You are critically injured. Wait for help or you will bleed out.', type = 'error' })

    -- No final text: the server's bleed-out sweep is coarse (5s), so rather
    -- than assert a death it hasn't confirmed yet, the clock just clears and
    -- the markDead handler below puts its own prompt up.
    runCountdown(myGeneration, GetGameTimer() + deathTimeMs, 'Bleeding out in')

    CreateThread(function()
        local ped = PlayerPedId()
        local endsAt = GetGameTimer() + deathTimeMs

        while State.inLaststand and downGeneration == myGeneration and GetGameTimer() < endsAt do
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

RegisterNetEvent('qbambulance:client:markDead', function(respawnTimeMs)
    State.inLaststand = false
    State.isDead = true
    downGeneration = downGeneration + 1

    if not deathScreenHandle then deathScreenHandle = QB.fx.screenEffect('DeathFailOut', 0, true) end
    QB.notify.send({ title = 'EMS', message = 'You have died. Wait for the coroner or a medic.', type = 'error' })

    respawnAvailableAt = GetGameTimer() + (tonumber(respawnTimeMs) or 0)
    runCountdown(downGeneration, respawnAvailableAt, 'You can respawn in',
        'Type /respawn to wake up at a hospital')
end)

RegisterNetEvent('qbambulance:client:revived', function(healthPct)
    local wasDead = State.isDead
    State.inLaststand = false
    State.isDead = false
    downGeneration = downGeneration + 1
    stopCountdown()

    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, math.floor(GetEntityMaxHealth(ped) * ((tonumber(healthPct) or 20) / 100)))
    SetPedCanRagdoll(ped, true)

    if wasDead then stopDeathScreen() end

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
    downGeneration = downGeneration + 1
    stopCountdown()
    stopDeathScreen()

    Wait(200)
    DoScreenFadeIn(800)
end)

-- /respawn re-triggers the exact legacy RespawnAtHospital path (compat/
-- hospital.lua) even for our own new system -- one code path either way.
--
-- The wait check here only saves a pointless round-trip and gives a straight
-- answer; Death.respawnAtHospital re-checks it against its own death
-- timestamp, so editing this out buys nothing but a refusal from the server.
RegisterCommand('respawn', function()
    if not State.isDead then return end

    local remaining = respawnAvailableAt - GetGameTimer()
    if remaining > 0 then
        QB.notify.send({ title = 'EMS', message = ('You cannot respawn for another %s.'):format(clockText(remaining)), type = 'error' })
        return
    end

    TriggerServerEvent('hospital:server:RespawnAtHospital')
end, false)
