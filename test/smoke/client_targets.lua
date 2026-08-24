-- client/stretcher.lua + client/revive.lua qbtarget registration smoke test.
-- Both files register a single qbtarget global type at load time; this
-- proves that registration also re-runs on a qbtarget restart mid-session
-- (qbtarget wipes its own global-type registry on restart, so a stale
-- one-shot registration would silently leave EMS without its "Pick Up
-- Patient"/"Release Patient"/"Perform CPR" target options after qbtarget
-- comes back up).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()

dofile('client/stretcher.lua')
dofile('client/revive.lua')

h.test('both client files register their qbtarget global type once at load', function()
    h.assertEqual(#handle.qbtarget.calls, 2, 'stretcher.lua and revive.lua should each call addGlobalType once at load')
end)

h.test('a qbtarget restart re-registers both global types', function()
    local before = #handle.qbtarget.calls

    handle.fireEvent('onClientResourceStart', nil, 'qbtarget')

    local after = #handle.qbtarget.calls
    h.assertEqual(after, before + 2, 'both stretcher.lua and revive.lua must re-call addGlobalType on a qbtarget restart')
end)

h.test('an unrelated resource restarting does not re-trigger anything', function()
    local before = #handle.qbtarget.calls

    handle.fireEvent('onClientResourceStart', nil, 'some_other_resource')

    h.assertEqual(#handle.qbtarget.calls, before, 'only a qbtarget restart should re-trigger addGlobalType')
end)

h.report('client_targets')
