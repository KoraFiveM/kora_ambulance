---
title: "API reference"
sidebar_position: 1
---

# API reference

| Module | Namespace | Realms |
| --- | --- | --- |
| [Death and injuries](./death.md) | `Death.* / exports.kora_ambulance` | server |
| [Legacy hospital exports](./hospital-compat.md) | `exports.kora_ambulance (qb-ambulancejob compatibility)` | client, server |

## Not exported

`Death`, `Hospital`, `Billing`, `Treatment`, `Stretcher` and the other module tables are globals **inside kora_ambulance only**. Other resources cannot call functions such as `Death.respawnAtHospital`. To integrate, use the exports documented here and the [events](../events.md).
