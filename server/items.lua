-- Items (server realm) -- the REAL gameplay effect of pharmacy items
-- (closing a wound, the painkiller cooldown gate). Cosmetic playback
-- (screen fx, anim, hunger/thirst/stress) is entirely handled by qbcore's
-- Core.consumables reading the `effect` table shared/items.lua registered --
-- nothing here calls QB.fx/QB.status for cosmetics, only for the durable
-- bleeding/limping state the wound actually being treated changes.

Items = Items or {}

-- qbcore has no QB proxy of its own (see this resource's own AGENTS-style
-- header note in the plan) -- every Core.<module>.<fn> call must cross the
-- exports boundary as a flat exports.qbcore:<fn>(...) call instead.
local QBCore = exports.qbcore

local lastPainkillerAt = {} -- src -> os.time()

---@param now integer os.time()
---@param lastUsedAt integer|nil
---@return boolean eligible
function Items.painkillerEligible(now, lastUsedAt)
    if not lastUsedAt then return true end
    return (now - lastUsedAt) >= math.floor(Config.painkillers.interval / 1000)
end

---@param src integer
---@param maxTier integer
---@return boolean treated
local function treatWound(src, maxTier)
    local woundData = Death.getWoundData(src)
    local bodyPart, tier = Wounds.pickTreatableWound(woundData, maxTier)
    if not bodyPart then return false end

    Death.clearWound(src, bodyPart)
    QB.notify.send(src, { title = 'First Aid', message = ('Treated a wound (%s).'):format(Wounds.bodyPartDef(bodyPart) and Wounds.bodyPartDef(bodyPart).label or bodyPart), type = 'success' })
    return true
end

-- qbinventory's own useItem does NOT auto-remove the item on use (verified
-- by reading qbinventory/server.lua's intentUse/useItem -- neither path
-- calls removePlayer) -- every handler below explicitly removes its own
-- item on a successful use, otherwise these would be infinite-use.

-- Client "feedback" step (client/pharmacy.lua's whole reason to exist,
-- per the plan): the SERVER asks the ITEM USER's own client to run a
-- QB.progressbar, using QB.callback.trigger's server->client direction
-- (the reverse of the usual client-asks-server shape), and awaits whether
-- it completed. Reuses the SAME duration/anim already registered on the
-- item's `effect` table (shared/items.lua) rather than duplicating it in a
-- second config -- one number/anim pair per item, not two.
---@param src integer
---@param itemName string
---@return boolean completed
local function runFeedback(src, itemName)
    local def = QBCore:getShared('items', itemName)
    local effect = def and def.effect or {}

    local ok, completed = pcall(QB.callback.trigger, src, 'qbambulance:client:pharmacyProgress', {
        label = def and def.label or itemName,
        duration = effect.duration or 2500,
        anim = effect.anim,
    })

    return ok and completed == true
end

QBCore:createUseable('bandage', function(src, item)
    if not Death.isAlive(src) then
        QB.notify.send(src, { title = 'First Aid', message = 'Can\'t apply a bandage right now.', type = 'error' })
        return
    end

    if not Wounds.pickTreatableWound(Death.getWoundData(src), 2) then
        QB.notify.send(src, { title = 'First Aid', message = 'No wound a bandage can treat.', type = 'warning' })
        return
    end

    if runFeedback(src, 'bandage') then
        local removed = QBCore:removeItem(src, 'bandage', 1, item and item.slot, 'first-aid')
        if removed and not treatWound(src, 2) then
            QBCore:addItem(src, 'bandage', 1, item and item.slot, item and item.info or {}, 'first-aid-rollback')
        end
    end
end)

QBCore:createUseable('ifak', function(src, item)
    if not Death.isAlive(src) then
        QB.notify.send(src, { title = 'First Aid', message = 'Can\'t apply an IFAK right now.', type = 'error' })
        return
    end

    if not Wounds.pickTreatableWound(Death.getWoundData(src), Wounds.MAX_TIER) then
        QB.notify.send(src, { title = 'First Aid', message = 'No open wound to treat.', type = 'warning' })
        return
    end

    if runFeedback(src, 'ifak') then
        local removed = QBCore:removeItem(src, 'ifak', 1, item and item.slot, 'first-aid')
        if removed and not treatWound(src, Wounds.MAX_TIER) then
            QBCore:addItem(src, 'ifak', 1, item and item.slot, item and item.info or {}, 'first-aid-rollback')
        end
    end
end)

QBCore:createUseable('painkillers', function(src, item)
    local now = os.time()
    if not Items.painkillerEligible(now, lastPainkillerAt[src]) then
        QB.notify.send(src, { title = 'Painkillers', message = 'You took some recently -- wait before taking more.', type = 'warning' })
        return
    end

    if not runFeedback(src, 'painkillers') then return end

    local removed = QBCore:removeItem(src, 'painkillers', 1, item and item.slot, 'painkillers')
    if not removed then return end
    lastPainkillerAt[src] = now
    QB.notify.send(src, { title = 'Painkillers', message = 'The pain dulls a little.', type = 'success' })
end)

AddEventHandler('playerDropped', function()
    lastPainkillerAt[source] = nil
end)
