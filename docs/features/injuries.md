---
title: Injuries and wounds
sidebar_position: 2
---

# Injuries and wounds

Each player has a **wound ledger** that maps a body part to a severity tier (1-4). Only the server writes to it. The client reports what it saw, and the server checks the report and turns it into a wound.

## How a hit becomes a wound

1. **Client** (`client/damage.lua`): when the local ped gets a `CEventNetworkEntityDamage` game event, the client stores the bone that was hit (`GetPedLastDamageBone`). Damage events that killed the ped are ignored.
2. If the ped's health drops within `Config.injuries.captureWindow` ms of that event, the client sends the measurement to the server with `Kora.events.trigger('kora_ambulance:server:hitObserved', ...)`. The payload contains a sequence number, the bone, the body part, the damage and the health after the hit. Drops smaller than `minDamage` or larger than `maxDamage` are not reported. If the bone does not match a configured body part, the client picks a random part weighted by `Config.bodyParts[n].weight` and marks the report as a fallback.
3. **Server** (`server/death.lua`) accepts the report only if all of these hold:
   - the player is loaded and alive, and not inside the post-heal grace window (`healGraceMs`),
   - the sequence number is higher than the last one, and `reportCooldown` has passed since the last accepted report,
   - damage, health and bone are finite and in range,
   - the bone matches the body part. A mapped bone must not be a fallback, and a fallback must name a valid part,
   - within 1 second, the server's own copy of the ped's health matches the reported value within `healthTolerance`.
4. The server works out the severity from the damage:

   | Damage (default thresholds `8, 20, 40`) | Tier |
   |---|---|
   | under 8 | 1 Minor |
   | 8 to 19 | 2 Moderate |
   | 20 to 39 | 3 Severe |
   | 40 or more | 4 Critical |

   A `vital` body part (head, neck, chest, abdomen, spine) adds one tier, up to the highest tier.
5. The wound is recorded only if it is **worse** than the wound already on that body part. Each part keeps its worst tier. A new or worse wound also undoes an earlier "bleeding stopped" state.

Health lost to kora_core hunger/thirst damage is not treated as an injury while `ignoreNeedsDamage` is on. The client ignores hits for `needsDamageWindowMs` after hunger or thirst reaches 0.

## Status effects

Wounds drive two `Kora.status` effects, which are registered in `shared/wounds.lua`:

| Effect | Applied when | Notes |
|---|---|---|
| `bleeding` | Any wound is open and no revive or painkiller has stopped the bleeding | Severity is the worst open tier. Has a `blood_stab` particle effect. |
| `limping` | The worst open tier has `canWalk = false` (tier 4 by default) | No movement effect of its own. |

After every change to the ledger or a revive, the server sends `kora_ambulance:client:syncStatus(bleedingTier, limpingTier)`. The client then adds or removes the effects to match. If the client cannot remove an effect that the server applied, it asks the server with `kora_ambulance:server:statusStale`. The server clears that effect only if the ledger agrees.

Bleeding is **only a status**. No code currently deals bleed damage over time, and wound tiers do not slow movement (`Config.bleed`, `blackoutTimer`, `fadeOutTimer` and `movementMultiplier` are not used at runtime).

## Ways wounds close

| Cause | Effect |
|---|---|
| Bandage or IFAK used on yourself | Closes the worst wound that item can treat. See [Items](../items.md). |
| EMS **Treat Wound** | Closes one wound. See [Medical care](./medical-care.md). |
| First aid kit | Closes every wound. |
| Field revive (CPR, AI doctor) | Follows `Config.revive`: stop the bleeding (default), close all wounds, or leave them. |
| Full revive (`fullRevive`, `/aheal`), check-in care, respawn | Closes every wound. |
| Back at full health (`clearWhenHealthy`, `clearOnHealEvent`) | Closes every wound of an alive player whose server-side health is within `healthyMargin` of max. |
| Painkillers with `stopBleeding = true` | Stops the bleeding. The wounds stay. |

When a player is healed outside this resource with kora_admin (`kora_admin:client:heal`), the client sends `kora_ambulance:server:healthRestored` 750 ms later. The server checks the real health. If the player really is healthy, it clears the wounds and fires `kora_ambulance:server:onPlayerHealed`, which also closes their EMS calls.

## Reading the ledger from another resource

Use the server export [`getPatientStatus`](../api/death.md). It returns a detached copy that includes `wounds` and `bleeding`.
