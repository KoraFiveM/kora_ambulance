---
title: Persistence
sidebar_position: 8
---

# Persistence

kora_ambulance has **no SQL files** and creates no tables. Everything that needs to survive a restart is stored in kora_core player metadata, which kora_core saves with the rest of the character.

## Metadata keys

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `isdead` | boolean | `server/death.lua` | Player is dead. |
| `inlaststand` | boolean | `server/death.lua` | Player is in laststand. |
| `kora_ambulanceMedical` | table | `server/death.lua` | Wound ledger and down-state timestamps (below). |

`isdead` and `inlaststand` are the source of the medical state. Exactly one of them can be `true`, and neither is `true` while alive.

### `kora_ambulanceMedical`

```lua
{
    version = 1,
    wounds = { chest = 3, left_leg = 1 }, -- bodyPart -> tier (1..4)
    bleedStopped = true,                  -- optional: a revive/painkiller stopped the bleeding
    laststandAt = 1767225600,             -- optional unix time, only while in laststand
    deadAt = 1767225900,                  -- optional unix time, only while dead
}
```

The record is rewritten whenever a wound, the bleed state or the down state changes. When it is loaded, the server cleans it up:

- unknown body parts, tiers that are not whole numbers or out of range, and timestamps in the future are dropped,
- `bleedStopped` is only kept if there are open wounds,
- the timestamps are made to match the `isdead` / `inlaststand` flags,
- a laststand that ran out while the player was offline becomes dead immediately,
- extra fields or a different `version` cause the record to be rewritten.

## Server memory only

These are **not** saved and are lost when the resource restarts: house call queue, bed reservations, CPR and treatment actions, duty vehicles (deleted on stop), stretchers (deleted on stop), dispatch and alert cooldowns, the painkiller cooldown and the AI doctor cooldown.

## Other resources' data

- **Money**: bills use kora_core `getMoney` / `removeMoney` on `Config.billing.account` and `fallbackAccount`.
- **Inventory**: items are removed and added through kora_core. Pharmacy shops and stashes are registered with kora_inventory, which owns the stash contents. `/respawn` can call `exports.kora_inventory:clearInventory`.
- **Job and duty**: read with kora_core `getJob` / `getPlayersByJob`, written with `setJobDuty`.
