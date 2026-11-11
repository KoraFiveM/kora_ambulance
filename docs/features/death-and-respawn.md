---
title: Death and respawn
sidebar_position: 1
---

# Death and respawn

The server owns each player's medical state. Its code is in `server/death.lua`. The state is stored in the kora_core metadata flags `inlaststand` and `isdead`.

| State | Meaning |
|---|---|
| `alive` | Normal play. |
| `laststand` | Downed and bleeding out. Can be revived, or checked in at a hospital desk. |
| `dead` | Bled out. Can be revived by CPR, or respawn at a hospital after the timer. |

Allowed transitions:

| From | Event | To |
|---|---|---|
| alive | died | laststand |
| laststand | bledOut or died | dead |
| laststand | revived | alive |
| dead | revived or respawned | alive |

## Going down

1. kora_lib's `Kora.cache` detects that the local ped became fatally injured.
2. The client calls the `kora_ambulance:server:reportDeath` callback. The server only accepts it if its own copy of the ped's health is 0. The client retries `Config.death.reportRetryAttempts` times every `reportRetryInterval` ms. After that it keeps retrying every 2.5 s for up to `reportRetryWindow` ms while still fatally injured.
3. When the server accepts, the player enters **laststand**. The server sets the metadata, records the start time, publishes the `emsDown` state bag as `'laststand'`, sends `kora_ambulance:client:enterLaststand` and fires the server event `kora_ambulance:server:onPlayerDied`.
4. The client resurrects the ped in place so GTA's native "wasted" screen and frozen death camera never appear. It then plays a writhe animation and shows a `Bleeding out in mm:ss` countdown.

While downed or dead, the client:

- disables movement, sprint, jump, combat, weapon wheel, cover, reload and vehicle controls every frame. Chat, voice and pause are not touched.
- keeps camera look enabled when `Config.death.allowCameraMovement` is `true`.
- holds ped health at `Config.death.downedHealth` (`holdDownedHealth`) and plays the downed animation again after ragdolls.
- with `Config.death.screen.enabled`, shows a `Downed` / `Dead` prompt at the top centre, dims the screen and adds hints.

The server sweep runs every 5 seconds. When `Config.death.deathTime` has passed, the player becomes **dead**. The server publishes `emsDown = 'dead'`, sends `kora_ambulance:client:markDead` with the remaining respawn wait and fires `kora_ambulance:server:onPlayerDead`. The client starts a `DeathFailOut` screen effect and shows `You can respawn in mm:ss`. When the wait is over, the prompt reads `Type /respawn to wake up at a hospital`.

## Alerting EMS while dead

When `Config.death.alertEms.enabled` is on, a dead player can press the `kora_ambulance_alert_ems` key mapping (default `G`, rebindable). The prompt shows `[G] Alert EMS`. The client sends only a street name. The server:

- ignores the alert unless the player is actually dead,
- applies `alertEms.cooldown` and tells the player how long to wait,
- reads the coordinates itself and trims the street label to 60 characters,
- raises a `10-52 Person Down -- Assistance Requested` call at the `personDown` priority,
- tells the player whether EMS was reached or `No paramedics are currently on duty.`

While in laststand, players use `/911e` instead (see [Dispatch](./dispatch.md)).

## Respawning

`/respawn` is a client command. It does nothing unless the player is dead. The client checks the timer and the medic block first to save a round trip, then fires `hospital:server:RespawnAtHospital`. The server runs `Death.respawnAtHospital`, which refuses with a message in these cases:

- `You are not dead.`
- `You cannot respawn for another Ns.` The wait is measured from the server's own death timestamp.
- `Respawn is disabled while N or more medics are on duty.` This only applies when `Config.death.respawn.blockWhenMedics.enabled` is on.

A refusal has no side effects. On success the server:

1. bills the patient: `baseCost` plus `perWoundCost[tier]` for each open wound (see [Hospitals and billing](./hospitals.md#billing)),
2. sets the state to alive, clears all wounds and calls kora_core's `reset` for the player,
3. if `respawn.clearInventory` is on, wipes the inventory except `respawn.keepItems`,
4. sends `kora_ambulance:client:respawnedAtHospital` with a random bed of the hospital (`respawn.useBeds`) or the hospital's `coords`,
5. fires `kora_ambulance:server:onPlayerRespawned(src, hospitalName)`.

Because `/respawn` sends no hospital name, the player always lands at the **first** entry of `Config.hospitals`. The legacy `hospital:server:RespawnAtHospital` event also accepts a hospital name or a 1-based index.

The client fades out and resurrects at the landing point. With `snapToBedProps` it moves the ped onto a nearby `v_med_bed2` / `v_med_emptybed` prop. It then restores full health and fades back in.

### Blocking respawn while medics are on duty

With `blockWhenMedics.enabled`, the server counts on-duty players whose job is in `blockWhenMedics.jobs`, never counting the dead player. While the count is `minOnDuty` or more, `/respawn` is refused. Dead clients get `kora_ambulance:client:respawnBlock` when they die and whenever the 5-second sweep sees the value change. The prompt then reads `Respawn is disabled while N medics are on duty`, and goes back to the respawn instruction once the count drops.

## Revives

A revive sends `kora_ambulance:client:revived(healthPct)`. The client restores health to that percentage of the survivable range (100 to max health), clears tasks and the death screen effect, and fires `kora_ambulance:server:onPlayerRevived`. What happens to the wounds depends on `Config.revive` (see [Medical care](./medical-care.md#cpr-and-defibrillator)).

Sometimes another resource flips a player back to alive without going through kora_ambulance, for example an admin `/revive`. The 5-second sweep detects this and runs a full revive. That clears the wounds, closes the patient's EMS calls and fires `onPlayerRevived`. Admin tools should call the [`fullRevive`](../exports.md#fullrevive) export directly.

## Persistence and reconnects

Wounds, the bleed-stopped flag and the laststand/death timestamps are saved in the `kora_ambulanceMedical` metadata key (see [Persistence](../database.md)). On `kora_core:server:playerLoaded`, and for every online player when the resource starts, the server:

- cleans up the saved data, dropping invalid wounds or timestamps,
- marks the player dead immediately if the laststand timer ran out while they were offline (the death time is backdated),
- republishes `emsDown` and sends the client the remaining laststand or respawn time.

A dead record with no saved timestamp, such as legacy data, can respawn immediately.
