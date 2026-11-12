---
title: "How to use"
sidebar_position: 3
---


# How to use

The resource is organised around one server-authoritative state machine (Death) that every other module reads from: injuries and bleeding (Wounds/Death), hospital check-in and duty vehicles (Hospital/Duty), patient carry/transport (Stretcher), billing (Billing), EMS dispatch (dispatch.lua/HouseCall), and the self-heal fallback AI (Doctors).

## Getting hurt: injuries, bleeding and the downed state

- Client-observed hits (`client/damage.lua`) are correlated within `Config.injuries.captureWindow` and reported to the server (`kora_ambulance:server:hitObserved`), which rolls a body part (`Wounds.pickBodyPart`, weighted by `Config.bodyParts[*].weight`) and severity tier (1-4, biased by `Config.weaponClassMap[weaponClass].severityBias`, thresholds `Config.injuries.severityThresholds`).
- A tier-4 wound to a `vital` body part shortens the blackout timer (`Config.blackoutTimer`, default 20s) before the screen fades to black and the player enters laststand. Each open wound bleeds `Config.bleed.damagePerSeverity[tier]` HP every `Config.bleed.tickRate` ms until treated, closed by a revive, or the player checks in at a hospital.
- Needs damage (starvation/dehydration applied by kora_core when hunger or thirst hits 0) is ignored as an injury source by default (`Config.injuries.ignoreNeedsDamage`), so it never opens a bleeding wound.
- A downed (laststand) player can press the configured key (`Config.death.alertEms.key`, default G) to send an EMS alert with their location; a fully dead player waits `Config.death.respawnTime` before `/respawn` is accepted, which places them on a random hospital bed (`Config.death.respawn.useBeds`) and bills them (see Billing).
- `Config.doctors.selfHealEnabled` (default false) lets an AI "doctor" auto-revive a laststand player (no bill) after `Config.doctors.selfHealDelay` if fewer than `Config.doctors.minimalDoctors` real EMS are on duty, each player gated by `Config.doctors.docCooldown`.

## Getting treated

- Field treatment: an on-duty medic within `Config.treatment.range` can assess (`kora_ambulance:server:assessPatient`), begin (`beginTreatment`) and complete (`completeTreatment`) a timed treatment (`Config.treatment.duration`) on one wound at a time. An IFAK-required wound (a `Config.woundLevels` entry with `ifakRequired = true`, tiers 3 and 4 by default) cannot be closed with a plain bandage.
- CPR/defibrillator revive: `kora_ambulance:server:beginRevive`/`completeRevive` run a cooldown-gated (`Config.death.reviveInterval`), proximity-checked (`Config.death.reviveRange`) revive that restores the patient to `Config.death.minimumRevive`% health; `Config.revive.clearBleeding`/`clearWounds` control how much of the injury ledger a field revive clears versus leaves for a hospital check-in.
- Hospital check-in: `Hospital.requestCheckIn` reserves the lowest free bed at a nearby hospital for an injured (or laststand), non-dead patient; `Config.hospitalCare.requireInjury` blocks a healthy player from occupying a bed. Care takes `Config.hospitalCare.duration` and must complete within `Config.hospitalCare.actionTtl` or the bed is released. A successful non-death check-in charges `Config.billing.checkInCost`.
- Painkillers (`Config.painkillers`) give a timed, cooldown-gated health bump (and optionally stop bleeding); first aid (`Config.firstaid`) fully heals and clears wounds/bleeding, usable on yourself or, if `targetEnabled`, on another player by an on-duty medic via a target option.

## Carrying and transporting patients

An on-duty medic can fireman’s-carry a downed patient (`Config.carry`) and load them onto a stretcher (`Stretcher` module) that attaches to a duty vehicle for transport to a hospital bed. Stretcher ownership is tracked with a heartbeat (`Config.transport.heartbeatInterval`/`heartbeatTtl`) so an abandoned session is cleaned up automatically.

## Duty and the vehicle garage

`/ems-duty` (or the kora_lib keybind-free command) toggles on/off duty at a hospital duty point. On duty, a medic can check out a configured duty vehicle (`Config.dutyVehicles`) from a hospital garage; the vehicle is created ephemerally (not inserted into the persistent owned-vehicle table) and deleted on return, disconnect, or resource stop so checkouts never leak a permanent garage row.

## Dispatch: /911e and house calls

- `/911e [message]` fires an immediate, one-shot alert (`kora_dispatch` priority `Config.dispatch.priorities.personDown`/`possibleFatality` depending on context) to every on-duty EMS of `Config.job.type`, cooldown-gated by `Config.dispatch.alertCooldown`. The caller’s own ped position is read server-side, so no client round-trip is required.
- `/housecall [note]` queues a non-emergency visit (cooldown `Config.dispatch.housecallCooldown`, capped at `Config.dispatch.maxHousecalls` live requests, expiring after `Config.dispatch.housecallTtl`). The queue is also published to kora_dispatch as a priority-3 call so it shows on the EMS map; a paramedic accepting the dispatch call fires `kora_ambulance:server:housecallAccepted` to claim it from the in-memory queue (the authority on what is still unclaimed).
- `/housecalls` lists open queue entries to players whose job is `Config.job.name` (the on-duty flag is not checked).
- `Config.dispatch.autoCall` (default true) automatically raises a dispatch call when a player enters laststand or dies, so a bleeding-out player is found even if they never type a command. `Config.dispatch.closeOnResolve` closes that call (and its blip) once the patient is revived by any means, admin-healed, respawned, or disconnects.

## Billing

`Death.respawnAtHospital` charges `Billing.calculateCost(woundData)` — a flat `Config.billing.baseCost` plus `Config.billing.perWoundCost[tier]` for every still-open wound at respawn time. `Billing.charge` drains `Config.billing.account` (e.g. cash) first, capped at what is available, then the `Config.billing.fallbackAccount` (e.g. bank) for the remainder — a bill is never allowed to block care, and the fallback account may go negative.

```lua title="server/billing.lua"
function Billing.calculateCost(woundData)
    local cost = Config.billing.baseCost
    for _, tier in pairs(woundData or {}) do
        cost = cost + (Config.billing.perWoundCost[tier] or Config.billing.perWoundCost[#Config.billing.perWoundCost])
    end
    return cost
end
```
