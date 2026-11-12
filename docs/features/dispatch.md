---
title: Dispatch and house calls
sidebar_position: 7
---

# Dispatch and house calls

[kora_dispatch](https://github.com/KoraFiveM/kora_dispatch) handles the call feed, map, history and response states. kora_ambulance decides what counts as an EMS call and how each call is worded. Calls go to the job **type** `Config.job.type` (`ems`), so every job of that type gets them.

## `/911e`: emergency call

`/911e [message]` can be used by any player. The server reads the caller's coordinates itself and raises:

| Field | Value |
|---|---|
| code | `911e` |
| title | `911 -- Medical Emergency` |
| message | The text after the command, or `Caller #<id> reported a medical emergency.` |
| priority | `1` |
| icon | `heart-pulse` |
| data | `requester` = caller's server id |

Each player can use it once per `Config.dispatch.alertCooldown` ms. The caller is told whether EMS got the call: `Your emergency has been reported to EMS.` or `No paramedics are currently on duty.`

## Automatic calls

When `Config.dispatch.autoCall` is on:

| Trigger | Code / title | Priority | Message |
|---|---|---|---|
| Player enters laststand (`onPlayerDied`) | `10-52` Person Down | `priorities.personDown` | `<name> is down and requires medical assistance.` |
| Player bleeds out (`onPlayerDead`) | `10-54` Possible Fatality | `priorities.possibleFatality` | `<name> has stopped breathing.` |
| Dead player presses the alert key | `10-52` Person Down -- Assistance Requested | `priorities.personDown` | `<name> is down and is asking for a medic at <street>.` |

`<name>` is the character's first and last name, or `Patient #<id>` if unknown. Each call has `data.source` set to the patient. Repeat person-down calls for one player are suppressed for `autoCallCooldown` ms, and a revive does **not** reset that cooldown. The fatality call and the alert key have no auto-call cooldown. The alert key has its own (`Config.death.alertEms.cooldown`).

With the shipped config, `personDown = 2` and `possibleFatality = 1`. In kora_dispatch's default labels that makes the fatality call Critical and the person-down call High. Swap the values to rank them the other way. See [Configuration](../configuration.md#configdispatch).

## Closing calls

When `Config.dispatch.closeOnResolve` is on, the server closes every active call in service `Config.job.type` that belongs to the patient. A call belongs to the patient if `data.source` is the patient, or, with `closeCallerAlerts` on, if it is a `911e` call with `data.requester` set to the patient. This happens when the patient is:

| Event | Close reason |
|---|---|
| Revived by any means (`onPlayerRevived`) | `patient treated` |
| Healed to full health by an admin heal (`onPlayerHealed`) | `patient healed` |
| Respawned at a hospital | `patient respawned` |
| Disconnected | `patient left` |

## House calls

A house call is a non-emergency visit request. The queue lives in server memory, and each request is also published as a dispatch call.

- **`/housecall [note]`** (anyone): adds a request at the player's current position. The note is cut to 120 characters. It is refused if the character (citizen ID) already has a pending request, if `housecallCooldown` has not passed for that character, or if the queue already holds `maxHousecalls` requests. The dispatch call has code `10-51`, title `House Call`, priority `3`, icon `home`, `onAccept = 'kora_ambulance:server:housecallAccepted'`, and `data` with `requester`, `requestId` and `note`.
- **`/housecalls`** (job `Config.job.name`): lists open requests as `#id -- note` in a notification.
- **`/accepthousecall <id>`** (on-duty EMS): claims a request.

There are two ways to accept a request: `/accepthousecall` and accepting the call in the kora_dispatch UI. kora_dispatch fires the `onAccept` server event. Both use one claim routine, so a request can only be handed out once. On a claim, the medic gets `kora_ambulance:client:housecallAccepted(request)` and a waypoint to the request's coordinates. The requester is told `A paramedic is on the way.`, and the dispatch call is closed (`accepted by a paramedic`).

Requests older than `housecallTtl` ms are removed whenever the queue is read or changed, and their dispatch calls are closed (`house call expired`).

## Legacy player alerts

When `Config.compat.enabled` is on, two kora_dispatch player alerts are registered (see [Compatibility](../compatibility.md)):

| Key | Code / title | Priority | Raised by |
|---|---|---|---|
| `kora_ambulance:emergency` | `10-52` Medical Emergency | 1 | `hospital:server:ambulanceAlert`, only from a downed player |
| `kora_ambulance:doctor` | `10-51` Doctor Requested | 3 | `hospital:server:SendDoctorAlert`, only within 15 m of a hospital's `coords` |
