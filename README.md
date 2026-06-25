# Viscosity Vehicle Damage

Realistic, progressive vehicle damage for FiveM. Crash hard enough and parts actually come off, bumpers, doors, hood, wheels, the fuel tank ruptures and leaks, and the engine degrades until it sputters and dies. The goal was to make wrecking a car feel like an event, not a cosmetic scratch.

I built this for my server (Viscosity) but it's standalone enough to drop into anything. It hooks into `viscosity_core` for branded notifications and a player-loaded gate, but the damage system itself is just native vehicle handling.

## What it does

- **Damage scales with how hard you actually hit.** I measure the impact by how much speed you scrub in a fraction of a second, not by GTA's body-health value, so it works even on god-mode/admin-spawned vehicles that normally ignore collision damage.
- **Parts detach by impact direction.** Drive into a wall and the front bumper/hood take it. Reverse into something and the rear/trunk go. Doors and wheels shear off the corner that got hit.
- **Catastrophic-only effects.** Wheels flying off and the fuel tank rupturing are reserved for genuine 75mph+ smashes. A fender bender won't do it.
- **Fuel leak to starvation to death.** A ruptured tank trails fuel, drains, and eventually starves the engine. It can catch fire if it's critical and still running.
- **Staged engine failure.** Healthy, then running rough (power loss), then sputtering/stalling, then dead. You get a window to limp somewhere before it gives out.
- **Field repair.** When the engine dies, get out, walk to the engine bay, and patch it just enough to limp to a mechanic. It's deliberately a bad fix, the car runs rough and you only get a couple of patches before it has to be properly repaired.
- **Properly networked.** Everyone sees the same wreck, including people who join after the crash. Damage is server-validated so clients can't forge it (works with `sv_stateBagStrictMode` on).

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- `viscosity_core` (for notifications + the loaded gate)

> Not running viscosity_core? It's a thin dependency, the only calls are `IsLoaded()` and `Notify()`. Swap `client/core.lua` for your framework's equivalents and you're done.

## Install

1. Drop the folder in your resources (e.g. `resources/[local]/viscosity_vehicledamage`).
2. Make sure `ox_lib` and `viscosity_core` start **before** it.
3. Add to your `server.cfg`:
   ```cfg
   ensure viscosity_vehicledamage
   ```

## Config

Everything lives in `config.lua` and it's commented top to bottom. The knobs you'll actually touch:

| Setting | What it does |
|---|---|
| `Config.Impact.catastrophic` | Severity (0-1) for the wheels-off / fuel-rupture tier. Lower = more carnage. |
| `Config.Impact.decelScale` | How much speed-scrub counts as a max-severity hit. Higher = more forgiving. |
| `Config.Engine` | Thresholds for rough / stall / dead, plus the sputter timing. |
| `Config.Petrol` | Leak rate, fuel starvation, and fire chance (set `fireChance = 0` to kill fires). |
| `Config.FieldRepair` | Whether the limp-home patch is enabled, how long it takes, and how many patches a wreck gets. |
| `Config.Notify` | Toggle the on-screen damage warnings. |

Set `Config.Debug = true` for a live `[vsfdmg]` readout in F8 and the `/vsfdmg` command.

## Notes

- The "bodycam" of damage, body/engine/petrol health, syncs natively. The cosmetic part-detachment is what I route through the server, because those natives are local-only and strict mode blocks client statebag writes.
- Field repair doesn't touch a leaking tank much on purpose. If you rupture the tank, patching the engine buys you time, not a free pass.
- There's an inventory item gate (`Config.FieldRepair.requireItem`) wired but disabled, I'll hook it to my inventory later.

## License

Copyright © 2026 **AndyBodnar (Viscosity)**. All rights reserved. See [LICENSE](LICENSE).

**Plain version:** run it on your own server and modify it however you like. Do **not** resell it, repackage it, re-upload it as your own, or strip the credits. Public use must credit AndyBodnar (Viscosity). If you want to do something the license doesn't cover, ask me first.

This is my work. I'm sharing it, not giving it away, don't snipe it.
