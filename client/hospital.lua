-- Hospital (client realm) -- multi-hospital check-in/bed system, pharmacy,
-- and EMS stash zones. The pharmacy shop / EMS stash themselves are
-- registered server-side (server/duty.lua) -- this file only wires up the
-- world-space interaction points via QB.interact.

local inBed = false

local function lieInBed(hospital, bedIndex)
    if inBed then return end
    inBed = true

    local bed = hospital.beds[bedIndex]
    local ped = PlayerPedId()

    TaskStartScenarioAtCoords(ped, 'PROP_HUMAN_BUM_BIN', bed.x, bed.y, bed.z, bed.w, 0, true, false)

    QB.notify.send({ title = hospital.label, message = 'Resting -- stand up to leave.', type = 'info' })

    CreateThread(function()
        while inBed do
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            if IsControlJustPressed(0, 38) then break end -- E to get up
            Wait(0)
        end

        ClearPedTasks(PlayerPedId())
        inBed = false
    end)
end

local function registerHospitalTargets()
for _, hospital in ipairs(Config.hospitals) do
    local bedOptions = {}
    for i in ipairs(hospital.beds) do
        bedOptions[#bedOptions + 1] = {
            label = ('Lie in bed %d'):format(i),
            icon = 'bed',
            onSelect = function() lieInBed(hospital, i) end,
        }
    end

    exports.qbtarget:addSphereZone({
        coords = hospital.coords,
        radius = 8.0,
        options = bedOptions,
    })

    exports.qbtarget:addSphereZone({
        coords = hospital.pharmacy,
        radius = 3.0,
        options = {
            {
                label = 'Browse Pharmacy',
                icon = 'pill',
                onSelect = function()
                    exports.qbinventory:openInventory('shop', ('ambulance_pharmacy_%s'):format(hospital.name))
                end,
            },
        },
    })

    exports.qbtarget:addSphereZone({
        coords = hospital.stash.coords,
        radius = 3.0,
        options = {
            {
                label = 'EMS Stash',
                icon = 'box',
                canInteract = function()
                    local job = exports.qbcore:getJob()
                    return job ~= nil and job.name == Config.job.name
                end,
                onSelect = function()
                    exports.qbinventory:openInventory('stash', ('ambulance_stash_%s'):format(hospital.name))
                end,
            },
        },
    })

    if hospital.blip then
        local blip = QB.blips.create(hospital.coords, hospital.blip)
        if blip and not hospital.blip.info then
            QB.blips.setInfo(blip, {
                title = hospital.label,
                rows = {
                    { kind = 'wrappedText', value = 'Medical services and EMS facilities are available here.' },
                },
            })
        end
    end
end
end

registerHospitalTargets()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'qbtarget' then registerHospitalTargets() end
end)
