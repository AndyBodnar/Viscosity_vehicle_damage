-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage — effects & networking
    --------------------------------------------------------------------------
    A "break" is a string key applied to a vehicle:
        bumperF | bumperR | door:0..5 | wheel:0/1/4/5
    (door:4 = hood, door:5 = trunk)

    The driver RECORDS breaks (apply locally + write to the replicated statebag).
    Every other client mirrors them through the statebag change handler so the
    wreck looks identical for everyone, including late joiners.

    Health pools (body/engine/petrol) are intentionally NOT in here — they sync
    natively, so the leaking-fuel trail and smoke appear everywhere on their own.
]]

Effects = {}

local STATE_KEY = 'vsf_vehdamage'

-- appliedCache[netId] = { [key] = true } — guards against re-applying a break
-- (the driver applies immediately, then the statebag echo would otherwise repeat).
local appliedCache = {}

local function netIdOf(veh)
    if NetworkGetEntityIsNetworked(veh) then
        return NetworkGetNetworkIdFromEntity(veh)
    end
    return ('local:%d'):format(veh) -- non-networked (e.g. menu/preview) vehicles
end

--==========================================================================--
-- LOW-LEVEL: perform the actual native for one break key on the LOCAL machine.
--==========================================================================--
local function doBreak(veh, key)
    if not DoesEntityExist(veh) then return end

    if key == 'bumperF' or key == 'bumperR' then
        -- Bumpers have no dedicated native — drive heavy localized deformation at
        -- the model's front/rear extent so the panel shears off. GetModelDimensions
        -- makes this work for any vehicle regardless of length.
        local minD, maxD = GetModelDimensions(GetEntityModel(veh))
        local y = (key == 'bumperF') and maxD.y or minD.y
        SetVehicleDamage(veh, 0.0, y, 0.35, 1000.0, 2.2, false)
        return
    end

    local doorIdx = key:match('^door:(%d+)$')
    if doorIdx then
        -- false = detach the door and let it physically fall (true would delete it).
        SetVehicleDoorBroken(veh, tonumber(doorIdx), false)
        return
    end

    local wheelIdx = key:match('^wheel:(%d+)$')
    if wheelIdx then
        wheelIdx = tonumber(wheelIdx)
        SetVehicleTyreBurst(veh, wheelIdx, true, 1000.0)
        -- (vehicle, wheel, leaveDebris, deleteWheel, unknown, putOnFire)
        BreakOffVehicleWheel(veh, wheelIdx, true, false, true, false)
        return
    end
end

-- Apply a break locally, once. Returns true if it was newly applied.
function Effects.ApplyLocal(veh, key)
    local id = netIdOf(veh)
    local set = appliedCache[id]
    if not set then set = {}; appliedCache[id] = set end
    if set[key] then return false end
    set[key] = true
    doBreak(veh, key)
    return true
end

--==========================================================================--
-- DRIVER SIDE: record a break — apply locally + replicate via statebag.
--==========================================================================--
function Effects.Record(veh, key)
    if not Effects.ApplyLocal(veh, key) then return end -- already broken (or applied), skip

    if not Config.NetworkBreaks then return end
    if not NetworkGetEntityIsNetworked(veh) then return end
    -- StateBag strict mode blocks client writes, so the SERVER owns the write.
    -- We've already applied locally above for instant feedback; this replicates it.
    TriggerServerEvent('vvd:break', NetworkGetNetworkIdFromEntity(veh), key)
end

-- Has this break already been recorded on the vehicle? (used by the driver loop
-- to avoid re-rolling a part that's already gone).
function Effects.Has(veh, key)
    local data = Entity(veh).state[STATE_KEY]
    return type(data) == 'table' and data[key] == true
end

-- Wipe damage state — called on repair.
function Effects.Clear(veh)
    appliedCache[netIdOf(veh)] = nil
    if Config.NetworkBreaks and DoesEntityExist(veh) and NetworkGetEntityIsNetworked(veh) then
        TriggerServerEvent('vvd:clear', NetworkGetNetworkIdFromEntity(veh))
    end
end

--==========================================================================--
-- REMOTE SIDE: mirror any vehicle's recorded breaks onto this client.
--==========================================================================--
AddStateBagChangeHandler(STATE_KEY, nil, function(bagName, _key, value)
    local veh = GetEntityFromStateBagName(bagName)
    if veh == 0 or not DoesEntityExist(veh) then return end

    -- Cleared (repaired): reset our local applied-cache so future breaks re-apply.
    if type(value) ~= 'table' then
        appliedCache[netIdOf(veh)] = nil
        return
    end

    for key, on in pairs(value) do
        if on then Effects.ApplyLocal(veh, key) end
    end
end)
