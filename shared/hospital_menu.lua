-- Hospital menu (shared) -- builds the list of interaction zones (check-in,
-- pharmacy, stash, duty toggle, garage) for ONE hospital entry. Pure Lua with no
-- natives so test/smoke/hospital_menu.lua can build the menu for every
-- configured hospital outside FiveM.
--
-- Every feature is optional: a hospital entry that omits (or malforms) a field
-- simply gets no zone for that feature, and never stops the others -- or the
-- other hospitals -- from being built.

HospitalMenu = HospitalMenu or {}

local function isPoint(value)
    local kind = type(value)
    return (kind == "table" or kind == "vector3" or kind == "vector4")
        and type(value.x) == "number" and type(value.y) == "number" and type(value.z) == "number"
end

local function radius(hospital, kind, fallback)
    local own = type(hospital.radius) == "table" and hospital.radius[kind]
    if type(own) == "number" and own > 0 then return own end
    local configured = Config.hospitalMenu and Config.hospitalMenu.radius and Config.hospitalMenu.radius[kind]
    if type(configured) == "number" and configured > 0 then return configured end
    return fallback
end

---The zone radius of one feature at one hospital (its own radius, else
---Config.hospitalMenu.radius, else `fallback`). The server checks use it too,
---so an option offered anywhere in its zone is also accepted there.
---@param hospital table
---@param kind string
---@param fallback number
---@return number
HospitalMenu.radius = radius

---@param hospital table one Config.hospitals entry; an optional `radius = { checkIn = n, duty = n, ... }`
---       overrides Config.hospitalMenu.radius for this hospital only (wide entrances)
---@param handlers table kind -> function(hospital) run on select for checkIn / pharmacy / stash / duty;
---       `garageOptions` -> function(hospital) returning the garage option list
---@return table[] zones { kind, coords, radius, options } -- never empty for a hospital with coords or checkIn
function HospitalMenu.build(hospital, handlers)
    local zones = {}
    if type(hospital) ~= "table" then return zones end
    handlers = handlers or {}

    local function add(kind, coords, fallbackRadius, options)
        if not isPoint(coords) or #options == 0 then return end
        zones[#zones + 1] = { kind = kind, coords = coords, radius = radius(hospital, kind, fallbackRadius), options = options }
    end

    local function run(kind)
        local handler = handlers[kind]
        return function() if handler then handler(hospital) end end
    end

    add("checkIn", isPoint(hospital.checkIn) and hospital.checkIn or hospital.coords,
        Config.hospitalCare.interactionRange, {
            { label = Kora.lang('ui.check_in_care'), icon = "bed", onSelect = run("checkIn") },
        })

    add("pharmacy", hospital.pharmacy, 3.0, {
        { label = Kora.lang('ui.browse_pharmacy'), icon = "pill", onSelect = run("pharmacy") },
    })

    add("stash", type(hospital.stash) == "table" and hospital.stash.coords or nil, 3.0, {
        {
            label = Kora.lang('ui.ems_stash'), icon = "box",
            canInteract = handlers.isEMS,
            onSelect = run("stash"),
        },
    })

    add("duty", hospital.duty, 2.0, {
        {
            label = Kora.lang('ui.toggle_duty'), icon = "briefcase",
            canInteract = handlers.isEMS,
            onSelect = run("duty"),
        },
    })

    add("garage", hospital.garage, 6.0, handlers.garageOptions and handlers.garageOptions(hospital) or {})

    return zones
end

---Registers the zones of `zones` whose kind is in `kinds`, first removing every
---zone this caller registered earlier. Registering again (kora_target
---restarting) therefore replaces the old zones instead of stacking a second,
---overlapping copy that lists every option twice.
---@param ids table caller-owned list of zone ids from the previous call (updated in place)
---@param zones table[] HospitalMenu.build result
---@param kinds table<string, boolean>
---@param add fun(definition: table): any returns the new zone id
---@param remove fun(id: any)
function HospitalMenu.register(ids, zones, kinds, add, remove)
    for i = #ids, 1, -1 do
        pcall(remove, ids[i])
        ids[i] = nil
    end
    for _, zone in ipairs(zones) do
        if kinds[zone.kind] then
            local id = add({ coords = zone.coords, radius = zone.radius, options = zone.options })
            if id ~= nil then ids[#ids + 1] = id end
        end
    end
end
