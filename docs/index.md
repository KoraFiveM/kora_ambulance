---
title: kora_ambulance
sidebar_position: 1
---

# kora_ambulance

kora_ambulance is the EMS / ambulance job for Kora FiveM servers. The server owns everything that matters. It runs the alive → laststand → dead state machine. It keeps a wound ledger per body part, built from hits that it validates itself. It checks every medic action, assigns hospital beds, bills patients and controls stretcher state. Clients only present that state and ask for actions. A guarded `hospital:*` / `qb-ambulancejob` compatibility layer keeps common legacy integrations working. It does not let a client heal, revive, pick a bed or remove items on its own authority.

## Features

- **Death and respawn**: when a player is downed they enter laststand with a bleed-out timer, then die when it runs out. Dead players can `/respawn` at a hospital after a timer. The server enforces the wait, can block respawn while enough medics are on duty, and can wipe the inventory. Dead players can press a key to alert EMS. See [Death and respawn](./features/death-and-respawn.md).
- **Anatomical injuries**: a hit is matched to the bone that was struck and becomes a wound (tier 1-4) on one of 15 body parts. Open wounds show the `bleeding` status, and critical wounds show `limping`. Wounds are saved and restored when the player reconnects. See [Injuries and wounds](./features/injuries.md).
- **Medical care**: on-duty EMS can assess a patient, treat wounds with bandages or IFAKs, perform CPR with a defibrillator and use a first aid kit on another player. Players can use bandages, IFAKs, first aid kits and painkillers on themselves. An optional AI doctor can revive downed players when too few medics are on duty. See [Medical care and revives](./features/medical-care.md).
- **Hospitals**: you can configure several hospitals. Each one can have a check-in desk that reserves a bed for timed care, plus a pharmacy shop, an EMS stash, a duty point, a vehicle garage and a map blip. See [Hospitals, check-in and billing](./features/hospitals.md).
- **Billing**: patients are billed when they respawn at a hospital (a base fee plus a fee per open wound) and when they complete check-in care. The bill comes from cash first, then bank.
- **Duty and fleet vehicles**: `/ems-duty` or a duty target toggles duty. While on duty, medics can check out vehicles from a garage. These vehicles are temporary: they are never saved and are deleted when returned. See [Duty and vehicles](./features/duty-and-vehicles.md).
- **Patient transport**: some vehicles carry a stretcher that can be deployed, pushed, loaded with a patient and stowed. Emergency carry is the fallback when a stretcher isn't practical. See [Patient transport](./features/transport.md).
- **Dispatch**: `/911e` emergency calls go out through [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch). Calls are also raised automatically when someone goes down or dies, and closed when the patient is revived, healed, respawns or leaves. Players can also queue non-emergency house calls. See [Dispatch and house calls](./features/dispatch.md).
- **Legacy compatibility**: the resource provides `qb-ambulancejob` and maps common `hospital:*` events, callbacks and exports onto the validated flows. See [Compatibility](./compatibility.md).

## Requirements

Declared in `fxmanifest.lua`:

- [kora_lib](https://github.com/KoraFiveM/kora_lib) (loaded as `@kora_lib/init.lua`)
- [kora_core](https://github.com/KoraFiveM/kora_core) (loaded as `@kora_core/init.lua`). Provides jobs, money, items, metadata and commands.
- [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch). Handles EMS calls, player alerts and the dispatch theme.
- [kora_inventory](https://github.com/KoraFiveM/kora_inventory). Handles pharmacy shops, EMS stashes and the optional inventory wipe on respawn.
- [kora_target](https://github.com/KoraFiveM/kora_target). Handles hospital zones and the player, vehicle and stretcher target options.

The resource also listens for `kora_admin:client:heal` and `kora_admin:client:revive` from [kora_admin](https://github.com/KoraFiveM/kora_admin) when that resource is installed. It is not a hard dependency.

There is no SQL to import. All state lives in kora_core player metadata (see [Persistence](./database.md)).

## Installation

1. Put the resource in your resources folder and add it to `server.cfg` after its dependencies:

   ```cfg
   ensure kora_sql
   ensure kora_lib
   ensure kora_core
   ensure kora_inventory
   ensure kora_target
   ensure kora_dispatch
   ensure kora_ambulance
   ```

2. Make sure the `ambulance` job exists in kora_core. The kora_core shared job list already seeds it with `type = 'ems'`. If you rename it, update `Config.job.name` and `Config.job.type` to match.
3. Items: kora_ambulance registers `bandage`, `ifak`, `painkillers` and `defibrillator` with kora_core when it starts. The `firstaid` and `ifaks` items it uses come from kora_core's own item list. Add item images to your inventory if you use custom ones. See [Items](./items.md).
4. Edit `config.lua` for your hospitals, beds, vehicles and gameplay timings. See [Configuration](./configuration.md). `Config.validate()` runs at load and stops the resource with an error message if the configuration is invalid.

## Documentation pages

- [Configuration](./configuration.md): every `config.lua` option
- Features:
  - [Death and respawn](./features/death-and-respawn.md)
  - [Injuries and wounds](./features/injuries.md)
  - [Medical care and revives](./features/medical-care.md)
  - [Hospitals, check-in and billing](./features/hospitals.md)
  - [Duty and vehicles](./features/duty-and-vehicles.md)
  - [Patient transport](./features/transport.md)
  - [Dispatch and house calls](./features/dispatch.md)
- [Commands and keybinds](./commands.md)
- [Items](./items.md)
- [Exports](./exports.md)
- [Events and state bags](./events.md)
- [Persistence](./database.md)
- [Compatibility](./compatibility.md)

## Related resources

- [kora_police](https://github.com/KoraFiveM/kora_police): police / LEO job
- [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch): call feed and map
- [kora_hud](https://github.com/KoraFiveM/kora_hud): shows the `bleeding` / `limping` status pills
