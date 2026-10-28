fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_ambulance'
-- Keep the legacy resource name resolvable for exports['qbambulance'] callers.
provide 'qbambulance'
author 'Jamie'
version '2.0.0'
description 'Authoritative EMS care, anatomical injuries, hospital admissions, transport, dispatch and billing'

dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_dispatch'
dependency 'kora_inventory'
dependency 'kora_target'

-- kora_lib strictly before kora_core, same rule every consumer resource follows
-- (kora_core's own mirror extends the QB table kora_lib's init.lua creates).
-- kora_inventory/qbtarget expose flat exports only (exports.kora_inventory:*,
-- exports.kora_target:*) -- neither needs a shared_script import.
shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'

-- config.lua first (everything below reads Config.*); shared/wounds.lua
-- second since shared/items.lua's pharmacy effect table references
-- Wounds.woundLevels labels for description text.
shared_scripts {
    'config.lua',
    'shared/wounds.lua',
    'shared/items.lua'
}

-- Explicit, never globbed -- matches every sibling resource's own rationale.
-- death.lua before revive/doctors/billing (they read the death-state helpers
-- it defines); items.lua after billing (its useable handlers reference
-- Billing); housecall.lua and duty.lua have no cross-file dependency;
-- compat/hospital.lua LAST so every legacy forwarder can call the real
-- server-side functions above it directly.
server_scripts {
    'server/death.lua',
    -- dispatch.lua after death.lua: it listens for the death lifecycle events
    -- that file emits, and before housecall.lua, which raises calls through it.
    'server/dispatch.lua',
    'server/billing.lua',
    'server/hospital.lua',
    'server/doctors.lua',
    'server/revive.lua',
    'server/duty.lua',
    'server/items.lua',
    'server/treatment.lua',
    'server/stretcher.lua',
    'server/housecall.lua',
    'server/compat/hospital.lua'
}

-- death.lua first (defines the local FSM state every other client file
-- reads via State.isDead()/isLaststand()); damage.lua next (feeds bleeding/
-- limping status off that FSM); the rest have no load-order dependency on
-- each other. compat.lua last so it can reference any of the above.
client_scripts {
    'client/death.lua',
    'client/damage.lua',
    'client/hospital.lua',
    'client/duty.lua',
    'client/revive.lua',
    'client/treatment.lua',
    'client/stretcher.lua',
    'client/pharmacy.lua',
    'client/housecall.lua',
    'client/compat.lua'
}
