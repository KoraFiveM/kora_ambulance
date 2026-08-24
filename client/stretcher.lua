-- Stretcher (client realm) -- NEW differentiator: drag a downed player.
--
-- The dragged player's ped is another player's own networked entity, not a
-- prop this resource owns -- QB.anim.attachProp (or any AttachEntityToEntity
-- call) can't be used on it (see the plan's stretcher section for why).
-- Instead: the DRAGGED player's client stays the network owner of their own
-- ped throughout (never transferred), and every frame recomputes its own
-- position LOCALLY as "the dragger's live ped coords/heading (already
-- streamed/networked to this client by ordinary FiveM entity sync) plus a
-- relative offset". The offset itself is small, constant while dragging, and
-- only re-broadcast at a low tick rate (every 2s, as a self-correction
-- heartbeat) via the server -- there is no per-frame network traffic for
-- position, which is what makes this cheap regardless of server population.

-- Client-realm Stretcher table (distinct from the server-realm Stretcher in
-- server/stretcher.lua -- same name, different Lua VM, no collision) so
-- client/compat.lua's isEscorted/CanHelp legacy exports can read real state
-- instead of stubbing it out.
Stretcher = Stretcher or {}

local dragging = nil -- { targetSrc } when I am the dragger
local dragged = nil  -- { draggerSrc, offset } when I am being dragged

---@return boolean
function Stretcher.isBeingDragged()
    return dragged ~= nil
end

---@return boolean
function Stretcher.isDragging()
    return dragging ~= nil
end

local DRAG_OFFSET = { x = 0.0, y = -0.65, z = 0.0 } -- behind the dragger, in their local space
local DRAG_ANIM = { dict = 'missfbi3', clip = 'fbi3_c3_speaker_lookback01', flag = 49 }

local function isOnDutyEMS()
    local job = exports.qbcore:getJob()
    return job ~= nil and job.name == Config.job.name and job.onduty == true
end

local function targetServerId(entity)
    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end
    return GetPlayerServerId(playerIndex)
end

local function isDowned(entity)
    local serverId = targetServerId(entity)
    if not serverId then return false end
    return Player(serverId).state.emsDown ~= nil and Player(serverId).state.emsDown ~= false
end

local function startDraggerThread(targetSrc)
    dragging = { targetSrc = targetSrc }
    QB.anim.play(PlayerPedId(), DRAG_ANIM.dict, DRAG_ANIM.clip, { flag = DRAG_ANIM.flag })

    CreateThread(function()
        while dragging and dragging.targetSrc == targetSrc do
            QB.events.trigger('qbambulance:server:stretcherOffset', DRAG_OFFSET)
            Wait(2000)
        end
    end)
end

local function stopDragging()
    if not dragging then return end
    dragging = nil
    QB.anim.stop(PlayerPedId())
end

local function startDraggedThread(draggerSrc, offset)
    dragged = { draggerSrc = draggerSrc, offset = offset or DRAG_OFFSET }

    local ped = PlayerPedId()
    SetPedCanRagdoll(ped, false)
    QB.anim.play(ped, 'get_up@multiplayer@transitions@prone_to_idle', 'prone_to_idle', { flag = 1 })

    CreateThread(function()
        while dragged and dragged.draggerSrc == draggerSrc do
            local draggerPlayer = GetPlayerFromServerId(draggerSrc)

            if draggerPlayer ~= -1 then
                local draggerPed = GetPlayerPed(draggerPlayer)
                if draggerPed and draggerPed ~= 0 and DoesEntityExist(draggerPed) then
                    local pos = GetOffsetFromEntityInWorldCoords(draggerPed, dragged.offset.x, dragged.offset.y, dragged.offset.z)
                    SetEntityCoordsNoOffset(PlayerPedId(), pos.x, pos.y, pos.z, false, false, false)
                    SetEntityHeading(PlayerPedId(), GetEntityHeading(draggerPed))
                end
            end

            Wait(0)
        end
    end)
end

local function stopBeingDragged()
    if not dragged then return end
    dragged = nil
    local ped = PlayerPedId()
    SetPedCanRagdoll(ped, true)
    QB.anim.stop(ped)
end

RegisterNetEvent('qbambulance:client:stretcherBegin', function(otherSrc, iAmDragger)
    if iAmDragger then
        startDraggerThread(otherSrc)
        QB.notify.send({ title = 'EMS', message = 'Carrying patient. Select "Release Patient" to set them down.', type = 'info' })
    else
        startDraggedThread(otherSrc)
        QB.notify.send({ title = 'EMS', message = 'You are being carried.', type = 'info' })
    end
end)

RegisterNetEvent('qbambulance:client:stretcherOffset', function(draggerSrc, offset)
    if dragged and dragged.draggerSrc == draggerSrc then dragged.offset = offset end
end)

RegisterNetEvent('qbambulance:client:stretcherEnd', function()
    stopDragging()
    stopBeingDragged()
end)

local function registerTargets()
    exports.qbtarget:addGlobalType('player', {
        {
            label = 'Pick Up Patient',
            icon = 'move',
            canInteract = function(entity) return isOnDutyEMS() and isDowned(entity) and not dragging end,
            onSelect = function(entity)
                local targetSrc = targetServerId(entity)
                if targetSrc then QB.events.trigger('qbambulance:server:stretcherPickup', targetSrc) end
            end,
        },
        {
            label = 'Release Patient',
            icon = 'x',
            canInteract = function(entity) return dragging ~= nil and targetServerId(entity) == dragging.targetSrc end,
            onSelect = function() QB.events.trigger('qbambulance:server:stretcherRelease') end,
        },
    }, 2.5)
end

registerTargets()

-- qbtarget restarting mid-session wipes its own global-type registry, so the
-- options added above are gone from qbtarget's side even though this file
-- never stopped. Re-add them the moment qbtarget comes back up.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerTargets() end
end)
