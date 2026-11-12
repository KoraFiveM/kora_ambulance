---
title: Items
sidebar_position: 7
---

# Items

## Items registered by kora_ambulance

`shared/items.lua` registers these items with kora_core (`registerShared('items', ...)`) when the server starts. You do not need to add them to kora_core yourself. They expect inventory images with the names shown.

| Name | Label | Weight | Image | Description |
|---|---|---|---|---|
| `bandage` | Bandage | 200 | `bandage.png` | Stops light bleeding and closes minor wounds. |
| `ifak` | IFAK | 350 | `ifak.png` | Individual First Aid Kit: treats severe wounds and restores meaningful health. |
| `painkillers` | Painkillers | 60 | `painkillers.png` | Dulls pain and steadies the nerves for a while. |
| `defibrillator` | Defibrillator | 1200 | `defibrillator.png` | Restarts a patient's heart. EMS use only. |

All four are `useable`, `shouldClose` and not unique. `bandage` and `ifak` have an `effect` table that kora_core's consumables bridge plays when the item is used (an animation and a stress reduction). These effects are also registered with `Kora.status`.

## Items from kora_core used here

| Name | Use |
|---|---|
| `firstaid` | First aid kit (see below). |
| `ifaks` | Legacy alias of `ifak` for self use. Patient treatment only uses `ifak`. |

## Use behaviour

All handlers are registered with kora_core `createUseable` in `server/items.lua` and `server/revive.lua`. A progress bar runs on the user's client and can be cancelled. **The item is only removed if the bar completes.**

| Item | Requirements | Bar | Effect |
|---|---|---|---|
| `bandage` | Alive, and has a wound a bandage can treat (no `ifakRequired`, tiers 1-2 by default) | 2500 ms | Closes the worst such wound. |
| `ifak` / `ifaks` | Alive, has any open wound | 4000 ms | Closes the worst open wound. Using it on yourself does not restore health. |
| `firstaid` | `Config.firstaid.enabled`, alive | `Config.firstaid.duration` | Closes every wound and restores full health. |
| `painkillers` | `Config.painkillers.interval` has passed since the last use | `Config.painkillers.animDuration` with the pill animation | Restores `healthAmount` health (alive only). Optionally stops the bleeding (`stopBleeding`). Starts the cooldown. |
| `defibrillator` | `Config.defibrillator.useable`, on-duty EMS, a downed patient within `reviveRange` | CPR minigame | Starts CPR on the nearest downed patient. Only a **successful** revive uses up the defibrillator. |

If an item is removed but the wound has already been closed by something else, the item is given back.

## Items used by medics

| Action | Item used up |
|---|---|
| Treat Wound target | One `bandage` (tier 1-2) or one `ifak` (any tier) from the medic. An IFAK also heals the patient by `Config.treatment.ifakHealthAmount`. |
| Perform CPR | One `defibrillator`, only when the revive succeeds. |
| Use First Aid Kit target | One `firstaid` from the medic. |

## Where to get them

Each hospital with a `pharmacy` point has a shop that sells `bandage` (15), `ifak` (60), `painkillers` (25) and `defibrillator` (350). See [Hospitals](./features/hospitals.md#pharmacy-and-stash). The shop is open to everyone, not only EMS.
