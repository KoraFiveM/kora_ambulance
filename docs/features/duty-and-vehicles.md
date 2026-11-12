---
title: Duty and vehicles
sidebar_position: 5
---

# Duty and vehicles

## Duty

There are two ways to toggle duty: the `/ems-duty` command and the **Toggle Duty** target at a hospital `duty` point. The target simply runs the command. The server (`Duty.setDuty`) requires that:

- the player's job is `Config.job.name` (`You are not employed as EMS.`),
- the player is near a configured hospital `duty` point. The allowed distance is the larger of 3 m and that hospital's duty zone radius (`Use a hospital duty point to change duty status.`),
- at least 1 second has passed since the player's last duty change.

Duty is then set with kora_core's `setJobDuty`. The player is notified `You are now on duty.` or `You are now off duty.`

Many features require being **on duty**: treatment, CPR, carry and stretcher, the garage and `/accepthousecall`. The EMS stash, the duty toggle and `/housecalls` only check the job.

## Duty vehicles

At a hospital `garage` point, on-duty EMS see a **Check out `label`** option for each `Config.dutyVehicles` entry, plus **Return Vehicle**.

**Checkout** (`kora_ambulance:server:spawnDutyVehicle`). The server requires:

- the player is on-duty EMS and has no other duty vehicle checked out,
- `Config.dutyGarage.actionCooldown` has passed since the player's last garage action,
- the hospital exists and the player is within `Config.dutyGarage.interactionRange` of its garage,
- the vehicle index is valid.

The server creates the vehicle at the garage coordinates and heading, in the player's routing bucket. It gets an `EMS` plate followed by 5 random letters or digits. The client warps the player into the driver's seat.

**Return** (`kora_ambulance:server:storeDutyVehicle`). The player must be inside a vehicle. The client makes them exit, waits 1.5 s, then asks the server. The server requires on-duty EMS, the cooldown and that the player is near **any** configured garage. It then deletes the player's checked-out vehicle and any stretcher deployed from it.

Duty vehicles are **temporary**. They are never written to the owned-vehicles table. They are deleted when returned, when the player disconnects and when kora_ambulance stops.

## Dispatch theme

On every client, 1.5 s after the resource starts, kora_ambulance calls `exports.kora_dispatch:setTheme(Config.dispatch.accent)`. This sets the dispatch UI accent colour to EMS red (`#EF4444`). It does this for all players, whatever their job.
