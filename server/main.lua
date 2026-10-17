local function hasIdentifier(src, list)
    if not list or #list == 0 then return false end
    local ids = GetPlayerIdentifiers(src)
    for _, id in ipairs(ids) do
        for __, wanted in ipairs(list) do
            if id == wanted then
                return true
            end
        end
    end
    return false
end

local function hasAce(src, aces)
    if not aces or #aces == 0 then return false end
    for _, ace in ipairs(aces) do
        if IsPlayerAceAllowed(src, ace) then
            return true
        end
    end
    return false
end

RegisterNetEvent('hsc_seatcontrol:sv:isExempt', function()
    local src = source
    local exempt = false

    if hasIdentifier(src, Config.ExemptIdentifiers) then
        exempt = true
    elseif hasAce(src, Config.ExemptAces) then
        exempt = true
    end

    TriggerClientEvent('hsc_seatcontrol:cl:exemptResult', src, exempt)
end)

-- server export for other resources
exports('IsPlayerExempt', function(src)
    if not src then return false end
    if hasIdentifier(src, Config.ExemptIdentifiers) then return true end
    if hasAce(src, Config.ExemptAces) then return true end
    return false
end)
