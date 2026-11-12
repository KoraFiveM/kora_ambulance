---
title: Compatibility
sidebar_position: 10
---

# Compatibility (`qb-ambulancejob` / `hospital:*`)

The manifest declares `provide 'qb-ambulancejob'`, so resources that list `qb-ambulancejob` as a dependency will start. When `Config.compat.enabled` is `true` (the default), `server/compat/hospital.lua` and `client/compat.lua` register the common legacy names.

These names keep working, but they do not give clients the power the original resource did. Every meaningful action goes through the same server checks as the native flow. Shortcuts that would let a client heal, revive, kill, choose a bed or remove items either do nothing or are off by default.

## Server events

| Event | Behaviour |
|---|---|
| `hospital:server:SetDeathStatus(isDead)` | Marks the sender dead only if `isDead == true` and the server sees the ped's health at 0 or below. |
| `hospital:server:SetLaststandStatus(inLaststand)` | Puts the sender in laststand (cause `legacy`) only if the server sees the ped's health at 0 or below. |
| `hospital:server:ambulanceAlert` | If the sender is downed, raises the `kora_ambulance:emergency` dispatch player alert. kora_dispatch can also register this event itself. |
| `hospital:server:SendDoctorAlert` | Raises the `kora_ambulance:doctor` alert if the sender is within 15 m of a hospital's `coords`. |
| `hospital:server:RespawnAtHospital(hospital)` | Runs `Death.respawnAtHospital` for the sender. `hospital` can be a name or a 1-based index. Unknown values fall back to the first hospital. A refusal reason is sent to the player as a notification. |
| `hospital:server:SendToBed(bedIndex)` | `bedIndex` is ignored. Starts a normal check-in at the nearest check-in point within `hospitalCare.interactionRange`. |
| `hospital:server:LeaveBed` | Releases the sender's bed. |
| `hospital:server:SyncInjuries(injuries)` | Ignored unless `Config.compat.acceptClientInjurySync` is on. Then it accepts a `bodyPart` to `tier` table and records wounds. The legacy `limbs` / `isBleeding` format is rejected. |
| `hospital:server:SetWeaponDamage(hash, modifier)` | Clamps `modifier` to the range 0-1 and sends `hospital:client:SetWeaponDamage` to the sender. |
| `hospital:server:RestoreWeaponDamage(hash)` | Sends `hospital:client:RestoreWeaponDamage` to the sender. |
| `hospital:server:SetArmor(armor)` | Clamps to 0-100 and asks the client to set armour. The client only applies it if it **lowers** armour. |
| `hospital:server:resetHungerThirst` | Does nothing. Needs are only reset by a hospital respawn. |
| `hospital:server:AddDoctor` / `RemoveDoctor` | Calls the duty toggle with the same job and duty-point checks as `/ems-duty`. |
| `hospital:server:RevivePlayer(targetSrc)` | If the sender is on-duty EMS within `reviveRange` of a downed target, starts the normal CPR flow on the sender's client. |
| `hospital:server:TreatWounds(targetSrc)` | If the sender is on-duty EMS within `treatment.range`, starts the normal Treat Wound flow. |
| `hospital:server:UseFirstAid` / `UseIfaks` / `UsePainkillers` | Uses `bandage` / `ifak` / `painkillers` through kora_core `useItem`, which runs the normal handlers. |
| `hospital:server:CanHelp` | Does nothing. |
| `hospital:server:removeBandage` / `removeIfaks` / `removePainkillers` | Remove one item only if `Config.compat.allowDestructiveItemEvents` is on. |

## Callbacks (kora_lib `Kora.callback`)

| Name | Returns |
|---|---|
| `hospital:GetDoctors` | Number of on-duty `Config.job.name` players. |
| `hospital:GetPlayerStatus(targetSrc?)` | `{ isdead, inlaststand, woundData }` for yourself, or for a target if you are on-duty EMS within `treatment.range`. Otherwise `nil, 'not authorized'`. |
| `hospital:GetPlayerBleeding(targetSrc?)` | Bleeding boolean. Same access rule. |

## Client events

| Event | Behaviour |
|---|---|
| `hospital:client:ambulanceAlert` | Registered but does nothing. kora_dispatch shows the call. |
| `hospital:client:Revive` / `RevivePlayer` | Shows a notice only if `Config.compat.reviveNotice` is on. Does not revive. |
| `hospital:client:SetPain(level)` | Turns a pain screen effect on (level above 0) or off. |
| `hospital:client:KillPlayer` | Does nothing. |
| `hospital:client:HealInjuries` | Notice only. Does not heal. |
| `hospital:client:SendToBed` | Notice only. |
| `hospital:client:leaveBed` | Fires `hospital:server:LeaveBed`. |
| `hospital:client:SetBed` / `SetBed2` | Notice only. |
| `hospital:client:RespawnAtHospital` | Fires `hospital:server:RespawnAtHospital`. |
| `hospital:client:SendBillEmail(amount)` | Shows a `Hospital Bill` notification. |
| `hospital:client:SetDoctorCount(count)` | Stores the count locally. |
| `hospital:client:adminHeal` | Shows `Client-side admin healing is disabled.` |
| `hospital:client:CheckStatus` | Shows your own dead, laststand and wound-count status (used by `/status`). |
| `hospital:client:TreatWounds` / `HelpPerson` | Notice that points to the target interactions. |
| `hospital:client:SetEscortingState(state)` | When `state` is falsy, tries to release a carry. |
| `hospital:client:UseFirstAid` / `UseBandage` / `UseIfaks` / `UsePainkillers` | Forward to the matching `hospital:server:Use*` event. |

## Exports and commands

- Server export `GetDoctorCount`. Client exports `isEscorted`, `CanHelp` and `PainKillerLoop`. See [Exports](./api/index.md). They are registered under `exports.kora_ambulance` only.
- `/aheal [id]` (admin) and `/status` (EMS). See [Commands](./commands.md).
- The `ifaks` item works as an alias of `ifak` for self use.

## Known gaps

- `hospital:client:SetWeaponDamage` and `hospital:client:RestoreWeaponDamage` are sent to the client, but this resource does not handle them.
- `hospital:client:SetEscortingState(false)` sends `kora_ambulance:server:stretcherRelease` with `TriggerServerEvent`. The server only registers that name through `Kora.events`, so the request never reaches it. Use the **Release Carried Patient** target instead.
