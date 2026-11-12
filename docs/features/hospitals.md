---
title: Hospitals, check-in and billing
sidebar_position: 4
---

# Hospitals, check-in and billing

Each entry in `Config.hospitals` creates its own kora_target sphere zones. A field that is missing or malformed only removes that one zone. With `Config.hospitalMenu.isolateErrors`, a hospital whose zones fail to register is logged and skipped, and the other hospitals still load. The zones are registered again when kora_target restarts.

| Zone | Option | Who can use it | Effect |
|---|---|---|---|
| `checkIn` (or `coords`) | **Check In for Care** | Anyone | Requests a bed (see below). |
| `pharmacy` | **Browse Pharmacy** | Anyone | Opens the kora_inventory shop `ambulance_pharmacy_<name>`. |
| `stash.coords` | **EMS Stash** | `Config.job.name` (on or off duty) | Opens the kora_inventory stash `ambulance_stash_<name>`. |
| `duty` | **Toggle Duty** | `Config.job.name` | Runs `/ems-duty`. |
| `garage` | **Check out ...** / **Return Vehicle** | On-duty EMS | See [Duty and vehicles](./duty-and-vehicles.md). |

Zone radii come from the hospital's own `radius` table, then from `Config.hospitalMenu.radius`, then from the built-in defaults.

If a hospital has a `blip`, a map blip is created at `coords` with an info card (`Medical services and EMS facilities are available here.`) unless the blip config has its own `info`.

## Pharmacy and stash

When the server starts, and again whenever kora_inventory restarts, kora_ambulance registers these for each hospital:

- **Pharmacy shop** `ambulance_pharmacy_<name>`, labelled `<label> Pharmacy`, with 4 slots and a 3.0 m access distance:

  | Item | Stock | Price |
  |---|---|---|
  | `bandage` | 200 | 15 |
  | `ifak` | 100 | 60 |
  | `painkillers` | 150 | 25 |
  | `defibrillator` | 20 | 350 |

  Stock and prices are hard-coded in `server/duty.lua`. They are not config options.
- **EMS stash** `ambulance_stash_<name>`, labelled `<label> EMS Stash`, with the configured `slots` and `maxWeight`. Access is limited to `Config.job.name`, any grade, at `stash.coords`.

## Check-in care

Check-in lets an injured player who is **not dead** get treated without a medic.

1. **Check In for Care** calls `kora_ambulance:server:checkInRequested(hospitalName)`. The server refuses with a reason when:
   - the hospital is unknown or has no beds (`this hospital has no beds available`),
   - the player already has a bed (`you already have a bed reserved`),
   - the player is dead (`dead patients must use hospital respawn`),
   - the player is not within `Config.hospitalCare.interactionRange` of the check-in point,
   - `requireInjury` is on and the player is not injured. Injured means laststand, an open wound, or health below max minus `healthTolerance`,
   - every bed is taken (`no beds are currently available`).
2. The server reserves the **lowest free bed index** for this player. Clients can never choose a bed. The server sends `kora_ambulance:client:checkInAccepted` and fires `kora_ambulance:server:onPatientCheckedIn(src, hospitalName, bedIndex)`.
3. The client moves the ped onto the bed and plays a resting scenario. It also turns on the `kora_ambulance_leave_bed` key mapping (default `E`).
4. After `Config.hospitalCare.duration` ms the client calls `kora_ambulance:server:bedCareCompleted(token)`. The server checks the token, that the duration has passed and `actionTtl` has not, that the bed is still reserved, that the player is not dead and is within `bedRange` of the bed. If all checks pass, it revives a laststand patient with a full revive, clears all wounds and charges `Config.billing.checkInCost`. It then releases the bed with reason `completed` and fires `kora_ambulance:server:onBedCareCompleted(src, hospitalName, bedIndex, cost)`. The client restores full health.

A bed is released (`kora_ambulance:client:bedReleased` and `kora_ambulance:server:onBedReleased(src, hospitalName, bedIndex, reason)`) for these reasons:

| Reason | Cause |
|---|---|
| `completed` | Care finished and was billed. |
| `left-bed` | The leave key was pressed, `hospital:server:LeaveBed` was triggered, or the player was too far from the bed at completion. |
| `expired` | `actionTtl` passed (checked every second). |
| `released` | The bed reservation no longer matched. |
| `dead` | The player died during care. |
| `disconnect` | The player left. |
| `resource-stop` | kora_ambulance stopped. |

Only `completed` is billed.

## Billing

All charges go through the same routine. The cost is taken from `Config.billing.account` (default `cash`), capped at that account's balance. The rest is taken from `fallbackAccount` (default `bank`). Care is never refused for lack of money. After a charge the server sends `hospital:client:SendBillEmail(cost)` to the player (the compatibility client shows `You were billed $N.`) and fires `kora_ambulance:server:onBillCharged(src, cost)`.

| Charge | Amount | Money reason |
|---|---|---|
| Respawn at hospital | `baseCost` plus the sum of `perWoundCost[tier]` over every open wound | `EMS hospital bill` |
| Completed check-in care | `checkInCost` | `EMS check-in care` |

Example with the defaults: a respawn with a tier 4 chest wound and a tier 1 hand wound costs 500 + 1200 + 150 = 1850.

CPR revives, treatment, the AI doctor and first aid are **not** billed.
