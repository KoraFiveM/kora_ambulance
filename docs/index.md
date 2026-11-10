---
layout: default
title: kora_ambulance
---

EMS/ambulance job for FiveM. Hits are correlated with the victim's actual damaged
bone, then validated and classified by the server into a persistent per-body-part
wound ledger. On-duty medics can assess and treat wounds, perform CPR, emergency-
carry a patient, or deploy a physical stretcher from a configured duty ambulance.
Patients can check in for timed care in an atomically assigned hospital bed;
hospital respawns remain an independent escape path for fully dead players.
Dispatch includes `/911e`, automatic casualty calls and a house-call queue. A
guarded compatibility adapter supports common `hospital:*`
integrations while intentionally refusing legacy shortcuts that would let a
client directly heal, revive, choose a bed, or remove inventory.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/)
- [kora_core](https://qbcore2.github.io/kora_core/)
- [kora_inventory](https://qbcore2.github.io/kora_inventory/)
- [kora_target](https://qbcore2.github.io/kora_target/)
- [kora_dispatch](https://qbcore2.github.io/kora_dispatch/)

## Installation

`server.cfg`, in this order:
```
ensure kora_sql
ensure kora_lib
ensure kora_core
ensure kora_inventory
ensure kora_target
ensure kora_dispatch
ensure kora_ambulance
```
kora_ambulance registers configured pharmacy shops and EMS stashes against
kora_inventory at boot. Pharmacy, stash, duty and garage points are optional per
hospital; the `ambulance` job record is already seeded by kora_core's shared job
list.

## Usage examples

### Go on duty and check out an ambulance
```
/ems-duty
```
The prompt at each hospital's garage (`Config.hospitals[n].garage`) only shows
"Check out Ambulance" / "Return Vehicle" options while on duty:
```lua
-- client, e.g. from another resource checking whether to show an EMS-only UI
local job = exports.kora_core:getJob()
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
caller's live coords read server-side. Medics see it in the kora_dispatch feed and
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
`kora_ambulance:client:housecallAccepted`.

### React to a field revive from another resource
```lua
-- server, any resource
AddEventHandler('kora_ambulance:server:onPlayerRevived', function(src)
    print(('%d was stabilised by EMS'):format(src))
end)

AddEventHandler('kora_ambulance:server:onPlayerRevivedBy', function(targetSrc, reviverSrc)
    exports.kora_core:incrementMetaData(reviverSrc, 'stat_revives', 1)
end)
```

### Assess and treat a patient

While on duty, target another player and choose **Assess Patient** for a stable,
head-to-toe summary of their open wounds. Choose **Treat Wound** to run a
cancellable kora_lib action and close one wound using the medic's own supplies.
The most urgent treatable wound is selected: a bandage handles tier 1-2 wounds,
while severe and critical wounds require an IFAK. Job, proximity, item ownership,
action timing and current wound severity are all checked again on the server when
the action completes.

```lua
AddEventHandler('kora_ambulance:server:onPatientTreated', function(patientSrc, medicSrc, bodyPart, tier, item)
    print(('%d treated %d (%s, tier %d) with %s'):format(medicSrc, patientSrc, bodyPart, tier, item))
end)
```

### Check in for hospital care

An injured or laststand player can use **Check In for Care** at a configured
hospital desk. The server atomically reserves the lowest free bed, moves the
patient into the timed care presentation, and rechecks the token, elapsed time,
death state and bed proximity before completing care. Successful care restores
health, clears wounds and charges `Config.billing.checkInCost`; cancellation,
expiry and disconnect release the bed without charging.

```lua
AddEventHandler('kora_ambulance:server:onPatientCheckedIn', function(src, hospitalName, bedIndex)
    print(('%d entered %s bed %d'):format(src, hospitalName, bedIndex))
end)

AddEventHandler('kora_ambulance:server:onBedCareCompleted', function(src, hospitalName, bedIndex, charged)
    print(('%d completed care at %s for $%d'):format(src, hospitalName, charged))
end)

AddEventHandler('kora_ambulance:server:onBedReleased', function(src, hospitalName, bedIndex, reason)
    print(('%s bed %d released: %s'):format(hospitalName, bedIndex, reason))
end)
```

### Transport a patient

Check out the configured Ambulance, target it to deploy its stretcher, then use
the stretcher targets to push or release it. Target a downed player to load them;
target the linked ambulance to stow or unstow the occupied stretcher. The server
creates the prop, binds it to the tracked duty vehicle and owns every operator,
patient and lifecycle transition. **Emergency Carry** remains available when a
physical stretcher is impractical.

### React to a hospital bill being charged
```lua
-- server, any resource
AddEventHandler('kora_ambulance:server:onBillCharged', function(src, cost)
    print(('%d was billed $%d for treatment'):format(src, cost))
end)
```

### Give a fresh EMS hire their starting gear
```lua
-- server
exports.kora_core:setJob(source, 'ambulance', 1)
exports.kora_core:addItem(source, 'defibrillator', 1)
exports.kora_core:addItem(source, 'bandage', 5)
```

## API reference

Cross-resource hooks use ordinary `TriggerEvent`/`AddEventHandler` (server) or
`RegisterNetEvent` (client) — no exports needed to listen. `Kora.callback.trigger`/
`Kora.events.trigger` calls below are kora_lib's RPC/fire-and-forget primitives, used
internally between kora_ambulance's own client and server realms.

### Duty & vehicles
```
/ems-duty                                                    -- command: toggle EMS duty
Kora.callback.trigger('kora_ambulance:server:spawnDutyVehicle', hospitalName, vehicleIndex) -- -> networkId | false, err
Kora.events.trigger('kora_ambulance:server:storeDutyVehicle', snapshot)
```

### Revive
```
Kora.callback.trigger('kora_ambulance:server:beginRevive', targetSrc)      -- -> token | nil, err
Kora.events.trigger('kora_ambulance:server:completeRevive', targetSrc, token, proof)
kora_ambulance:server:onPlayerRevivedBy(targetSrc, reviverSrc)           -- hook
kora_ambulance:server:onPlayerRevived(src)                               -- hook
```

### Patient assessment & treatment
```
Kora.callback.trigger('kora_ambulance:server:assessPatient', targetSrc) -- -> report | nil, err
Kora.callback.trigger('kora_ambulance:server:beginTreatment', targetSrc) -- -> token | nil, err
Kora.callback.trigger('kora_ambulance:server:completeTreatment', targetSrc, token, completed) -- -> treated, err
kora_ambulance:server:onPatientTreated(patientSrc, medicSrc, bodyPart, tier, item) -- hook
```

### Hospital admission
```
Kora.callback.trigger('kora_ambulance:server:checkInRequested', hospitalName) -- -> care | false, reason
Kora.callback.trigger('kora_ambulance:server:bedCareCompleted', token)        -- -> true | false, reason
Kora.events.trigger('kora_ambulance:server:bedLeft', token)
kora_ambulance:server:onPatientCheckedIn(src, hospitalName, bedIndex)       -- hook
kora_ambulance:server:onBedCareCompleted(src, hospitalName, bedIndex, cost) -- hook
kora_ambulance:server:onBedReleased(src, hospitalName, bedIndex, reason)    -- hook
```

### Death state machine
```
/respawn                                          -- command: client, only while dead and only after Config.death.respawnTime
kora_ambulance:client:enterLaststand(deathTimeMs)    -- client event
kora_ambulance:client:markDead(respawnTimeMs)        -- client event
kora_ambulance:client:revived(healthPct)             -- client event
kora_ambulance:client:respawnedAtHospital(coords)    -- client event
kora_ambulance:client:respawnBlock(minOnDuty|false)  -- client event: /respawn disabled by on-duty medics (Config.death.respawn.blockWhenMedics)
kora_ambulance:server:alertEms(street?)              -- net event: dead player's alert key (Config.death.alertEms); the server re-checks dead state and cooldown
kora_ambulance:server:onPlayerDied(src, cause)       -- hook
kora_ambulance:server:onPlayerDead(src)              -- hook
kora_ambulance:server:onPlayerRespawned(src, hospitalName) -- hook
```

The server also exposes a detached, read-only medical snapshot:
```lua
local status = exports.kora_ambulance:getPatientStatus(source)
-- { version = 1, state = 'alive'|'laststand'|'dead', wounds = {...},
--   laststandAt = unixTimestamp|nil, deadAt = unixTimestamp|nil }
```

Wounds and down-state deadlines are stored in
`metadata.kora_ambulanceMedical`. A reconnect or resource restart restores the
ledger, continues the bleed-out/respawn clocks, and republishes the server-owned
`emsDown` state bag. Invalid or stale metadata fields are discarded.

**Two visible timers.** A downed player sees a `Kora.textui` clock counting the
bleed-out down (`Config.death.deathTime`), and once they die a second clock
counting down to their respawn (`Config.death.respawnTime`), replaced by a
`Type /respawn to wake up at a hospital` prompt as soon as that expires. Both
tick once a second on their own thread — the laststand loop that disables
controls has to run every frame, and a clock does not.

`Config.death.allowCameraMovement` controls whether mouse/controller look is
left available while those downed controls are locked. It defaults to `true`
and applies to both laststand and the fully dead state (one control loop serves
both); set it to `false` for the old locked-camera behaviour. Movement and
combat remain disabled in either mode, and chat, voice and pause controls are
never disabled by this resource.

`Config.death.screen` (`enabled = false` by default) swaps the plain countdown
for a death screen: a `Downed` / `Dead` prompt at the top of the screen with the
countdown, the key hints (`/911e` to call EMS, the alert-EMS key, `/respawn` once allowed —
`showHints`) and a screen dim, lighter while downed and darker when dead
(`dim`). It uses a kora_lib textui prompt and a drawn overlay, never NUI focus,
so camera look is unaffected. If the server only confirms a death late (health
replicates slowly after a vehicle crash) the client keeps retrying for
`Config.death.reportRetryWindow` ms (`0` = give up after the quick retries).

**What a revive clears.** `Config.revive.clearBleeding` (default `true`) stops
the bleeding on revive: the Bleeding status ends and `Death.isBleeding(src)`
turns false, so any bleed-damage tick gated on it stops, while the wounds stay
on the ledger. `Config.revive.clearWounds` (default `false`, the previous
behaviour) also closes every wound, ending limping. A new or worse wound after
the revive bleeds again. Hospital check-in care, respawn at a hospital and
`exports.kora_ambulance:fullRevive(src)` always clear everything. After every
wound or revive change the server pushes `kora_ambulance:client:syncStatus`, and
the client reconciles its bleeding/limping effects against it, so the HUD pill
cannot go stale. A player flipped back to alive by another resource (admin
`/revive`) is reconciled by the periodic sweep; admin tools should call
`fullRevive` directly.

**The respawn wait is enforced server-side**, in `Death.respawnAtHospital`,
against the timestamp the server took when it marked the player dead:
```lua
-- server, any resource
local remaining = Death.respawnWaitRemaining(src) -- seconds, 0 once respawn is allowed
local ok, reason = Death.respawnAtHospital(src, 'pillbox')
-- ok = false, reason = 'You cannot respawn for another 42s.'
```
The client-side check on `/respawn` only saves a round-trip; a player who fires
`hospital:server:RespawnAtHospital` by hand is refused with the same reason,
notified back to them rather than failing silently. Refusal happens before any
side effect, so a rejected attempt is never billed.

**Death screen options** (all under `Config.death`, read at use time):

| Option | Default | Effect |
|---|---|---|
| `respawnTime` | `60000` | ms a dead player waits before `/respawn` works; `0` = immediately. Shown as a countdown, then `Type /respawn to wake up at a hospital`. |
| `alertEms.enabled` | `true` | While dead, a key sends the player's location to on-duty EMS through `kora_dispatch` (`createCall`, EMS job type). The prompt shows `[G] Alert EMS`. `false` removes the key and hint. |
| `alertEms.key` | `'G'` | Default key; registered with `Kora.keybind.add`, so players can rebind it in FiveM key settings. |
| `alertEms.cooldown` | `60000` | ms between alerts per player, enforced on the server. The reply notify says whether EMS was reached or nobody is on duty. |
| `respawn.clearInventory` | `false` | `true` wipes the inventory on a successful `/respawn` (`exports.kora_inventory:clearInventory`, server-side). |
| `respawn.keepItems` | `{}` | Item names that survive the wipe, e.g. `{ 'phone', 'id_card' }`. kora_inventory also always keeps its own physical-cash item when that mode is active. |
| `respawn.blockWhenMedics.enabled` | `false` | `true` refuses `/respawn` while enough medics are on duty. |
| `respawn.blockWhenMedics.minOnDuty` | `3` | Respawn is disabled while this many (or more) on-duty medics exist. |
| `respawn.blockWhenMedics.jobs` | `{ 'ambulance' }` | Job names counted as medics (on-duty only; the dead player is never counted). |

The alert key only works while dead (`/911e` still covers laststand). The
server ignores it for a living player, applies the cooldown and reads the
coordinates itself; the client only supplies a street label, which is trimmed
and used as display text. The call lands in the dispatch feed with
`data.source` set to the patient, so a revive closes it like the automatic calls.

The medic block is evaluated server-side on every `/respawn` attempt (in
`Death.respawnAtHospital`, so firing `hospital:server:RespawnAtHospital` by hand
is refused too). While it is enabled the server also tells each dead client via
`kora_ambulance:client:respawnBlock` (on death and whenever the state changes, checked
by the 5 s sweep), and the prompt reads `Respawn is disabled while N medics are on
duty`. It returns to the `/respawn` instruction by itself when the count drops
below `minOnDuty`. `Death.medicsOnDuty(src)` and `Death.respawnBlocked(src)` expose the count.

A dead player who reconnects keeps the original persisted respawn deadline. A
legacy dead record with no medical timestamp remains immediately respawnable so
older data cannot strand a player during migration.

### Dispatch / house-calls
```
/911e [message]              -- command: priority-1 EMS call
/housecall [note]            -- command: queue a non-emergency request
/housecalls                  -- command: EMS, lists the open queue
/accepthousecall <id>        -- command: EMS, accepts a queued request
kora_ambulance:client:housecallList(list)         -- client event
kora_ambulance:client:housecallAccepted(request)  -- client event
```

Presentation belongs to **kora_dispatch**: the feed, the map, history and the
response state machine. This resource decides only what counts as an EMS matter
and how each call is worded.

**Automatic calls** (`Config.dispatch.autoCall`) cover laststand, death, and the
help key:

| Event | Call | Priority |
| --- | --- | --- |
| Enters laststand | `10-52 Person Down` | 1 |
| Bleeds out | `10-54 Possible Fatality` | 2 |
| Revived (any means, admin `/revive` and `/selfrevive` included), healed by an admin `/heal`, respawned or disconnected | the patient's open calls are **closed** (`Config.dispatch.closeOnResolve`) | — |

The priorities are kora_dispatch priority numbers (its default labels: 1 =
Critical, 2 = High, 3 = Routine). By default the fatality is below the person-down
call: nobody is being saved now, so it does not outrank a patient who still can be.
Servers that prefer the opposite ranking set `Config.dispatch.priorities`:

| Option | Default | Effect |
|---|---|---|
| `priorities.personDown` | `1` | Priority of the `10-52 Person Down` calls: entering laststand, and the dead-player help key alert (`Config.death.alertEms`). |
| `priorities.possibleFatality` | `2` | Priority of the `10-54 Possible Fatality` call. Swap the two values (`2` / `1`) to make the fatality Critical and the person-down call High. |

The `/911e` house-call alert is separate and stays priority 1. Repeat calls for the same
casualty are suppressed for `Config.dispatch.autoCallCooldown`, so one messy
firefight is one call rather than ten — and the cooldown is *not* reset by a
revive, because a patient put straight back down is the same incident to the
paramedic already standing over them.

A `/911e` alert the patient raised themself (the downed screen points them at it)
counts as their call and closes the same way; set `Config.dispatch.closeCallerAlerts`
to `false` to leave `/911e` alerts for EMS to close by hand.

**The house-call queue** is published as a priority-3 dispatch call carrying an
`onAccept` hook. Accepting it in the dispatch UI and `/accepthousecall` go through
one implementation, so a request can never be handed out twice because two doors
disagreed about whether it was still open. kora_dispatch knows nothing about house
calls — it just fires the event name it was handed.

### Billing
```
kora_ambulance:server:onBillCharged(src, cost) -- hook, fires from Death.respawnAtHospital
```
Cost is `Config.billing.baseCost` plus `Config.billing.perWoundCost[tier]` for
every still-open wound at respawn time.

### Patient transport
```
Kora.callback.trigger('kora_ambulance:server:stretcherDeployRequested', vehicleNetId)
Kora.events.trigger('kora_ambulance:server:stretcherPushRequested', stretcherNetId)
Kora.events.trigger('kora_ambulance:server:stretcherReleased', stretcherNetId)
Kora.events.trigger('kora_ambulance:server:patientLoadedOnStretcher', stretcherNetId, targetSrc)
Kora.events.trigger('kora_ambulance:server:patientUnloadedFromStretcher', stretcherNetId)
Kora.events.trigger('kora_ambulance:server:stretcherStowed', stretcherNetId, vehicleNetId)
Kora.events.trigger('kora_ambulance:server:stretcherUnstowed', vehicleNetId)

-- emergency-carry fallback
Kora.events.trigger('kora_ambulance:server:stretcherPickup', targetSrc)
Kora.events.trigger('kora_ambulance:server:stretcherRelease')
```
All models, attachment offsets, duty-vehicle associations and relationship
changes are resolved from server/config state. Network events are internal
transport surfaces; integrations should prefer the target interactions.

### Legacy `hospital:*` compatibility

`Config.compat.enabled` registers the common `hospital:client:*`,
`hospital:server:*` and callback names. Compatibility is semantic and guarded,
not a promise to reproduce insecure client authority:

- revive and treatment requests enter the modern server-validated CPR/action
  flows;
- `SendToBed` ignores the supplied bed index and asks the hospital service to
  allocate a free bed;
- another player's status is visible only to nearby on-duty EMS;
- legacy injury ingestion and direct item-removal events are disabled by
  default through `Config.compat`;
- locally callable admin-heal/kill shortcuts are inert;
- `RespawnAtHospital` takes a hospital name or a 1-based `Config.hospitals`
  index (out of range falls back to the first); it still requires being dead
  and past the respawn timer;
- `aheal [id]` (admin permission, audit-logged via `Kora.logging`) reuses the
  server revive path; `status` (EMS job) shows the caller's own status;
- the resource also `provide`s `qb-ambulancejob`; `GetDoctorCount` (server)
  and an inert `PainKillerLoop` (client) exports are available, and the
  `ifaks` item is an alias of `ifak`;
- respawn, alerts, duty aliases, usable items and reduce-only armour/weapon
  modifiers retain guarded mappings.

`hospital:GetDoctors`, `hospital:GetPlayerStatus` and
`hospital:GetPlayerBleeding` remain available. Two legacy client exports remain:
```lua
exports.kora_ambulance:isEscorted()  -- true while carried or loaded on a stretcher
exports.kora_ambulance:CanHelp()     -- UX availability only; never authorization
```

## Config highlights (`config.lua`)

`Config.job` selects the EMS job/type; `Config.death` controls the FSM and CPR;
`Config.injuries` controls hit correlation, report validation and damage-to-tier
thresholds; `Config.hospitalCare` controls admissions (`leaveKey`, default `'E'`, is the
rebindable key mapping that leaves the bed early; it is only enabled while a bed is
reserved, `''` leaves it unbound); `Config.transport`
controls the stretcher model/attachments/heartbeat; `Config.compat` controls the
legacy adapter; `Config.billing` covers respawn and check-in costs;
`Config.dispatch` controls emergency/house-call behavior; and `Config.treatment`
controls medic-to-patient actions. `Config.hospitals` supports multiple facilities
with beds plus optional check-in/pharmacy/stash/duty/garage points.
`Config.dutyVehicles[n].stretcher` opts a vehicle into physical transport.
`Config.bodyParts` maps GTA bones to 15 anatomical regions, and
`Config.woundLevels` defines four treatment/mobility tiers.
`Config.painkillers` sets the cooldown, the pill animation (`animDict`/`animClip`),
`animDuration` (ms; the animation and the "Using Painkillers" bar end together),
`healthAmount` (HP restored on completion, capped at the ped's max health, applied
client-side because SetEntityHealth is a client-only native; 0 = none) and
`stopBleeding`; the item is only consumed when the bar completes. Downed players
get no health boost. `Config.defibrillator.useable` registers the
defibrillator inventory item so using it starts CPR on the nearest downed patient
(on-duty EMS only).

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library
- [kora_sql](https://qbcore2.github.io/kora_sql/) — database driver
- [kora_core](https://qbcore2.github.io/kora_core/) — framework core
- [kora_inventory](https://qbcore2.github.io/kora_inventory/) — headless inventory
- [kora_target](https://qbcore2.github.io/kora_target/) — targeting/interaction
- [kora_police](https://qbcore2.github.io/kora_police/) — police/LEO job
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
