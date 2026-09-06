-- Revive (client realm) -- the defibrillator/CPR flow: a qbtarget option on
-- any downed player (visibility gated by their replicated `emsDown` state
-- bag, set in client/death.lua -- see that file's header for why a plain
-- PlayerData read can't be used to detect ANOTHER player's death state),
-- a CPR minigame + anim, then a secure server report. All real validation
-- (job/duty, item, target eligibility, cooldown) happens server-side in
-- server/revive.lua -- a client reporting `success = true` without actually
-- winning the minigame gains nothing, since QB.minigames' own pass/fail is
-- already server-validated inside qblib.

local CPR_ANIM = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' }

---@param entity number
---@return integer|nil
local function targetServerId(entity)
    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end
    return GetPlayerServerId(playerIndex)
end

---@param entity number
---@return boolean
local function isDowned(entity)
    local serverId = targetServerId(entity)
    if not serverId then return false end
    local state = Player(serverId).state
    return state.emsDown == 'laststand' or state.emsDown == 'dead'
end

local function performCPR(entity)
    local targetSrc = targetServerId(entity)
    if not targetSrc then return end

    local token, beginErr, authorization = QB.callback.trigger('qbambulance:server:beginRevive', targetSrc)
    if not token then
        QB.notify.send({ title = 'EMS', message = beginErr or 'Unable to begin CPR.', type = 'error' })
        return
    end

    local ped = PlayerPedId()
    QB.anim.play(ped, CPR_ANIM.dict, CPR_ANIM.clip, { flag = 1 })

    local ok, result = pcall(QB.minigames.play, 'mash', nil, authorization)
    QB.anim.stop(ped)

    local proof = ok and type(result) == 'table' and result.success == true and result.proof or nil
    QB.events.trigger('qbambulance:server:completeRevive', targetSrc, token, proof)
end

local function registerTargets()
    exports.qbtarget:addGlobalType('player', {
        {
            label = 'Perform CPR',
            icon = 'heart-pulse',
            canInteract = function(entity) return isDowned(entity) end,
            onSelect = function(entity) performCPR(entity) end,
        },
    }, 2.0)
end

registerTargets()

-- qbtarget restarting mid-session wipes its own global-type registry, so the
-- CPR option added above is gone from qbtarget's side even though this file
-- never stopped. Re-add it the moment qbtarget comes back up.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerTargets() end
end)
