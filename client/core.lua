-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage — viscosity_core integration shim
    --------------------------------------------------------------------------
    Every call into the framework lives here so the damage logic stays decoupled
    from core's export names. FiveM gives each resource its own Lua state, so we
    reach core only through its registered exports — never its `Vsf` globals.
]]

VDCore = {}

-- True once the player has a spawned character (don't process damage / show the
-- field-repair prompt during char-select or the spawn cinematic).
function VDCore.Ready()
    return exports.viscosity_core:IsLoaded() == true
end

function VDCore.PlayerData()
    return exports.viscosity_core:GetPlayerData() or {}
end

-- Branded violet toast. opts = { title?, message, type?, duration?, icon? }
-- type: "info" | "success" | "error" | "warning" | "police"
function VDCore.Notify(opts)
    if type(opts) == 'string' then opts = { message = opts } end
    exports.viscosity_core:Notify(opts)
end
