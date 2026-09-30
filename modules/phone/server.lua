Phone = Phone or {}

local function started(res)
    return GetResourceState(res) == 'started'
end

local function single(sql, params)
    local ok, row = pcall(function() return MySQL.single.await(sql, params) end)
    return ok and row or nil
end

function Phone.Get(identifier, character)
    if not identifier then return nil end

    if started('codem-phone') then
        local ok, number = pcall(function() return exports['codem-phone']:GetPhoneNumberByIdentifier(identifier) end)
        if ok and number then return number end
    end

    if started('lb-phone') then
        local row = single('SELECT `phone_number` FROM `phone_phones` WHERE `owner_id` = ? LIMIT 1', { identifier })
        return row and row.phone_number or nil
    end

    local char = character
    if type(char) ~= 'table' and type(Framework) == 'table' and Framework.Server and Framework.Server.GetCharacter then
        char = Framework.Server.GetCharacter(identifier)
    end
    if type(char) == 'table' and char.phone and char.phone ~= '' then return tostring(char.phone) end
    return nil
end

function Phone.Owner(number)
    if not number or number == '' then return nil end

    if started('lb-phone') then
        local row = single('SELECT `owner_id` FROM `phone_phones` WHERE `phone_number` = ? LIMIT 1', { number })
        return row and row.owner_id or nil
    end

    if started('codem-phone') then
        local row = single('SELECT `owner` FROM `codem_mphone_data` WHERE `phone_number` = ? LIMIT 1', { number })
        return row and row.owner or nil
    end

    return nil
end

exports('GetPhoneNumber', Phone.Get)
exports('GetPhoneOwner', Phone.Owner)
