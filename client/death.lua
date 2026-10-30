-- Death (client realm) -- reacts to the server-authoritative ALIVE/
-- LASTSTAND/DEAD transitions (server/death.lua) and kora_lib cache's fatal-
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
local downedAnimHandle

-- Spacing of the slow retries: longer than the server callback's 2s rate-limit
-- window, so a late retry is never rejected as spam.
local LATE_RETRY_INTERVAL = 2500

local DOWNED_ANIMS = {
    laststand = { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
    dead = { dict = 'dead', clip = 'dead_a' },
}

local DOWNED_DISABLED_CONTROLS = {
    21, 22, 23, 24, 25,             -- sprint, jump, enter vehicle, attack, aim
    30, 31, 32, 33, 34, 35, 36,    -- movement and duck
    37, 44, 45, 47, 58,            -- weapon wheel, cover, reload and weapon actions
    59, 60, 63, 64, 71, 72, 75,    -- vehicle movement, throttle, brake and exit
    140, 141, 142, 143, 257, 263, 264, -- melee and alternate attacks
}

local function stopDeathScreen()
    if not deathScreenHandle then return end
    QB.fx.stopScreenEffect(deathScreenHandle)
    deathScreenHandle = nil
end

local function stopDownedAnimation()
    if not downedAnimHandle then return end
    QB.anim.stopHandle(downedAnimHandle)
    downedAnimHandle = nil
end

---@param state 'laststand'|'dead'
local function playDownedAnimation(state)
    if Stretcher and Stretcher.isBeingDragged and Stretcher.isBeingDragged() then return end

    stopDownedAnimation()
    local animation = DOWNED_ANIMS[state]
    local handle = QB.anim.play(PlayerPedId(), animation.dict, animation.clip, { flag = 1 })
    if handle then downedAnimHandle = handle end
end

local function disableDownedControls()
    for i = 1, #DOWNED_DISABLED_CONTROLS do
        DisableControlAction(0, DOWNED_DISABLED_CONTROLS[i], true)
    end
    DisablePlayerFiring(PlayerId(), true)

    if Config.death.allowCameraMovement then
        -- Not merely "don't disable": re-enable every frame so a look lock
        -- another script left on this frame can't freeze the camera while down.
        EnableControlAction(0, 1, true) -- LookLeftRight
        EnableControlAction(0, 2, true) -- LookUpDown
        return
    end
    DisableControlAction(0, 0, true) -- NextCamera
    DisableControlAction(0, 1, true) -- LookLeftRight
    DisableControlAction(0, 2, true) -- LookUpDown
end

-- A resurrect or ragdoll clears the ped's tasks, which used to leave the
-- player standing/lying idle with the downed animation gone for good.
---@param state 'laststand'|'dead'
local function reassertDownedAnimation(state)
    local ped = PlayerPedId()
    if IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) then return end
    local animation = DOWNED_ANIMS[state]
    if IsEntityPlayingAnim(ped, animation.dict, animation.clip, 3) then return end
    playDownedAnimation(state)
end

---One per-frame loop for both down states, fenced on the transition that
---started it. Keeps controls locked (camera look free when configured) and
---re-applies the animation after a ragdoll.
---@param generation integer
---@param state 'laststand'|'dead'
local function runDownedLoop(generation, state)
    CreateThread(function()
        local nextAnimCheck = 0
        while downGeneration == generation and (state == 'dead' and State.isDead or state == 'laststand' and State.inLaststand) do
            disableDownedControls()
            if state == 'laststand' then SetPedCanRagdoll(PlayerPedId(), true) end

            local now = GetGameTimer()
            if now >= nextAnimCheck then
                nextAnimCheck = now + 500
                reassertDownedAnimation(state)
            end
            Wait(0)
        end
    end)
end

---@return boolean
function State.isAlive()
    return not State.inLaststand and not State.isDead
end

-- Keeps the ped from staying in (or entering) the native wasted flow. A ped
-- left fatally injured keeps GTA's death camera: the view freezes and look
-- input is ignored whatever controls we leave enabled. So every path that
-- puts the player into a down state -- the cache's death edge, the server's
-- enterLaststand/markDead pushes (restore, legacy status events, sweeps) --
-- ends here. A no-op for a ped that is not fatally injured.
---@return boolean resurrected
local function suppressVanillaWasted(coords)
    local ped = PlayerPedId()
    if not IsPedFatallyInjured(ped) then return false end
    coords = coords or GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    SetEntityHealth(ped, 50)
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
    return true
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
    if countdown and QB.textui.isVisible(countdown) and QB.textui.update(countdown, text, { icon = icon }) then return end
    -- Gone, or buried under a prompt another resource stacked on top (textui
    -- renders only the newest entry): put a fresh one on top.
    if countdown then QB.textui.hide(countdown) end
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
    -- OneSync health can trail the client's cache edge, a lot so after a
    -- vehicle crash, so retry the authenticated callback quickly for
    -- reportRetryAttempts, then slowly until reportRetryWindow runs out. Giving
    -- up after the quick burst left the ped natively dead with no timer and a
    -- frozen death camera. Only after acceptance do we resurrect locally to
    -- suppress GTA's wasted flow; a forged report can no longer manufacture
    -- laststand from a healthy ped.
    CreateThread(function()
        local startedAt = GetGameTimer()
        local attempt = 0
        while true do
            attempt = attempt + 1
            if QB.callback.trigger('qbambulance:server:reportDeath', 'died') then
                suppressVanillaWasted(coords)
                return
            end

            if attempt < Config.death.reportRetryAttempts then
                Wait(Config.death.reportRetryInterval)
            elseif GetGameTimer() - startedAt < Config.death.reportRetryWindow and QB.cache.isDead() then
                Wait(LATE_RETRY_INTERVAL)
            else
                return
            end
        end
    end)
end)

RegisterNetEvent('qbambulance:client:enterLaststand', function(deathTimeMs)
    State.inLaststand = true
    State.isDead = false

    downGeneration = downGeneration + 1
    local myGeneration = downGeneration

    QB.notify.send({ title = 'EMS', message = 'You are critically injured. Wait for help or you will bleed out.', type = 'error' })
    suppressVanillaWasted()
    playDownedAnimation('laststand')

    -- The server's bleed-out sweep is coarse (5s), so when the clock runs out
    -- before markDead lands the prompt keeps saying so instead of vanishing.
    runCountdown(myGeneration, GetGameTimer() + deathTimeMs, 'Bleeding out in', 'Bleeding out...')
    runDownedLoop(myGeneration, 'laststand')
end)

RegisterNetEvent('qbambulance:client:markDead', function(respawnTimeMs)
    State.inLaststand = false
    State.isDead = true
    downGeneration = downGeneration + 1

    if not deathScreenHandle then deathScreenHandle = QB.fx.screenEffect('DeathFailOut', 0, true) end
    QB.notify.send({ title = 'EMS', message = 'You have died. Wait for the coroner or a medic.', type = 'error' })
    suppressVanillaWasted()
    playDownedAnimation('dead')

    respawnAvailableAt = GetGameTimer() + (tonumber(respawnTimeMs) or 0)
    runDownedLoop(downGeneration, 'dead')
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
    stopDownedAnimation()
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
    stopDownedAnimation()
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
