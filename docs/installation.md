---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Ambulance is the EMS job resource: an anatomical injury/bleeding model, hospital check-in and duty-vehicle garages, patient carry/stretcher transport, dispatch alerts and house calls, and hospital billing. It declares `provide 'qb-ambulancejob'` so legacy resources resolve the old export name.

## Install Kora Ambulance

1. **Add the folder** — Place `kora_ambulance` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_ambulance`).

2. **Have the dependencies running** — The manifest declares `kora_lib`, `kora_core`, `kora_dispatch`, `kora_inventory` and `kora_target` as dependencies. `kora_lib`’s init.lua must load before `kora_core`’s (kora_core’s own mirror extends the shared `Kora` table kora_lib creates). `kora_dispatch` carries EMS alerts and house calls; `kora_inventory` backs the pharmacy shops, EMS stash and consumable items (bandage, ifak, painkillers, defibrillator, firstaid); `kora_target` is used for hospital check-in, duty and garage interaction points.

3. **Start it after its dependencies** — Start kora_ambulance after all five dependencies.

   ```bash title="server.cfg" {7}
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_dispatch
   ensure kora_inventory
   ensure kora_target
   ensure kora_ambulance
   ```

4. **The ambulance job must exist** — `Config.job.name` (default `ambulance`) must match a job record already seeded by kora_core’s `shared/jobs.lua`. `Config.job.type` (default `ems`) is the kora_core job TYPE house calls and /911e dispatch to — not the job name — so a server adding a second EMS-type department reaches it from the same radio with no config change here.

5. **Configure your hospitals** — Edit `Config.hospitals`: each entry needs unique `name`, `coords`, `checkIn`, and (unless `Config.hospitalCare.allowBedless` is true) at least one unique bed vector. `Config.validate()` runs at load and asserts the whole config is internally consistent — a misconfigured server fails loudly at boot rather than at runtime.

6. **Pharmacy shops and the EMS stash are registered automatically** — On start, `server/duty.lua` calls `exports.kora_inventory:registerShop` and `registerStash` for every hospital that has a `pharmacy`/`stash` entry, and re-registers them whenever `kora_inventory` restarts (its shop/stash tables are wiped on restart).

## Manifest reference

Load order is deliberate and commented in the source.

```lua title="fxmanifest.lua"
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_ambulance'
provide 'qb-ambulancejob'

dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_dispatch'
dependency 'kora_inventory'
dependency 'kora_target'

shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'

shared_scripts {
    'config.lua',
    'shared/wounds.lua',
    'shared/items.lua',
    'shared/downed.lua',
    'shared/hospital_menu.lua'
}
```

- Shared scripts load `config.lua` first (everything else reads `Config.*`), then `shared/wounds.lua` before `shared/items.lua` (the pharmacy item effect table references `Wounds.woundLevels` labels).
- Server scripts load `server/death.lua` first (the death-state helpers other files read), then `server/dispatch.lua` (listens for the death lifecycle events death.lua emits), then billing/hospital/doctors/revive/duty/items/treatment/stretcher/housecall, with `server/compat/hospital.lua` last so every legacy forwarder can call the real functions directly.
- Client scripts load `client/death.lua` first (defines the local state machine every other client file reads via `State.isDead()`/`isLaststand()`), then `client/damage.lua` (feeds bleeding/limping status off that state machine), with `client/compat.lua` last.

## Compatibility

`Config.compat.enabled` (default true) turns on legacy `qb-ambulancejob` compatibility endpoints in `server/compat/hospital.lua` and `client/compat.lua`.

- `Config.compat.acceptClientInjurySync` (default false) keeps legacy client-reported injuries opt-in; server-owned injury reports from `client/damage.lua` are preferred and authoritative.
- `Config.compat.allowDestructiveItemEvents` (default false) prevents legacy item-removal events from silently deleting inventory items unless explicitly turned on.
- `Config.compat.reviveNotice` (default false) controls whether a legacy `hospital:client:Revive`/`RevivePlayer` event (as fired by an admin `/revive` or the kora_admin menu) shows an "EMS - a medic must perform CPR" toast.

## Requirements

Declared in `fxmanifest.lua`:

- [kora_lib](https://github.com/KoraFiveM/kora_lib) (loaded as `@kora_lib/init.lua`)
- [kora_core](https://github.com/KoraFiveM/kora_core) (loaded as `@kora_core/init.lua`). Provides jobs, money, items, metadata and commands.
- [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch). Handles EMS calls, player alerts and the dispatch theme.
- [kora_inventory](https://github.com/KoraFiveM/kora_inventory). Handles pharmacy shops, EMS stashes and the optional inventory wipe on respawn.
- [kora_target](https://github.com/KoraFiveM/kora_target). Handles hospital zones and the player, vehicle and stretcher target options.

The resource also listens for `kora_admin:client:heal` and `kora_admin:client:revive` from [kora_admin](https://github.com/KoraFiveM/kora_admin) when that resource is installed. It is not a hard dependency.

There is no SQL to import. All state lives in kora_core player metadata (see [Persistence](./database.md)).

## Job and items

The kora_core shared job list already seeds the `ambulance` job with `type = 'ems'`. If you rename it, update `Config.job.name` and `Config.job.type` to match.

kora_ambulance registers `bandage`, `ifak`, `painkillers` and `defibrillator` with kora_core when it starts. The `firstaid` and `ifaks` items it uses come from kora_core's own item list. Add item images to your inventory if you use custom ones. See [Items](./items.md). Edit `config.lua` for your hospitals, beds, vehicles and gameplay timings. See [Configuration](./configuration.md). `Config.validate()` stops the resource with an error message if the configuration is invalid.

## Related resources

- [kora_police](https://github.com/KoraFiveM/kora_police): police / LEO job
- [kora_dispatch](https://github.com/KoraFiveM/kora_dispatch): call feed and map
- [kora_hud](https://github.com/KoraFiveM/kora_hud): shows the `bleeding` / `limping` status pills
