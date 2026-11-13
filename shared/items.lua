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

KoraAmbulance = KoraAmbulance or {}

local QBCore = exports.kora_core

KoraAmbulance.items = {
    {
        name = 'bandage',
        label = Kora.lang('items.bandage'),
        weight = 200,
        type = 'item',
        image = 'bandage.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = Kora.lang('items.bandage_description'),
        effect = {
            duration = 2500,
            stacking = 'replace',
            anim = { dict = 'anim@amb@medic@standing@kneel@base', clip = 'base' },
            stressDelta = -3,
        },
    },
    {
        name = 'ifak',
        label = Kora.lang('items.ifak'),
        weight = 350,
        type = 'item',
        image = 'ifak.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = Kora.lang('items.ifak_description'),
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
        label = Kora.lang('items.painkillers'),
        weight = 60,
        type = 'item',
        image = 'painkillers.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = Kora.lang('items.painkillers_description'),
        -- Deliberately no `effect` table: kora_core's usingItem hook applies an
        -- item's effect (anim included) the moment Use is clicked, before the
        -- progress bar and even if it is cancelled, and a looping status anim
        -- never ended with the bar. Animation, bar and benefit are all driven
        -- by server/items.lua from Config.painkillers on completion.
    },
    {
        name = 'defibrillator',
        label = Kora.lang('items.defibrillator'),
        weight = 1200,
        type = 'item',
        image = 'defibrillator.png',
        unique = false,
        -- Using it from the inventory (server/revive.lua, Config.defibrillator.
        -- useable) starts CPR on the nearest downed patient; the item is only
        -- consumed by a successful revive (also reachable via the kora_target
        -- option in client/revive.lua).
        useable = true,
        shouldClose = true,
        description = Kora.lang('items.defibrillator_description'),
    },
}

for _, item in ipairs(KoraAmbulance.items) do
    if item.effect then Kora.status.registerEffect(item.name, item.effect) end
end

if IsDuplicityVersion() then
    for _, item in ipairs(KoraAmbulance.items) do
        QBCore:registerShared('items', item.name, item)
    end
end
