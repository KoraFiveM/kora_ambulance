---
layout: default
title: qbambulance
---

EMS/ambulance job for FiveM. A per-body-part wound ledger drives bleeding/limping
severity, a defibrillator + CPR minigame powers field revives, dispatch runs
through both a one-shot `/911e` alert and a browsable house-call queue, hospital
respawns charge a wound-scaled bill, and on-duty medics get duty vehicles from a
per-hospital garage plus a stretcher system to drag downed players. A doctor
self-heal AI steps in when too few EMS are on duty. Ships full drop-in
compatibility with legacy `qb-ambulancejob`/`hospital:*` events — existing
resources that call `hospital:client:Revive`, `hospital:server:TreatWounds`, etc.
keep working unmodified.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/)
- [qbcore](https://qbcore2.github.io/qbcore/)
- [qbinventory](https://qbcore2.github.io/qbinventory/)
- [qbtarget](https://qbcore2.github.io/qbtarget/)

## Installation

`server.cfg`, in this order:
```
ensure qbsql
ensure qblib
ensure qbcore
ensure qbinventory
ensure qbtarget
ensure qbambulance
```
qbambulance registers its own pharmacy shops and EMS stashes (one pair per
`Config.hospitals` entry) against qbinventory at boot — no manual setup needed
beyond the job record `ambulance` already seeded by qbcore's shared job list.

## Usage examples

### Go on duty and check out an ambulance
```
/ems-duty
```
The prompt at each hospital's garage (`Config.hospitals[n].garage`) only shows
"Check out Ambulance" / "Return Vehicle" options while on duty:
```lua
-- client, e.g. from another resource checking whether to show an EMS-only UI
local job = exports.qbcore:getJob()
if job and job.name == 'ambulance' and job.onduty then
    -- show EMS-only UI
end
```

### Report a medical emergency and respond to it
```
/911e stabbed outside the Yellow Jack
```
This raises a priority-1 dispatch call to the whole **EMS service** — every job
registered with `type = 'ems'`, not just this resource's own job name — with the
caller's live coords read server-side. Medics see it in the qbdispatch feed and
on the map, and respond with the dispatch keybinds.

The caller is told whether anybody actually heard them: `createCall` returns a
recipient count, and "no paramedics are currently on duty" is very different news
to "your emergency has been reported".

### Queue and accept a non-emergency house-call
```
-- player
/housecall need a pickup, broken leg

-- on-duty EMS
/housecalls
/accepthousecall 3
```
`/housecalls` lists the open queue; `/accepthousecall <id>` removes that entry
and sets a waypoint on the accepting medic's client via
`qbambulance:client:housecallAccepted`.

### React to a field revive from another resource
```lua
-- server, any resource
AddEventHandler('qbambulance:server:onPlayerRevived', function(src)
    print(('%d was stabilised by EMS'):format(src))
end)

AddEventHandler('qbambulance:server:onPlayerRevivedBy', function(targetSrc, reviverSrc)
    exports.qbcore:incrementMetaData(reviverSrc, 'stat_revives', 1)
end)
```

### React to a hospital bill being charged
```lua
-- server, any resource
AddEventHandler('qbambulance:server:onBillCharged', function(src, cost)
    print(('%d was billed $%d for treatment'):format(src, cost))
end)
```

### Give a fresh EMS hire their starting gear
```lua
-- server
exports.qbcore:setJob(source, 'ambulance', 1)
exports.qbcore:addItem(source, 'defibrillator', 1)
exports.qbcore:addItem(source, 'bandage', 5)
```

## API reference

Cross-resource hooks use ordinary `TriggerEvent`/`AddEventHandler` (server) or
`RegisterNetEvent` (client) — no exports needed to listen. `QB.callback.trigger`/
`QB.events.trigger` calls below are qblib's RPC/fire-and-forget primitives, used
internally between qbambulance's own client and server realms.

### Duty & vehicles
```
/ems-duty                                                    -- command: toggle EMS duty
QB.callback.trigger('qbambulance:server:spawnDutyVehicle', hospitalName, vehicleIndex) -- -> networkId | false, err
QB.events.trigger('qbambulance:server:storeDutyVehicle', snapshot)
```

### Revive
```
QB.callback.trigger('qbambulance:server:beginRevive', targetSrc)      -- -> token | nil, err
QB.events.trigger('qbambulance:server:completeRevive', targetSrc, token, proof)
qbambulance:server:onPlayerRevivedBy(targetSrc, reviverSrc)           -- hook
qbambulance:server:onPlayerRevived(src)                               -- hook
```

### Death state machine
```
/respawn                                        -- command: client, only while dead
qbambulance:client:enterLaststand(deathTimeMs)   -- client event
qbambulance:client:markDead()                    -- client event
qbambulance:client:revived(healthPct)            -- client event
qbambulance:client:respawnedAtHospital(coords)   -- client event
qbambulance:server:onPlayerDied(src, cause)      -- hook
qbambulance:server:onPlayerDead(src)             -- hook
qbambulance:server:onPlayerRespawned(src, hospitalName) -- hook
```

### Dispatch / house-calls
```
/911e [message]              -- command: priority-1 EMS call
/housecall [note]            -- command: queue a non-emergency request
/housecalls                  -- command: EMS, lists the open queue
/accepthousecall <id>        -- command: EMS, accepts a queued request
qbambulance:client:housecallList(list)         -- client event
qbambulance:client:housecallAccepted(request)  -- client event
```

Presentation belongs to **qbdispatch**: the feed, the map, history and the
response state machine. This resource decides only what counts as an EMS matter
and how each call is worded.

**Automatic calls** (`Config.dispatch.autoCall`) restore behaviour the rewrite had
dropped — real qb-ambulancejob alerted on laststand, on death and on the help
key, and none of that survived. Now:

| Event | Call | Priority |
| --- | --- | --- |
| Enters laststand | `10-52 Person Down` | 1 |
| Bleeds out | `10-54 Possible Fatality` | 2 |
| Revived | the patient's open call is **closed** | — |

The fatality is deliberately below the person-down call: nobody is being saved
now, so it must not outrank a patient who still can be. Repeat calls for the same
casualty are suppressed for `Config.dispatch.autoCallCooldown`, so one messy
firefight is one call rather than ten — and the cooldown is *not* reset by a
revive, because a patient put straight back down is the same incident to the
paramedic already standing over them.

**The house-call queue** is published as a priority-3 dispatch call carrying an
`onAccept` hook. Accepting it in the dispatch UI and `/accepthousecall` go through
one implementation, so a request can never be handed out twice because two doors
disagreed about whether it was still open. qbdispatch knows nothing about house
calls — it just fires the event name it was handed.

### Billing
```
qbambulance:server:onBillCharged(src, cost) -- hook, fires from Death.respawnAtHospital
```
Cost is `Config.billing.baseCost` plus `Config.billing.perWoundCost[tier]` for
every still-open wound at respawn time.

### Stretcher
```
QB.events.trigger('qbambulance:server:stretcherPickup', targetSrc)
QB.events.trigger('qbambulance:server:stretcherRelease')
QB.events.trigger('qbambulance:server:stretcherOffset', offset)
qbambulance:client:stretcherBegin(otherSrc, iAmDragger)  -- client event
qbambulance:client:stretcherEnd()                        -- client event
```
qbtarget options "Pick Up Patient" / "Release Patient" are registered globally
on the `player` target type, gated to on-duty EMS against a downed target.

### Legacy `qb-ambulancejob` / `hospital:*` compat
Full `hospital:client:*` / `hospital:server:*` event surface (Revive,
RevivePlayer, TreatWounds, SendToBed, RespawnAtHospital, SetDoctorCount,
UseFirstAid/UseIfaks/UsePainkillers, ambulanceAlert, ...) plus callbacks
`hospital:GetDoctors`, `hospital:GetPlayerStatus`, `hospital:GetPlayerBleeding`.
Two legacy client exports:
```lua
exports.qbambulance:isEscorted()  -- true while this client is being dragged on a stretcher
exports.qbambulance:CanHelp()     -- always true; no client-side item check is wired up
```

## Config highlights (`config.lua`)

`Config.job.name` (`'ambulance'`) and `Config.job.onDutyDoctorGrade` (minimum
grade counted toward the self-heal gate); `Config.death.deathTime/minimumRevive/
reviveRange/reviveInterval`; `Config.doctors.minimalDoctors/selfHealDelay/
docCooldown` (AI self-heal when too few medics are on duty); `Config.billing.
baseCost/perWoundCost/account/fallbackAccount`; `Config.dispatch.autoCall/autoCallCooldown/accent/alertCooldown/
housecallCooldown`; `Config.hospitals` (multiple check-in points, each with its
own beds/pharmacy/stash/duty/garage coords); `Config.dutyVehicles`;
`Config.bodyParts` (15 parts with hit-weight and `vital` flag) and
`Config.woundLevels` (4-tier bleed severity, tier ≥ `ifakRequired` can't be
closed with a plain bandage); `Config.weaponClassMap` (per weapon-class injury/
bleed chance and severity bias).

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library
- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/qbtarget/) — targeting/interaction
- [qbpolice](https://qbcore2.github.io/qbpolice/) — police/LEO job
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
