---
title: Events and state bags
sidebar_position: 8
---

# Events and state bags

## Server hooks (listen with `AddEventHandler`)

kora_ambulance fires these as local server events with `TriggerEvent`. Other server resources can listen to them. **Do not trigger them yourself.** kora_ambulance's own listeners (dispatch call closing, stretcher release) react to them.

| Event | Payload | Fired when |
|---|---|---|
| `kora_ambulance:server:onPlayerDied` | `src, cause` | Player entered laststand. `cause` is a string of 64 characters or less (`'died'`, `'legacy'`). |
| `kora_ambulance:server:onPlayerDead` | `src` | Player bled out (laststand to dead). |
| `kora_ambulance:server:onPlayerRevived` | `src` | Any revive: CPR, AI doctor, check-in care on a laststand patient, `/aheal`, `fullRevive`, or a sweep that finds someone revived outside this resource. |
| `kora_ambulance:server:onPlayerRevivedBy` | `targetSrc, reviverSrc` | A medic's CPR succeeded. Fired after `onPlayerRevived`. |
| `kora_ambulance:server:onPlayerRespawned` | `src, hospitalName` | Successful respawn at a hospital. |
| `kora_ambulance:server:onPlayerHealed` | `src` | An alive player was confirmed at full health after a reported admin heal. |
| `kora_ambulance:server:onBillCharged` | `src, cost` | Any bill was charged (respawn or check-in care). |
| `kora_ambulance:server:onPatientTreated` | `patientSrc, medicSrc, bodyPart, tier, item` | A medic closed a wound. `item` is `'bandage'` or `'ifak'`. |
| `kora_ambulance:server:onPatientCheckedIn` | `src, hospitalName, bedIndex` | A bed was reserved. |
| `kora_ambulance:server:onBedCareCompleted` | `src, hospitalName, bedIndex, cost` | Check-in care finished and was billed. |
| `kora_ambulance:server:onBedReleased` | `src, hospitalName, bedIndex, reason` | A bed was released. See [reasons](./features/hospitals.md#check-in-care). |

```lua
-- server, any resource
AddEventHandler('kora_ambulance:server:onPlayerRevivedBy', function(targetSrc, reviverSrc)
    print(('%d was revived by medic %d'):format(targetSrc, reviverSrc))
end)

AddEventHandler('kora_ambulance:server:onBillCharged', function(src, cost)
    print(('%d was billed $%d'):format(src, cost))
end)
```

## Client events (server to client)

The server sends these with `TriggerClientEvent`. Other client resources can listen with `RegisterNetEvent` / `AddEventHandler` to react, for example in a HUD. Triggering them locally only changes how things look. The server state does not change.

| Event | Payload | Meaning |
|---|---|---|
| `kora_ambulance:client:enterLaststand` | `deathTimeMs` | Local player is downed. The argument is the remaining bleed-out time. |
| `kora_ambulance:client:markDead` | `respawnTimeMs` | Local player is dead. The argument is the remaining respawn wait. |
| `kora_ambulance:client:revived` | `healthPct` | Local player was revived. |
| `kora_ambulance:client:respawnedAtHospital` | `coords` (vector4) | Local player respawned at this landing point. |
| `kora_ambulance:client:respawnBlock` | `minOnDuty` or `false` | Whether `/respawn` is blocked by on-duty medics. |
| `kora_ambulance:client:syncStatus` | `bleedingTier` or `false`, `limpingTier` or `false` | Authoritative bleeding/limping state. |
| `kora_ambulance:client:checkInAccepted` | `care` table: `token`, `hospital`, `bedIndex`, `bed`, `duration`, `readyAt`, `expiresAt` | A bed was reserved. |
| `kora_ambulance:client:bedReleased` | `reason` | The bed reservation ended. |
| `kora_ambulance:client:housecallList` | list of requests | Response to `/housecalls`. |
| `kora_ambulance:client:housecallAccepted` | request: `id`, `citizenid`, `src`, `coords`, `note`, `createdAt`, `callId` | The medic claimed a house call. |
| `kora_ambulance:client:stretcherStateChanged` | snapshot: `networkId`, `vehicleNetworkId`, `mode`, `operator`, `patient` (plus `removed`, `reason` on removal) | Broadcast to all clients. |
| `kora_ambulance:client:stretcherPatientLoaded` | snapshot | The local player was loaded onto a stretcher. |
| `kora_ambulance:client:stretcherPatientReleased` | `reason` | The local player was taken off a stretcher. |
| `kora_ambulance:client:stretcherBegin` | `otherSrc, iAmDragger` | Emergency carry started. |
| `kora_ambulance:client:stretcherEnd` | none | Emergency carry ended. |
| `kora_ambulance:client:painkillerBenefit` | `amount` | Add health (painkillers, IFAK treatment). |
| `kora_ambulance:client:firstAidHeal` | none | Restore full health after a first aid kit. |
| `kora_ambulance:client:reviveRequested` | `targetSrc` | Start the CPR flow on this target. Still fully checked by the server. |
| `kora_ambulance:client:treatmentRequested` | `patientSrc` | Start the Treat Wound flow. Still fully checked by the server. |
| `kora_ambulance:client:setArmour` | `armour` | Lower armour (from `hospital:server:SetArmor`). Can only reduce it. |
| `hospital:client:SendBillEmail` | `cost` | A bill was charged. |

## Client to server (internal)

These are the transport between kora_ambulance's own client and server. They are listed so you can audit them. Do not call them from other resources. Every one of them checks job, duty, distance, tokens and state on the server. Use the target interactions or the exports instead.

| Name | Kind | Purpose |
|---|---|---|
| `kora_ambulance:server:reportDeath` | callback (rate limit `reportRetryAttempts` per 2 s) | Client reports the ped is fatally injured. |
| `kora_ambulance:server:hitObserved` | `Kora.events` | Injury measurement. |
| `kora_ambulance:server:healthRestored` | `Kora.events` (3 per 10 s) | Admin heal happened on this client. |
| `kora_ambulance:server:statusStale` | `Kora.events` (4 per 10 s) | Client cannot remove a status effect. |
| `kora_ambulance:server:alertEms` | net event | Dead-player alert key. `street` is display text only. |
| `kora_ambulance:server:beginRevive` / `completeRevive` | callback / `Kora.events` | CPR. |
| `kora_ambulance:server:assessPatient`, `beginTreatment`, `completeTreatment` | callbacks | Assessment and treatment. |
| `kora_ambulance:server:firstAidTarget` | net event | First aid kit on another player. |
| `kora_ambulance:server:checkInRequested`, `bedCareCompleted` / `bedLeft` | callbacks / `Kora.events` | Hospital check-in. |
| `kora_ambulance:server:spawnDutyVehicle` / `storeDutyVehicle` | callback / `Kora.events` | Garage. |
| `kora_ambulance:server:stretcherDeployRequested` | callback | Deploy a stretcher. |
| `kora_ambulance:server:stretcherPushRequested`, `stretcherReleased`, `patientLoadedOnStretcher`, `patientUnloadedFromStretcher`, `stretcherStowed`, `stretcherUnstowed`, `stretcherHeartbeatReceived` | `Kora.events` | Stretcher actions. |
| `kora_ambulance:server:stretcherPickup`, `stretcherRelease`, `stretcherHeartbeat` | `Kora.events` | Emergency carry. |
| `kora_ambulance:client:pharmacyProgress` | client callback (server to client) | Runs an item-use progress bar and returns whether it completed. |

`kora_ambulance:server:housecallAccepted` is registered as a net event, but it **refuses any call that comes from a client** (non-zero `source`). kora_dispatch fires it on the server as the house call's `onAccept` hook.

## Events consumed from other resources

| Event | Side | Use |
|---|---|---|
| `kora_core:server:playerLoaded` | server | Restore the saved medical state. |
| `kora_admin:client:heal` | client | Report an admin heal (`Config.injuries.clearOnHealEvent`) and start the injury grace window. |
| `kora_admin:client:revive` | client | Start the injury grace window. |
| `onResourceStart` (`kora_inventory`) | server | Register pharmacies and stashes again. |
| `onClientResourceStart` (`kora_target`, `kora_lib`, `kora_core`) | client | Register targets, cache watchers and needs watchers again. |

For legacy `hospital:*` events see [Compatibility](./compatibility.md).

## State bags

| Bag | Scope | Values | Notes |
|---|---|---|---|
| `emsDown` | Player state, replicated | `'laststand'`, `'dead'` or `false` | Set only by the server. Use it to tell whether **another** player is downed, for example in target `canInteract` checks. |
| `kora_ambulanceStretcher` | Entity state on the stretcher prop, replicated | snapshot: `networkId`, `vehicleNetworkId`, `mode`, `operator`, `patient` | Set only by the server. |

```lua
-- client: is the targeted player downed?
local state = Player(serverId).state.emsDown
local downed = state == 'laststand' or state == 'dead'
```
