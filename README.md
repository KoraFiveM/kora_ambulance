> [!WARNING]
> **Kora Framework is in alpha and actively being developed.**
>
> This resource is a work in progress. Features may be incomplete or unstable,
> and APIs, configuration, and behavior may change. It is not ready for production use.
>
> **Help shape Kora:** try it out, share feedback, report bugs through this
> repository’s Issues, and contribute improvements through pull requests.

# kora_ambulance

A modern, kora_lib-native ambulance resource for FiveM.

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
