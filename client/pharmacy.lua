-- Pharmacy (client realm) -- use-feedback ONLY. The real gameplay effect of
-- each item (closing a wound, the painkiller cooldown) lives entirely in
-- server/items.lua's QBCore:createUseable handlers; the cosmetic
-- screen-fx/anim/hunger/thirst/stress playback is entirely generic
-- (kora_core's Core.consumables reading the item's own `effect` table) -- this
-- file's only job is running the QB.progressbar the server asks for while a
-- pharmacy item is being applied, so treatment can be interrupted (moving,
-- taking damage, the cancel key) instead of being an instant, un-interactable
-- server-side flip.

QB.callback.register('qbambulance:client:pharmacyProgress', function(payload)
    return QB.progressbar.start({
        label = ('Using %s'):format(payload.label or 'item'),
        duration = payload.duration or 2500,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = payload.anim and { dict = payload.anim.dict, clip = payload.anim.clip } or nil,
    })
end)
