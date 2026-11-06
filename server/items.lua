-- Items (server realm) -- the REAL gameplay effect of pharmacy items
-- (closing a wound, the painkiller cooldown gate). Cosmetic playback
-- (screen fx, anim, hunger/thirst/stress) is entirely handled by kora_core's
-- Core.consumables reading the `effect` table shared/items.lua registered --
-- nothing here calls Kora.fx/Kora.status for cosmetics, only for the durable
-- bleeding/limping state the wound actually being treated changes.

Items = Items or {}

-- kora_core has no Kora proxy; every call crosses the exports boundary.
local QBCore = exports.kora_core

local lastPainkillerAt = {} -- src -> os.time()

---@param now integer os.time()
---@param lastUsedAt integer|nil
---@return boolean eligible
function Items.painkillerEligible(now, lastUsedAt)
    if not lastUsedAt then return true end
    return (now - lastUsedAt) >= math.floor(Config.painkillers.interval / 1000)
end

---Health boost / bleeding stop of a completed painkiller use (Config.painkillers).
---SetEntityHealth is a client-only native (calling it here was a nil-global
---script error that skipped the whole benefit), so the server only decides
---that the boost applies and tells the owning client; the client applies it
---capped at the ped's max health (client/pharmacy.lua). The bleeding state is
---server-owned and changes here.
---@param src integer
function Items.applyPainkillerBenefit(src)
    local cfg = Config.painkillers
    -- A downed player's health is held by the death flow, never boosted.
    if (cfg.healthAmount or 0) > 0 and Death.isAlive(src) then
        TriggerClientEvent('qbambulance:client:painkillerBenefit', src, cfg.healthAmount)
    end
    if cfg.stopBleeding then Death.stopBleeding(src) end
end

---@param src integer
---@param maxTier integer
---@return boolean treated
local function treatWound(src, maxTier)
    local woundData = Death.getWoundData(src)
    local bodyPart, tier = Wounds.pickTreatableWound(woundData, maxTier)
    if not bodyPart then return false end

    Death.clearWound(src, bodyPart)
    Kora.notify.send(src, { title = 'First Aid', message = ('Treated a wound (%s).'):format(Wounds.bodyPartDef(bodyPart) and Wounds.bodyPartDef(bodyPart).label or bodyPart), type = 'success' })
    return true
end

-- kora_inventory's useItem does not remove the item, so each handler below
-- removes its own on successful use.

-- Asks the item user's client to run a progressbar (server->client callback)
-- and awaits completion. Duration/anim come from the item's `effect` table
-- in shared/items.lua.
---@param src integer
---@param itemName string
---@param override? {duration: integer, anim: table} Replaces the item's `effect` duration/anim.
---@return boolean completed
local function runFeedback(src, itemName, override)
    local def = QBCore:getShared('items', itemName)
    local effect = def and def.effect or {}
    override = override or {}

    -- Same-VM Kora.callback.trigger returns a promise (only a cross-resource
    -- caller gets the awaited value); comparing the promise to `true` left every
    -- completed bar looking cancelled, so no item was ever consumed.
    local completed = Kora.callback.trigger(src, 'qbambulance:client:pharmacyProgress', {
        label = def and def.label or itemName,
        duration = override.duration or effect.duration or 2500,
        anim = override.anim or effect.anim,
    })
    if type(completed) == 'table' and completed.next then completed = Citizen.Await(completed) end

    return completed == true
end

QBCore:createUseable('bandage', function(src, item)
    if not Death.isAlive(src) then
        Kora.notify.send(src, { title = 'First Aid', message = 'Can\'t apply a bandage right now.', type = 'error' })
        return
    end

    if not Wounds.pickTreatableWound(Death.getWoundData(src), 2) then
        Kora.notify.send(src, { title = 'First Aid', message = 'No wound a bandage can treat.', type = 'warning' })
        return
    end

    if runFeedback(src, 'bandage') then
        local removed = QBCore:removeItem(src, 'bandage', 1, item and item.slot, 'first-aid')
        if removed and not treatWound(src, 2) then
            QBCore:addItem(src, 'bandage', 1, item and item.slot, item and item.info or {}, 'first-aid-rollback')
        end
    end
end)

---@param itemName string
local function registerIfak(itemName)
    QBCore:createUseable(itemName, function(src, item)
        if not Death.isAlive(src) then
            Kora.notify.send(src, { title = 'First Aid', message = 'Can\'t apply an IFAK right now.', type = 'error' })
            return
        end

        if not Wounds.pickTreatableWound(Death.getWoundData(src), Wounds.MAX_TIER) then
            Kora.notify.send(src, { title = 'First Aid', message = 'No open wound to treat.', type = 'warning' })
            return
        end

        if runFeedback(src, itemName) then
            local removed = QBCore:removeItem(src, itemName, 1, item and item.slot, 'first-aid')
            if removed and not treatWound(src, Wounds.MAX_TIER) then
                QBCore:addItem(src, itemName, 1, item and item.slot, item and item.info or {}, 'first-aid-rollback')
            end
        end
    end)
end

registerIfak('ifak')
registerIfak('ifaks')

-- First aid kit: consumed on a completed use, clears every wound/bleed and
-- tells the owning client to restore full health (SetEntityHealth is client-only).
if Config.firstaid and Config.firstaid.enabled then
    QBCore:createUseable('firstaid', function(src, item)
        if not Death.isAlive(src) then
            Kora.notify.send(src, { title = 'First Aid', message = 'Can\'t use a first aid kit right now.', type = 'error' })
            return
        end

        if not runFeedback(src, 'firstaid', { duration = Config.firstaid.duration }) then return end

        local removed = QBCore:removeItem(src, 'firstaid', 1, item and item.slot, 'first-aid')
        if not removed then return end
        Death.clearAllWounds(src)
        TriggerClientEvent('qbambulance:client:firstAidHeal', src)
        Kora.notify.send(src, { title = 'First Aid', message = 'You patched yourself up.', type = 'success' })
    end)

    -- On-duty EMS use a first aid kit on another player (ALT target option).
    -- The medic's kit is consumed; the patient is cleared and healed.
    local busyMedics = {}

    RegisterNetEvent('qbambulance:server:firstAidTarget', function(patientSrc)
        local src = source
        local cfg = Config.firstaid
        if not cfg.targetEnabled or busyMedics[src] then return end
        patientSrc = tonumber(patientSrc)
        if not patientSrc or patientSrc == src or patientSrc < 1 or patientSrc % 1 ~= 0 then return end

        local function nearby()
            if not QBCore:getPlayerData(src) or not QBCore:getPlayerData(patientSrc) then return false end
            return Kora.world.resolveNearbyPlayer(src, patientSrc, { maxDistance = cfg.targetRange or 3.0 }) ~= nil
        end
        local function fail(message)
            Kora.notify.send(src, { title = 'First Aid', message = message, type = 'error' })
        end

        local job = QBCore:getJob(src)
        if not job or job.name ~= Config.job.name or job.onduty ~= true then return fail('Only on-duty EMS can use a first aid kit on others.') end
        if not Death.isAlive(src) then return fail('Can\'t use a first aid kit right now.') end
        if not Death.isAlive(patientSrc) then return fail('The patient needs a revive, not a first aid kit.') end
        if not nearby() then return fail('The patient is too far away.') end
        if not QBCore:hasItem(src, 'firstaid') then return fail('You have no first aid kit.') end

        busyMedics[src] = true
        local completed = runFeedback(src, 'firstaid', { duration = cfg.duration })
        busyMedics[src] = nil
        if not completed then return end

        if not Death.isAlive(src) or not Death.isAlive(patientSrc) or not nearby() then
            return fail('The patient is no longer treatable.')
        end
        local removed = QBCore:removeItem(src, 'firstaid', 1, nil, 'first-aid-target')
        if not removed then return end
        Death.clearAllWounds(patientSrc)
        TriggerClientEvent('qbambulance:client:firstAidHeal', patientSrc)
        Kora.notify.send(src, { title = 'First Aid', message = 'You patched the patient up.', type = 'success' })
        Kora.notify.send(patientSrc, { title = 'First Aid', message = 'A medic patched you up.', type = 'success' })
    end)

    AddEventHandler('playerDropped', function()
        busyMedics[source] = nil
    end)
end

QBCore:createUseable('painkillers', function(src, item)
    local now = os.time()
    if not Items.painkillerEligible(now, lastPainkillerAt[src]) then
        Kora.notify.send(src, { title = 'Painkillers', message = 'You took some recently -- wait before taking more.', type = 'warning' })
        return
    end

    local cfg = Config.painkillers
    if not runFeedback(src, 'painkillers', {
        duration = cfg.animDuration,
        anim = { dict = cfg.animDict, clip = cfg.animClip, flag = 1 },
    }) then return end -- cancelled: nothing consumed, no cooldown

    local removed = QBCore:removeItem(src, 'painkillers', 1, item and item.slot, 'painkillers')
    if not removed then return end
    lastPainkillerAt[src] = now
    Items.applyPainkillerBenefit(src)
    Kora.notify.send(src, { title = 'Painkillers', message = 'The pain dulls a little.', type = 'success' })
end)

AddEventHandler('playerDropped', function()
    lastPainkillerAt[source] = nil
end)
