-- Revive (client realm) -- the defibrillator/CPR flow: a kora_target option on
-- any downed player (visibility gated by their replicated `emsDown` state
-- bag, owned by server/death.lua -- see that file's header for why a plain
-- PlayerData read can't be used to detect ANOTHER player's death state),
-- a CPR minigame + anim, then a secure server report. All real validation
-- (job/duty, item, target eligibility, cooldown) happens server-side in
-- server/revive.lua -- a client reporting `success = true` without actually
-- winning the minigame gains nothing, since Kora.minigames' own pass/fail is
-- already server-validated inside kora_lib.

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

---@param targetSrc integer
local function performCPRForTarget(targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc < 1 or targetSrc % 1 ~= 0 then return end

    local token, beginErr, authorization = Kora.callback.trigger('kora_ambulance:server:beginRevive', targetSrc)
    if not token then
        Kora.notify.send({ title = 'EMS', message = beginErr or 'Unable to begin CPR.', type = 'error' })
        return
    end

    local ped = PlayerPedId()
    Kora.anim.play(ped, CPR_ANIM.dict, CPR_ANIM.clip, { flag = 1 })

    local ok, result = pcall(Kora.minigames.play, 'mash', nil, authorization)
    Kora.anim.stop(ped)

    local proof = ok and type(result) == 'table' and result.success == true and result.proof or nil
    Kora.events.trigger('kora_ambulance:server:completeRevive', targetSrc, token, proof)
end

local function performCPR(entity)
    local targetSrc = targetServerId(entity)
    if targetSrc then performCPRForTarget(targetSrc) end
end

-- Compatibility asks the caller to run this exact modern flow. Triggering
-- the client event locally cannot bypass anything: begin/complete still bind
-- the action token, proof, job, duty, item, range and patient state server-side.
RegisterNetEvent('kora_ambulance:client:reviveRequested', performCPRForTarget)

local function registerTargets()
    exports.kora_target:addGlobalType('player', {
        {
            label = 'Perform CPR',
            icon = 'heart-pulse',
            canInteract = isDowned,
            onSelect = performCPR,
        },
    }, 2.0)
end

registerTargets()

-- kora_target restarting mid-session wipes its own global-type registry, so the
-- CPR option added above is gone from kora_target's side even though this file
-- never stopped. Re-add it the moment kora_target comes back up.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTargets() end
end)
