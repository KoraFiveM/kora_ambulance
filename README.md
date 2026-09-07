# qbambulance

A modern, qblib-native successor to `qb-ambulancejob` for FiveM.

It provides a server-authoritative death state machine, per-body-part wounds,
EMS patient assessment and treatment, CPR/defibrillator revives, stretchers,
hospital billing, pharmacies and stashes, duty vehicles, emergency dispatch and
a house-call queue. The legacy `hospital:*` event surface remains available so
existing resources can migrate without a flag day.

## Requirements

- qblib
- qbcore
- qbinventory
- qbtarget
- qbdispatch

Start those resources first, then `ensure qbambulance`.

See [the full documentation](docs/index.md) for setup, configuration, commands,
integration hooks and compatibility details.
