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

## Documentation map

- [Installation](./installation.md): dependencies, start order, manifest, requirements and compatibility switches
- [How to use](./how-to-use.md): how injuries, treatment, transport, duty, dispatch and billing fit together
- [Commands and keybinds](./commands.md): every command with arguments, access and results, plus key mappings
- [API reference](./api/index.md): exports
  - [Death and injuries](./api/death.md): `getPatientStatus` and `fullRevive`
  - [Legacy hospital exports](./api/hospital-compat.md): `GetDoctorCount`, `isEscorted`, `CanHelp`, `PainKillerLoop`
- [Configuration](./configuration.md): every `config.lua` option
- [Items](./items.md)
- [Events and state bags](./events.md)
- [Persistence](./database.md)
- [Compatibility](./compatibility.md)
- Features:
  - [Death and respawn](./features/death-and-respawn.md)
  - [Injuries and wounds](./features/injuries.md)
  - [Medical care and revives](./features/medical-care.md)
  - [Hospitals, check-in and billing](./features/hospitals.md)
  - [Duty and vehicles](./features/duty-and-vehicles.md)
  - [Patient transport](./features/transport.md)
  - [Dispatch and house calls](./features/dispatch.md)

## Related resources

- [kora_police](https://github.com/KoraFiveM/kora_police): police / LEO job
- [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch): call feed and map
- [kora_hud](https://github.com/KoraFiveM/kora_hud): shows the `bleeding` / `limping` status pills
