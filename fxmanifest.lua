fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbambulance'
author 'Jamie'
version '1.0.0'
description 'EMS/ambulance job -- wounds, revive, dispatch, billing, duty vehicles, stretcher, house-calls'

dependency 'qblib'
dependency 'qbcore'
dependency 'qbinventory'
dependency 'qbtarget'

-- qblib strictly before qbcore, same rule every consumer resource follows
-- (qbcore's own mirror extends the QB table qblib's init.lua creates).
-- qbinventory/qbtarget expose flat exports only (exports.qbinventory:*,
-- exports.qbtarget:*) -- neither needs a shared_script import.
shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'

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
    'server/billing.lua',
    'server/doctors.lua',
    'server/revive.lua',
    'server/duty.lua',
    'server/items.lua',
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
    'client/stretcher.lua',
    'client/pharmacy.lua',
    'client/housecall.lua',
    'client/compat.lua'
}
