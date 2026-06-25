-- ============================================================================
--  viscosity_vehicledamage  ·  (c) 2026 AndyBodnar (Viscosity)
--  https://github.com/AndyBodnar/Viscosity_vehicle_damage
--  Server use only. No resale, repackaging, or credit removal. See LICENSE.
-- ============================================================================
fx_version 'cerulean'
games { 'gta5' }

name 'viscosity_vehicledamage'
description 'Realistic progressive vehicle damage: detachable bumpers/doors/wheels, fuel-tank leaks, and staged engine failure that ends in a stall. Networked via entity statebags so every client sees the same wreck.'
author 'viscosity'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/core.lua',       -- viscosity_core integration shim (notify / ready gate)
    'client/effects.lua',
    'client/main.lua',
    'client/fieldrepair.lua',
}

-- Server owns the statebag writes (sv_stateBagStrictMode blocks client writes).
server_script 'server/main.lua'

dependencies {
    'ox_lib',
    'viscosity_core',
}
