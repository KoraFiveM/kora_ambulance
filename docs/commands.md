---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora Ambulance registers a handful of player-facing commands directly (not through kora_admin’s permission gates). None of these are staff-only — EMS-specific ones check on-duty job state inside their handler instead of a permission tier.

## Built-in commands

### `/respawn`

Accepted only once the post-death respawn timer has elapsed (and, if `Config.death.respawn.blockWhenMedics.enabled`, only while fewer than `minOnDuty` medics are on duty). Places the player at a random bed of the first configured hospital (or its entrance when `Config.death.respawn.useBeds` is off) and charges the hospital bill.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any dead player; the server independently re-validates timing and the medic-block gate on every attempt. |

**Example**

```text
/respawn
```

**Result**

Player respawns at a hospital bed and is billed via Billing.chargeForRespawn.

### `/911e [message]`

Reports a medical emergency to every on-duty EMS of Config.job.type, with the caller’s own server-read position.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | message? — free text describing the emergency. |
| Access | Any player; cooldown Config.dispatch.alertCooldown per player. |

**Example**

```text
/911e Shot at the docks
```

**Result**

"Your emergency has been reported to EMS." or "No paramedics are currently on duty." depending on recipient count.

### `/housecall [note]`

Queues a non-emergency EMS visit request.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | note? — what you need. |
| Access | Any player; cooldown Config.dispatch.housecallCooldown, one pending request per character, capped at Config.dispatch.maxHousecalls total. |

**Example**

```text
/housecall Need a checkup, no rush
```

**Result**

"Your request has been queued for EMS." Appears on the EMS dispatch feed as a priority-3 call.

### `/housecalls`

Lists open house-call queue entries.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | Restricted to the configured EMS job (checked inside the handler against Config.job.name) — not reachable by other players. |

**Example**

```text
/housecalls
```

**Result**

Chat list of unclaimed requests.

### `/ems-duty`

Toggles on/off duty for the ambulance job. Requires the player to hold the EMS job and be near a configured hospital duty point.

| Field | Details |
| --- | --- |
| Context | In-game · server command (Kora.commands.add) |
| Arguments | No arguments. |
| Access | Must hold Config.job.name; refused away from a duty point or within 1 second of a previous change. |

**Example**

```text
/ems-duty
```

**Result**

"You are now on duty."/"You are now off duty." or the specific refusal reason.

### `/accepthousecall <id>`

Claims a queued house-call request, by request id (see /housecalls). Shares one implementation with the dispatch UI’s accept button so a request can never be claimed twice.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id — the request id. |
| Access | Must hold Config.job.name and be on duty (checked inside the handler, not a kora_admin permission tier). |

**Example**

```text
/accepthousecall 7
```

**Result**

"A paramedic is on the way." to the requester, or "That request is no longer available." if someone else claimed it first.

### `/aheal [id]`

Admin-style heal: fully revives a dead target or heals/clears wounds on a laststand target to 100%. Part of the legacy compatibility layer, only registered when Config.compat.enabled is true.

| Field | Details |
| --- | --- |
| Context | In-game · server command (legacy compat) |
| Arguments | id? — defaults to yourself if omitted. |
| Access | Registered with kora_core's addCommand permission argument literally `'admin'` — the only command in this resource that uses kora_core's own permission-string gating rather than an in-handler job check. |

**Example**

```text
/aheal 7
```

**Result**

"Healed player 7." Logged via Kora.logging.event('ambulance:aheal', ...).

### `/status`

Shows your own health/wound status, part of the legacy compatibility layer (Config.compat.enabled).

| Field | Details |
| --- | --- |
| Context | In-game · server command (legacy compat) |
| Arguments | No arguments. |
| Access | Must hold Config.job.name (EMS only). |

**Example**

```text
/status
```

**Result**

Triggers hospital:client:CheckStatus on your own client to display the status UI.

## No kora_admin-gated staff commands

Most of this resource’s commands check job/on-duty state directly rather than a kora_admin permission tier. /aheal is the one exception, using kora_core’s own `'admin'` permission string. kora_admin’s /revive, /heal and the admin menu remain the primary staff-facing surface for ambulance-adjacent actions (see the kora_admin documentation); this resource exposes Death.fullRevive and getPatientStatus as exports for that integration (see Functions).

## Command summary

| Command | Args | Who | Registered by | Effect |
|---|---|---|---|---|
| `/ems-duty` | none | Job `Config.job.name`, near a hospital duty point | `Kora.commands.add` (server) | Toggles EMS duty. See [Duty](./features/duty-and-vehicles.md). |
| `/911e` | `[message]` (optional) | Anyone | kora_core `addCommand` | Priority 1 EMS call at the caller's position. Cooldown `Config.dispatch.alertCooldown`. See [Dispatch](./features/dispatch.md). |
| `/housecall` | `[note]` (optional, max 120 chars) | Anyone | kora_core `addCommand` | Queues a non-emergency house call. |
| `/housecalls` | none | Job `Config.job.name` (duty not checked) | kora_core `addCommand` | Lists open house calls. |
| `/accepthousecall` | `<id>` (required) | On-duty EMS | kora_core `addCommand` | Claims a house call and sets a waypoint. |
| `/respawn` | none | A dead player, after `Config.death.respawnTime` | `RegisterCommand` (client) | Respawns at the first configured hospital and bills the player. See [Death and respawn](./features/death-and-respawn.md). |
| `/aheal` | `[id]` (optional, defaults to self) | kora_core `admin` permission | kora_core `addCommand` | Full revive and heal of the target. Logged through `Kora.logging` as `ambulance:aheal`. Only registered when `Config.compat.enabled` is on. |
| `/status` | none | Job `Config.job.name` | kora_core `addCommand` | Shows **your own** dead / laststand flags and open wound count. Only registered when `Config.compat.enabled` is on. |

> Registration and access notes above reflect the code. The `Registered by` column shows whether a command comes from `Kora.commands.add`, kora_core `addCommand` or a client `RegisterCommand`. `/aheal` and `/status` exist only when `Config.compat.enabled` is on.

## Key mappings

Both are registered with `Kora.keybind.add`, so players can rebind them in the FiveM key settings.

| Name | Default key | Description | When active |
|---|---|---|---|
| `kora_ambulance_alert_ems` | `Config.death.alertEms.key` (`G`) | EMS: alert paramedics while dead | Only registered when `alertEms.enabled` is on. Does nothing unless the player is dead. |
| `kora_ambulance_leave_bed` | `Config.hospitalCare.leaveKey` (`E`) | EMS: leave your hospital bed | Only enabled while a check-in bed is reserved. Not registered when `leaveKey` is `''`. |

## Other controls

- **Stop Carrying**: while carrying a patient with `Config.carry.stopPrompt` on, pressing control `Config.carry.stopControl` (default 38, E) releases the patient. This is a polled control, not a key mapping, and it is ignored while the kora_target menu is open.
- **CPR minigame**: a kora_lib `mash` minigame (15 presses within 8 seconds, one attempt).
