-- Pharmacy item registry. Each item's `effect` table is the ONLY place its
-- cosmetic consumption behaviour (screen fx, animation, hunger/thirst/stress
-- deltas) lives -- Core.consumables' generic bridge (kora_core) plays it back
-- automatically via Kora.status whenever the item is used, so nothing in this
-- resource's own client/server code calls Kora.fx/StartScreenEffect directly
-- for these items. `effect` is registered TWICE, deliberately: once on the
-- item record itself (QBCore:registerShared, server-authoritative,
-- what Core.consumables' hook reads) and once directly into Kora.status's own
-- registry (Kora.status.registerEffect, shared realm) -- Kora.status.apply only
-- knows an effect BY NAME if it was separately registered there; the item
-- record's `effect` field alone is not enough for playback to resolve it.
--
-- The REAL gameplay effect of each item (stopping bleed, restoring HP) is
-- NOT here -- that's server/items.lua's QBCore:createUseable handlers,
-- which run independently of this cosmetic bridge.

QBAmbulance = QBAmbulance or {}

local QBCore = exports.kora_core

QBAmbulance.items = {
    {
        name = 'bandage',
        label = 'Bandage',
        weight = 200,
        type = 'item',
        image = 'bandage.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Stops light bleeding and closes minor wounds.',
        effect = {
            duration = 2500,
            stacking = 'replace',
            anim = { dict = 'anim@amb@medic@standing@kneel@base', clip = 'base' },
            stressDelta = -3,
        },
    },
    {
        name = 'ifak',
        label = 'IFAK',
        weight = 350,
        type = 'item',
        image = 'ifak.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Individual First Aid Kit -- treats severe wounds and restores meaningful health.',
        effect = {
            duration = 4000,
            stacking = 'replace',
            anim = { dict = 'anim@amb@medic@standing@kneel@base', clip = 'idle_c' },
            stressDelta = -5,
            hungerDelta = 0,
            thirstDelta = 0,
        },
    },
    {
        name = 'painkillers',
        label = 'Painkillers',
        weight = 60,
        type = 'item',
        image = 'painkillers.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Dulls pain and steadies the nerves for a while. Not a substitute for real treatment.',
        effect = {
            duration = 180000,
            stacking = 'extend',
            fx = { screen = 'DrugsMichaelAliensFightIn' },
            anim = { dict = 'mp_suicide', clip = 'pill' },
            stressDelta = -10,
        },
    },
    {
        name = 'defibrillator',
        label = 'Defibrillator',
        weight = 1200,
        type = 'item',
        image = 'defibrillator.png',
        unique = false,
        -- Deliberately NOT self-useable: reviving is inherently target-based
        -- (you defib a specific downed patient, never yourself), so this
        -- item is consumed via client/revive.lua's kora_target option on a
        -- laststand/dead player, not QBCore:createUseable.
        useable = false,
        shouldClose = false,
        description = 'Delivers a controlled shock to restart a patient\'s heart. EMS use only.',
    },
}

for _, item in ipairs(QBAmbulance.items) do
    if item.effect then Kora.status.registerEffect(item.name, item.effect) end
end

if IsDuplicityVersion() then
    for _, item in ipairs(QBAmbulance.items) do
        QBCore:registerShared('items', item.name, item)
    end
end
