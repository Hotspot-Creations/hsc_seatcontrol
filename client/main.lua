-- client/main.lua
local R = Utils or {}

-- Hard fallback stubs so it never crashes even if shared misloads
R.isIgnoredModel = R.isIgnoredModel or function() return false end
R.debug = R.debug or function() end
R.resourceStarted = R.resourceStarted or function(name) return GetResourceState(name) == 'started' end
R.getSeatCountByModel = R.getSeatCountByModel or function(model) return GetVehicleModelNumberOfSeats(model) or 0 end

-- =========================================================
-- Runtime state
-- =========================================================
local enabled = (Config and Config.Enabled) == true
local tempAllowUntil = 0
local cachedExempt = false
local exemptionKnown = false
local driverAccessOverrides = {}

-- =========================================================
-- Small helpers
-- =========================================================
local function nowMs() return GetGameTimer() end
local function ped() return PlayerPedId() end

local fastWatchUntil = 0
local function startFastWatch(ms)
    fastWatchUntil = nowMs() + (ms or 1200)
end

-- Some artifacts/builds don't expose SetPedCanShuffleSeat. Guard it.
local HAS_SET_PED_CAN_SHUFFLE = type(SetPedCanShuffleSeat) == 'function'

-- allowed=true  -> shuffle allowed (flag off)
-- allowed=false -> shuffle blocked (flag on)
local function setShuffleAllowed(p, allowed)
    -- Flag 184 is the reliable cross-build control for seat shuffle prevention.
    SetPedConfigFlag(p, 184, not allowed)

    -- Optional native when available.
    if HAS_SET_PED_CAN_SHUFFLE then
        SetPedCanShuffleSeat(p, allowed)
    end
end

local function inVehicle(p)
    return IsPedInAnyVehicle(p, false)
end

local function vehicleOf(p)
    return GetVehiclePedIsIn(p, false)
end

local function vehSpeed(veh)
    return (veh and veh ~= 0) and GetEntitySpeed(veh) or 0.0
end

local function vehClass(veh)
    return (veh and veh ~= 0) and GetVehicleClass(veh) or -1
end

local function classAllowed(veh)
    local c = vehClass(veh)
    return Config.AllowClasses and Config.AllowClasses[c] == true
end

local function isEmergencyVehicle(veh)
    if not Config.EmergencyVehicles or not Config.EmergencyVehicles.Enabled then return false end
    local classes = Config.EmergencyVehicles.Classes or {}
    return classes[vehClass(veh)] == true
end

local function normalizePlate(plate)
    return tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1')
end

local function hasDriverAccess(veh)
    if not Config.DriverLock or not Config.DriverLock.Enabled then return true end
    if not Config.DriverLock.RequireKeys then return true end
    if not veh or veh == 0 then return false end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local override = driverAccessOverrides[netId]
    if override then
        if override.expiresAt == 0 or override.expiresAt > nowMs() then
            return override.allowed == true
        end
        driverAccessOverrides[netId] = nil
    end

    local callback = Config.DriverLock.CanTakeDriverSeat
    if type(callback) ~= 'function' then return false end

    local plate = normalizePlate(GetVehicleNumberPlateText(veh))
    local ok, allowed = pcall(callback, veh, plate)
    if not ok then
        R.debug('DriverLock callback failed: %s', tostring(allowed))
        return false
    end

    return allowed == true
end

local function seatCount(veh)
    if not veh or veh == 0 then return 0 end
    return R.getSeatCountByModel(GetEntityModel(veh))
end

local function getPedSeatIndex(p, veh)
    if not veh or veh == 0 then return nil end
    local total = seatCount(veh)
    for seat = -1, (total - 2) do
        if GetPedInVehicleSeat(veh, seat) == p then
            return seat
        end
    end
    return nil
end

local function isSeatFree(veh, seat)
    return IsVehicleSeatFree(veh, seat)
end

local function isDriverSeatFree(veh)
    return isSeatFree(veh, -1)
end

local function isAirborne(veh)
    if not veh or veh == 0 then return false end

    if IsEntityInAir(veh) then return true end

    -- Optional: treat "not on all wheels" as airborne-ish
    if not IsVehicleOnAllWheels(veh) then return true end

    return false
end

local function notify(msg)
    local mode = (Config.NotifyMode or 'auto')
    if mode == 'none' then return end

    local function tryQb()
        if not R.resourceStarted('qb-core') then return false end
        local ok = pcall(function()
            exports['qb-core']:GetCoreObject().Functions.Notify(msg, 'primary', 3500)
        end)
        return ok
    end

    local function tryEsx()
        if not R.resourceStarted('es_extended') then return false end
        local ok = pcall(function()
            local ESX = exports['es_extended']:getSharedObject()
            ESX.ShowNotification(msg)
        end)
        return ok
    end

    local function tryOx()
        if not R.resourceStarted('ox_lib') or not lib or type(lib.notify) ~= 'function' then return false end
        local ok = pcall(function()
            lib.notify({ description = msg, type = 'inform', duration = 3500 })
        end)
        return ok
    end

    local function tryChat()
        TriggerEvent('chat:addMessage', { args = { '^2SeatControl', msg } })
        return true
    end

    if mode == 'qb' then if tryQb() then return end end
    if mode == 'esx' then if tryEsx() then return end end
    if mode == 'ox' then if tryOx() then return end end
    if mode == 'chat' then return tryChat() end
    if mode == 'print' then
        print(('[hsc_seatcontrol] %s'):format(msg))
        return
    end

    if tryQb() then return end
    if tryEsx() then return end
    if tryOx() then return end
    if tryChat() then return end
    print(('[hsc_seatcontrol] %s'):format(msg))
end

local function shouldEnforce(p, veh)
    if not enabled then return false end
    if not Config.BlockAutoShuffle then return false end
    if cachedExempt then return false end
    if classAllowed(veh) then return false end
    if R.isIgnoredModel(veh) then return false end
    return true
end

-- =========================================================
-- Exemption handshake
-- =========================================================
local function requestExemption()
    if Config.CacheExemption and exemptionKnown then return end
    TriggerServerEvent('hsc_seatcontrol:sv:isExempt')
end

CreateThread(function()
    Wait(1000)
    requestExemption()
end)

RegisterNetEvent('hsc_seatcontrol:cl:exemptResult', function(isExempt)
    cachedExempt = isExempt == true
    exemptionKnown = true
    R.debug('Exempt result: %s', tostring(cachedExempt))
end)

-- =========================================================
-- Hard block: prevents passenger->driver shuffle animation
-- Runs at frame rate ONLY when needed (passenger seat + driver empty)
-- =========================================================
CreateThread(function()
    while true do
        Wait(250)

        if not enabled or not Config.BlockAutoShuffle or cachedExempt then
            goto continue
        end

        local p = ped()
        if not inVehicle(p) then
            goto continue
        end

        local veh = vehicleOf(p)
        if veh == 0 or classAllowed(veh) or R.isIgnoredModel(veh) then
            goto continue
        end

        local curSeat = getPedSeatIndex(p, veh)
        if curSeat ~= 0 or not isDriverSeatFree(veh) then
            goto continue
        end

        while true do
            Wait(0)

            if not enabled or not Config.BlockAutoShuffle or cachedExempt then break end
            if not inVehicle(p) then break end

            veh = vehicleOf(p)
            if veh == 0 then break end
            if classAllowed(veh) or R.isIgnoredModel(veh) then break end

            curSeat = getPedSeatIndex(p, veh)
            if curSeat ~= 0 then break end
            if not isDriverSeatFree(veh) then break end

            -- enforce every frame
            setShuffleAllowed(p, false)

            if GetIsTaskActive(p, 165) then
                ClearPedTasksImmediately(p)
                SetPedIntoVehicle(p, veh, 0)
            end
        end

        ::continue::
    end
end)

-- =========================================================
-- Anti-shuffle enforcement loop (optimized)
-- =========================================================
CreateThread(function()
    local lastVeh = 0
    local lastSeat = nil

    while true do
        local waitMs = (nowMs() < fastWatchUntil) and 0 or (Config.PollInterval or 200)
        Wait(waitMs)

        local p = ped()
        if not inVehicle(p) then
            lastVeh = 0
            lastSeat = nil
            goto continue
        end

        local veh = vehicleOf(p)
        if veh == 0 then goto continue end

        local curSeat = getPedSeatIndex(p, veh)

        if not shouldEnforce(p, veh) then
            setShuffleAllowed(p, true)
            goto continue
        end

        local tempAllow = nowMs() < tempAllowUntil
        if tempAllow then
            setShuffleAllowed(p, true)
            goto continue
        end

        if veh ~= lastVeh then
            lastVeh = veh
            lastSeat = curSeat
            startFastWatch(1200)
        elseif curSeat ~= nil and curSeat ~= lastSeat then
            lastSeat = curSeat
        end

        -- Primary prevention
        setShuffleAllowed(p, false)

        -- Secondary kill
        if GetIsTaskActive(p, 165) then
            ClearPedTasksImmediately(p)

            if lastSeat ~= nil then
                SetPedIntoVehicle(p, veh, lastSeat)
            elseif curSeat ~= nil then
                SetPedIntoVehicle(p, veh, curSeat)
            end

            startFastWatch(800)
        end

        ::continue::
    end
end)

-- =========================================================
-- Seat switching
-- =========================================================
local function canChangeSeat(p, veh, targetSeat)
    if not inVehicle(p) then return false, 'You are not in a vehicle.' end
    if veh == 0 then return false, 'Vehicle not found.' end
    if R.isIgnoredModel(veh) then return false, 'Seat switching disabled for this vehicle.' end

    local emergency = isEmergencyVehicle(veh)
    local ignoreAirborne = emergency and Config.EmergencyVehicles.IgnoreAirborneBlock
    if Config.BlockSeatChangeWhileAirborne and not ignoreAirborne and isAirborne(veh) then
        return false, 'Cannot change seats while airborne.'
    end

    local ignoreSpeed = emergency and Config.EmergencyVehicles.IgnoreSeatChangeSpeed
    local speed = vehSpeed(veh)
    if not ignoreSpeed and speed > (Config.SeatChangeMaxSpeed or 3.5) then
        return false, ('Too fast to change seats (%.1f m/s).'):format(speed)
    end

    if targetSeat == -1 and not hasDriverAccess(veh) then
        return false, (Config.DriverLock and Config.DriverLock.DeniedMessage) or 'Driver-seat access denied.'
    end

    return true
end

local function performSeatChange(targetSeat)
    local p = ped()
    local veh = vehicleOf(p)
    local ok, why = canChangeSeat(p, veh, targetSeat)
    if not ok then
        notify(why)
        return
    end

    if not isSeatFree(veh, targetSeat) then
        notify('That seat is not free.')
        return
    end

    local restoreAt = nowMs() + 1500
    setShuffleAllowed(p, true)

    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
    end

    startFastWatch(1200)
    SetPedIntoVehicle(p, veh, targetSeat)

    CreateThread(function()
        while nowMs() < restoreAt do Wait(50) end
        local pp = ped()
        if Config.BlockAutoShuffle and shouldEnforce(pp, vehicleOf(pp)) then
            setShuffleAllowed(pp, false)
        end
    end)
end

local function nameToSeat(name)
    name = tostring(name or ''):lower()
    if name == 'driver' or name == 'd' then return -1 end
    if name == 'passenger' or name == 'p' then return 0 end
    if name == 'rearleft' or name == 'rl' then return 1 end
    if name == 'rearright' or name == 'rr' then return 2 end
    local num = tonumber(name)
    if num then return math.floor(num) end
    return nil
end

local function nextFreeSeat(veh, fromSeat, dir)
    local total = seatCount(veh)
    if total <= 1 then return fromSeat end

    dir = dir or 1
    local start = fromSeat or 0
    local seat = start

    for _ = 1, (total + 2) do
        seat = seat + dir
        if seat < -1 then seat = total - 2 end
        if seat > (total - 2) then seat = -1 end
        if isSeatFree(veh, seat) then return seat end
    end

    return start
end

-- =========================================================
-- ox_lib context menu
-- =========================================================
local oxMenuRegistered = false
local function canUseOxMenu()
    return Config.OxLibMenu and Config.OxLibMenu.Enabled
        and R.resourceStarted('ox_lib')
        and lib and type(lib.registerContext) == 'function'
end

local function seatLabel(seat)
    if seat == -1 then return 'Driver' end
    if seat == 0 then return 'Front Passenger' end
    if seat == 1 then return 'Rear Left' end
    if seat == 2 then return 'Rear Right' end
    return ('Seat %d'):format(seat)
end

local function buildSeatOptions(veh)
    local opts = {}
    local total = seatCount(veh)
    for seat = -1, (total - 2) do
        local free = isSeatFree(veh, seat)
        local label = seatLabel(seat)
        if free then
            opts[#opts + 1] = {
                title = label,
                description = 'Move to this seat',
                icon = 'chair',
                onSelect = function() performSeatChange(seat) end
            }
        else
            opts[#opts + 1] = {
                title = label,
                description = 'Occupied',
                icon = 'chair',
                disabled = true
            }
        end
    end
    return opts
end

local function openOxSeatMenu()
    local p = ped()
    if not inVehicle(p) then
        notify('Not in a vehicle.')
        return
    end
    local veh = vehicleOf(p)
    local ok, why = canChangeSeat(p, veh)
    if not ok then
        notify(why)
        return
    end

    if not oxMenuRegistered then
        lib.registerContext({
            id = 'hsc_seatcontrol_menu',
            title = (Config.OxLibMenu.Title or 'Vehicle Seats'),
            options = {}
        })
        oxMenuRegistered = true
    end

    lib.registerContext({
        id = 'hsc_seatcontrol_menu',
        title = (Config.OxLibMenu.Title or 'Vehicle Seats'),
        options = buildSeatOptions(veh)
    })

    lib.showContext('hsc_seatcontrol_menu')
end

local function openMenu()
    if canUseOxMenu() then
        return openOxSeatMenu()
    end

    if Config.FallbackMenu then
        notify('Menu requires ox_lib. Use /seat <driver|passenger|rearleft|rearright|index>.')
    end
end

-- =========================================================
-- Commands + keymaps
-- =========================================================
local function registerCommands()
    if not Config.Commands or not Config.Commands.Enabled then return end

    RegisterCommand(Config.Commands.TempAllow, function()
        if not inVehicle(ped()) then
            notify('Not in a vehicle.')
            return
        end
        tempAllowUntil = nowMs() + (Config.TempAllowDuration or 5000)
        notify(('Seat shuffle temporarily enabled for %.1f seconds.'):format((Config.TempAllowDuration or 5000) / 1000))
    end, false)

    RegisterCommand(Config.Commands.Seat, function(_, args)
        local p = ped()
        if not inVehicle(p) then
            notify('Not in a vehicle.')
            return
        end

        local want = nameToSeat(args[1])
        if want == nil then
            notify(('Usage: /%s <driver|passenger|rearleft|rearright|seatIndex>'):format(Config.Commands.Seat))
            return
        end

        local veh = vehicleOf(p)
        if want == -1 and not hasDriverAccess(veh) then
            notify((Config.DriverLock and Config.DriverLock.DeniedMessage) or 'Driver-seat access denied.')
            return
        end

        local emergencyMovingAllowed = isEmergencyVehicle(veh) and Config.EmergencyVehicles.AllowDriverTakeWhileMoving
        if want == -1 and Config.RequireParkedForDriverTake and not emergencyMovingAllowed then
            if not isDriverSeatFree(veh) then
                notify('Driver seat occupied.')
                return
            end
            if vehSpeed(veh) > (Config.DriverTakeMaxSpeed or 0.15) then
                notify('Vehicle must be fully stopped to take the driver seat.')
                return
            end
        end

        performSeatChange(want)
    end, false)

    RegisterCommand(Config.Commands.NextSeat, function()
        local p = ped()
        if not inVehicle(p) then return end
        local veh = vehicleOf(p)
        local curSeat = getPedSeatIndex(p, veh) or 0
        performSeatChange(nextFreeSeat(veh, curSeat, 1))
    end, false)

    RegisterCommand(Config.Commands.PrevSeat, function()
        local p = ped()
        if not inVehicle(p) then return end
        local veh = vehicleOf(p)
        local curSeat = getPedSeatIndex(p, veh) or 0
        performSeatChange(nextFreeSeat(veh, curSeat, -1))
    end, false)

    RegisterCommand(Config.Commands.TakeWheel, function()
        local p = ped()
        if not inVehicle(p) then
            notify('Not in a vehicle.')
            return
        end
        local veh = vehicleOf(p)
        if not isDriverSeatFree(veh) then
            notify('Driver seat occupied.')
            return
        end
        if not hasDriverAccess(veh) then
            notify((Config.DriverLock and Config.DriverLock.DeniedMessage) or 'Driver-seat access denied.')
            return
        end
        local emergencyMovingAllowed = isEmergencyVehicle(veh) and Config.EmergencyVehicles.AllowDriverTakeWhileMoving
        if Config.RequireParkedForDriverTake and not emergencyMovingAllowed and vehSpeed(veh) > (Config.DriverTakeMaxSpeed or 0.15) then
            notify('Vehicle must be fully stopped to take the driver seat.')
            return
        end
        performSeatChange(-1)
    end, false)

    RegisterCommand(Config.Commands.SeatMenu, function()
        openMenu()
    end, false)
end

local function registerKeymaps()
    if not Config.RegisterKeyMappings then return end
    if type(Config.KeyMap) ~= 'table' then return end
    for _, m in ipairs(Config.KeyMap) do
        if m.command and m.defaultMapper and m.defaultKey then
            RegisterKeyMapping(('/%s'):format(m.command), ('%s (hsc_seatcontrol)'):format(m.command), m.defaultMapper,
                m.defaultKey)
        end
    end
end

registerCommands()
registerKeymaps()

-- =========================================================
-- Exports
-- =========================================================
exports('TempAllow', function(ms)
    ms = tonumber(ms) or Config.TempAllowDuration or 5000
    tempAllowUntil = nowMs() + ms
end)

exports('SetEnabled', function(state)
    enabled = state == true
    local p = ped()
    if not enabled then
        setShuffleAllowed(p, true)
    else
        requestExemption()
    end
end)

exports('IsEnabled', function()
    return enabled
end)

exports('SetDriverAccess', function(vehicle, allowed, durationMs)
    if not vehicle or vehicle == 0 then return false end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    driverAccessOverrides[netId] = {
        allowed = allowed == true,
        expiresAt = durationMs and durationMs > 0 and (nowMs() + durationMs) or 0,
    }
    return true
end)

exports('HasDriverAccess', function(vehicle)
    return hasDriverAccess(vehicle)
end)

RegisterNetEvent('hsc_seatcontrol:cl:setDriverAccess', function(netId, allowed, durationMs)
    netId = tonumber(netId)
    if not netId then return end
    driverAccessOverrides[netId] = {
        allowed = allowed == true,
        expiresAt = durationMs and durationMs > 0 and (nowMs() + durationMs) or 0,
    }
end)

exports('OpenMenu', function()
    openMenu()
end)

RegisterNetEvent('hsc_seatcontrol:cl:openMenu', function()
    openMenu()
end)