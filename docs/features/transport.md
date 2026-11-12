---
title: Patient transport
sidebar_position: 6
---

# Patient transport

There are two ways to move a downed patient. Both are run by the server (`server/stretcher.lua`). The client only picks the target entity. Models, offsets and relationships always come from server config and state.

## Physical stretcher

Only **duty vehicles that are currently checked out** and whose `Config.dutyVehicles` entry has a `stretcher` table can carry a stretcher. In the shipped config that is the `ambulance` model. The vehicle can be any medic's checkout. Only one stretcher can be deployed per vehicle.

A stretcher is always in one of three modes:

| Mode | Meaning | Allowed actions |
|---|---|---|
| `world` | Standing frozen on the ground | push, stow |
| `pushed` | Attached to the medic pushing it | release, stow |
| `vehicle` | Attached to the vehicle at `stretcher.offset` / `rotation` | unstow |

### Target options

| Target | Option | Shown when | Server event |
|---|---|---|---|
| Stretcher-equipped vehicle | **Deploy Stretcher** | On-duty, no stretcher of this vehicle nearby | `stretcherDeployRequested` (callback, 3 per 10 s) |
| Stretcher-equipped vehicle | **Stow Stretcher** | Its stretcher is nearby, not stowed, and not pushed by someone else | `stretcherStowed` |
| Stretcher-equipped vehicle | **Unstow Stretcher** | Its stretcher is stowed | `stretcherUnstowed` |
| Stretcher prop (`Config.transport.model`) | **Push Stretcher** | On-duty, mode `world`, not already moving something | `stretcherPushRequested` |
| Stretcher prop | **Stop Pushing** | You are the one pushing it | `stretcherReleased` |
| Stretcher prop | **Unload Patient** | On-duty, not stowed, occupied | `patientUnloadedFromStretcher` |
| Downed player | **Load onto Stretcher** | On-duty, an empty stretcher that is not stowed is within range of the patient | `patientLoadedOnStretcher` |

All of these use `Config.transport.interactionRange`, and the server checks distance and routing bucket again. Deploying creates the `Config.transport.model` prop at the vehicle's stretcher offset. A patient stays loaded when the stretcher is stowed, so you can drive them away inside the vehicle. You must unstow the stretcher before unloading.

The pushing medic's client sends a heartbeat every `heartbeatInterval` ms. The server sweep (also every `heartbeatInterval`) releases the pusher back to `world` mode if the heartbeat is older than `heartbeatTtl`, the medic went off duty, or the medic is more than twice the interaction range away. The sweep unloads the patient if they are alive again, gone, in another routing bucket, or more than three times the interaction range from a stretcher that is not stowed. If the vehicle or the prop disappears, the stretcher is removed.

The stretcher's state is replicated in the entity state bag `kora_ambulanceStretcher` and in the `kora_ambulance:client:stretcherStateChanged` event (see [Events](../events.md)).

## Emergency carry

**Emergency Carry** is a target option on a downed player for on-duty EMS who are not already moving someone. The server requires the patient within `Config.death.reviveRange`, in the same routing bucket, downed, and not already being carried or on a stretcher. The carrier and patient play the `Config.carry` animations, and the patient is attached to the carrier at `Config.carry.patientOffset` / `patientRotation`.

To put the patient down, use the **Release Carried Patient** target. If `Config.carry.stopPrompt` is on, the `Stop Carrying` prompt key (`stopControl`, default E) also works. That key is ignored while the kora_target menu is open. The carrier's client sends a heartbeat every 2 s. The carry ends if the heartbeat is older than `heartbeatTtl`, the carrier goes off duty, the two are more than twice `reviveRange` apart, or the patient is alive again.

## Automatic release

A patient is released from a carry or stretcher when they are revived (`onPlayerRevived`), respawn, or disconnect. If the medic disconnects, any carry ends and the stretcher they were pushing goes back to `world` mode. When kora_ambulance stops, every stretcher is deleted.
