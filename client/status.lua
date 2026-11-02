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
        Kora.status.remove(name)
    end
end

RegisterNetEvent('qbambulance:client:syncStatus', function(bleedingTier, limpingTier)
    reconcile('bleeding', bleedingTier)
    reconcile('limping', limpingTier)
end)

-- Admin /heal only sets health on this client (qbadmin:client:heal), so the
-- server never learns of it. Report it once the new health has replicated; the
-- server re-checks health itself and closes the wounds. Event driven, no polling.
RegisterNetEvent('qbadmin:client:heal', function()
    if not Config.injuries.clearOnHealEvent then return end
    SetTimeout(750, function()
        Kora.events.trigger('qbambulance:server:healthRestored')
    end)
end)
