-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage, configuration
    --------------------------------------------------------------------------
    All health pools in GTA are floats:
        body   : 0..1000   (1000 = pristine, deformation scales as it drops)
        engine : -4000..1000 (1000 = healthy, <=0 = dead/fire, ~300 = smoking)
        petrol : 0..1000   (1000 = sealed, low = leaking, <0 = explodes)

    Tune the curve here. Lower thresholds = parts survive longer (more forgiving);
    raise them = the car falls apart sooner (more punishing).
]]

Config = {}

-- How often the driver's processing loop runs (ms). Lower = more responsive
-- detection but more CPU. 200-300ms is a good balance.
Config.Interval = 250

-- Replicate cosmetic breaks (bumpers/doors/wheels/leak) to every client via
-- statebags. Health pools always sync natively regardless of this flag.
Config.NetworkBreaks = true

-- Print debug info + enable the /vsfdmg command (driver-side state dump).
Config.Debug = false

-- Branded viscosity_core toast notifications on damage milestones (fuel leak,
-- engine running rough / stalling / dead). false = silent (physical effects only).
Config.Notify = true

-- Vehicle classes that are IMMUNE to this system (indices from GET_VEHICLE_CLASS).
-- 13 = Cycles, 14 = Boats, 15 = Helicopters, 16 = Planes, 21 = Trains.
Config.ImmuneClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

--==========================================================================--
-- IMPACT DETECTION
--==========================================================================--
-- Crashes are detected by DECELERATION (speed scrubbed in one tick), NOT by
-- body-health drop, because god-mode / invincible vehicles never lose body
-- health. The script then applies the damage itself with explicit setters, which
-- bypass invincibility. This makes the system work on ANY vehicle.
Config.Impact = {
    -- Crash = a drop from the PEAK speed in the last `window` ms down to now. This
    -- captures the full velocity change of a collision even though it spans several
    -- frames (a single 250ms tick would split one big crash into small ones).
    window   = 180,   -- ms rolling window to measure the speed drop over
    cooldown = 450,   -- ms after a crash before another can register (one hit = one event)

    -- Speed (m/s) lost to count as a crash. Hard braking scrubs only ~2-3 m/s, so 7 is safe.
    minDecel   = 7.0,
    -- m/s of scrub for FULL severity. Higher = more headroom, so "catastrophic" is
    -- genuinely rare. 40 ≈ a ~90mph slam to a dead stop.
    decelScale = 40.0,

    -- Severity at/above which a hit is CATASTROPHIC: wheels shear, fuel tank ruptures.
    -- 0.85 ≈ ~75mph+ into something solid with no run-off.
    catastrophic = 0.85,

    -- Health the SCRIPT removes on a max-severity hit (scaled by severity 0..1).
    -- Explicit setters, so these apply even to invincible / "strong" vehicles.
    bodyDamageMax   = 520.0,
    engineDamageMax = 540.0,

    -- Petrol: normal hard hits only nick the tank; a CATASTROPHIC hit ruptures it.
    petrolDamageMax   = 110.0,   -- mild tank damage per normal hard hit
    petrolMinSeverity = 0.50,
    tankRuptureTo     = 230.0,   -- catastrophic: tank slammed to here -> visibly gushes (not instant boom)
}

--==========================================================================--
-- COSMETIC DETACH THRESHOLDS (gated on BODY health)
-- A part can only detach once body health is at/below its value AND the impact
-- severity roll succeeds. chance = baseChance * severity.
--==========================================================================--
-- Each part detaches when the car is WORN DOWN (body <= body) OR a single hit is
-- VIOLENT enough (severity >= hardImpact, 0..1), so an 80mph head-on rips parts
-- off a pristine car, while gentle wear also sheds them over time.
Config.Cosmetic = {
    bumperFront = { body = 700, chance = 0.90, hardImpact = 0.45 },
    bumperRear  = { body = 700, chance = 0.90, hardImpact = 0.45 },

    -- Doors: 0 FL, 1 FR, 2 RL, 3 RR. Hood = 4, Trunk = 5.
    doors       = { body = 500, chance = 0.50, hardImpact = 0.70 },
    hood        = { body = 480, chance = 0.65, hardImpact = 0.55 },
    trunk       = { body = 480, chance = 0.50, hardImpact = 0.60 },
}

-- Wheels shear off ONLY on a catastrophic impact (Config.Impact.catastrophic).
-- Indices: 0 FL, 1 FR, 4 RL, 5 RR (2/3 are mid-axle on 6-wheelers).
Config.WheelShear = {
    chance              = 0.90,  -- chance to shear the impact-corner wheel on a catastrophic hit
    secondWheelSeverity = 0.97,  -- near-total wrecks can lose a second wheel
    secondWheelChance   = 0.50,
}

--==========================================================================--
-- ENGINE FAILURE STAGES (gated on ENGINE health)
--==========================================================================--
Config.Engine = {
    rough      = 320,   -- below: power loss + occasional sputter
    stall      = 160,   -- below: frequent stalls, hard to keep running
    dead       = 0,     -- at/below: engine will not run at all

    roughPower = 0.62,  -- SetVehicleCheatPowerIncrease multiplier while "rough"
    stallPower = 0.40,  -- power multiplier while "stalling"

    -- Sputter timing window (ms between cut-outs) and duration of each cut-out.
    sputterEveryMin = 2200,
    sputterEveryMax = 6500,
    sputterDurMin   = 180,
    sputterDurMax   = 650,

    -- When stalling, cut-outs come faster:
    stallEveryMin   = 900,
    stallEveryMax   = 2600,
}

--==========================================================================--
-- PETROL TANK / FUEL
--==========================================================================--
Config.Petrol = {
    leakBelow   = 700,   -- below: fuel trail leaks, tank health bleeds down
    drainRate   = 1.2,   -- petrol-health lost per tick while leaking

    starveBelow = 130,   -- below: engine fuel-starves (forces sputter/stall)
    starveEngineDrain = 4.0, -- engine-health lost per tick while starving

    -- Fire: when tank is critical AND engine is running, small per-tick chance
    -- to ignite. Set to 0 to disable fires entirely.
    fireBelow   = 90,
    fireChance  = 0.015,

    -- Optional integration with a fuel resource that reads a 'fuel' statebag
    -- (0-100). When leaking we also drain this. Set false if you don't use one.
    syncFuelStatebag = true,
    fuelDrainRate    = 0.15, -- fuel% lost per tick while leaking
}

--==========================================================================--
-- REPAIR DETECTION
-- If body health jumps UP by more than this between ticks, we treat it as a
-- repair (mechanic / SetVehicleFixed) and clear all recorded damage state.
--==========================================================================--
Config.RepairJumpThreshold = 60.0

--==========================================================================--
-- FIELD REPAIR ("limp home")
-- When the engine is dead, a player on foot can wrench at the engine bay to
-- patch it *just* enough to drive to a real mechanic. The patch lands the engine
-- in the "rough" band, so it runs but sputters, by design.
--==========================================================================--
Config.FieldRepair = {
    enabled        = true,
    availableBelow = 50.0,   -- engine health at/below which the patch is offered (dead-ish)
    interactDist   = 1.6,    -- metres from the engine bone to show the prompt
    requireStopped = true,   -- can't patch a rolling car
    duration       = 12000,  -- ms of wrenching

    limpHealth     = 250.0,  -- engine health after patch (rough band: runs, sputters)

    -- A leaking/empty tank would re-starve the engine, so the patch also tops the
    -- tank just enough to reach a shop (still in the leak band, keep moving).
    sealTankPartial = true,
    tankBuffer      = 90.0,  -- petrol health granted ABOVE Config.Petrol.starveBelow

    -- Patches allowed per wreck before it MUST be shop-repaired (0 = unlimited).
    maxUses = 2,

    animDict = 'mini@repair',
    animClip = 'fixing_a_ped',

    key        = 38,                                  -- E
    promptText = '[E] Patch engine  (field repair)',

    -- Optional: gate behind an inventory item (e.g. 'repairkit'). Leave false to
    -- disable; wiring to viscosity_inventory is a marked hook in fieldrepair.lua.
    requireItem = false,
}
