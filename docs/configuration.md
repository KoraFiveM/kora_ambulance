---
title: Configuration
sidebar_position: 6
---

# Configuration

All options are in `config.lua` in one global `Config` table. The file is loaded as a shared script, so client and server see the same values. At the end of the file `Config.validate()` checks the structure. If an assertion fails, the resource stops loading and prints a message such as `hospital names must be unique` or `dispatch priorities needs whole-number personDown and possibleFatality (>= 1)`. If kora_lib provides `Kora.config.adopt`, the table is also registered with it.

Times are in **milliseconds** and distances in **metres** unless noted otherwise.

## General

| Key | Type | Default | Description |
|---|---|---|---|
| `Config.Debug` | boolean | `false` | Prints hospital setup diagnostics to the console, such as hospitals with no beds, refused bedless check-ins and target registration. |

## `Config.job`

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | string | `'ambulance'` | Job name treated as EMS. Must match a kora_core job. |
| `onDutyDoctorGrade` | integer | `1` | Minimum grade level a medic needs to count as a doctor for the self-heal AI check (`Config.doctors.minimalDoctors`). |
| `type` | string | `'ems'` | kora_core job **type** that dispatch calls go to. Every job with this type gets EMS calls, not only `name`. Also used as the `service` when looking up calls to close. |

## `Config.death`

| Key | Type | Default | Description |
|---|---|---|---|
| `deathTime` | number | `300000` | How long a player stays in laststand before bleeding out to dead. |
| `respawnTime` | number | `60000` | How long a dead player must wait before `/respawn` is accepted. `0` means immediately. The server enforces this wait. |
| `allowCameraMovement` | boolean | `true` | `true` keeps mouse/controller look enabled while downed or dead. `false` locks the camera. Movement and combat controls are always disabled while down. |
| `cameraMode` | string | `'free'` | Must be `'free'` or `'fixed'` (validated). **Not read by the current client code.** Only `allowCameraMovement` controls the camera. |
| `holdDownedHealth` | boolean | `true` | Every 500 ms the client keeps a downed ped at `downedHealth`. If a fall or tick takes it to the fatal line, the ped is resurrected in place so the death camera never freezes. |
| `downedHealth` | number | `101` | Health a downed ped is held at. Must be above 100. |
| `respawnHoldTime` | number | `1500` | Validated (must be at least 0) but **not used by the current code**. `/respawn` is a plain command. |
| `reportRetryInterval` | number | `100` | Time between the quick retries of the client's death report. |
| `reportRetryAttempts` | number | `5` | Number of quick retries. Also the rate limit of the `reportDeath` callback (per 2 s). |
| `reportRetryWindow` | number | `15000` | After the quick retries, the client keeps retrying every 2.5 s while still fatally injured, for this long. This covers health that replicates late after a vehicle crash. `0` stops after the quick retries. |
| `minimumRevive` | number | `20` | Percent of the survivable health range (100 to max health) a CPR or AI revive restores. |
| `reviveInterval` | number | `5000` | Cooldown between CPR attempts on the same patient. |
| `reviveRange` | number | `3.0` | How close the reviver must be to the patient. Also the range for emergency carry. |
| `reviveActionTtl` | number | `20000` | How long a server-issued CPR action stays valid. |

### `Config.death.screen`

Optional death screen. Takes no NUI focus.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `false` | `true` shows a `Downed` / `Dead` prompt at the top centre of the screen instead of the plain countdown prompt. |
| `dim` | boolean | `true` | Dims the screen while downed (lighter) and dead (darker). Only used when `enabled`. |
| `showHints` | boolean | `true` | Adds key hints to the prompt: `/911e to call EMS` while downed, and the alert key and `/respawn once the timer ends` while dead. Only used when `enabled`. |

### `Config.death.alertEms`

Lets a dead player press a key to send their location to EMS.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | `false` removes the key mapping and its hint. The server also refuses alerts while this is off. |
| `key` | string | `'G'` | Default key of the `kora_ambulance_alert_ems` key mapping. Players can rebind it in the FiveM key settings. |
| `cooldown` | number | `60000` | Minimum time between alerts per player. Enforced on the server. |

### `Config.death.respawn`

| Key | Type | Default | Description |
|---|---|---|---|
| `clearInventory` | boolean | `false` | `true` wipes the player's inventory on a successful `/respawn` using `exports.kora_inventory:clearInventory`. |
| `keepItems` | string list | `{}` | Item names kept when the inventory is wiped, for example `{ 'phone', 'id_card' }`. kora_inventory also always keeps its physical cash item when that mode is active. |
| `useBeds` | boolean | `true` | `true` places the respawned player on a random configured bed of the hospital. `false` uses the hospital's `coords`. |
| `snapToBedProps` | boolean | `true` | After landing, the client looks for a `v_med_bed2` / `v_med_emptybed` prop nearby and moves the ped onto a random one. |
| `bedSearchRadius` | number | `40.0` | Search radius for bed props. |
| `bedZOffset` | number | `0.9` | Height above the bed prop where the ped is placed. |

### `Config.death.respawn.blockWhenMedics`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `false` | `true` refuses `/respawn` while enough medics are on duty. |
| `minOnDuty` | integer | `3` | Respawn is blocked while at least this many medics are on duty. Must be 1 or more. |
| `jobs` | string list | `{ 'ambulance' }` | Job names that count as medics. Only on-duty players count, and the dead player never counts. |

## `Config.revive`

Controls what a field revive does to injuries. Field revives are CPR, the self-heal AI and the `hospital:server:RevivePlayer` path. Full revives always clear everything, whatever these flags say. Full revives are the `fullRevive` export, `/aheal`, hospital check-in care and respawn.

| Key | Type | Default | Description |
|---|---|---|---|
| `clearBleeding` | boolean | `true` | A revive stops the bleeding. The `bleeding` status ends, but the wounds stay on the ledger. |
| `clearWounds` | boolean | `false` | A revive also closes every wound, which ends limping too. |

## `Config.doctors`

| Key | Type | Default | Description |
|---|---|---|---|
| `minimalDoctors` | integer | `1` | The self-heal AI can act while fewer than this many on-duty EMS (grade at least `Config.job.onDutyDoctorGrade`) are online. |
| `docCooldown` | number | `600000` | Minimum time between two AI revives of the same player. |
| `selfHealEnabled` | boolean | `false` | Turns the self-heal AI on. `nil` is treated as off. |
| `selfHealDelay` | number | `90000` | How long a player must be in laststand before the AI revives them. |

## `Config.billing`

| Key | Type | Default | Description |
|---|---|---|---|
| `baseCost` | integer | `500` | Flat fee charged on every respawn at a hospital. |
| `checkInCost` | integer | `250` | Fee charged when check-in bed care completes successfully. |
| `perWoundCost` | integer list | `{ 150, 350, 650, 1200 }` | Extra respawn fee for each open wound, indexed by tier 1-4. A tier with no entry uses the last value. |
| `account` | string | `'cash'` | Account charged first. The charge is capped at the account's balance. |
| `fallbackAccount` | string | `'bank'` | Account charged for whatever `account` could not cover. |

## `Config.hospitalCare`

| Key | Type | Default | Description |
|---|---|---|---|
| `interactionRange` | number | `3.0` | How close the patient must be to the check-in point. Also the default radius of the check-in target zone. |
| `bedRange` | number | `2.5` | How close the patient must stay to the assigned bed for care to complete. |
| `duration` | number | `15000` | How long check-in care takes. |
| `actionTtl` | number | `45000` | How long a reservation can stay unfinished before the bed is released. The effective value is at least `duration + 1000`. |
| `requireInjury` | boolean | `true` | Only injured players can check in: laststand, an open wound, or health below max minus `Config.injuries.healthTolerance`. |
| `allowBedless` | boolean | `true` | `true` allows hospitals with no beds. They still get their other zones, and check-in shows a notice. `false` makes validation fail. |
| `leaveKey` | string | `'E'` | Default key of the `kora_ambulance_leave_bed` mapping. It is only enabled while a bed is reserved. `''` registers no mapping. |

## `Config.hospitalMenu`

| Key | Type | Default | Description |
|---|---|---|---|
| `isolateErrors` | boolean | `true` | `true` logs and skips a hospital whose targets fail to register, so the other hospitals still load. `false` lets the error propagate. |
| `radius.checkIn` | number or nil | `nil` | Radius of the check-in zone. `nil` uses `Config.hospitalCare.interactionRange`. |
| `radius.pharmacy` | number | `3.0` | Radius of the pharmacy zone. |
| `radius.stash` | number | `3.0` | Radius of the EMS stash zone. |
| `radius.duty` | number | `2.0` | Radius of the duty zone. The server always accepts a duty toggle within at least 3 m. |
| `radius.garage` | number | `6.0` | Radius of the garage zone. |

A hospital can override these radii with its own `radius` table (see `Config.hospitals` below).

## `Config.injuries`

| Key | Type | Default | Description |
|---|---|---|---|
| `captureWindow` | number | `500` | Maximum time between a native damage event and the matching health drop for the two to be correlated. |
| `reportCooldown` | number | `300` | Minimum time between two accepted injury reports from one player. |
| `healthTolerance` | number | `5` | Allowed difference between the client-reported and server-side health. Also the health below max that still counts as healthy for check-in. |
| `minDamage` | number | `3` | Smallest health loss that is reported as an injury. |
| `maxDamage` | number | `100` | Largest single health loss that is accepted. |
| `severityThresholds` | number list | `{ 8, 20, 40 }` | Ascending damage cutoffs. Damage below the first is tier 1, and each threshold reached adds one tier. |
| `clearWhenHealthy` | boolean | `true` | The 5-second server sweep closes every wound of an alive player whose health is back at max. |
| `clearOnHealEvent` | boolean | `true` | When `kora_admin:client:heal` fires, the client reports it and the server closes wounds right away if health really is at max. |
| `healthyMargin` | number | `0` | Health below max that still counts as fully healthy for the two options above. |
| `healGraceMs` | number | `2500` | After a heal or revive, new injury reports are ignored for this long on both client and server. `0` disables this. |
| `ignoreNeedsDamage` | boolean | `true` | Health lost to starvation or dehydration from kora_core needs never opens a wound. |
| `needsDamageWindowMs` | number | `1500` | How long after an empty hunger/thirst update health loss is treated as needs damage. |

## `Config.transport`

| Key | Type | Default | Description |
|---|---|---|---|
| `model` | string or hash | `'v_med_emptybed'` | Stretcher prop model. |
| `interactionRange` | number | `3.0` | Range for stretcher, deploy/stow and load interactions. |
| `heartbeatInterval` | number | `2000` | Interval of the stretcher push heartbeat and of the server transport sweep. |
| `heartbeatTtl` | number | `6500` | Time without a heartbeat before a pusher or carrier is released. Must be greater than `heartbeatInterval`. |
| `patientOffset` | vector3 | `vector3(0.0, 0.0, 0.55)` | Patient attachment offset on the stretcher. |
| `patientRotation` | vector3 | `vector3(0.0, 0.0, 180.0)` | Patient attachment rotation. |
| `pushOffset` | vector3 | `vector3(0.0, -1.15, 0.15)` | Stretcher offset from the pushing medic (bone 28422). |
| `pushRotation` | vector3 | `vector3(0.0, 0.0, 0.0)` | Stretcher rotation while being pushed. |

## `Config.compat`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Registers the legacy `hospital:*` events, callbacks, exports and the `/aheal` and `/status` commands. See [Compatibility](./compatibility.md). |
| `acceptClientInjurySync` | boolean | `false` | Allows `hospital:server:SyncInjuries` to record wounds. |
| `allowDestructiveItemEvents` | boolean | `false` | Allows `hospital:server:removeBandage` / `removeIfaks` / `removePainkillers` to remove items. |
| `reviveNotice` | boolean | `false` | Shows a notice when `hospital:client:Revive` / `RevivePlayer` fire (for example from an admin revive). |

## `Config.carry`

Emergency carry animations and attachment.

| Key | Type | Default | Description |
|---|---|---|---|
| `dragger` | table | `{ dict = 'missfinale_c2mcs_1', clip = 'fin_c2_mcs_1_camman', flag = 49 }` | Animation of the carrying medic. |
| `patient` | table | `{ dict = 'nm', clip = 'firemans_carry', flag = 33 }` | Animation of the carried patient. |
| `patientOffset` | table | `{ x = 0.27, y = 0.15, z = 0.63 }` | Patient offset relative to the carrier. |
| `patientRotation` | table | `{ x = 0.5, y = 0.5, z = 180.0 }` | Patient rotation relative to the carrier. |
| `stopPrompt` | boolean | `true` | Shows a `Stop Carrying` prompt to the carrier. The key in `stopControl` releases the patient. |
| `stopControl` | integer | `38` | Control index for `stopPrompt`. `38` is `INPUT_PICKUP`, E by default. The prompt label always shows `E`. |

## `Config.firstaid`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Makes the kora_core `firstaid` item usable. Using it clears all wounds and restores full health. |
| `duration` | number | `5000` | Length of the progress bar. |
| `targetEnabled` | boolean | `true` | Gives on-duty EMS a `Use First Aid Kit` target option on other players. |
| `targetRange` | number | `3.0` | Range for that target option, enforced on the server. |

## `Config.painkillers`

| Key | Type | Default | Description |
|---|---|---|---|
| `interval` | number | `300000` | Cooldown between painkiller uses per player. Kept in memory. |
| `animDict` | string | `'mp_suicide'` | Animation dictionary. |
| `animClip` | string | `'pill'` | Animation clip. |
| `animDuration` | number | `3400` | Length of the animation and of the `Using Painkillers` progress bar. |
| `healthAmount` | number | `15` | Health restored when a use completes, capped at max health. Only applied while alive. `0` disables it. |
| `stopBleeding` | boolean | `false` | `true` also stops the bleeding (the wounds stay). |

## `Config.defibrillator`

| Key | Type | Default | Description |
|---|---|---|---|
| `useable` | boolean | `true` | Registers the `defibrillator` item as usable. Using it starts CPR on the nearest downed patient within `Config.death.reviveRange` (on-duty EMS only). |

## `Config.treatment`

| Key | Type | Default | Description |
|---|---|---|---|
| `duration` | number | `5000` | How long treating one wound takes. |
| `range` | number | `3.0` | How close the medic must stay to the patient. Also the range of the Assess, Treat and First Aid target options. |
| `actionTtl` | number | `15000` | How long a treatment action stays valid. The effective value is at least `duration + 1000`. |
| `ifakHealthAmount` | number | `50` | Health an IFAK treatment restores to an alive patient, capped at max. `0` disables it. |

## `Config.dispatch`

| Key | Type | Default | Description |
|---|---|---|---|
| `alertCooldown` | number | `30000` | Cooldown per player for `/911e`. |
| `housecallCooldown` | number | `60000` | Cooldown per character (citizen ID) for submitting a house call. |
| `housecallTtl` | number | `900000` | How long an unclaimed house call stays in the queue. |
| `maxHousecalls` | integer | `50` | Maximum number of queued house calls on the server. |
| `accent` | string | `'#EF4444'` | Colour passed to `exports.kora_dispatch:setTheme` on the client. |
| `autoCall` | boolean | `true` | Raises calls automatically when a player enters laststand or dies. |
| `autoCallCooldown` | number | `45000` | Per-player cooldown for the automatic person-down call. Also the cooldown of the legacy player alerts. |
| `closeOnResolve` | boolean | `true` | Closes a patient's open EMS calls when they are revived, healed, respawn or disconnect. |
| `closeCallerAlerts` | boolean | `true` | With `closeOnResolve`, also closes `/911e` calls the patient raised themselves. |
| `priorities.personDown` | integer | `2` | kora_dispatch priority of `10-52` calls (laststand and the dead-player alert key). |
| `priorities.possibleFatality` | integer | `1` | kora_dispatch priority of the `10-54 Possible Fatality` call. |

The shipped `priorities` values are `personDown = 2` and `possibleFatality = 1`. The comment above them in `config.lua` says the defaults rank the downed patient higher, but with these values the fatality call ranks higher. That comment matches the code fallback (`1` / `2`), which is only used when a value is missing or invalid. Set the values to the ranking you want. In kora_dispatch's default labels, 1 is Critical, 2 is High and 3 is Routine.

## `Config.hospitals`

A list of hospitals. You need at least one, and names must be unique. All coordinates are absolute world coordinates.

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Unique id. Used in pharmacy/stash ids, events and `RespawnAtHospital`. |
| `label` | string | yes | Display name. Used for the pharmacy/stash labels and the blip info title. |
| `coords` | vector4 | yes | Main point. Respawn landing point when `useBeds` is off or there are no beds. Also the blip position. |
| `checkIn` | vector4 | no | Check-in desk. Falls back to `coords`. |
| `beds` | vector4 list | yes, unless `allowBedless` | Treatment beds. Must be unique across all hospitals. Check-in reserves the lowest free bed, and respawn picks a random one. |
| `pharmacy` | vector4 | no | Pharmacy shop point. |
| `stash` | table | no | `{ coords = vector4, slots = n, maxWeight = n }`. EMS-only stash. |
| `duty` | vector4 | no | Duty toggle point. |
| `garage` | vector4 | no | Vehicle checkout point. Vehicles spawn here, using the w value as heading. |
| `blip` | table | no | Passed to `Kora.blips.create`, for example `{ sprite = 61, color = 1, scale = 0.8, category = 'Hospital', name = '...' }`. If it has no `info`, a default info card is set. |
| `radius` | table | no | Overrides `Config.hospitalMenu.radius` for this hospital, for example `{ checkIn = 5.5, duty = 5.5 }`. |

The shipped config has `pillbox` (Pillbox Hill, 3 beds) and `sandy` (Sandy Shores, 2 beds).

```lua
Config.hospitals = {
    {
        name = 'pillbox',
        label = 'Pillbox Hill Medical Center',
        coords = vector4(298.7, -584.7, 43.3, 90.0),
        checkIn = vector4(307.1, -595.1, 43.3, 70.0),
        beds = {
            vector4(295.5, -595.6, 43.3, 90.0),
            vector4(295.5, -597.9, 43.3, 90.0),
        },
        pharmacy = vector4(316.4, -594.7, 43.3, 340.0),
        stash = { coords = vector4(308.6, -598.8, 43.3, 160.0), slots = 50, maxWeight = 4000000 },
        duty = vector4(308.0, -595.0, 43.2, 340.0),
        garage = vector4(294.5, -583.5, 43.2, 250.0),
        blip = { sprite = 61, color = 1, scale = 0.8, category = 'Hospital', name = 'Pillbox Hill Medical' },
    },
}
```

`/respawn` does not send a hospital name, so respawns always go to the **first** hospital in this list.

## `Config.dutyVehicles`

A list of vehicles that can be checked out at any garage. You need at least one.

| Field | Type | Description |
|---|---|---|
| `label` | string | Shown as `Check out <label>` in the garage target. |
| `model` | string or hash | Vehicle model. |
| `stretcher` | table | Optional. `{ offset = vector3, rotation = vector3 }`. Equips the vehicle with a deployable stretcher and sets where it attaches when stowed. |

Shipped vehicles: `Ambulance` (`ambulance`, with a stretcher), `Ambulance (Lifeguard)` (`lguard`) and `Response Bike` (`faggio2`).

## `Config.dutyGarage`

| Key | Type | Default | Description |
|---|---|---|---|
| `interactionRange` | number | `8.0` | How close to a garage point a medic must be to check out or return a vehicle. |
| `actionCooldown` | number | `3000` | Minimum time between checkout/return requests from one player. |

## `Config.bodyParts`

15 body parts. Each has a `name` (unique), a `label`, a `weight`, a `vital` flag and a list of GTA `bones` (unique IDs from 0 to 65535).

| name | label | weight | vital | bones |
|---|---|---|---|---|
| `head` | Head | 3 | yes | 31086 |
| `neck` | Neck | 2 | yes | 39317 |
| `chest` | Chest | 10 | yes | 24816, 24817 |
| `abdomen` | Abdomen | 8 | yes | 11816 |
| `spine` | Spine | 3 | yes | 23553 |
| `left_shoulder` | Left Shoulder | 5 | no | 64729 |
| `right_shoulder` | Right Shoulder | 5 | no | 10706 |
| `left_arm` | Left Arm | 8 | no | 61163 |
| `right_arm` | Right Arm | 8 | no | 28252 |
| `left_hand` | Left Hand | 4 | no | 18905 |
| `right_hand` | Right Hand | 4 | no | 57005 |
| `left_leg` | Left Leg | 10 | no | 58271 |
| `right_leg` | Right Leg | 10 | no | 63931 |
| `left_foot` | Left Foot | 4 | no | 14201 |
| `right_foot` | Right Foot | 4 | no | 52301 |

`weight` sets how likely a random part is when the hit bone is not mapped. A `vital` part raises the wound severity by one tier. The assessment report lists wounds in the order of this table.

## `Config.woundLevels`

| tier | label | movementMultiplier | canWalk | ifakRequired |
|---|---|---|---|---|
| 1 | Minor | 1.00 | yes | no |
| 2 | Moderate | 0.85 | yes | no |
| 3 | Severe | 0.65 | yes | yes |
| 4 | Critical | 0.40 | no | yes |

The number of entries sets the highest tier. `label` is shown in assessments. `canWalk = false` applies the `limping` status. `ifakRequired` means a bandage cannot treat that tier. `movementMultiplier` is currently **not applied** by any runtime code.

## Values not used at runtime

These values are defined and used only by helper functions in `shared/wounds.lua`. No gameplay code calls those helpers today:

| Key | Default | Notes |
|---|---|---|
| `Config.bleed.tickRate` | `15000` | No bleed damage tick runs. Bleeding is a status effect only. |
| `Config.bleed.damagePerSeverity` | `{ 1, 2, 4, 7 }` | Used only by `Wounds.bleedTickDamage`, which nothing calls. |
| `Config.blackoutTimer` | `20000` | Not referenced. |
| `Config.fadeOutTimer` | `8000` | Not referenced. |
| `Config.weaponClassMap` | per-class `injuryChance`, `bleedChance`, `severityBias` | Used only by `Wounds.rollInjury` / `rollBleed` / `rollSeverity`. Severity actually comes from damage (`Config.injuries.severityThresholds`). |
