-- EMS calls raised automatically off the death lifecycle, and the wording each
-- one carries. The call lifecycle itself belongs to kora_dispatch and has its own
-- suite; this asserts what kora_ambulance decides is an EMS matter.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/wounds.lua')
dofile('server/death.lua')
dofile('server/dispatch.lua')
dofile('server/billing.lua')

local PATIENT, MEDIC = 5, 1

handle.ensurePlayer(MEDIC)
handle.players[MEDIC].job = { name = Config.job.name, onduty = true, grade = { level = 1 } }

handle.ensurePlayer(PATIENT)
handle.players[PATIENT].data = handle.players[PATIENT].data or {}
handle.players[PATIENT].charinfo = { firstname = 'Alex', lastname = 'Stone' }

local function callsBefore() return #handle.dispatchCalls end

h.test('going into laststand raises a critical EMS call', function()
    local before = callsBefore()
    Death.enterLaststand(PATIENT, 'gunshot')

    h.assertEqual(#handle.dispatchCalls, before + 1, 'exactly one call for one casualty')

    local call = handle.lastDispatchCall()
    h.assertEqual(call.jobTypes[1], Config.job.type, 'targets the EMS service, not a job name')
    h.assertEqual(call.code, '10-52', 'person down')
    h.assertEqual(call.priority, 1, 'a savable patient is the highest priority there is')
    h.assertEqual(call.data.source, PATIENT, 'the patient is identified so the call can be closed on revive')
end)

h.test('the same casualty does not spam the feed', function()
    -- Death and laststand both fire on the way down, and a revive-then-die cycle
    -- can repeat in seconds. One firefight must not fill the EMS feed with the
    -- same patient over and over.
    local before = callsBefore()
    Death.reviveInField(PATIENT, 30)
    Death.enterLaststand(PATIENT, 'gunshot')

    h.assertEqual(#handle.dispatchCalls, before, 'the cooldown suppressed the repeat call')
end)

h.test('bleeding out raises a lower-priority call than going down did', function()
    local before = callsBefore()
    Death.markDead(PATIENT)

    h.assertEqual(#handle.dispatchCalls, before + 1, 'a death is still worth reporting')

    local call = handle.lastDispatchCall()
    h.assertEqual(call.code, '10-54', 'possible fatality')
    -- Nobody is being saved now, so it must not outrank a patient who still can
    -- be -- a feed that ranks the dead above the dying is worse than no feed.
    h.assertEqual(call.priority, 2, 'below the person-down call')
end)

h.test('the two death-lifecycle priorities are configurable and swappable', function()
    local cfg = Config.dispatch.priorities
    h.assertEqual(cfg.personDown, 1, 'default person-down priority')
    h.assertEqual(cfg.possibleFatality, 2, 'default possible-fatality priority')
    h.assertTrue(Config.validate())

    local down, fatality = cfg.personDown, cfg.possibleFatality
    local cooldown = Config.dispatch.autoCallCooldown
    Config.dispatch.autoCallCooldown = 0
    cfg.personDown, cfg.possibleFatality = 2, 1

    Death.reviveInField(PATIENT, 30)
    Death.enterLaststand(PATIENT, 'gunshot')
    h.assertEqual(handle.lastDispatchCall().code, '10-52')
    h.assertEqual(handle.lastDispatchCall().priority, 2, 'person down follows Config.dispatch.priorities')

    Death.markDead(PATIENT)
    h.assertEqual(handle.lastDispatchCall().code, '10-54')
    h.assertEqual(handle.lastDispatchCall().priority, 1, 'possible fatality follows Config.dispatch.priorities')

    cfg.personDown = 'high'
    h.assertThrows(Config.validate)

    cfg.personDown, cfg.possibleFatality = down, fatality
    Config.dispatch.autoCallCooldown = cooldown
end)

h.test('a treated patient stops being an open incident', function()
    handle.ensurePlayer(6)
    handle.players[6].charinfo = { firstname = 'Robin', lastname = 'Vale' }

    Death.enterLaststand(6, 'crash')
    local call = handle.lastDispatchCall()
    h.assertTrue(call ~= nil, 'sanity: the call was raised')

    Death.reviveInField(6, 30)

    -- A feed still listing people who were treated ten minutes ago stops being
    -- read at all.
    local open = handle.kora_dispatch:getCalls({ service = Config.job.type, activeOnly = true })
    for _, entry in ipairs(open) do
        h.assertTrue(not entry.data or entry.data.source ~= 6, 'the treated patient has no open call left')
    end
end)

local function openCallsFor(src)
    local count = 0
    for _, entry in ipairs(handle.kora_dispatch:getCalls({ service = Config.job.type, activeOnly = true })) do
        if entry.data and entry.data.source == src then count = count + 1 end
    end
    return count
end

h.test('an admin full revive closes the call even for a patient this resource never tracked', function()
    handle.ensurePlayer(11)
    -- A call is open but the ledger says alive (vanilla death, admin tool).
    Ambulance.dispatch.call({ code = '10-52', title = 'Person Down', priority = 1, data = { source = 11 } })
    h.assertEqual(openCallsFor(11), 1, 'sanity: the call is open')

    Death.fullRevive(11)
    h.assertEqual(openCallsFor(11), 0, 'no open call left')
end)

h.test('a patient who leaves the server stops being an open incident', function()
    handle.ensurePlayer(13)
    handle.players[13].charinfo = { firstname = 'Lee', lastname = 'Park' }
    Death.enterLaststand(13, 'gunshot')
    h.assertEqual(openCallsFor(13), 1, 'sanity: the call is open')

    handle.fireEvent('playerDropped', 13)
    h.assertEqual(openCallsFor(13), 0, 'the call was closed on disconnect')
end)

h.test('closeOnResolve = false leaves calls open', function()
    Config.dispatch.closeOnResolve = false
    handle.ensurePlayer(14)
    Death.enterLaststand(14, 'gunshot')
    handle.fireEvent('playerDropped', 14)
    h.assertEqual(openCallsFor(14), 1, 'call kept')
    Config.dispatch.closeOnResolve = true
end)

local function open911eFor(src)
    local count = 0
    for _, entry in ipairs(handle.kora_dispatch:getCalls({ service = Config.job.type, activeOnly = true })) do
        if entry.code == '911e' and entry.data and entry.data.requester == src then count = count + 1 end
    end
    return count
end

local function raise911e(src)
    Ambulance.dispatch.call({ code = '911e', title = '911 -- Medical Emergency', priority = 1, data = { requester = src } })
end

h.test('a /911e the patient raised themself closes when an admin revives them', function()
    handle.ensurePlayer(15)
    raise911e(15)
    h.assertEqual(open911eFor(15), 1, 'sanity: the alert is open')
    Death.fullRevive(15)
    h.assertEqual(open911eFor(15), 0, 'the caller is up, the alert is gone')
end)

h.test('closeCallerAlerts = false leaves /911e alerts open', function()
    Config.dispatch.closeCallerAlerts = false
    handle.ensurePlayer(16)
    raise911e(16)
    Death.fullRevive(16)
    h.assertEqual(open911eFor(16), 1, 'alert kept')
    Config.dispatch.closeCallerAlerts = true
end)

h.test('an admin /heal closes the call only once the server sees full health', function()
    local healthRestored = handle.Kora.events.registry['kora_ambulance:server:healthRestored']
    handle.ensurePlayer(17)
    raise911e(17)
    Ambulance.dispatch.call({ code = '10-52', title = 'Person Down', priority = 1, data = { source = 17 } })

    handle.players[17].health = 150
    healthRestored(17)
    h.assertEqual(open911eFor(17) + openCallsFor(17), 2, 'still hurt: calls stay open')

    handle.players[17].health = 200
    healthRestored(17)
    h.assertEqual(open911eFor(17) + openCallsFor(17), 0, 'healed: every call for them closed')
end)

h.test('a heal report from a downed player closes nothing', function()
    local healthRestored = handle.Kora.events.registry['kora_ambulance:server:healthRestored']
    handle.ensurePlayer(18)
    Death.enterLaststand(18, 'gunshot')
    h.assertEqual(openCallsFor(18), 1, 'sanity: the call is open')
    handle.players[18].health = 200
    healthRestored(18)
    h.assertEqual(openCallsFor(18), 1, 'still down: the call stays open')
end)

h.test('automatic calls can be turned off entirely', function()
    Config.dispatch.autoCall = false
    handle.ensurePlayer(7)

    local before = callsBefore()
    Death.enterLaststand(7, 'gunshot')
    h.assertEqual(#handle.dispatchCalls, before, 'no call raised when the feature is disabled')

    Config.dispatch.autoCall = true
end)

h.test('a call names the patient rather than exposing a source id', function()
    handle.ensurePlayer(8)
    handle.players[8].charinfo = { firstname = 'Casey', lastname = 'Nolan' }

    Death.enterLaststand(8, 'fall')

    local call = handle.lastDispatchCall()
    h.assertTrue(call.message:find('Casey Nolan', 1, true) ~= nil,
        'dispatch reads out a name: ' .. tostring(call.message))
end)

h.test('alert key: a dead player sends their street to EMS, with a cooldown and dead-only enforcement', function()
    local now = 5000
    os.time = function() return now end
    local before = callsBefore()

    handle.ensurePlayer(60)
    handle.fireEvent('kora_ambulance:server:alertEms', 60, 'Alta Street')
    h.assertEqual(#handle.dispatchCalls, before, 'an alive player is ignored')

    Death.markDead(60)
    before = callsBefore() -- markDead itself raises the automatic fatality call
    handle.fireEvent('kora_ambulance:server:alertEms', 60, 'Alta Street\n')
    h.assertEqual(#handle.dispatchCalls, before + 1)
    local call = handle.lastDispatchCall()
    h.assertEqual(call.jobTypes[1], Config.job.type)
    h.assertTrue(call.message:find('Alta Street', 1, true) ~= nil, call.message)
    h.assertEqual(call.data.source, 60)

    now = now + 10
    handle.fireEvent('kora_ambulance:server:alertEms', 60, 'Alta Street')
    h.assertEqual(#handle.dispatchCalls, before + 1, 'cooldown holds')

    now = now + math.floor(Config.death.alertEms.cooldown / 1000)
    handle.fireEvent('kora_ambulance:server:alertEms', 60, 123)
    h.assertEqual(#handle.dispatchCalls, before + 2, 'allowed again once the cooldown lapsed; bad street input is dropped')

    Config.death.alertEms.enabled = false
    now = now + 1000
    handle.fireEvent('kora_ambulance:server:alertEms', 60, 'x')
    h.assertEqual(#handle.dispatchCalls, before + 2, 'Config.death.alertEms.enabled = false disables it')
    Config.death.alertEms.enabled = true
end)

h.report('dispatch')
