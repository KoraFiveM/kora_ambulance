-- Death (client realm) -- reacts to the server-authoritative ALIVE/
-- LASTSTAND/DEAD transitions (server/death.lua) and kora_lib cache's fatal-
-- injury edge, for an immediate local reaction that doesn't wait on the
-- network round-trip.
--
-- Kora.cache owns the shared 200ms IsPedFatallyInjured poll. This file presents
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
    Kora.fx.stopScreenEffect(deathScreenHandle)
    deathScreenHandle = nil
end

local function stopDownedAnimation()
    if not downedAnimHandle then return end
    Kora.anim.stopHandle(downedAnimHandle)
    downedAnimHandle = nil
end

---@param state 'laststand'|'dead'
local function playDownedAnimation(state)
    if Stretcher and Stretcher.isBeingDragged and Stretcher.isBeingDragged() then return end

    stopDownedAnimation()
    local animation = DOWNED_ANIMS[state]
    downedAnimHandle = Kora.anim.play(PlayerPedId(), animation.dict, animation.clip, { flag = 1 })
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

---@return table|nil screen Config.death.screen while the optional death screen is on (read at use time).
local function screenSettings()
    local screen = Config.death.screen
    if type(screen) ~= 'table' or screen.enabled ~= true then return nil end
    return screen
end

local DIM_ALPHA = { laststand = 70, dead = 150 }

---@param state 'laststand'|'dead'
local function drawScreenDim(state)
    local screen = screenSettings()
    if not screen or screen.dim == false then return end
    DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, DIM_ALPHA[state])
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

-- Resurrects at the ped's own position. Z is only lifted when the ped sits
-- below the ground probe, so a fall onto uneven ground never relocates it.
-- NetworkResurrectLocalPlayer hands back a new ped handle: callers re-fetch it.
local function resurrectInPlace(coords)
    local ped = PlayerPedId()
    coords = coords or GetEntityCoords(ped)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    local z = Downed.groundedZ(coords.z, found and groundZ or nil)
    NetworkResurrectLocalPlayer(coords.x, coords.y, z, GetEntityHeading(ped), true, false)
end

-- A fall or bleed tick can take a downed ped to the fatal line (100). The ped
-- then dies again natively: it is flung, the death camera ignores look input and
-- the cache edge fires a second death. Keep it above the line while down.
local function holdDownedHealth()
    if Config.death.holdDownedHealth == false then return end
    if IsPedFatallyInjured(PlayerPedId()) then resurrectInPlace() end
    local ped = PlayerPedId()
    local held = Downed.downedHealth(Config.death.downedHealth, GetEntityMaxHealth(ped))
    if GetEntityHealth(ped) < held then SetEntityHealth(ped, held) end
end

---One per-frame loop for both down states, fenced on the transition that
---started it. Keeps controls locked (camera look free when configured), draws
---the optional death screen dim and re-applies the animation after a ragdoll.
---@param generation integer
---@param state 'laststand'|'dead'
local function runDownedLoop(generation, state)
    CreateThread(function()
        local nextAnimCheck = 0
        while downGeneration == generation and (state == 'dead' and State.isDead or state == 'laststand' and State.inLaststand) do
            disableDownedControls()
            drawScreenDim(state)
            -- A carried/stretcher patient has ragdoll off; re-enabling it here knocks them off.
            if state == 'laststand' and not (Stretcher and Stretcher.isBeingDragged and Stretcher.isBeingDragged()) then
                SetPedCanRagdoll(PlayerPedId(), true)
            end

            local now = GetGameTimer()
            if now >= nextAnimCheck then
                nextAnimCheck = now + 500
                holdDownedHealth()
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
    resurrectInPlace(coords)
    SetEntityHealth(PlayerPedId(), Downed.downedHealth(Config.death.downedHealth, GetEntityMaxHealth(PlayerPedId())))
    SetPedToRagdoll(PlayerPedId(), 5000, 5000, 0, false, false, false)
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
    Kora.textui.hide(countdown)
    countdown = nil
end

local SCREEN_TITLES = { laststand = 'Downed', dead = 'Dead' }
local SCREEN_HINTS = { laststand = '/911e to call EMS', dead = '/respawn once the timer ends' }

-- minOnDuty while the server has /respawn disabled because enough medics are on
-- duty (Config.death.respawn.blockWhenMedics), nil otherwise. Display only.
local respawnBlockedBy

---@return string|nil hint The alert-key hint while Config.death.alertEms is on.
local function alertHint()
    local alert = Config.death.alertEms
    if type(alert) ~= 'table' or alert.enabled ~= true then return nil end
    return ('[%s] Alert EMS'):format(alert.key)
end

---Death screen presentation of a prompt: a state title, optionally the hint
---keys, anchored top-centre. A plain textui entry -- no NUI focus, so mouse
---look is never taken. Without the death screen the prompt is left as it was.
---@param state 'laststand'|'dead'
---@param text string
---@param icon string
---@param final? boolean The closing text already carries its own hint.
---@return string text
---@return table options
local function promptFor(state, text, icon, final)
    local screen = screenSettings()
    local alert = state == 'dead' and alertHint() or nil
    if not screen then
        if alert then text = ('%s · %s'):format(text, alert) end
        return text, { icon = icon }
    end

    text = ('**%s** · %s'):format(SCREEN_TITLES[state], text)
    if screen.showHints ~= false then
        if alert and not final then
            text = ('%s · %s · %s'):format(text, alert, SCREEN_HINTS.dead)
        elseif alert then
            text = ('%s · %s'):format(text, alert)
        elseif not final then
            text = ('%s · %s'):format(text, SCREEN_HINTS[state])
        end
    end
    return text, { icon = icon, position = 'top-center' }
end

---@param state 'laststand'|'dead'
---@param text string
---@param icon string
---@param final? boolean
local function showCountdown(state, text, icon, final)
    local shown, options = promptFor(state, text, icon, final)
    if countdown and Kora.textui.isVisible(countdown) and Kora.textui.update(countdown, shown, options) then return end
    -- Gone, or buried under a prompt another resource stacked on top (textui
    -- renders only the newest entry): put a fresh one on top.
    if countdown then Kora.textui.hide(countdown) end
    countdown = Kora.textui.show(shown, options)
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
---@param state 'laststand'|'dead' Which down state the prompt describes (death screen title and hints).
local function runCountdown(generation, endsAt, label, finalText, state)
    CreateThread(function()
        while downGeneration == generation and GetGameTimer() < endsAt do
            showCountdown(state, ('%s %s'):format(label, clockText(endsAt - GetGameTimer())), 'Clock')
            Wait(1000)
        end

        -- Another transition already owns the prompt -- leave its text alone.
        if downGeneration ~= generation then return end

        if finalText then
            showCountdown(state, finalText, 'Heart', true)
        else
            stopCountdown()
        end
    end)
end

---Dead prompt: the respawn clock, then either "disabled while N medics are on
---duty" or the /respawn instruction. Re-evaluated every second, so a medic
---going on or off duty changes it without a new death event.
---@param generation integer
local function runDeadPrompt(generation)
    CreateThread(function()
        while downGeneration == generation and State.isDead do
            local remaining = respawnAvailableAt - GetGameTimer()
            if remaining > 0 then
                showCountdown('dead', ('You can respawn in %s'):format(clockText(remaining)), 'Clock')
            elseif respawnBlockedBy then
                showCountdown('dead', ('Respawn is disabled while %d medics are on duty'):format(respawnBlockedBy), 'Heart', true)
            else
                showCountdown('dead', 'Type /respawn to wake up at a hospital', 'Heart', true)
            end
            Wait(1000)
        end
    end)
end

local function onFatalInjuryChange(isDead, wasDead)
    if not isDead or wasDead or State.inLaststand or State.isDead then return end

    local coords = Kora.cache.coords()

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
            if Kora.callback.trigger('qbambulance:server:reportDeath', 'died') then
                suppressVanillaWasted(coords)
                return
            end

            if attempt < Config.death.reportRetryAttempts then
                Wait(Config.death.reportRetryInterval)
            elseif GetGameTimer() - startedAt < Config.death.reportRetryWindow and Kora.cache.isDead() then
                Wait(LATE_RETRY_INTERVAL)
            else
                return
            end
        end
    end)
end

-- kora_lib drops every onChange registration when it restarts, so the death
-- edge is registered at load and again on its restart. Only the restart path
-- seeds from the current value: a death that happened while kora_lib was down
-- would otherwise never fire an edge (the State guards above make it a no-op
-- when the server already put this player down).
local function watchFatalInjury()
    Kora.cache.onChange('isDead', onFatalInjuryChange)
end

watchFatalInjury()
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_lib' then return end
    watchFatalInjury()
    onFatalInjuryChange(Kora.cache.isDead(), false)
end)

RegisterNetEvent('qbambulance:client:enterLaststand', function(deathTimeMs)
    State.inLaststand = true
    State.isDead = false

    downGeneration = downGeneration + 1
    local myGeneration = downGeneration

    Kora.notify.send({ title = 'EMS', message = 'You are critically injured. Wait for help or you will bleed out.', type = 'error' })
    suppressVanillaWasted()
    playDownedAnimation('laststand')

    -- The server's bleed-out sweep is coarse (5s), so when the clock runs out
    -- before markDead lands the prompt keeps saying so instead of vanishing.
    runCountdown(myGeneration, GetGameTimer() + deathTimeMs, 'Bleeding out in', 'Bleeding out...', 'laststand')
    runDownedLoop(myGeneration, 'laststand')
end)

RegisterNetEvent('qbambulance:client:markDead', function(respawnTimeMs)
    State.inLaststand = false
    State.isDead = true
    downGeneration = downGeneration + 1

    if not deathScreenHandle then deathScreenHandle = Kora.fx.screenEffect('DeathFailOut', 0, true) end
    Kora.notify.send({ title = 'EMS', message = 'You have died. Wait for the coroner or a medic.', type = 'error' })
    suppressVanillaWasted()
    playDownedAnimation('dead')

    respawnAvailableAt = GetGameTimer() + (tonumber(respawnTimeMs) or 0)
    runDownedLoop(downGeneration, 'dead')
    runDeadPrompt(downGeneration)
end)

RegisterNetEvent('qbambulance:client:respawnBlock', function(minOnDuty)
    respawnBlockedBy = tonumber(minOnDuty) or nil
end)

RegisterNetEvent('qbambulance:client:revived', function(healthPct)
    local wasDead = State.isDead
    State.inLaststand = false
    State.isDead = false
    downGeneration = downGeneration + 1
    respawnBlockedBy = nil
    stopCountdown()

    stopDownedAnimation()
    -- Health below the fatal line (20% of 200 = 40) re-killed the revived ped.
    if IsPedFatallyInjured(PlayerPedId()) then resurrectInPlace() end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, Downed.revivedHealth(healthPct, GetEntityMaxHealth(ped)))
    SetPedCanRagdoll(ped, true)

    if wasDead then stopDeathScreen() end

    Kora.notify.send({ title = 'EMS', message = 'You have been stabilised.', type = 'success' })
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
    respawnBlockedBy = nil
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
        Kora.notify.send({ title = 'EMS', message = ('You cannot respawn for another %s.'):format(clockText(remaining)), type = 'error' })
        return
    end

    if respawnBlockedBy then
        Kora.notify.send({ title = 'EMS', message = ('Respawn is disabled while %d medics are on duty.'):format(respawnBlockedBy), type = 'error' })
        return
    end

    TriggerServerEvent('hospital:server:RespawnAtHospital')
end, false)

-- Alert EMS while dead (Config.death.alertEms). A real key mapping, rebindable in
-- FiveM settings; the server re-checks dead state, cooldown and location.
if alertHint() then
    Kora.keybind.add({
        name = 'qbambulance_alert_ems',
        description = 'EMS: alert paramedics while dead',
        defaultKey = Config.death.alertEms.key,
        onPressed = function()
            if not State.isDead then return end
            TriggerServerEvent('qbambulance:server:alertEms', (Kora.world.getStreetNames()))
        end,
    })
end
