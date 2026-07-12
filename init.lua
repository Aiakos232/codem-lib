--[[
    codem-lib init shim — consumer scripts add
    `shared_scripts { '@codem-lib/init.lua' }` to their fxmanifest and use
    Lib.*. Every call goes through a codem-lib export; provider selection
    lives in the lib config.
]]

local LIB = 'codem-lib'

Lib = Lib or {}

if IsDuplicityVersion() then
    -- ── Server ──────────────────────────────────────────────────────────────
    Lib.Society = {
        ---@param account string society/job name
        ---@param amount number
        ---@return boolean
        Pay = function(account, amount) return exports[LIB]:SocietyPay(account, amount) end,
        ---@param account string
        ---@param amount number
        ---@return boolean
        Remove = function(account, amount) return exports[LIB]:SocietyRemove(account, amount) end,
        ---@param account string
        ---@return number
        Balance = function(account) return exports[LIB]:SocietyBalance(account) end,
    }

    Lib.Keys = {
        ---@param src number player server id
        ---@param vehicle number vehicle entity
        ---@param plate? string
        Give = function(src, vehicle, plate) return exports[LIB]:GiveKeys(src, vehicle, plate) end,
        ---@param src number
        ---@param vehicle number
        ---@param plate? string
        Remove = function(src, vehicle, plate) return exports[LIB]:RemoveKeys(src, vehicle, plate) end,
    }

    Lib.Fuel = {
        ---@param src number player server id (used when the provider is client-side)
        ---@param vehicle number vehicle entity
        ---@param amount number fuel level 0-100
        Set = function(src, vehicle, amount) return exports[LIB]:SetFuel(src, vehicle, amount) end,
    }

    ---@param src number player server id (-1 = everyone)
    ---@param message string
    ---@param nType? string 'info'|'success'|'error'|'warning'
    ---@param duration? number ms
    Lib.Notify = function(src, message, nType, duration)
        return exports[LIB]:Notify(src, message, nType, duration)
    end

    Lib.Inventory = {
        ---@param src number @return table items
        Items = function(src) return exports[LIB]:GetPlayerItems(src) end,
        ---@param src number, itemName string, count number, metadata? table, slot? number
        Add = function(src, itemName, count, metadata, slot) return exports[LIB]:AddItem(src, itemName, count, metadata, slot) end,
        Remove = function(src, itemName, count, metadata, slot) return exports[LIB]:RemoveItem(src, itemName, count, metadata, slot) end,
        ---@return number
        Count = function(src, itemName, metadata) return exports[LIB]:GetItemCount(src, itemName, metadata) end,
        Slot = function(src, slot) return exports[LIB]:GetItemSlot(src, slot) end,
        Drop = function(prefix, items, coords) return exports[LIB]:CustomDrop(prefix, items, coords) end,
        CreateShop = function(shopName, data) return exports[LIB]:CreateShop(shopName, data) end,
    }
else
    -- ── Client ──────────────────────────────────────────────────────────────
    Lib.Keys = {
        ---@param vehicle number vehicle entity
        ---@param plate? string
        Give = function(vehicle, plate) return exports[LIB]:GiveKeys(vehicle, plate) end,
        ---@param vehicle number
        ---@param plate? string
        Remove = function(vehicle, plate) return exports[LIB]:RemoveKeys(vehicle, plate) end,
    }

    Lib.Fuel = {
        ---@param vehicle number vehicle entity
        ---@param amount number fuel level 0-100
        Set = function(vehicle, amount) return exports[LIB]:SetFuel(vehicle, amount) end,
    }

    ---@param message string
    ---@param nType? string 'info'|'success'|'error'|'warning'
    ---@param duration? number ms
    Lib.Notify = function(message, nType, duration)
        return exports[LIB]:Notify(message, nType, duration)
    end
end
