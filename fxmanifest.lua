fx_version 'cerulean'
game 'gta5'

name 'hsc_seatcontrol'
author 'Hotspot Creations'
description 'Professional vehicle seat management with anti-shuffle, safe seat switching, emergency vehicle rules, keybinds, ACE exemptions, and driver-seat access integration.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua',
    'config.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    'server/*.lua',
}

exports {
    'TempAllow',
    'SetEnabled',
    'IsEnabled',
    'OpenMenu',
    'SetDriverAccess',
    'HasDriverAccess',
}

server_exports {
    'IsPlayerExempt',
}

escrow_ignore {
    'config.lua',
}
