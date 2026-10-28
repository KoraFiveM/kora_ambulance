# kora_ambulance

A modern, qblib-native ambulance resource for FiveM.

It provides a server-authoritative death state machine, persistent anatomical
wounds, EMS patient assessment and treatment, CPR/defibrillator revives,
server-assigned hospital beds, physical ambulance stretchers, billing,
pharmacies and stashes, duty vehicles, emergency dispatch and a house-call
queue. A guarded `hospital:*` compatibility adapter keeps common legacy
integrations working without preserving insecure client-authoritative shortcuts.

## Requirements

- kora_lib
- kora_core
- kora_inventory
- kora_target
- kora_dispatch

Start those resources first, then `ensure kora_ambulance`.

See [the full documentation](docs/index.md) for setup, configuration, commands,
integration hooks and compatibility details.
