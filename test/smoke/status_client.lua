-- Client status sync smoke test -- the server's pushed wound state wins over
-- whatever bleeding/limping effects the client is still showing.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

local active = {}
local applied, removed = {}, {}
handle.Kora.status = {
    getActive = function()
        local out = {}
        for name, severity in pairs(active) do out[#out + 1] = { name = name, severity = severity } end
        return out
    end,
    apply = function(name, opts) active[name] = opts.severity; applied[#applied + 1] = name; return true end,
    remove = function(name) active[name] = nil; removed[#removed + 1] = name; return true end,
}

dofile('client/status.lua')

local function sync(bleeding, limping) handle.fireEvent('qbambulance:client:syncStatus', 0, bleeding, limping) end

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

h.report('status_client')
