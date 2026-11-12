---
title: Exports
sidebar_position: 6
---

# Exports

## Server exports

### `fullRevive`

```lua
local ok = exports.kora_ambulance:fullRevive(src)
```

| Param | Type | Description |
|---|---|---|
| `src` | integer or numeric string | Player server id. |

**Returns** `boolean`. It is `false` if the player is not loaded.

Revives and clears **everything**, whatever `Config.revive` says. If the player is downed, they are revived at 100 percent health with every wound and the bleeding cleared. If the player is already alive, it clears every wound and the down-state timestamps, and republishes `emsDown = false`. Either way it fires `kora_ambulance:server:onPlayerRevived`, which closes the player's EMS calls and releases them from any carry or stretcher. This is the export admin tools should use.

### `getPatientStatus`

```lua
local status = exports.kora_ambulance:getPatientStatus(src)
if status and status.state ~= 'alive' then
    print(('%d is %s, bleeding: %s'):format(src, status.state, tostring(status.bleeding)))
end
```

| Param | Type | Description |
|---|---|---|
| `src` | integer or numeric string | Player server id. |

**Returns** a table, or `nil` if the player is not loaded. The table is a copy, so changing it does not change the ledger.

| Field | Type | Description |
|---|---|---|
| `version` | integer | Format version, currently `1`. |
| `state` | string | `'alive'`, `'laststand'` or `'dead'`. |
| `wounds` | table | Body part name mapped to tier, for example `{ chest = 3, left_leg = 1 }`. |
| `bleeding` | boolean | `true` while any wound is open and the bleeding has not been stopped. |
| `laststandAt` | integer or nil | Unix time the player entered laststand. |
| `deadAt` | integer or nil | Unix time the player died. |

### `GetDoctorCount` (compatibility)

```lua
local count = exports.kora_ambulance:GetDoctorCount()
```

Returns the number of on-duty players with job `Config.job.name`, of any grade. Only registered when `Config.compat.enabled` is on. It is registered under the `kora_ambulance` name only. The manifest's `provide 'qb-ambulancejob'` satisfies dependency checks, but kora_ambulance does not register `__cfx_export_qb-ambulancejob_*` aliases. Callers using `exports['qb-ambulancejob']` must switch to `exports.kora_ambulance`.

## Client exports

These are all compatibility exports. They are only registered when `Config.compat.enabled` is on.

### `isEscorted`

```lua
local carried = exports.kora_ambulance:isEscorted()
```

Returns `true` while the local player is being carried or lies on a stretcher.

### `CanHelp`

```lua
local canHelp = exports.kora_ambulance:CanHelp()
```

Returns `true` when the local player is alive and not being carried or on a stretcher. Use it only for display purposes. It does **not** authorise anything.

### `PainKillerLoop`

```lua
exports.kora_ambulance:PainKillerLoop()
```

Does nothing. It exists so legacy callers do not error.

## Not exported

`Death`, `Hospital`, `Billing`, `Treatment`, `Stretcher` and the other module tables are globals **inside kora_ambulance only**. Other resources cannot call functions such as `Death.respawnAtHospital`. To integrate, use the exports above and the [events](./events.md).
