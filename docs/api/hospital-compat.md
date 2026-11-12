---
title: "Legacy hospital exports"
sidebar_position: 3
---


# Legacy hospital exports

## Client

Small client exports that scripts written against qb-ambulancejob call. The native way to read a patient's state is `getPatientStatus` on the Death module.

Namespace: `exports.kora_ambulance (qb-ambulancejob compatibility)` · Source: `client/compat.lua`

### Functions

Three exports.

#### `exports.kora_ambulance:isEscorted()`

Whether the local player is currently being dragged on a stretcher.

**Parameters**



**Returns**

- **`boolean`** — `true` while the local player is being dragged, otherwise `false`.

**Example**

```lua
if exports.kora_ambulance:isEscorted() then return end
```

**Representative console output**

```text
Registered in client/compat.lua for scripts written against qb-ambulancejob.
```

#### `exports.kora_ambulance:CanHelp()`

Whether the local player is able to help another player right now: alive and not being dragged.

**Parameters**



**Returns**

- **`boolean`** — `true` when the local player is alive and not being dragged on a stretcher.

**Example**

```lua
if exports.kora_ambulance:CanHelp() then
    -- offer the first-aid action
end
```

**Representative console output**

```text
Registered in client/compat.lua for scripts written against qb-ambulancejob.
```

#### `exports.kora_ambulance:PainKillerLoop()`

Does nothing. Kept so scripts that call qb-ambulancejob's `PainKillerLoop` do not error.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
exports.kora_ambulance:PainKillerLoop()
```

**Representative console output**

```text
A deliberate no-op: the function body is empty.
```

## Server

A small server export that scripts written against qb-ambulancejob call.

Namespace: `exports.kora_ambulance (qb-ambulancejob compatibility)` · Source: `server/compat/hospital.lua`

### Functions

One export.

#### `exports.kora_ambulance:GetDoctorCount()`

Counts the on-duty players who have the ambulance job.

**Parameters**



**Returns**

- **`integer`** — the number of on-duty players whose job is `Config.job.name` (default `ambulance`).

**Example**

```lua
local doctors = exports.kora_ambulance:GetDoctorCount()
```

**Representative console output**

```text
Registered in server/compat/hospital.lua for scripts written against qb-ambulancejob.
```

## Registration notes

These compatibility exports (`GetDoctorCount`, `isEscorted`, `CanHelp`, `PainKillerLoop`) are only registered when `Config.compat.enabled` is on. They are registered under the `kora_ambulance` name only. The manifest's `provide 'qb-ambulancejob'` satisfies dependency checks, but kora_ambulance does not register `__cfx_export_qb-ambulancejob_*` aliases. Callers using `exports['qb-ambulancejob']` must switch to `exports.kora_ambulance`.

`CanHelp` is for display only. It does **not** authorise anything. `isEscorted` is `true` while the local player is carried or lies on a stretcher.
