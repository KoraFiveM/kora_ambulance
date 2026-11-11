-- Status sync (client realm) -- keeps the local bleeding/limping Kora.status
-- effects (the HUD's status pills read them) equal to the wound state the
-- server owns. The server pushes this after every wound or revive change; a
-- revive path that only ever removed the effect server-side (or an admin
-- revive that bypassed us) used to leave the pill up forever.

---@param name string
---@param severity integer|false
local function reconcile(name, severity)
    local current
    for _, entry in ipairs(Kora.status.getActive()) do
        if entry.name == name then current = entry; break end
    end

    if type(severity) == 'number' and severity >= 1 then
        if not current or current.severity ~= severity then
            Kora.status.apply(name, { severity = severity })
        end
    elseif current then
        -- kora_lib refuses a removal from this resource for an effect it applied
        -- itself (a server push), so the pill survives. Only the server can
        -- clear that one: ask it to, once it has checked the ledger agrees.
        if not Kora.status.remove(name) and Kora.status.isActive(name) then
            Kora.events.trigger('kora_ambulance:server:statusStale', name)
        end
    end
end

RegisterNetEvent('kora_ambulance:client:syncStatus', function(bleedingTier, limpingTier)
    reconcile('bleeding', bleedingTier)
    reconcile('limping', limpingTier)
end)

-- Admin /heal only sets health on this client (kora_admin:client:heal), so the
-- server never learns of it. Report it once the new health has replicated; the
-- server re-checks health itself and closes the wounds. Event driven, no polling.
RegisterNetEvent('kora_admin:client:heal', function()
    if not Config.injuries.clearOnHealEvent then return end
    SetTimeout(750, function()
        Kora.events.trigger('kora_ambulance:server:healthRestored')
    end)
end)

-- Every path that sets this ped's health from outside a fight (admin heal and
-- revive, CPR, hospital respawn): the health change that follows is not an
-- injury, so a hit pending from before must not turn it into a new wound.
for _, eventName in ipairs({
    'kora_admin:client:heal',
    'kora_admin:client:revive',
    'kora_ambulance:client:revived',
    'kora_ambulance:client:respawnedAtHospital',
}) do
    RegisterNetEvent(eventName, function()
        Damage.suppressFor(Config.injuries.healGraceMs)
    end)
end
