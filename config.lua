Config = {}

-- =========================================================
-- Core
-- =========================================================

-- Master enable switch. Can be changed at runtime with SetEnabled.
Config.Enabled = true

-- Prevent GTA from automatically moving a front passenger into the driver seat.
Config.BlockAutoShuffle = true

-- Client polling interval while the player is in a vehicle.
Config.PollInterval = 200

-- Maximum speed in m/s for normal seat changes. 3.5 m/s is about 7.8 mph.
Config.SeatChangeMaxSpeed = 3.5

-- Temporary shuffle allowance used by /shuff and the TempAllow export.
Config.TempAllowDuration = 5000

-- Driver-seat changes can require a fully stopped vehicle.
Config.RequireParkedForDriverTake = true
Config.DriverTakeMaxSpeed = 0.15

-- Prevent seat changes while the vehicle is airborne or not on all wheels.
Config.BlockSeatChangeWhileAirborne = true

-- =========================================================
-- Emergency vehicles
-- =========================================================

Config.EmergencyVehicles = {
    Enabled = true,

    -- GTA vehicle classes treated as emergency vehicles.
    Classes = {
        [18] = true,
    },

    -- These are disabled by default for safety. Enable only if your server needs them.
    IgnoreSeatChangeSpeed = false,
    IgnoreAirborneBlock = false,
    AllowDriverTakeWhileMoving = false,
}

-- =========================================================
-- Driver-seat access / vehicle keys integration
-- =========================================================

Config.DriverLock = {
    -- Keep disabled until CanTakeDriverSeat is connected to your key resource.
    Enabled = false,
    RequireKeys = true,

    DeniedMessage = 'You do not have access to the driver seat.',

    -- Return true when the player may move into the driver seat.
    -- This callback runs client-side. Replace the body with your key-resource check.
    --
    -- Example structure:
    -- CanTakeDriverSeat = function(vehicle, plate)
    --     return exports['your_key_resource']:HasKeys(plate)
    -- end,
    CanTakeDriverSeat = function(vehicle, plate)
        return true
    end,
}

-- =========================================================
-- Vehicle filters
-- =========================================================

-- Vehicle classes where anti-shuffle and the seat menu are not enforced.
Config.AllowClasses = {
    [8]  = true, -- Motorcycles
    [13] = true, -- Cycles
    [14] = true, -- Boats
    [15] = true, -- Helicopters
    [16] = true, -- Planes
}

-- Ignore specific vehicle models completely.
Config.IgnoreModels = {
    -- [`wheelchair`] = true,
}

-- =========================================================
-- Permissions / exemptions
-- =========================================================

Config.ExemptIdentifiers = {
    -- 'license:1234567890abcdef...',
}

Config.ExemptAces = {
    -- 'seatcontrol.bypass',
}

Config.CacheExemption = true

-- =========================================================
-- Notifications
-- =========================================================

-- auto tries QBCore -> ESX -> ox_lib -> chat -> console.
-- Supported: auto, qb, esx, ox, chat, print, none
Config.NotifyMode = 'auto'

-- =========================================================
-- Commands
-- =========================================================

Config.Commands = {
    Enabled = true,
    TempAllow = 'shuff',
    Seat = 'seat',
    NextSeat = 'nextseat',
    PrevSeat = 'prevseat',
    TakeWheel = 'takewheel',
    SeatMenu = 'seatmenu',
}

-- =========================================================
-- Keybinds
-- =========================================================

Config.RegisterKeyMappings = true
Config.KeyMap = {
    -- { command = 'seatmenu', defaultMapper = 'keyboard', defaultKey = 'U' },
    -- { command = 'nextseat', defaultMapper = 'keyboard', defaultKey = 'PAGEUP' },
    -- { command = 'prevseat', defaultMapper = 'keyboard', defaultKey = 'PAGEDOWN' },
}

-- =========================================================
-- Menu
-- =========================================================

Config.OxLibMenu = {
    Enabled = true,
    Title = 'Vehicle Seats',
}

Config.FallbackMenu = true

-- =========================================================
-- Developer
-- =========================================================

Config.Debug = false
