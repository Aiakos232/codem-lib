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

    CodemLib.Billing = {
        ---Send an invoice to a player.
        ---@param data table { identifier | targetSource, amount, reason, senderSource?, job?, jobLabel?, maxDistance? }
        ---@return string|false invoiceId, string|nil reason
        Send = function(data) return exports[LIB]:SendInvoice(data) end,
        ---@param invoiceId string|number
        ---@return boolean
        IsPaid = function(invoiceId) return exports[LIB]:IsInvoicePaid(invoiceId) end,
        ---Provider's invoice table (`invoiceid` column). Query it yourself to
        ---see whether an invoice is still there - cancelled ones are deleted.
        ---@return string|nil
        BillsTable = function() return exports[LIB]:GetBillingTable() end,
        ---@return string|nil active provider name
        Provider = function() return exports[LIB]:GetBillingProvider() end,
    }

    CodemLib.Phone = {
        ---Number the player's phone is actually using (falls back to charinfo).
        ---@param src number player server id
        ---@return string|nil
        Get = function(src) return exports[LIB]:GetPhoneNumber(src) end,
        ---Change the number in the phone resource and mirror it to the framework.
        ---@param src number player server id
        ---@param number string|number
        ---@return { ok: boolean, error: string|nil } error: offline | invalid_number | number_taken | no_phone | no_identifier | provider_error | unsupported
        Set = function(src, number) return exports[LIB]:SetPhoneNumber(src, number) end,
        ---@param number string
        ---@return boolean|nil nil = the provider cannot tell
        Exists = function(number) return exports[LIB]:PhoneNumberExists(number) end,
        ---@return string|nil a free number
        Generate = function() return exports[LIB]:GeneratePhoneNumber() end,
        ---@return string active provider name ('framework' when no phone resource runs)
        Provider = function() return exports[LIB]:GetPhoneProvider() end,
    }

    CodemLib.Medical = {
        ---Revive a downed player through the server's ambulance script.
        ---The client-side resurrection stays with the caller: this only clears
        ---the death state the ambulance resource is holding.
        ---@param src number player server id
        ---@return boolean handled
        Revive = function(src) return exports[LIB]:MedicalRevive(src) end,
        ---@return string|nil active ambulance resource name
        Provider = function() return exports[LIB]:GetMedicalProvider() end,
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

    CodemLib.Doorlock = {
        Provider = function() return exports[LIB]:GetDoorlockProvider() end,
    }

    CodemLib.Dispatch = {
        Provider = function() return exports[LIB]:GetDispatchProvider() end,
        ---@param src number|nil source that triggered the alert (0 = system)
        ---@param jobs string|string[] job names to alert
        ---@param coords vector3|table
        ---@param data { title?: string, description?: string, code?: string, length?: number, sound?: table }
        ---@param blip? { sprite?: number, colour?: number, scale?: number, flash?: boolean, length?: number, text?: string }
        ---@param flash? boolean
        Send = function(src, jobs, coords, data, blip, flash) return exports[LIB]:SendDispatch(src, jobs, coords, data, blip, flash) end,
    }

    CodemLib.Garage = {
        Provider = function() return exports[LIB]:GetGarageProvider() end,
        Enabled = function() return exports[LIB]:GetGarageProvider() ~= 'none' end,
        Name = function(id, pointId) return exports[LIB]:GarageName(id, pointId) end,
        Register = function(lots, opts) return exports[LIB]:RegisterGarages(lots, opts) end,
        Reset = function() return exports[LIB]:ResetGarageRegistry() end,
    }

    CodemLib.Wardrobe = {
        Provider = function() return exports[LIB]:GetWardrobeProvider() end,
        Enabled = function() return exports[LIB]:GetWardrobeProvider() ~= 'none' end,
    }

    CodemLib.Weather = {
        ---@param weather string native hash name, uppercase
        ---@return boolean
        Set = function(weather) return exports[LIB]:SetWeather(weather) end,
        ---@param hour number
        ---@param minute number
        ---@return boolean
        SetTime = function(hour, minute) return exports[LIB]:SetGameTime(hour, minute) end,
        ---@param state boolean
        ---@return boolean
        SetBlackout = function(state) return exports[LIB]:SetBlackout(state) end,
        ---@param state boolean
        ---@return boolean
        SetFreeze = function(state) return exports[LIB]:SetTimeFreeze(state) end,
        ---@param state boolean
        ---@return boolean
        SetDynamic = function(state) return exports[LIB]:SetDynamicWeather(state) end,
        ---@return { weather: string, blackout: boolean, freezeTime: boolean, dynamic: boolean, provider: string|nil }
        State = function() return exports[LIB]:GetWeatherState() end,
        ---@return string|nil active weathersync resource name
        Provider = function() return exports[LIB]:GetWeatherProvider() end,
    }

    ---@param src number player server id (-1 = everyone)
    ---@param message string
    ---@param nType? string 'info'|'success'|'error'|'warning'
    ---@param duration? number ms
    CodemLib.Notify = function(src, message, nType, duration)
        return exports[LIB]:Notify(src, message, nType, duration)
    end

    --[[
        Owned vehicles.

        The framework's own table behind one interface: qb writes
        `player_vehicles`, ESX `owned_vehicles`, and they agree on nothing.
        Reads come back normalised (status as a word, health as 0-100), writes
        take the same words.
    ]]
    CodemLib.Vehicles = {
        ---@param limit? number @return table[]|nil nil = no supported framework
        List = function(limit) return exports[LIB]:GetVehicles(limit) end,
        ---@param owner string citizenid (qb) / identifier (esx)
        ---@param limit? number @return table[]|nil
        ByOwner = function(owner, limit) return exports[LIB]:GetOwnerVehicles(owner, limit) end,
        ---@param plate string @return table|nil
        Get = function(plate) return exports[LIB]:GetVehicle(plate) end,
        ---@return { total: number, garage: number, impound: number, outside: number }|nil
        Counts = function() return exports[LIB]:GetVehicleCounts() end,
        ---@param plate string, state 'garage'|'impound'|'outside' @return boolean
        SetState = function(plate, state) return exports[LIB]:SetVehicleState(plate, state) end,
        ---@param plate string, next string @return boolean
        SetPlate = function(plate, next_) return exports[LIB]:SetVehiclePlate(plate, next_) end,
        ---@param plate string, owner string, license? string @return boolean
        SetOwner = function(plate, owner, license) return exports[LIB]:SetVehicleOwner(plate, owner, license) end,
        ---@param plate string @return boolean
        Delete = function(plate) return exports[LIB]:DeleteVehicleRow(plate) end,
        ---@param owner string @return boolean
        DeleteByOwner = function(owner) return exports[LIB]:DeleteOwnerVehicles(owner) end,
        ---@param plate string @return boolean false when the framework keeps condition elsewhere
        Repair = function(plate) return exports[LIB]:RepairVehicleRow(plate) end,
        ---@param plate string @return boolean
        Refuel = function(plate) return exports[LIB]:RefuelVehicleRow(plate) end,
        ---@param data { owner: string, license?: string, model: string, plate: string, garage?: string }
        ---@return boolean
        Create = function(data) return exports[LIB]:CreateVehicleRow(data) end,
        ---Plate -> spawned entity, one pass over the world.
        ---@return table<string, number>
        Spawned = function() return exports[LIB]:GetSpawnedVehicles() end,
    }

    CodemLib.Inventory = {
        ---@param src number @return table items
        Items = function(src) return exports[LIB]:GetPlayerItems(src) end,
        ---@param src number, itemName string, count number, metadata? table, slot? number
        ---@return boolean success (providers that return nil on success are treated as success)
        Add = function(src, itemName, count, metadata, slot) return exports[LIB]:AddItem(src, itemName, count, metadata,
                slot) ~= false end,
        ---@return boolean success (nil = success)
        Remove = function(src, itemName, count, metadata, slot) return exports[LIB]:RemoveItem(src, itemName, count,
                metadata, slot) ~= false end,
        ---@return number
        Count = function(src, itemName, metadata) return exports[LIB]:GetItemCount(src, itemName, metadata) end,
        ---@param src number, itemName string, count? number, metadata? table @return boolean
        Has = function(src, itemName, count, metadata) return (exports[LIB]:GetItemCount(src, itemName, metadata) or 0) >=
            (count or 1) end,
        ---@param src number, itemName string, count? number, metadata? table @return boolean can carry (default true when provider has no check)
        CanCarry = function(src, itemName, count, metadata) return exports[LIB]:CanCarry(src, itemName, count or 1,
                metadata) end,
        Slot = function(src, slot) return exports[LIB]:GetItemSlot(src, slot) end,
        ---Item metadata for every item on the server.
        ---@return table<string, { label: string, weight: number, image: string|nil }>|nil
        Catalog = function() return exports[LIB]:GetItemCatalog() end,
        ---@param src number @return { slots: number|nil, maxWeight: number|nil }|nil kg
        Capacity = function(src) return exports[LIB]:GetCapacity(src) end,
        ---@param stashId string|number @return table|nil items (nil = provider cannot read stashes)
        Stash = function(stashId) return exports[LIB]:GetStashItems(stashId) end,
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
        ---The level as the fuel provider itself reports it (0-100).
        ---@param vehicle number vehicle entity
        Get = function(vehicle) return exports[LIB]:GetFuel(vehicle) end,
    }

    CodemLib.Doorlock = {
        Provider = function() return exports[LIB]:GetDoorlockProvider() end,
        Apply = function(door) return exports[LIB]:ApplyDoorlock(door) end,
        ApplyLeaves = function(leaves, locked) return exports[LIB]:ApplyDoorlockLeaves(leaves, locked) end,
        Clear = function() return exports[LIB]:ClearDoorlock() end,
    }

    CodemLib.Garage = {
        Provider = function() return exports[LIB]:GetGarageProvider() end,
        Enabled = function() return exports[LIB]:GetGarageProvider() ~= 'none' end,
        Name = function(id, pointId) return exports[LIB]:GarageName(id, pointId) end,
    }

    CodemLib.Wardrobe = {
        Provider = function() return exports[LIB]:GetWardrobeProvider() end,
        Enabled = function() return exports[LIB]:GetWardrobeProvider() ~= 'none' end,
        Open = function() return exports[LIB]:OpenWardrobe() end,
    }

    CodemLib.Weather = {
        ---@param enabled boolean pause weathersync for this player and force local weather/time (interiors)
        ---@param opts? { weather?: string, hour?: number, minute?: number }
        ---@return boolean
        LocalOverride = function(enabled, opts) return exports[LIB]:SetLocalWeatherOverride(enabled, opts) end,
        ---@return { weather: string, hour: number, minute: number }|nil
        LocalState = function() return exports[LIB]:GetLocalWeatherOverride() end,
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
        Has = function(itemName, count, metadata) return (exports[LIB]:GetItemCount(itemName, metadata) or 0) >=
            (count or 1) end,
        ItemData = function(itemName) return exports[LIB]:GetItemData(itemName) end,
        ---@return string|nil item icon url/path
        Image = function(itemName)
            local d = exports[LIB]:GetItemData(itemName); return d and d.image or nil
        end,
        ---@return string item label (falls back to the item name)
        Label = function(itemName)
            local d = exports[LIB]:GetItemData(itemName); return (d and d.label) or itemName
        end,
        Items = function() return exports[LIB]:GetPlayerItems() end,
        ---@param stashId string, invData? table @return boolean handled
        OpenStash = function(stashId, invData) return exports[LIB]:OpenStash(stashId, invData) end,
    }
end

if not IsDuplicityVersion() then
    loadLibFile('modules/garage/client.lua')
end
