--[[
    codem-lib init — the ONLY line a consumer resource needs:

        shared_scripts { '@codem-lib/init.lua' }

    Loading this file sets up everything in the consumer's own context:
      - LibConfig            (provider selection)
      - Framework.Client/Server bridge (right framework, right side)
      - Target bridge        (client only; ox_target / qb-target)
      - CodemLib.*                (Society / Keys / Fuel / Notify / Inventory shims
                              over the codem-lib exports)
]]

local LIB = 'codem-lib'

---Run one of codem-lib's shared files inside THIS resource's context.
local function loadLibFile(path)
    local chunk = LoadResourceFile(LIB, path)
    if not chunk then
        print(('[codem-lib] init: could not read %s'):format(path))
        return
    end
    local fn, err = load(chunk, ('@@%s/%s'):format(LIB, path))
    if not fn then
        print(('[codem-lib] init: %s'):format(err))
        return
    end
    fn()
end

-- 1) Provider config (skip when the consumer already loaded it).
if type(LibConfig) ~= 'table' then
    loadLibFile('config.lua')
end

-- 2) Framework bridge — player objects can't cross exports, so the
--    implementation runs here. framework.lua resolves the framework and side.
loadLibFile('framework.lua')

-- 3) Target bridge (client only) — options carry functions, same reason.
--    Defines the `Target` global when ox_target / qb-target is running.
if not IsDuplicityVersion() then
    loadLibFile('modules/target/client.lua')
end

-- 4) CodemLib.* shims over the codem-lib exports.
CodemLib = CodemLib or {}

if IsDuplicityVersion() then
    -- ── Server ──────────────────────────────────────────────────────────────
    CodemLib.Society = {
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

    CodemLib.Keys = {
        ---@param src number player server id
        ---@param vehicle number vehicle entity
        ---@param plate? string
        Give = function(src, vehicle, plate) return exports[LIB]:GiveKeys(src, vehicle, plate) end,
        ---@param src number
        ---@param vehicle number
        ---@param plate? string
        Remove = function(src, vehicle, plate) return exports[LIB]:RemoveKeys(src, vehicle, plate) end,
    }

    CodemLib.Fuel = {
        ---@param src number player server id (used when the provider is client-side)
        ---@param vehicle number vehicle entity
        ---@param amount number fuel level 0-100
        Set = function(src, vehicle, amount) return exports[LIB]:SetFuel(src, vehicle, amount) end,
    }

    ---@param src number player server id (-1 = everyone)
    ---@param message string
    ---@param nType? string 'info'|'success'|'error'|'warning'
    ---@param duration? number ms
    CodemLib.Notify = function(src, message, nType, duration)
        return exports[LIB]:Notify(src, message, nType, duration)
    end

    CodemLib.Inventory = {
        ---@param src number @return table items
        Items = function(src) return exports[LIB]:GetPlayerItems(src) end,
        ---@param src number, itemName string, count number, metadata? table, slot? number
        ---@return boolean success (providers that return nil on success are treated as success)
        Add = function(src, itemName, count, metadata, slot) return exports[LIB]:AddItem(src, itemName, count, metadata, slot) ~= false end,
        ---@return boolean success (nil = success)
        Remove = function(src, itemName, count, metadata, slot) return exports[LIB]:RemoveItem(src, itemName, count, metadata, slot) ~= false end,
        ---@return number
        Count = function(src, itemName, metadata) return exports[LIB]:GetItemCount(src, itemName, metadata) end,
        ---@param src number, itemName string, count? number, metadata? table @return boolean
        Has = function(src, itemName, count, metadata) return (exports[LIB]:GetItemCount(src, itemName, metadata) or 0) >= (count or 1) end,
        ---@param src number, itemName string, count? number, metadata? table @return boolean can carry (default true when provider has no check)
        CanCarry = function(src, itemName, count, metadata) return exports[LIB]:CanCarry(src, itemName, count or 1, metadata) end,
        Slot = function(src, slot) return exports[LIB]:GetItemSlot(src, slot) end,
        Drop = function(prefix, items, coords) return exports[LIB]:CustomDrop(prefix, items, coords) end,
        CreateShop = function(shopName, data) return exports[LIB]:CreateShop(shopName, data) end,
        ---@param stashId string, label string, slots number, weight number, groups? table, coords? vector3, opts? table
        RegisterStash = function(stashId, label, slots, weight, groups, coords, opts)
            return exports[LIB]:RegisterStash(stashId, label, slots, weight, groups, coords, opts)
        end,
        ---@param src number, stashId string, invData? table @return boolean handled
        OpenStashServer = function(src, stashId, invData) return exports[LIB]:OpenStashServer(src, stashId, invData) end,
    }
else
    -- ── Client ──────────────────────────────────────────────────────────────
    CodemLib.Keys = {
        ---@param vehicle number vehicle entity
        ---@param plate? string
        Give = function(vehicle, plate) return exports[LIB]:GiveKeys(vehicle, plate) end,
        ---@param vehicle number
        ---@param plate? string
        Remove = function(vehicle, plate) return exports[LIB]:RemoveKeys(vehicle, plate) end,
    }

    CodemLib.Fuel = {
        ---@param vehicle number vehicle entity
        ---@param amount number fuel level 0-100
        Set = function(vehicle, amount) return exports[LIB]:SetFuel(vehicle, amount) end,
    }

    ---@param message string
    ---@param nType? string 'info'|'success'|'error'|'warning'
    ---@param duration? number ms
    CodemLib.Notify = function(message, nType, duration)
        return exports[LIB]:Notify(message, nType, duration)
    end

    CodemLib.TextUI = {
        ---@param text string
        ---@param opts? { position?: string, icon?: string }
        Show = function(text, opts) return exports[LIB]:ShowTextUI(text, opts) end,
        Hide = function() return exports[LIB]:HideTextUI() end,
    }

    ---@param opts { label: string, duration: number, canCancel?: boolean, useWhileDead?: boolean, disable?: table, anim?: table, prop?: table }
    ---@return boolean completed
    CodemLib.Progress = function(opts) return exports[LIB]:Progress(opts) end

    ---@param difficulty string|string[]
    ---@param inputs? string[]
    ---@return boolean passed
    CodemLib.SkillCheck = function(difficulty, inputs) return exports[LIB]:SkillCheck(difficulty, inputs) end

    CodemLib.Inventory = {
        Open = function(invType, data) return exports[LIB]:OpenInventory(invType, data) end,
        ---@return number
        Count = function(itemName, metadata) return exports[LIB]:GetItemCount(itemName, metadata) end,
        ---@param itemName string, count? number, metadata? table @return boolean
        Has = function(itemName, count, metadata) return (exports[LIB]:GetItemCount(itemName, metadata) or 0) >= (count or 1) end,
        ItemData = function(itemName) return exports[LIB]:GetItemData(itemName) end,
        ---@return string|nil item icon url/path
        Image = function(itemName) local d = exports[LIB]:GetItemData(itemName); return d and d.image or nil end,
        ---@return string item label (falls back to the item name)
        Label = function(itemName) local d = exports[LIB]:GetItemData(itemName); return (d and d.label) or itemName end,
        Items = function() return exports[LIB]:GetPlayerItems() end,
        ---@param stashId string, invData? table @return boolean handled
        OpenStash = function(stashId, invData) return exports[LIB]:OpenStash(stashId, invData) end,
    }
end
