-- Mocks for smoke-testing qbambulance modules under plain lua5.4 (no FiveM,
-- no DB, no qbcore/qblib actually running). Unlike qbcore/qblib's own test
-- mocks (which mock FiveM natives to test THEIR real internals), qbambulance
-- is a CONSUMER resource -- everything it calls on qbcore/qblib crosses an
-- exports boundary, so this only needs to fake that boundary: a colon-
-- callable `exports.qbcore` backed by a tiny in-memory player store, and a
-- `QB` table with the handful of qblib primitives qbambulance's server code
-- actually calls (status/notify/events/callback/commands). Follows the same
-- install()/fireEvent() shape as qbcore's own test/mocks.lua so the smoke
-- tests read the same way.

local M = {}

function M.install()
    local eventHandlers = {}
    local netHandlers = {}
    local clientEvents = {}   -- recorded TriggerClientEvent
    local serverEvents = {}   -- recorded TriggerServerEvent
    local resourceStates = {}
    local players = {}        -- src -> { job, metadata, money, items }

    _G.source = nil

    function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
    function _G.RegisterNetEvent(name, cb) if cb then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], cb) end end
    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end
    function _G.TriggerClientEvent(name, target, ...) table.insert(clientEvents, { name = name, target = target, args = { ... } }) end
    function _G.TriggerServerEvent(name, ...) table.insert(serverEvents, { name = name, args = { ... } }) end

    local threads = {}
    function _G.CreateThread(fn) table.insert(threads, coroutine.create(fn)) end
    function _G.Wait(_) end
    local clock = 0
    function _G.GetGameTimer() clock = clock + 16; return clock end
    function _G.GetInvokingResource() return nil end
    function _G.GetCurrentResourceName() return 'qbambulance' end
    function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
    local VEC3 = {}
    VEC3.__index = VEC3
    VEC3.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, VEC3) end
    VEC3.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    local function vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC3) end
    function _G.vector4(x, y, z, w) local v = vector(x, y, z); v.w = w; return v end
    function _G.IsDuplicityVersion() return true end
    function _G.joaat(s) return s end -- identity stub; only client/damage.lua's group-hash lookup needs real hashing, and that file is never dofile'd by these tests

    _G.os = os
    _G.math = math

    ---@param src integer
    local function ensure(src)
        players[src] = players[src] or {
            job = { name = 'unemployed', label = 'Civilian', onduty = false, grade = { name = 'Freelancer', level = 1 } },
            metadata = {},
            money = { cash = 0, bank = 0 },
            items = {},
        }
        return players[src]
    end

    -- --- fake qblib QB ---
    local QB = {}

    QB.status = {
        registry = {},
        applied = {},   -- src -> name -> {severity, expiresAt}
        registerEffect = function(name, def) QB.status.registry[name] = def end,
        getEffectDef = function(name) return QB.status.registry[name] end,
        apply = function(target, name, opts)
            QB.status.applied[target] = QB.status.applied[target] or {}
            QB.status.applied[target][name] = { severity = opts and opts.severity }
            return true
        end,
        remove = function(target, name)
            local bucket = QB.status.applied[target]
            if not bucket or not bucket[name] then return false end
            bucket[name] = nil
            return true
        end,
        isActive = function(target, name)
            local bucket = QB.status.applied[target]
            return bucket ~= nil and bucket[name] ~= nil
        end,
        getActive = function(target)
            local bucket = QB.status.applied[target] or {}
            local out = {}
            for name, entry in pairs(bucket) do out[#out + 1] = { name = name, severity = entry.severity } end
            return out
        end,
    }

    QB.notify = { sent = {}, send = function(...) end }
    function QB.notify.send(...)
        table.insert(QB.notify.sent, { ... })
    end

    QB.events = {
        registry = {},        -- name -> handler(src, ...)
        register = function(name, handler) QB.events.registry[name] = handler end,
        trigger = function() end,
        push = function(target, name, ...) table.insert(clientEvents, { name = 'push:' .. name, target = target, args = { ... } }) end,
        onPush = function() end,
    }

    QB.callback = {
        registry = {},         -- name -> handler(src, ...) [server-registered]
        clientHandlers = {},   -- name -> handler(...) [test-stubbed, for server->client QB.callback.trigger]
        register = function(name, handler) QB.callback.registry[name] = handler end,
        trigger = function(target, name, ...)
            local handler = QB.callback.clientHandlers[name]
            if not handler then return nil end
            return handler(...)
        end,
    }

    QB.commands = { add = function() end, remove = function() end, refresh = function() end, list = function() return {} end }

    _G.QB = QB

    -- --- fake exports.qbcore -- a colon-callable object backed by `players` ---
    local qbcore = {}

    function qbcore:getJob(src) return ensure(src).job end
    function qbcore:getPlayerData(src, path)
        local player = players[src]
        if not player then return nil end
        if not path then return player end
        local value = player
        for _, key in ipairs(path) do value = type(value) == 'table' and value[key] or nil end
        return value
    end
    function qbcore:setJobDuty(src, onDuty) ensure(src).job.onduty = onDuty; return true end
    function qbcore:getMetaData(src, key) return ensure(src).metadata[key] end
    function qbcore:setMetaData(src, key, value) ensure(src).metadata[key] = value; return true end
    function qbcore:getMoney(src, account) return ensure(src).money[account] or 0 end
    function qbcore:addMoney(src, account, amount)
        local p = ensure(src); p.money[account] = (p.money[account] or 0) + amount; return true
    end
    function qbcore:removeMoney(src, account, amount)
        local p = ensure(src); p.money[account] = (p.money[account] or 0) - amount; return true
    end
    function qbcore:getPlayers()
        local out = {}
        for src in pairs(players) do out[#out + 1] = src end
        table.sort(out)
        return out
    end
    function qbcore:getPlayersByJob(name, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            if p.job.name == name and (not onDutyOnly or p.job.onduty) then out[#out + 1] = src end
        end
        table.sort(out)
        return out
    end
    function qbcore:hasItem(src, name) return (ensure(src).items[name] or 0) > 0 end
    function qbcore:removeItem(src, name, amount)
        local p = ensure(src)
        p.items[name] = math.max(0, (p.items[name] or 0) - (amount or 1))
        return true
    end
    function qbcore:createUseable(name, handler) qbcore.useables = qbcore.useables or {}; qbcore.useables[name] = handler end
    function qbcore:useItem(src, name)
        local handler = qbcore.useables and qbcore.useables[name]
        if handler then handler(src, { name = name }) end
    end
    function qbcore:createVehicle(_citizenid, _model, _plate, _job, _extra) return true end
    function qbcore:spawnVehicle(_src, _plate, _coords, _heading) return 12345 end
    function qbcore:deleteVehicle(_plate) return true end
    function qbcore:storeVehicle(_plate, _snapshot) return true end
    function qbcore:reset(src) local p = ensure(src); p.metadata.hunger = 100; p.metadata.thirst = 100; p.metadata.stress = 0 end
    function qbcore:alert(payload)
        local count = 0
        for _, jobName in ipairs(payload.jobs) do count = count + #qbcore:getPlayersByJob(jobName, true) end
        return count
    end
    function qbcore:addCommand(_name, _help, _args, _argsRequired, _handler, _permission) end
    function qbcore:getShared(_name, _key) return nil end
    function qbcore:registerShared(_name, _key, _record) end

    -- Fake exports.qbtarget -- just records addGlobalType calls so provider-
    -- restart re-registration tests can assert it was called again, rather
    -- than actually doing anything with the option lists passed in.
    local qbtarget
    qbtarget = {
        calls = {},
        addGlobalType = function(self, kind, options, distance)
            table.insert(qbtarget.calls, { kind = kind, options = options, distance = distance })
        end,
    }

    -- Fake exports.qbinventory -- records registerShop/registerStash calls
    -- (server/duty.lua's hospital-fixture registration) so provider-restart
    -- re-registration tests can assert on call counts. Any other method
    -- falls through to a harmless stub via __index, same as before.
    local qbinventory
    qbinventory = {
        calls = {},
        registerShop = function(self, ...) table.insert(qbinventory.calls, { fn = 'registerShop', args = { ... } }) end,
        registerStash = function(self, ...) table.insert(qbinventory.calls, { fn = 'registerStash', args = { ... } }) end,
    }
    setmetatable(qbinventory, { __index = function() return function() end end })

    _G.exports = setmetatable({ qbcore = qbcore, qbtarget = qbtarget, qbinventory = qbinventory }, {
        __index = function() return setmetatable({}, { __index = function() return function() end end }) end,
    })

    function _G.GetPlayerRoutingBucket(_) return 0 end
    function _G.GetPlayerPed(src) return players[src] and src or 0 end
    function _G.GetEntityCoords(_) return vector(0, 0, 0) end

    return {
        players = players,
        ensurePlayer = ensure,
        clientEvents = clientEvents,
        serverEvents = serverEvents,
        resourceStates = resourceStates,
        QB = QB,
        qbcore = qbcore,
        qbtarget = qbtarget,
        qbinventory = qbinventory,
        step = function() for _, co in ipairs(threads) do coroutine.resume(co) end end,
        fireEvent = function(name, src, ...)
            local prev = _G.source
            _G.source = src
            _G.TriggerEvent(name, ...)
            _G.source = prev
        end,
        lastClient = function(name)
            for i = #clientEvents, 1, -1 do if clientEvents[i].name == name then return clientEvents[i] end end
        end,
    }
end

return M
