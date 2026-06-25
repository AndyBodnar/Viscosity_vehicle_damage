-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage — server (statebag authority)
    --------------------------------------------------------------------------
    With sv_stateBagStrictMode enabled, clients can't write statebags. Clients
    REPORT damage via net events; the server validates (entity exists + reporter
    is actually near the vehicle, so a client can't forge damage on a car across
    the map) and writes the replicated statebag that every client mirrors.
]]

local STATE_KEY = 'vsf_vehdamage'   -- table of break keys -> true
local USE_KEY   = 'vsf_fieldrepairs' -- field-repair counter

-- Reject reports from a player who isn't near the vehicle (anti-spoof).
local function reporterNear(src, veh, maxDist)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local pc, vc = GetEntityCoords(ped), GetEntityCoords(veh)
    return #(pc - vc) <= (maxDist or 10.0)
end

local function resolve(netId)
    if type(netId) ~= 'number' then return 0 end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == 0 or not DoesEntityExist(veh) then return 0 end
    return veh
end

-- Record one cosmetic break (merge into the entity's break table).
RegisterNetEvent('vvd:break', function(netId, key)
    local src = source
    if type(key) ~= 'string' then return end
    local veh = resolve(netId)
    if veh == 0 or not reporterNear(src, veh) then return end

    local data = Entity(veh).state[STATE_KEY]
    if type(data) ~= 'table' then data = {} end
    if data[key] then return end
    data[key] = true
    Entity(veh).state:set(STATE_KEY, data, true) -- replicated to all clients
end)

-- Clear all recorded damage (repair).
RegisterNetEvent('vvd:clear', function(netId)
    local src = source
    local veh = resolve(netId)
    if veh == 0 or not reporterNear(src, veh) then return end
    Entity(veh).state:set(STATE_KEY, nil, true)
    Entity(veh).state:set(USE_KEY, nil, true)
end)

-- Increment the field-repair counter (enforces FieldRepair.maxUses per wreck).
RegisterNetEvent('vvd:fieldRepair', function(netId)
    local src = source
    local veh = resolve(netId)
    if veh == 0 or not reporterNear(src, veh, 6.0) then return end
    local used = (Entity(veh).state[USE_KEY] or 0) + 1
    Entity(veh).state:set(USE_KEY, used, true)
end)
