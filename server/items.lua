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
---@return boolean completed
local function runFeedback(src, itemName)
    local def = QBCore:getShared('items', itemName)
    local effect = def and def.effect or {}

    local completed = Kora.callback.trigger(src, 'qbambulance:client:pharmacyProgress', {
        label = def and def.label or itemName,
        duration = effect.duration or 2500,
        anim = effect.anim,
    })

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

QBCore:createUseable('painkillers', function(src, item)
    local now = os.time()
    if not Items.painkillerEligible(now, lastPainkillerAt[src]) then
        Kora.notify.send(src, { title = 'Painkillers', message = 'You took some recently -- wait before taking more.', type = 'warning' })
        return
    end

    if not runFeedback(src, 'painkillers') then return end

    local removed = QBCore:removeItem(src, 'painkillers', 1, item and item.slot, 'painkillers')
    if not removed then return end
    lastPainkillerAt[src] = now
    Kora.notify.send(src, { title = 'Painkillers', message = 'The pain dulls a little.', type = 'success' })
end)

AddEventHandler('playerDropped', function()
    lastPainkillerAt[source] = nil
end)
