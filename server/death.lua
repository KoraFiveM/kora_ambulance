-- Death (server realm) -- the ALIVE/LASTSTAND/DEAD state machine and the
-- per-body-part wound ledger. Uses qbcore's EXISTING metadata.isdead/
-- inlaststand fields (see qbcore/modules/player/shared.lua's freshData) --
-- zero new schema. Wound data itself is intentionally NOT persisted: like
-- QB.status's own `active` table, an open wound is ambient combat state that
-- resets on relog/death, not a durable record (mirrors real qb-ambulancejob/
-- qbx_medical, neither of which persists wounds across sessions either).
--
-- Death detection is baseevents' job (see client/death.lua's header) -- this
-- file only reacts to the SERVER-side mirror of those events
-- (baseevents:onPlayerDied/onPlayerKilled/onPlayerWasted are fired via BOTH
-- TriggerEvent and TriggerServerEvent by deathevents.lua) plus the client's
-- own explicit lifecycle calls (enterLaststand/markDead can also be invoked
-- directly, e.g. by the legacy compat layer's KillPlayer/SetDeathStatus).

Death = Death or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local woundData = {}     -- src -> { [bodyPart] = tier }
local laststandAt = {}   -- src -> os.time() the player entered laststand

------------------------------------------------------------------------------
-- Pure state machine -- no side effects, fully covered by
-- test/smoke/death.lua. Real callers go through the side-effecting
-- enterLaststand/markDead/reviveInField/respawnAtHospital below, which each
-- consult this to decide whether the requested transition is even legal
-- rather than trusting the caller's intent blindly.
------------------------------------------------------------------------------

local VALID_TRANSITIONS = {
    alive     = { died = 'laststand' },
    laststand = { bledOut = 'dead', revived = 'alive', died = 'dead' },
    dead      = { respawned = 'alive', revived = 'alive' },
}

---@param state "alive"|"laststand"|"dead"
---@param event "died"|"bledOut"|"revived"|"respawned"
---@return "alive"|"laststand"|"dead" nextState Unchanged if the transition isn't legal from `state`.
---@return boolean changed
function Death.transition(state, event)
    local row = VALID_TRANSITIONS[state]
    local nextState = row and row[event]
    if not nextState then return state, false end
    return nextState, true
end

------------------------------------------------------------------------------
-- State reads
------------------------------------------------------------------------------

---@param src integer
---@return "alive"|"laststand"|"dead"
function Death.getState(src)
    local isdead = QBCore:getMetaData(src, 'isdead')
    local inlaststand = QBCore:getMetaData(src, 'inlaststand')
    if isdead then return 'dead' end
    if inlaststand then return 'laststand' end
    return 'alive'
end

---@param src integer
---@return boolean
function Death.isDead(src) return Death.getState(src) == 'dead' end

---@param src integer
---@return boolean
function Death.isLaststand(src) return Death.getState(src) == 'laststand' end

---@param src integer
---@return boolean
function Death.isAlive(src) return Death.getState(src) == 'alive' end

------------------------------------------------------------------------------
-- Wound ledger
------------------------------------------------------------------------------

---@param src integer
---@return table<string, integer> A live reference -- do not mutate from outside recordWound/clearWound.
function Death.getWoundData(src)
    woundData[src] = woundData[src] or {}
    return woundData[src]
end

---Records (or escalates) a wound and re-applies the resulting `bleeding`/
---`limping` QB.status severity for the worst OPEN wound across every body
---part -- a fresh graze on an already-critical patient never downgrades the
---visible severity (Wounds.worstOpenTier takes the max, not the latest).
---@param src integer
---@param bodyPart string
---@param tier integer
function Death.recordWound(src, bodyPart, tier)
    local bucket = Death.getWoundData(src)
    local existing = bucket[bodyPart]
    if existing and existing >= tier then return end -- never downgrade an existing wound
    bucket[bodyPart] = tier
    Death._syncStatus(src)
end

---@param src integer
---@param bodyPart string
function Death.clearWound(src, bodyPart)
    local bucket = Death.getWoundData(src)
    bucket[bodyPart] = nil
    Death._syncStatus(src)
end

---Fully closes every open wound (a successful hospital respawn or a
---sufficiently strong field treatment).
---@param src integer
function Death.clearAllWounds(src)
    woundData[src] = {}
    QB.status.remove(src, 'bleeding')
    QB.status.remove(src, 'limping')
end

---Re-derives and re-applies the bleeding/limping QB.status severity from the
---current wound ledger. Underscore-prefixed: internal, not exported by
---build/finalise-style conventions, but this resource has no finalise step
---of its own -- kept for the same "this is plumbing, not public API" reason
---qbcore's own Core.persistence._adopt is.
---@param src integer
function Death._syncStatus(src)
    local tier = Wounds.worstOpenTier(Death.getWoundData(src))
    if not tier then
        QB.status.remove(src, 'bleeding')
        QB.status.remove(src, 'limping')
        return
    end

    QB.status.apply(src, 'bleeding', { severity = tier })

    local level = Wounds.woundLevelDef(tier)
    if level and not level.canWalk then
        QB.status.apply(src, 'limping', { severity = tier })
    else
        QB.status.remove(src, 'limping')
    end
end

------------------------------------------------------------------------------
-- Transitions with side effects
------------------------------------------------------------------------------

---@param src integer
---@param cause? string Freeform, forwarded to qbcore:server:onPlayerDied listeners.
---@return boolean
function Death.enterLaststand(src, cause)
    local newState, changed = Death.transition(Death.getState(src), 'died')
    if not changed or newState ~= 'laststand' then return false end

    QBCore:setMetaData(src, 'inlaststand', true)
    QBCore:setMetaData(src, 'isdead', false)
    laststandAt[src] = os.time()

    TriggerClientEvent('qbambulance:client:enterLaststand', src, Config.death.deathTime)
    TriggerEvent('qbambulance:server:onPlayerDied', src, cause)

    return true
end

---Direct alive -> dead (skips laststand) -- used by an instant-kill legacy
---compat call (KillPlayer) rather than the normal bleed-out path.
---@param src integer
---@return boolean
function Death.markDead(src)
    local state = Death.getState(src)
    local newState, changed

    if state == 'alive' then
        newState, changed = Death.transition('laststand', 'died')
        state = 'laststand'
    end
    if state == 'laststand' then
        newState, changed = Death.transition(state, 'bledOut')
    end

    if not changed or newState ~= 'dead' then return false end

    QBCore:setMetaData(src, 'isdead', true)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil

    TriggerClientEvent('qbambulance:client:markDead', src)
    TriggerEvent('qbambulance:server:onPlayerDead', src)

    return true
end

---A successful field CPR/defib save: patient gets back up where they are.
---No hospital bill (that's respawnAtHospital's job) -- wounds are NOT
---cleared, only stabilised (bleeding stops; whatever's still open keeps its
---tier and can still be bandaged normally afterwards).
---@param src integer
---@param healthPct? number Overrides Config.death.minimumRevive.
---@return boolean
function Death.reviveInField(src, healthPct)
    local state = Death.getState(src)
    if state ~= 'laststand' and state ~= 'dead' then return false end

    local newState, changed = Death.transition(state, 'revived')
    if not changed then return false end

    QBCore:setMetaData(src, 'isdead', false)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil

    QB.status.remove(src, 'bleeding')

    TriggerClientEvent('qbambulance:client:revived', src, healthPct or Config.death.minimumRevive)
    TriggerEvent('qbambulance:server:onPlayerRevived', src)

    return true
end

---@param src integer
---@param hospitalName? string Defaults to Config.hospitals[1].
---@return boolean, string|nil
function Death.respawnAtHospital(src, hospitalName)
    local state = Death.getState(src)
    if state ~= 'dead' then return false, 'player is not dead' end

    local hospital
    for _, h in ipairs(Config.hospitals) do
        if h.name == hospitalName then hospital = h; break end
    end
    hospital = hospital or Config.hospitals[1]

    Billing.chargeForRespawn(src, Death.getWoundData(src))

    local newState, changed = Death.transition(state, 'respawned')
    if not changed then return false, 'invalid transition' end

    QBCore:setMetaData(src, 'isdead', false)
    QBCore:setMetaData(src, 'inlaststand', false)
    laststandAt[src] = nil
    Death.clearAllWounds(src)
    QBCore:reset(src) -- mirrors legacy hospital:server:resetHungerThirst

    TriggerClientEvent('qbambulance:client:respawnedAtHospital', src, hospital.coords)
    TriggerEvent('qbambulance:server:onPlayerRespawned', src, hospital.name)

    return true
end

---@param src integer
---@return integer seconds Elapsed since entering laststand, or 0 if not in laststand.
function Death.laststandElapsed(src)
    local startedAt = laststandAt[src]
    if not startedAt then return 0 end
    return os.time() - startedAt
end

------------------------------------------------------------------------------
-- baseevents wiring
------------------------------------------------------------------------------

local function onDied(_killertype, _coords)
    Death.enterLaststand(source, 'died')
end

local function onKilled(_killerid, _payload)
    Death.enterLaststand(source, 'killed')
end

RegisterNetEvent('baseevents:onPlayerDied', onDied)
RegisterNetEvent('baseevents:onPlayerKilled', onKilled)
-- baseevents:onPlayerWasted fires once the vanilla wasted UI would have
-- appeared -- client/death.lua suppresses that UI itself (see its header),
-- so server-side this is only a backstop in case a client somehow reaches
-- laststand -> wasted without this module's own laststand timeout catching
-- it first (e.g. a resource restart mid-laststand).
RegisterNetEvent('baseevents:onPlayerWasted', function(_coords)
    if Death.isLaststand(source) then Death.markDead(source) end
end)

-- Per-body-part wound location while ALIVE, reported by client/damage.lua's
-- gameEventTriggered listener (baseevents only tells us about the death
-- transition, not where a still-living player got hit -- see that file's
-- header). Client-reported and therefore not fully trustable, but the worst
-- a forged report can do is apply a cosmetic bleed/limp status to the
-- reporter's OWN character -- validated to a legal body part and tier
-- regardless.
QB.events.register('qbambulance:server:reportWound', function(src, bodyPart, tier)
    if not Death.isAlive(src) then return end
    if type(bodyPart) ~= 'string' or not Wounds.bodyPartDef(bodyPart) then return end
    tier = math.floor(tonumber(tier) or 0)
    if tier < 1 or tier > Wounds.MAX_TIER then return end

    Death.recordWound(src, bodyPart, tier)
end)

------------------------------------------------------------------------------
-- Bleed-out timer: sweeps every laststand player and force-transitions to
-- dead once Config.death.deathTime has elapsed unrevived. Runs on a coarse
-- interval (5s) -- laststand->dead doesn't need sub-second precision.
------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(5000)
        for src, startedAt in pairs(laststandAt) do
            if os.time() - startedAt >= math.floor(Config.death.deathTime / 1000) then
                Death.markDead(src)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    woundData[src] = nil
    laststandAt[src] = nil
end)
