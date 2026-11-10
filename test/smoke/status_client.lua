-- Client status sync smoke test -- the server's pushed wound state wins over
-- whatever bleeding/limping effects the client is still showing.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

local active = {}
local applied, removed = {}, {}
local refuseRemoval = false
local stale = {}
handle.Kora.status = {
    getActive = function()
        local out = {}
        for name, severity in pairs(active) do out[#out + 1] = { name = name, severity = severity } end
        return out
    end,
    apply = function(name, opts) active[name] = opts.severity; applied[#applied + 1] = name; return true end,
    remove = function(name)
        if refuseRemoval then return false end
        active[name] = nil; removed[#removed + 1] = name; return true
    end,
    isActive = function(name) return active[name] ~= nil end,
}
handle.Kora.events.trigger = function(name, ...) stale[#stale + 1] = { name = name, args = { ... } } end

SetTimeout = function() end -- the heal report timer is not under test here

local suppressed
Damage = { suppressFor = function(ms) suppressed = ms end }

dofile('client/status.lua')

local function sync(bleeding, limping) handle.fireEvent('kora_ambulance:client:syncStatus', 0, bleeding, limping) end

h.test('a stale bleeding pill is removed when the server reports none', function()
    active = { bleeding = 2 }
    sync(false, false)
    h.assertEqual(active.bleeding, nil)
end)

h.test('missing effects are applied at the reported severity and matching ones are left alone', function()
    active = { limping = 4 }
    applied, removed = {}, {}
    sync(3, 4)
    h.assertEqual(active.bleeding, 3)
    h.assertEqual(active.limping, 4)
    h.assertEqual(#applied, 1, 'the already-correct limp is not re-applied')
    h.assertEqual(#removed, 0)
end)

h.test('a severity mismatch is corrected and a lone limp survives bleeding ending', function()
    active = { bleeding = 1, limping = 4 }
    sync(false, 4)
    h.assertEqual(active.bleeding, nil)
    h.assertEqual(active.limping, 4)
    sync(2, 4)
    h.assertEqual(active.bleeding, 2)
end)

h.test('a pill kora_lib refuses to remove is reported so the server can force-clear it', function()
    active = { bleeding = 1 }
    stale = {}
    refuseRemoval = true
    sync(false, false)
    refuseRemoval = false
    h.assertEqual(#stale, 1)
    h.assertEqual(stale[1].name, 'kora_ambulance:server:statusStale')
    h.assertEqual(stale[1].args[1], 'bleeding')

    active = { bleeding = 1 }
    stale = {}
    sync(false, false)
    h.assertEqual(#stale, 0, 'a removal that worked reports nothing')
end)

h.test('every heal and revive event opens the injury ignore window', function()
    for _, eventName in ipairs({
        'kora_admin:client:heal', 'kora_admin:client:revive',
        'kora_ambulance:client:revived', 'kora_ambulance:client:respawnedAtHospital',
    }) do
        suppressed = nil
        handle.fireEvent(eventName, 0)
        h.assertEqual(suppressed, Config.injuries.healGraceMs, eventName)
    end
end)

h.report('status_client')
