---
title: "Death and injuries"
sidebar_position: 2
---


# Death and injuries

The authoritative life-cycle state machine (alive / laststand / dead) and the anatomical wound ledger every other module (billing, hospital, treatment, dispatch, doctors) reads from.

Namespace: `Death.* / exports.kora_ambulance` · Source: `server/death.lua, shared/wounds.lua, shared/downed.lua, config.lua (Config.death, Config.injuries, Config.revive, Config.bleed, Config.woundLevels, Config.bodyParts, Config.weaponClassMap)`

## How it works

Client-observed hits are reported via the `kora_ambulance:server:hitObserved` event and correlated/validated before a wound is recorded (Death.recordWound) with a body part and severity tier. Bleeding wounds tick damage on a shared sweep (Death._sweep) until treated, revived, or checked in at a hospital. A sustained tier-4 bleed on a vital body part shortens the blackout timer before forced laststand.

## Check and act on a player’s state from another resource

1. **Read the status** — Call exports.kora_ambulance:getPatientStatus(src) rather than guessing at health alone.
2. **Revive without a bill when appropriate** — Use exports.kora_ambulance:fullRevive(src) for an unconditional, no-bill revive (admin tooling, event rewards, etc.).
3. **Let the hospital/billing flow handle normal play** — Do not bypass Death.respawnAtHospital/Billing for ordinary player deaths — it is what keeps the billing and wound-clearing behavior consistent.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Laststand | The downed-but-not-dead state; a bleed-out timer (Config.death.deathTime) runs until a revive or the timer expires into full death. |
| Wound ledger | The table of still-open body-part -> severity-tier entries a player carries; cleared by treatment, a sufficiently thorough revive, or hospital check-in care. |

## Functions

The core state and revive functions; two are exported for other resources (fullRevive, getPatientStatus).

### `exports.kora_ambulance:getPatientStatus(src)`

Reads back a player’s current death/wound status for another resource (e.g. a HUD or medical UI).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **status** — `{ version, state, wounds, bleeding, laststandAt, deadAt }`, or `nil` when `src` is not an online player.
- **`state`** — `'alive'`, `'laststand'` or `'dead'`.
- **`wounds`** — `{ [bodyPart] = tier }`, a copy: changing it never alters the ledger.
- **`bleeding`** — boolean.
- **`laststandAt` / `deadAt`** — Unix timestamps (`os.time()`), or `nil` when not applicable.
- **`version`** — the snapshot format, currently `1`.

**Example**

```lua
local status = exports.kora_ambulance:getPatientStatus(src)
```

**Representative console output**

```text
The snapshot is detached, so a caller can modify it freely. Source: server/death.lua.
```

## Limits and related APIs

Server only on this module; client/death.lua owns the local downed-state presentation (camera, respawn prompt) that mirrors this server state.

### `exports.kora_ambulance:fullRevive(src)`

Revives and clears everything for a player, whatever `Config.revive` says. This is the export admin tools should use. Source: `server/death.lua`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer or numeric string | Player server id. |

**Returns**

- **`boolean`** — `false` if the player is not loaded.

If the player is downed, they are revived at 100 percent health with every wound and the bleeding cleared. If the player is already alive, it clears every wound and the down-state timestamps, and republishes `emsDown = false`. Either way it fires `kora_ambulance:server:onPlayerRevived`, which closes the player's EMS calls and releases them from any carry or stretcher.

**Example**

```lua
local ok = exports.kora_ambulance:fullRevive(src)
```

### `getPatientStatus` result fields

The table returned by `getPatientStatus` has these fields. A `nil` result means the player is not loaded.

| Field | Type | Description |
|---|---|---|
| `version` | integer | Format version, currently `1`. |
| `state` | string | `'alive'`, `'laststand'` or `'dead'`. |
| `wounds` | table | Body part name mapped to tier, for example `{ chest = 3, left_leg = 1 }`. |
| `bleeding` | boolean | `true` while any wound is open and the bleeding has not been stopped. |
| `laststandAt` | integer or nil | Unix time the player entered laststand. |
| `deadAt` | integer or nil | Unix time the player died. |

```lua
local status = exports.kora_ambulance:getPatientStatus(src)
if status and status.state ~= 'alive' then
    print(('%d is %s, bleeding: %s'):format(src, status.state, tostring(status.bleeding)))
end
```
