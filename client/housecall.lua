-- HouseCall (client realm) -- rendering only. Submission/acceptance/cooldowns
-- are entirely server-authoritative (server/housecall.lua's /911e,
-- /housecall, /housecalls, /accepthousecall commands) -- this file just
-- reacts to what the server reports back.

RegisterNetEvent('qbambulance:client:housecallList', function(list)
    if type(list) ~= 'table' or #list == 0 then return end

    local lines = {}
    for _, entry in ipairs(list) do
        lines[#lines + 1] = ('#%d -- %s'):format(entry.id, entry.note or 'No details given')
    end

    Kora.notify.send({ title = 'Open House Calls', message = table.concat(lines, '\n'), type = 'info', duration = 8000 })
end)

-- server/housecall.lua reads the requester's coords server-side
-- (GetPlayerPed + GetEntityCoords) at submission time, no client round-trip
-- needed -- set a waypoint straight to them.
RegisterNetEvent('qbambulance:client:housecallAccepted', function(request)
    if type(request) ~= 'table' then return end
    Kora.notify.send({ title = 'House Call', message = ('Request #%d accepted.'):format(request.id), type = 'success' })

    if request.coords then
        SetNewWaypoint(request.coords.x, request.coords.y)
    end
end)
