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

local function radius(kind, fallback)
    local configured = Config.hospitalMenu and Config.hospitalMenu.radius and Config.hospitalMenu.radius[kind]
    if type(configured) == "number" and configured > 0 then return configured end
    return fallback
end

---@param hospital table one Config.hospitals entry
---@param handlers table kind -> function(hospital) run on select for checkIn / pharmacy / stash / duty;
---       `garageOptions` -> function(hospital) returning the garage option list
---@return table[] zones { kind, coords, radius, options } -- never empty for a hospital with coords or checkIn
function HospitalMenu.build(hospital, handlers)
    local zones = {}
    if type(hospital) ~= "table" then return zones end
    handlers = handlers or {}

    local function add(kind, coords, fallbackRadius, options)
        if not isPoint(coords) or #options == 0 then return end
        zones[#zones + 1] = { kind = kind, coords = coords, radius = radius(kind, fallbackRadius), options = options }
    end

    local function run(kind)
        local handler = handlers[kind]
        return function() if handler then handler(hospital) end end
    end

    add("checkIn", isPoint(hospital.checkIn) and hospital.checkIn or hospital.coords,
        Config.hospitalCare.interactionRange, {
            { label = "Check In for Care", icon = "bed", onSelect = run("checkIn") },
        })

    add("pharmacy", hospital.pharmacy, 3.0, {
        { label = "Browse Pharmacy", icon = "pill", onSelect = run("pharmacy") },
    })

    add("stash", type(hospital.stash) == "table" and hospital.stash.coords or nil, 3.0, {
        {
            label = "EMS Stash", icon = "box",
            canInteract = handlers.isEMS,
            onSelect = run("stash"),
        },
    })

    add("duty", hospital.duty, 2.0, {
        {
            label = "Toggle Duty", icon = "briefcase",
            canInteract = handlers.isEMS,
            onSelect = run("duty"),
        },
    })

    add("garage", hospital.garage, 6.0, handlers.garageOptions and handlers.garageOptions(hospital) or {})

    return zones
end
