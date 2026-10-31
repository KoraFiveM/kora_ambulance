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
