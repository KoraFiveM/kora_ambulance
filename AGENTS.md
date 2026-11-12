# kora_ambulance agent guide

kora_ambulance is the server-authoritative EMS job for Kora: it covers the death state machine, anatomical wounds, treatment and CPR, hospital check-in and billing, duty vehicles, stretchers, dispatch, and a guarded `hospital:*` compatibility layer. `config.lua` holds all settings. `shared/` has the pure helpers (wounds, items, downed health, hospital menu), `server/` holds the authority (`server/compat/` for the legacy adapter), `client/` handles presentation only, and `test/` contains plain-Lua smoke tests (`test/run.sh`).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first (overview and a map of every page). Layout: `installation.md` (dependencies, start order, manifest, requirements), `how-to-use.md` (how the modules fit together), `commands.md` (commands, keybinds, controls), `api/` (exports: `api/index.md`, `api/death.md`, `api/hospital-compat.md`), and topic pages (`configuration.md`, `items.md`, `events.md`, `database.md`, `compatibility.md`, `features/*`). Update the page that owns the topic; there is no separate exports page.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
