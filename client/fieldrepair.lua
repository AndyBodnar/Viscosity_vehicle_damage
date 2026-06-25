-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage, field repair ("limp home")
    --------------------------------------------------------------------------
    On foot + standing at a dead engine -> [E] prompt -> wrench emote (ox_lib
    progressCircle) -> engine patched into the "rough" band so it runs but
    sputters, just enough to reach a real mechanic. Optionally tops a ruptured
    tank a little so fuel starvation doesn't instantly re-kill it.

    Uses ox_lib (already ensured server-wide). No ox_target dependency.
]]

local FR = Config.FieldRepair

if not FR.enabled then return end

local USE_KEY = 'vsf_fieldrepairs' -- replicated per-vehicle patch counter

-- World position of the engine bay for any model (engine bone, then bonnet,
-- then a forward offset as a last resort).
local function engineCoords(veh)
    local bone = GetEntityBoneIndexByName(veh, 'engine')
    if bone == -1 then bone = GetEntityBoneIndexByName(veh, 'bonnet') end
    if bone ~= -1 then
        return GetWorldPositionOfEntityBone(veh, bone)
    end
    local _, maxD = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, maxD.y, 0.0)
end

-- Is this vehicle a valid field-repair candidate right now?
local function isCandidate(veh)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    if GetVehicleEngineHealth(veh) > FR.availableBelow then return false end
    if FR.requireStopped and GetEntitySpeed(veh) > 0.5 then return false end
    if FR.maxUses > 0 then
        local used = Entity(veh).state[USE_KEY] or 0
        if used >= FR.maxUses then return false end
    end
    return true
end

-- Take ownership so SetVehicle* writes apply + replicate.
local function ensureControl(veh)
    if NetworkHasControlOfEntity(veh) then return true end
    for _ = 1, 20 do
        NetworkRequestControlOfEntity(veh)
        if NetworkHasControlOfEntity(veh) then return true end
        Wait(40)
    end
    return NetworkHasControlOfEntity(veh)
end

local function doFieldRepair(veh)
    -- HOOK: gate on an inventory item here if FR.requireItem is set, e.g.
    --   if FR.requireItem and not exports.viscosity_inventory:HasItem(FR.requireItem) then
    --       lib.notify({ description = 'You need a '..FR.requireItem, type = 'error' }); return
    --   end

    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, veh, 1000)
    Wait(300)

    local ok = lib.progressCircle({
        duration    = FR.duration,
        label       = 'Patching the engine…',
        position    = 'bottom',
        useWhileDead = false,
        canCancel   = true,
        disable     = { move = true, car = true, combat = true, sprint = true },
        anim        = { dict = FR.animDict, clip = FR.animClip, flag = 1 },
    })

    if not ok then
        VDCore.Notify({ title = 'Field Repair', message = 'Repair interrupted.', type = 'error' })
        return
    end

    if not ensureControl(veh) then
        VDCore.Notify({ title = 'Field Repair', message = 'Can\'t reach the engine right now.', type = 'error' })
        return
    end

    -- Patch the engine into the "rough" band: runs, but rough/sputtery.
    SetVehicleEngineHealth(veh, FR.limpHealth)
    SetVehicleUndriveable(veh, false)

    -- A leaking/empty tank would re-starve it; grant a small buffer to reach a shop.
    if FR.sealTankPartial then
        local minSafe = Config.Petrol.starveBelow + FR.tankBuffer
        if GetVehiclePetrolTankHealth(veh) < minSafe then
            SetVehiclePetrolTankHealth(veh, minSafe)
        end
    end

    -- Count the patch against this wreck (server owns the statebag write).
    if FR.maxUses > 0 then
        local used = (Entity(veh).state[USE_KEY] or 0) + 1
        if NetworkGetEntityIsNetworked(veh) then
            TriggerServerEvent('vvd:fieldRepair', NetworkGetNetworkIdFromEntity(veh))
        end
        local left = FR.maxUses - used
        VDCore.Notify({
            title = 'Field Repair',
            message = left > 0
                and ('Patched, get it to a shop. (%d temp fix%s left)'):format(left, left == 1 and '' or 'es')
                or  'Patched, this is the last time. Get it to a shop NOW.',
            type = left > 0 and 'success' or 'warning',
        })
    else
        VDCore.Notify({
            title = 'Field Repair',
            message = 'Patched the engine just enough to limp to a shop. Don\'t push it.',
            type = 'success',
        })
    end
end

--==========================================================================--
-- Prompt loop: scan slowly when idle; tighten to per-frame at a dead engine.
--==========================================================================--
CreateThread(function()
    local shown = false
    local function hide() if shown then lib.hideTextUI(); shown = false end end

    while true do
        local wait = 600
        local ped = PlayerPedId()

        if not IsPedInAnyVehicle(ped, false) and VDCore.Ready() then
            local pc = GetEntityCoords(ped)
            local veh = GetClosestVehicle(pc.x, pc.y, pc.z, 4.0, 0, 71)

            if isCandidate(veh) then
                local dist = #(pc - engineCoords(veh))
                if dist <= FR.interactDist then
                    wait = 0
                    if not shown then lib.showTextUI(FR.promptText, { position = 'left-center' }); shown = true end
                    if IsControlJustReleased(0, FR.key) then
                        hide()
                        doFieldRepair(veh)
                    end
                else
                    hide()
                end
            else
                hide()
            end
        else
            hide()
        end

        Wait(wait)
    end
end)
