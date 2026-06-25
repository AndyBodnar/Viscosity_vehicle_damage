-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
--[[
    viscosity_vehicledamage, driver-side processing loop
    --------------------------------------------------------------------------
    Only the DRIVER of a vehicle runs this (they own its physics). Each tick we:
      1. Detect impacts by diffing body health, scaled by speed -> "severity".
      2. Bleed some impact into the engine + petrol tank (hard hits wreck more
         than panels).
      3. Roll directional cosmetic detaches (bumper / door / hood / trunk / wheel),
         gated by body-health thresholds and severity.
      4. Run the petrol leak -> fuel-starvation chain.
      5. Stage engine failure: power loss -> sputter -> stall -> dead.
    Body/engine/petrol health sync natively; cosmetic breaks sync via Effects.
]]

local C = Config

local function isImmune(veh)
    return C.ImmuneClasses[GetVehicleClass(veh)] == true
end

-- Engine failure stages for branded milestone toasts (fire on getting WORSE only).
local STAGE_RANK = { ok = 0, rough = 1, stall = 2, dead = 3 }
local STAGE_MSG = {
    rough = { title = 'Engine', message = 'Running rough, get it to a mechanic.', type = 'warning' },
    stall = { title = 'Engine', message = 'Sputtering, it\'s about to stall.',    type = 'warning' },
    dead  = { title = 'Engine', message = 'The engine\'s dead.',                    type = 'error'   },
}

local function engineStage(engine, petrol)
    if engine <= C.Engine.dead then return 'dead' end
    if engine <= C.Engine.stall or petrol < C.Petrol.starveBelow then return 'stall' end
    if engine <= C.Engine.rough then return 'rough' end
    return 'ok'
end

-- Wheel index per quadrant (0 FL, 1 FR, 4 RL, 5 RR).
local WHEEL = { fl = 0, fr = 1, rl = 4, rr = 5 }
-- Door index per quadrant (0 FL, 1 FR, 2 RL, 3 RR; 4 hood, 5 trunk).
local DOOR  = { fl = 0, fr = 1, rl = 2, rr = 3 }

-- Roll one cosmetic break. A part is vulnerable if the body is worn past its
-- threshold OR this single hit is violent enough (hardImpact). Then chance scales
-- with severity.
local function tryBreak(veh, key, spec, body, severity)
    if Effects.Has(veh, key) then return end
    local vulnerable = body <= spec.body or (spec.hardImpact and severity >= spec.hardImpact)
    if not vulnerable then return end
    if spec.minSeverity and severity < spec.minSeverity then return end
    if math.random() < spec.chance * severity then
        Effects.Record(veh, key)
    end
end

-- Apply crash damage with EXPLICIT setters (these bypass vehicle invincibility /
-- god mode, unlike collision damage). The script, not GTA, is the authority.
local function applyCrashDamage(veh, severity, catastrophic)
    local I = C.Impact

    SetVehicleBodyHealth(veh, math.max(GetVehicleBodyHealth(veh) - severity * I.bodyDamageMax, 0.0))
    SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh) - severity * I.engineDamageMax, -500.0))

    if catastrophic then
        -- Rupture the tank: slam it into the gushing band (visible fuel trail) but not
        -- to zero, so it leaks out and starves the engine rather than instantly exploding.
        if GetVehiclePetrolTankHealth(veh) > I.tankRuptureTo then
            SetVehiclePetrolTankHealth(veh, I.tankRuptureTo)
        end
    elseif severity >= I.petrolMinSeverity then
        SetVehiclePetrolTankHealth(veh, math.max(GetVehiclePetrolTankHealth(veh) - severity * I.petrolDamageMax, 0.0))
    end

    -- Make the crumple visible even on a "strong"/invincible body (explicit deform).
    if severity > 0.25 then
        SetVehicleDamage(veh, 0.0, 0.5, 0.0, severity * 600.0, severity * 2.5, false)
    end
end

local function handleImpact(veh, severity, body, catastrophic)
    -- Direction of travel at impact: forward hits the front, reverse hits the rear.
    local rel = GetEntitySpeedVector(veh, true) -- entity-relative: x=right, y=forward
    local front = rel.y >= -1.0                  -- bias to front unless clearly reversing
    local rightSide = math.random() < 0.5        -- side of a collision is chaotic; randomise

    local cc = C.Cosmetic

    -- Bumper: only the struck end.
    if front then tryBreak(veh, 'bumperF', cc.bumperFront, body, severity)
    else          tryBreak(veh, 'bumperR', cc.bumperRear,  body, severity) end

    -- Hood on front impacts, trunk on rear impacts.
    if front then tryBreak(veh, 'door:4', cc.hood,  body, severity)
    else          tryBreak(veh, 'door:5', cc.trunk, body, severity) end

    -- A door in the impact quadrant.
    local doorKey = front and (rightSide and DOOR.fr or DOOR.fl)
                          or  (rightSide and DOOR.rr or DOOR.rl)
    tryBreak(veh, 'door:' .. doorKey, cc.doors, body, severity)

    -- WHEELS: catastrophic impacts only. Shear the impact-corner wheel; a near-total
    -- wreck can lose a second.
    if catastrophic then
        local ws = C.WheelShear
        local wheelKey = front and (rightSide and WHEEL.fr or WHEEL.fl)
                               or  (rightSide and WHEEL.rr or WHEEL.rl)
        if not Effects.Has(veh, 'wheel:' .. wheelKey) and math.random() < ws.chance then
            Effects.Record(veh, 'wheel:' .. wheelKey)
        end
        if severity >= ws.secondWheelSeverity and math.random() < ws.secondWheelChance then
            -- diagonally opposite corner for a proper barrel-roll wreck
            local opp = front and (rightSide and WHEEL.rl or WHEEL.rr)
                              or  (rightSide and WHEEL.fl or WHEEL.fr)
            if not Effects.Has(veh, 'wheel:' .. opp) then
                Effects.Record(veh, 'wheel:' .. opp)
            end
        end
    end
end

-- Petrol leak -> fuel drain -> starvation -> fire. Returns possibly-lowered engine health.
local function applyPetrol(veh, petrol, engine)
    local P = C.Petrol
    if petrol >= P.leakBelow then return engine end

    -- Leak: bleed the tank down (and the optional fuel statebag).
    petrol = math.max(petrol - P.drainRate, 0.0)
    SetVehiclePetrolTankHealth(veh, petrol)

    if P.syncFuelStatebag then
        local fuel = Entity(veh).state.fuel
        if type(fuel) == 'number' and fuel > 0 then
            Entity(veh).state:set('fuel', math.max(fuel - P.fuelDrainRate, 0.0), true)
        end
    end

    -- Fire when critical and running.
    if P.fireChance > 0 and petrol < P.fireBelow and GetIsVehicleEngineRunning(veh) then
        if math.random() < P.fireChance then
            SetVehiclePetrolTankHealth(veh, 0.0) -- hands off to GTA's own ignition/explosion
            StartEntityFire(veh)
        end
    end

    -- Fuel starvation chews the engine.
    if petrol < P.starveBelow then
        engine = math.max(engine - P.starveEngineDrain, -100.0)
        SetVehicleEngineHealth(veh, engine)
    end

    return engine
end

-- Per-driver sputter bookkeeping.
local sp = { cut = false, restoreAt = 0, nextAt = 0 }

local function beginCut(veh, now, everyMin, everyMax)
    SetVehicleEngineOn(veh, false, true, true) -- disableAutoStart so it actually stumbles
    sp.cut = true
    sp.restoreAt = now + math.random(C.Engine.sputterDurMin, C.Engine.sputterDurMax)
    sp.nextAt = now + math.random(everyMin, everyMax)
end

local function applyEngine(veh, engine, petrol, now)
    local E = C.Engine

    -- End an active cut-out once its duration elapses.
    if sp.cut and now >= sp.restoreAt then
        SetVehicleEngineOn(veh, true, true, false)
        sp.cut = false
    end

    if engine <= E.dead then
        SetVehicleCheatPowerIncrease(veh, 1.0)
        if GetIsVehicleEngineRunning(veh) then
            SetVehicleEngineOn(veh, false, true, true)
        end
        return
    end

    local starving = petrol < C.Petrol.starveBelow
    if engine <= E.stall or starving then
        SetVehicleCheatPowerIncrease(veh, E.stallPower)
        if not sp.cut and now >= sp.nextAt then
            beginCut(veh, now, E.stallEveryMin, E.stallEveryMax)
        end
    elseif engine <= E.rough then
        SetVehicleCheatPowerIncrease(veh, E.roughPower)
        if not sp.cut and now >= sp.nextAt then
            beginCut(veh, now, E.sputterEveryMin, E.sputterEveryMax)
        end
    else
        SetVehicleCheatPowerIncrease(veh, 1.0) -- healthy: full power
    end
end

-- The vehicle the local player is actively driving (or 0). Shared by both threads.
local function drivenVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and not isImmune(veh) and VDCore.Ready() then
        return veh
    end
    return 0
end

--==========================================================================--
-- FAST crash-detection thread.
-- A collision dumps its speed over ~100ms (several frames), so a slow tick would
-- split one big crash into small ones. We sample fast and measure the drop from
-- the PEAK speed in a short rolling window, the true impact energy.
--==========================================================================--
CreateThread(function()
    local hist = {}        -- recent { t, s } samples within the window
    local lastCrashAt = 0
    local I = C.Impact

    while true do
        local veh = drivenVehicle()
        if veh == 0 then
            hist = {}
            Wait(150)
        else
            local now = GetGameTimer()
            local s = GetEntitySpeed(veh)
            hist[#hist + 1] = { t = now, s = s }
            while hist[1] and now - hist[1].t > I.window do table.remove(hist, 1) end

            local peak = s
            for i = 1, #hist do if hist[i].s > peak then peak = hist[i].s end end
            local decel = peak - s

            if decel >= I.minDecel and (now - lastCrashAt) > I.cooldown then
                lastCrashAt = now
                hist = {}  -- reset so the same crash can't re-trigger
                local sev = math.min(1.0, decel / I.decelScale)
                local catastrophic = sev >= I.catastrophic
                if C.Debug then
                    print(('[vsfdmg] CRASH decel=%.1f sev=%.2f%s body=%.0f eng=%.0f'):format(
                        decel, sev, catastrophic and ' CATASTROPHIC' or '',
                        GetVehicleBodyHealth(veh), GetVehicleEngineHealth(veh)))
                end
                applyCrashDamage(veh, sev, catastrophic)
                handleImpact(veh, sev, GetVehicleBodyHealth(veh), catastrophic)
            end
            Wait(0)
        end
    end
end)

CreateThread(function()
    local lastVeh, lastBody = 0, nil
    local lastStage, lastLeak = 'ok', false
    local dbgLast = 0

    while true do
        local wait = C.Interval
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        -- DIAGNOSTIC: prints once/sec while in any vehicle, regardless of gates, so
        -- we can see exactly which condition (driver/class/ready) is failing.
        if C.Debug and veh ~= 0 then
            local t = GetGameTimer()
            if t - dbgLast >= 1000 then
                dbgLast = t
                print(('[vsfdmg] veh=%d driver=%s class=%d ready=%s body=%.0f eng=%.0f')
                    :format(veh, tostring(GetPedInVehicleSeat(veh, -1) == ped),
                            GetVehicleClass(veh), tostring(VDCore.Ready()),
                            GetVehicleBodyHealth(veh), GetVehicleEngineHealth(veh)))
            end
        end

        -- Only process for a spawned character driving a non-immune vehicle.
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and not isImmune(veh) and VDCore.Ready() then
            -- New vehicle: prime the baseline so we don't read the entry as an impact.
            if veh ~= lastVeh then
                lastVeh, lastBody = veh, GetVehicleBodyHealth(veh)
                lastStage, lastLeak = 'ok', false
                sp.cut, sp.nextAt = false, 0
            end

            local body   = GetVehicleBodyHealth(veh)
            local engine = GetVehicleEngineHealth(veh)
            local petrol = GetVehiclePetrolTankHealth(veh)
            local now    = GetGameTimer()

            -- Repair detection: a big upward jump in body health = mechanic/SetVehicleFixed.
            if lastBody and body > lastBody + C.RepairJumpThreshold then
                Effects.Clear(veh)
                lastStage, lastLeak = 'ok', false
            end
            -- (Crash detection lives in the fast thread below.)

            engine = applyPetrol(veh, petrol, engine)
            applyEngine(veh, engine, petrol, now)

            -- Branded milestone toasts, fired once per worsening transition.
            if C.Notify then
                local leaking = petrol < C.Petrol.leakBelow
                if leaking and not lastLeak then
                    VDCore.Notify({ title = 'Vehicle', message = 'Fuel leak, you\'re losing fuel.', type = 'warning' })
                end
                lastLeak = leaking

                local stage = engineStage(engine, petrol)
                if STAGE_RANK[stage] > STAGE_RANK[lastStage] and STAGE_MSG[stage] then
                    VDCore.Notify(STAGE_MSG[stage])
                end
                lastStage = stage
            end

            lastBody = GetVehicleBodyHealth(veh)
        else
            -- Not driving: reset the power tweak on the car we just left, if any.
            if lastVeh ~= 0 then
                if DoesEntityExist(lastVeh) then SetVehicleCheatPowerIncrease(lastVeh, 1.0) end
                lastVeh, lastBody, sp.cut = 0, nil, false
            end
            wait = 500
        end

        Wait(wait)
    end
end)

--==========================================================================--
-- Exports
--==========================================================================--
-- Clear recorded cosmetic damage on a vehicle (does NOT un-deform the body; call
-- SetVehicleFixed yourself for a full repair).
exports('ResetVehicleDamage', function(veh)
    if veh and DoesEntityExist(veh) then Effects.Clear(veh) end
end)

--==========================================================================--
-- Debug
--==========================================================================--
if C.Debug then
    RegisterCommand('vsfdmg', function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then print('[vsfdmg] not in a vehicle'); return end
        print(('[vsfdmg] body=%.0f engine=%.0f petrol=%.0f speed=%.1f')
            :format(GetVehicleBodyHealth(veh), GetVehicleEngineHealth(veh),
                    GetVehiclePetrolTankHealth(veh), GetEntitySpeed(veh)))
        local st = Entity(veh).state['vsf_vehdamage']
        print('[vsfdmg] breaks: ' .. (type(st) == 'table' and json.encode(st) or 'none'))
    end, false)
end
