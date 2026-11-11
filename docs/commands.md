---
title: Commands and keybinds
sidebar_position: 4
---

# Commands and keybinds

## Commands

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

## Key mappings

Both are registered with `Kora.keybind.add`, so players can rebind them in the FiveM key settings.

| Name | Default key | Description | When active |
|---|---|---|---|
| `kora_ambulance_alert_ems` | `Config.death.alertEms.key` (`G`) | EMS: alert paramedics while dead | Only registered when `alertEms.enabled` is on. Does nothing unless the player is dead. |
| `kora_ambulance_leave_bed` | `Config.hospitalCare.leaveKey` (`E`) | EMS: leave your hospital bed | Only enabled while a check-in bed is reserved. Not registered when `leaveKey` is `''`. |

## Other controls

- **Stop Carrying**: while carrying a patient with `Config.carry.stopPrompt` on, pressing control `Config.carry.stopControl` (default 38, E) releases the patient. This is a polled control, not a key mapping, and it is ignored while the kora_target menu is open.
- **CPR minigame**: a kora_lib `mash` minigame (15 presses within 8 seconds, one attempt).
