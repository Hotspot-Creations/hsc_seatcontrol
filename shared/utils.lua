-- shared/utils.lua
Utils = Utils or {}

local seatCache = {}

function Utils.getSeatCountByModel(model)
    if not model or model == 0 then return 0 end
    local cached = seatCache[model]
    if cached then return cached end

    local seats = GetVehicleModelNumberOfSeats(model) or 0
    seatCache[model] = seats
    return seats
end

function Utils.resourceStarted(name)
    if not name or name == '' then return false end
    return GetResourceState(name) == 'started'
end

function Utils.isIgnoredModel(veh)
    if not veh or veh == 0 then return false end

    local cfg = Config
    if not cfg or not cfg.IgnoreModels then return false end

    local model = GetEntityModel(veh)
    if not model or model == 0 then return false end

    -- Support hashed keys (recommended)
    if cfg.IgnoreModels[model] == true then return true end

    -- Support string display names (optional convenience)
    local dn = GetDisplayNameFromVehicleModel(model)
    if dn and dn ~= '' then
        dn = string.lower(dn)
        if cfg.IgnoreModels[dn] == true then return true end
    end

    return false
end

function Utils.debug(fmt, ...)
    local cfg = Config
    if not cfg then return end

    local dbg = cfg.Debug

    -- Support both:
    -- Config.Debug = true/false
    -- Config.Debug = { Enabled = true/false }
    local enabled = false
    if type(dbg) == 'boolean' then
        enabled = dbg
    elseif type(dbg) == 'table' then
        enabled = dbg.Enabled == true
    end

    if not enabled then return end

    local msg
    if select('#', ...) > 0 then
        msg = string.format(tostring(fmt), ...)
    else
        msg = tostring(fmt)
    end

    print(('[hsc_seatcontrol] %s'):format(msg))
end