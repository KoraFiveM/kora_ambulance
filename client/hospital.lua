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

for _, hospital in ipairs(Config.hospitals) do
    local bedOptions = {}
    for i in ipairs(hospital.beds) do
        bedOptions[#bedOptions + 1] = {
            label = ('Lie in bed %d'):format(i),
            icon = 'bed',
            action = function() lieInBed(hospital, i) end,
        }
    end

    QB.interact.addCircleZone(('qbambulance:beds:%s'):format(hospital.name), hospital.coords, 8.0, bedOptions, false)

    QB.interact.addCircleZone(('qbambulance:pharmacy:%s'):format(hospital.name), hospital.pharmacy, 3.0, {
        {
            label = 'Browse Pharmacy',
            icon = 'pill',
            action = function()
                exports.qbinventory:openInventory('shop', ('ambulance_pharmacy_%s'):format(hospital.name))
            end,
        },
    }, false)

    QB.interact.addCircleZone(('qbambulance:stash:%s'):format(hospital.name), hospital.stash.coords, 3.0, {
        {
            label = 'EMS Stash',
            icon = 'box',
            job = Config.job.name,
            action = function()
                exports.qbinventory:openInventory('stash', ('ambulance_stash_%s'):format(hospital.name))
            end,
        },
    }, false)

    if hospital.blip then
        QB.blips.create(hospital.coords, hospital.blip)
    end
end
