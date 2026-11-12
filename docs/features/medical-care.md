---
title: Medical care and revives
sidebar_position: 3
---

# Medical care and revives

Medics do their work through kora_target options on other players. Every action is checked again on the server. The server checks the job (`Config.job.name`), duty status, distance, items and the patient's state.

## Target options on players

| Option | Who sees it | Range | Effect |
|---|---|---|---|
| **Perform CPR** | Anyone, on a player whose `emsDown` state bag is `laststand` or `dead` | 2.0 m | Starts CPR. The server requires on-duty EMS and a defibrillator. |
| **Assess Patient** | On-duty EMS | `Config.treatment.range` | Shows the patient's state and open wounds in head-to-toe order. |
| **Treat Wound** | On-duty EMS | `Config.treatment.range` | Treats one wound with the medic's own bandage or IFAK. |
| **Use First Aid Kit** | On-duty EMS, when `Config.firstaid.enabled` and `targetEnabled` are on | `Config.treatment.range` (server: `firstaid.targetRange`) | Uses one of the medic's `firstaid` kits on the patient. |
| **Emergency Carry** / **Load onto Stretcher** | On-duty EMS | `Config.transport.interactionRange` | See [Patient transport](./transport.md). |

## Assessment

The `kora_ambulance:server:assessPatient` callback (rate limit 10 per 10 s) requires an on-duty medic within `treatment.range` of a different player. It returns `state` plus a list of wounds. Each wound has `bodyPart`, `bodyPartLabel`, `tier` and `severityLabel`, in `Config.bodyParts` order. The client shows the result as a notification, for example `Chest: Severe | Left Leg: Minor`.

## Treatment

**Treat Wound** runs a cancellable `Kora.actions` action for `Config.treatment.duration` ms. Movement, combat and vehicle controls are disabled during it.

1. `beginTreatment` (rate limit 5 per 10 s) reserves the patient so only one medic can treat them at a time, and picks the supply:
   - if the worst open wound is tier 3 or higher and the medic has an `ifak`, the IFAK is used on the worst wound,
   - otherwise, if the medic has a `bandage`, it treats the worst wound of tier 2 or lower,
   - otherwise, if the medic has an `ifak`, it is used on the worst wound,
   - otherwise the server refuses with `patient has no open wounds` or `no suitable medical supplies`.
2. `completeTreatment` checks that the action was not finished early (more than 250 ms before the end) or late (after `actionTtl`). It then checks access again, makes sure the wound still exists and can still be treated with the chosen item, and that the medic still has the item. It removes **one** of the medic's items and closes the wound.
3. The patient is notified. An IFAK also restores `Config.treatment.ifakHealthAmount` health if the patient is alive. The server fires `kora_ambulance:server:onPatientTreated(patientSrc, medicSrc, bodyPart, tier, item)`.

A bandage can only close tiers that do not have `ifakRequired` set (tiers 1-2 by default). An IFAK can close any tier.

## CPR and defibrillator

CPR can be started from the **Perform CPR** target, by using the `defibrillator` item (when `Config.defibrillator.useable` is on, the nearest downed patient within `reviveRange` is chosen), or through the legacy `hospital:server:RevivePlayer` event.

1. `beginRevive` requires: a different target player, on-duty EMS, a `defibrillator` in the medic's inventory, the target within `Config.death.reviveRange`, and the target downed (`laststand` or `dead`). It also requires that `reviveInterval` ms have passed since the last attempt on this target, and that no other medic is working on them. The server then authorises a kora_lib **mash** minigame: 15 presses in 8 seconds, one attempt.
2. The medic plays the CPR animation and the minigame.
3. `completeRevive` uses up the minigame proof. If it fails, the attempt is recorded (which starts the cooldown) and the medic sees `CPR attempt failed.` If it succeeds, the server checks everything again, removes **one defibrillator** and revives the patient to `Config.death.minimumRevive` percent. It then fires `kora_ambulance:server:onPlayerRevivedBy(targetSrc, reviverSrc)` and `onPlayerRevived(targetSrc)`.

The CPR action expires after `Config.death.reviveActionTtl` ms.

What a field revive does to the wounds depends on `Config.revive`:

| `clearWounds` | `clearBleeding` | Result |
|---|---|---|
| `true` | any | Every wound closes. |
| `false` | `true` (default) | The bleeding stops, but the wounds (and limping) stay on the ledger. |
| `false` | `false` | Nothing changes. The wounds keep bleeding. |

## First aid kit

- **Self use** (`firstaid` item): requires being alive. A progress bar runs for `Config.firstaid.duration` ms. When it completes, one kit is used up, every wound is closed and the client restores full health.
- **On another player** (`Use First Aid Kit` target): requires on-duty EMS, both players alive, the patient within `firstaid.targetRange` and a kit in the medic's inventory. The medic's progress bar runs, then everything is checked again. The medic's kit is used up, and the patient's wounds are cleared and their health restored to full.

## Self-heal AI doctor

This is off by default (`Config.doctors.selfHealEnabled = false`). When it is on, a server thread checks every 10 seconds. If fewer than `minimalDoctors` on-duty EMS of grade `onDutyDoctorGrade` or higher are online, every laststand player who has been down for at least `selfHealDelay` ms is revived in the field to `minimumRevive` percent. Each player can only be AI-revived once per `docCooldown` ms. AI revives are not billed. The player sees `No paramedics were available -- you stabilised on your own.`
