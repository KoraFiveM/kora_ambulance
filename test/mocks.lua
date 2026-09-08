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
    local playerStates = {}   -- src -> replicated state-bag values
    local entityStates = {}   -- entity -> replicated state-bag values
    local registeredExports = {}
    local entities = {}
    local nextEntity = 1000
    local minigameAuthorizations, minigameProofs = {}, {}
    local nextMinigameToken = 0

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
    function _G.vector3(x, y, z) return vector(x, y, z) end
    function _G.vector4(x, y, z, w) local v = vector(x, y, z); v.w = w; return v end
    function _G.IsDuplicityVersion() return true end
    function _G.joaat(s) return s end -- identity stub; only client/damage.lua's group-hash lookup needs real hashing, and that file is never dofile'd by these tests

    _G.os = os
    _G.math = math

    ---@param src integer
    local function ensure(src)
        players[src] = players[src] or {
            citizenid = ('CID%04d'):format(src),
            job = { name = 'unemployed', label = 'Civilian', onduty = false, grade = { name = 'Freelancer', level = 1 } },
            metadata = {},
            money = { cash = 0, bank = 0 },
            items = {},
            health = 200,
            armour = 0,
            coords = vector(0, 0, 0),
        }
        return players[src]
    end

    function _G.Player(src)
        playerStates[src] = playerStates[src] or {}
        local values = playerStates[src]
        return {
            state = setmetatable({
                set = function(_, key, value) values[key] = value end,
            }, { __index = values }),
        }
    end

    function _G.Entity(entity)
        entityStates[entity] = entityStates[entity] or {}
        local values = entityStates[entity]
        return {
            state = setmetatable({
                set = function(_, key, value) values[key] = value end,
            }, { __index = values }),
        }
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

    QB.blips = {
        create = function() return nil end,
        setInfo = function() end,
    }

    QB.fx = { started = {}, stopped = {} }
    function QB.fx.screenEffect(name, duration, looped)
        local handle = { id = #QB.fx.started + 1, name = name }
        QB.fx.started[#QB.fx.started + 1] = { handle = handle, duration = duration, looped = looped }
        return handle
    end
    function QB.fx.stopScreenEffect(handle)
        QB.fx.stopped[#QB.fx.stopped + 1] = handle
        return true
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

    QB.minigames = {
        authorizeProof = function(src, gameType, opts)
            nextMinigameToken = nextMinigameToken + 1
            local token = ('authorization:%d'):format(nextMinigameToken)
            minigameAuthorizations[token] = { src = src, gameType = gameType, opts = opts }
            return token
        end,
        consumeProof = function(src, proofToken, gameType, authorizationToken)
            local proof = minigameProofs[proofToken]
            if not proof or proof.src ~= src or proof.gameType ~= gameType
                or proof.authorization ~= authorizationToken then return false end
            minigameProofs[proofToken] = nil
            return true
        end,
    }

    QB.commands = {
        registry = {},
        add = function(name, _, _, _, handler) QB.commands.registry[name] = handler end,
        remove = function(name) QB.commands.registry[name] = nil end,
        refresh = function() end,
        list = function() return {} end,
    }

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
    -- Job types mirror qbcore/shared/jobs.lua. Dispatch calls target the TYPE,
    -- so a fire department registered with type='ems' answers the same radio.
    local JOB_TYPES = { police = 'leo', sheriff = 'leo', ambulance = 'ems', tow = 'recovery' }
    function qbcore:getPlayersByJobType(jobType, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            if p.job and JOB_TYPES[p.job.name] == jobType and (not onDutyOnly or p.job.onduty) then
                out[#out + 1] = src
            end
        end
        table.sort(out)
        return out
    end
    function qbcore:getDutyCountByType(jobType) return #qbcore:getPlayersByJobType(jobType, true) end
    function qbcore:alert(payload)
        local count = 0
        for _, jobName in ipairs(payload.jobs or {}) do count = count + #qbcore:getPlayersByJob(jobName, true) end
        for _, jobType in ipairs(payload.jobTypes or {}) do count = count + #qbcore:getPlayersByJobType(jobType, true) end
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
        addSphereZone = function(self, definition)
            table.insert(qbtarget.calls, { kind = 'sphere', definition = definition })
        end,
        addModel = function(self, model, options, distance)
            table.insert(qbtarget.calls, { kind = 'model', model = model, options = options, distance = distance })
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

    -- qbdispatch owns the call lifecycle; qbambulance only raises calls through
    -- it. Recorded rather than simulated -- what these tests care about is the
    -- payload this resource builds, not qbdispatch's storage (which has its own
    -- suite).
    local dispatchCalls = {}
    local dispatchClosed = {}
    local playerAlertDefinitions = {}
    local nextCallId = 0
    local qbdispatch = {}
    function qbdispatch:createCall(payload)
        nextCallId = nextCallId + 1
        payload.id = nextCallId
        dispatchCalls[#dispatchCalls + 1] = payload

        local recipients = {}
        for _, jobName in ipairs(payload.jobs or {}) do
            for _, src in ipairs(qbcore:getPlayersByJob(jobName, true)) do recipients[src] = true end
        end
        for _, jobType in ipairs(payload.jobTypes or {}) do
            for _, src in ipairs(qbcore:getPlayersByJobType(jobType, true)) do recipients[src] = true end
        end
        local count = 0
        for _ in pairs(recipients) do count = count + 1 end
        return nextCallId, count
    end
    function qbdispatch:registerPlayerAlert(key, definition)
        playerAlertDefinitions[key] = definition
        return true
    end
    function qbdispatch:createPlayerCall(src, key)
        local definition = playerAlertDefinitions[key]
        if not definition then return false, 'unknown player alert type' end

        local payload = {}
        for field, value in pairs(definition) do payload[field] = value end
        payload.coords = players[src] and players[src].coords or nil
        payload.data = { incident = key, reporter = src }
        return self:createCall(payload)
    end
    function qbdispatch:getCalls(filter)
        local out = {}
        for _, call in ipairs(dispatchCalls) do
            if not dispatchClosed[call.id] and (not filter or not filter.service
                or (call.jobTypes and call.jobTypes[1] == filter.service)) then
                out[#out + 1] = call
            end
        end
        return out
    end
    function qbdispatch:closeCall(id, reason) dispatchClosed[id] = reason or true; return true end
    function qbdispatch:setTheme() return true end

    _G.exports = setmetatable({ qbcore = qbcore, qbtarget = qbtarget, qbinventory = qbinventory,
                                qbdispatch = qbdispatch }, {
        __index = function() return setmetatable({}, { __index = function() return function() end end }) end,
        __call = function(_, name, fn) registeredExports[name] = fn end,
    })

    function _G.CreateVehicle(model, x, y, z, heading)
        nextEntity = nextEntity + 1
        entities[nextEntity] = { model = model, type = 2, coords = vector(x, y, z), heading = heading, bucket = 0 }
        return nextEntity
    end
    function _G.CreateObjectNoOffset(model, x, y, z, _networked, _mission, _dynamic)
        nextEntity = nextEntity + 1
        entities[nextEntity] = { model = model, type = 3, coords = vector(x, y, z), heading = 0, bucket = 0 }
        return nextEntity
    end
    function _G.DoesEntityExist(entity) return entities[entity] ~= nil or players[entity] ~= nil end
    function _G.DeleteEntity(entity) entities[entity] = nil end
    function _G.NetworkGetNetworkIdFromEntity(entity) return entities[entity] and entity or 0 end
    function _G.NetworkGetEntityFromNetworkId(networkId) return entities[networkId] and networkId or 0 end
    function _G.SetEntityRoutingBucket(entity, bucket) if entities[entity] then entities[entity].bucket = bucket end end
    function _G.GetEntityRoutingBucket(entity) return entities[entity] and entities[entity].bucket or 0 end
    function _G.SetVehicleNumberPlateText(entity, plate) if entities[entity] then entities[entity].plate = plate end end
    function _G.GetEntityType(entity) return entities[entity] and entities[entity].type or 0 end
    function _G.GetEntityModel(entity) return entities[entity] and entities[entity].model or 0 end
    function _G.GetOffsetFromEntityInWorldCoords(entity, x, y, z)
        local coords = GetEntityCoords(entity)
        return vector(coords.x + x, coords.y + y, coords.z + z)
    end
    function _G.FreezeEntityPosition(entity, frozen) if entities[entity] then entities[entity].frozen = frozen == true end end
    function _G.SetEntityHeading(entity, heading) if entities[entity] then entities[entity].heading = heading end end
    function _G.GetPlayerRoutingBucket(_) return 0 end
    function _G.GetPlayerPed(src) return players[src] and src or 0 end
    function _G.GetEntityCoords(entity)
        if players[entity] then return players[entity].coords end
        return entities[entity] and entities[entity].coords or vector(0, 0, 0)
    end
    function _G.GetEntityHealth(ped) return players[ped] and players[ped].health or 0 end
    function _G.GetEntityMaxHealth(ped) return players[ped] and (players[ped].maxHealth or 200) or 200 end
    function _G.SetEntityHealth(ped, value) if players[ped] then players[ped].health = value end end
    function _G.GetPedArmour(ped) return players[ped] and players[ped].armour or 0 end
    function _G.SetPedArmour(ped, value) if players[ped] then players[ped].armour = value end end

    return {
        players = players,
        playerStates = playerStates,
        entityStates = entityStates,
        exports = registeredExports,
        entities = entities,
        ensurePlayer = ensure,
        clientEvents = clientEvents,
        serverEvents = serverEvents,
        resourceStates = resourceStates,
        QB = QB,
        qbcore = qbcore,
        qbdispatch = qbdispatch,
        dispatchCalls = dispatchCalls,
        playerAlertDefinitions = playerAlertDefinitions,
        lastDispatchCall = function() return dispatchCalls[#dispatchCalls] end,
        qbtarget = qbtarget,
        qbinventory = qbinventory,
        setHealth = function(src, health) ensure(src).health = health end,
        setCoords = function(src, x, y, z) ensure(src).coords = vector(x, y, z) end,
        advanceTime = function(ms) clock = clock + ms end,
        issueMinigameProof = function(src, gameType, authorization)
            nextMinigameToken = nextMinigameToken + 1
            local token = ('proof:%d'):format(nextMinigameToken)
            minigameProofs[token] = { src = src, gameType = gameType, authorization = authorization }
            return token
        end,
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
