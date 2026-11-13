-- HouseCall (client realm) -- rendering only. Submission/acceptance/cooldowns
-- are entirely server-authoritative (server/housecall.lua's /911e,
-- /housecall, /housecalls, /accepthousecall commands) -- this file just
-- reacts to what the server reports back.

RegisterNetEvent('kora_ambulance:client:housecallList', function(list)
    if type(list) ~= 'table' or #list == 0 then return end

    local lines = {}
    for _, entry in ipairs(list) do
        lines[#lines + 1] = Kora.lang('ui.housecall_line', entry.id, entry.note or Kora.lang('ui.no_housecall_details'))
    end

    Kora.notify.send({ title = Kora.lang('title.house_calls'), message = table.concat(lines, '\n'), type = 'info', duration = 8000 })
end)

-- server/housecall.lua reads the requester's coords server-side
-- (GetPlayerPed + GetEntityCoords) at submission time, no client round-trip
-- needed -- set a waypoint straight to them.
RegisterNetEvent('kora_ambulance:client:housecallAccepted', function(request)
    if type(request) ~= 'table' then return end
    Kora.notify.send({ title = Kora.lang('title.house_call'), message = Kora.lang('ui.request_accepted', request.id), type = 'success' })

    if request.coords then
        SetNewWaypoint(request.coords.x, request.coords.y)
    end
end)
