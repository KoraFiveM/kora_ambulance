-- Pharmacy (client realm) -- use-feedback ONLY. The real gameplay effect of
-- each item (closing a wound, the painkiller cooldown) lives entirely in
-- server/items.lua's QBCore:createUseable handlers; the cosmetic
-- screen-fx/anim/hunger/thirst/stress playback is entirely generic
-- (kora_core's Core.consumables reading the item's own `effect` table) -- this
-- file's only job is running the Kora.progressbar the server asks for while a
-- pharmacy item is being applied, so treatment can be interrupted (moving,
-- taking damage, the cancel key) instead of being an instant, un-interactable
-- server-side flip.

Kora.callback.register('qbambulance:client:pharmacyProgress', function(payload)
    return Kora.progressbar.start({
        label = ('Using %s'):format(payload.label or 'item'),
        duration = payload.duration or 2500,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = payload.anim and { dict = payload.anim.dict, clip = payload.anim.clip, flag = payload.anim.flag } or nil,
    })
end)

-- First aid kit: server/items.lua consumed the item and cleared the wounds;
-- restore the ped to full health (a downed player is left to the death flow).
RegisterNetEvent('qbambulance:client:firstAidHeal', function()
    if State and State.isAlive and not State.isAlive() then return end
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end)

-- Painkiller benefit. SetEntityHealth only exists client-side, so server/items.lua
-- (which owns item removal and the cooldown) sends the Config.painkillers.
-- healthAmount here after a completed use. Capped at max health; a downed
-- player's health is left to the death flow.
RegisterNetEvent('qbambulance:client:painkillerBenefit', function(amount)
    if State and State.isAlive and not State.isAlive() then return end
    local ped = PlayerPedId()
    local boosted = Downed.boostedHealth(GetEntityHealth(ped), amount, GetEntityMaxHealth(ped))
    if boosted then SetEntityHealth(ped, boosted) end
end)
