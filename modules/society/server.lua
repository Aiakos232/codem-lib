--[[
    Society / job fund (server) — routes an owned mechanic's earnings into the
    shop's banking account, and can pull money back out (refunds, wages, admin
    panel deposits/withdraws). One module, framework-agnostic: the banking
    resource is picked by LibConfig.Society.provider ('auto' detects a running one).

    Global API:
      Society.Pay(account, amount)     -> deposit into the society fund
      Society.Remove(account, amount)  -> withdraw from the society fund
      Society.Balance(account)         -> current fund balance (number)

    single table here). Adding a banking script = one PROVIDERS entry. Every
    export call is pcall-guarded, so a wrong provider / missing export logs a
    warning instead of breaking the purchase.
]]

Society = Society or {}

local PROVIDERS = {
    ['qb-banking'] = {
        add    = function(a, n) return exports['qb-banking']:AddMoney(a, n) end,
        remove = function(a, n) return exports['qb-banking']:RemoveMoney(a, n) end,
        get    = function(a)
            local acc = exports['qb-banking']:GetAccount(a)
            return acc and acc.account_balance or 0
        end,
    },

    ['qb-management'] = {
        add    = function(a, n) return exports['qb-management']:AddMoney(a, n) end,
        remove = function(a, n) return exports['qb-management']:RemoveMoney(a, n) end,
        get    = function(a) return exports['qb-management']:GetAccount(a) end,
    },

    ['Renewed-Banking'] = {
        add    = function(a, n) return exports['Renewed-Banking']:addAccountMoney(a, n) end,
        remove = function(a, n) return exports['Renewed-Banking']:removeAccountMoney(a, n) end,
        get    = function(a) return exports['Renewed-Banking']:getAccountMoney(a) end,
    },

    ['okokBanking'] = {
        add    = function(a, n) exports['okokBanking']:AddMoney(a, n) end,
        remove = function(a, n) exports['okokBanking']:RemoveMoney(a, n) end,
        get    = function(a) return exports['okokBanking']:GetAccount(a) end,
    },

    ['fd_banking'] = {
        add    = function(a, n) return exports.fd_banking:AddMoney(a, n) end,
        remove = function(a, n) return exports.fd_banking:RemoveMoney(a, n) end,
        get    = function(a)
            local acc = exports.fd_banking:GetAccount(a)
            return acc and acc.account_balance or 0
        end,
    },

    ['tgg-banking'] = {
        add    = function(a, n) return exports['tgg-banking']:AddSocietyMoney(a, n) end,
        remove = function(a, n) return exports['tgg-banking']:RemoveSocietyMoney(a, n) end,
        get    = function(a) return exports['tgg-banking']:GetSocietyAccountMoney(a) end,
    },

    ['tgiann-bank'] = {
        add    = function(a, n) return exports['tgiann-bank']:AddJobMoney(a, n) end,
        remove = function(a, n) return exports['tgiann-bank']:RemoveJobMoney(a, n) end,
        get    = function(a) return exports['tgiann-bank']:GetJobAccountBalance(a) end,
    },

    ['RxBanking'] = {
        add    = function(a, n) return exports['RxBanking']:AddSocietyMoney(a, n) end,
        remove = function(a, n) return exports['RxBanking']:RemoveSocietyMoney(a, n) end,
        get    = function(a)
            local data = exports['RxBanking']:GetSocietyAccount(a)
            if type(data) == 'number' then return data end
            return data and (data.money or data.balance) or 0
        end,
    },

    ['crm-banking'] = {
        add    = function(a, n) return exports['crm-banking']:addSocietyMoney(a, n) end,
        remove = function(a, n) return exports['crm-banking']:removeSocietyMoney(a, n) end,
        get    = function(a) return exports['crm-banking']:getSocietyMoney(a) end,
    },

    ['kartik-banking'] = {
        add    = function(a, n) return exports['kartik-banking']:AddAccountMoney(a, n) end,
        remove = function(a, n) return exports['kartik-banking']:RemoveAccountMoney(a, n) end,
        get    = function(a) return exports['kartik-banking']:GetAccountMoney(a) end,
    },

    ['nass_bossmenu'] = {
        add    = function(a, n) exports['nass_bossmenu']:addMoney(a, n) end,
        remove = function(a, n) return exports['nass_bossmenu']:removeMoney(a, n) end,
        get    = function(a) return exports['nass_bossmenu']:getAccount(a) end,
    },


    ['nfs-banking'] = {
        add    = function(a, n) return exports['nfs-banking']:addAccountMoney(a, n) end,
        remove = function(a, n) return exports['nfs-banking']:removeAccountMoney(a, n) end,
        get    = function(a) return exports['nfs-banking']:getAccountMoney(a) end,
    },

    ['nfs-billing'] = {
        add    = function(a, n) exports['nfs-billing']:depositSociety(a, n) end,
        remove = function(a, n) exports['nfs-billing']:withdrawSociety(a, n) end,
        get    = function(a) return exports['nfs-billing']:getSocietyBalance(a) end,
    },

    ['p_banking'] = {
        add    = function(a, n) return exports['p_banking']:addAccountMoney(a, n) end,
        remove = function(a, n) return exports['p_banking']:removeAccountMoney(a, n) end,
        get    = function(a) return exports['p_banking']:getAccountMoney(a) end,
    },

    ['qs-banking'] = {
        add    = function(a, n) return exports['qs-banking']:AddMoney(a, n) end,
        remove = function(a, n) return exports['qs-banking']:RemoveMoney(a, n) end,
        get    = function(a) return exports['qs-banking']:GetAccountBalance(a) end,
    },

    ['sd-multijob'] = {
        add    = function(a, n) return exports['sd-multijob']:addSocietyDeposit(0, a, n, 'bank') end,
        remove = function(a, n) return exports['sd-multijob']:withdrawSocietyFunds(0, a, n, 'bank') end,
        get    = function(a) return exports['sd-multijob']:getSocietyBalance(a) end,
    },

    ['snipe-banking'] = {
        add    = function(a, n) return exports['snipe-banking']:AddMoneyToAccount(a, n) end,
        remove = function(a, n) return exports['snipe-banking']:RemoveMoneyFromAccount(a, n) end,
        get    = function(a) return exports['snipe-banking']:GetAccountBalance(a) end,
    },


    ['vms_bossmenu'] = {
        add    = function(a, n)
            local result = nil
            exports['vms_bossmenu']:addMoney(a, n, function(success) result = success end)
            while result == nil do Wait(1) end
            return result
        end,
        remove = function(a, n)
            local result = nil
            exports['vms_bossmenu']:removeMoney(a, n, function(success) result = success end)
            while result == nil do Wait(1) end
            return result
        end,
        get    = function(a)
            local acc = exports['vms_bossmenu']:getSociety(a)
            return acc and acc.balance or 0
        end,
    },

    ['wasabi_banking'] = {
        add    = function(a, n) return exports['wasabi_banking']:AddMoney('society', a, n) end,
        remove = function(a, n) return exports['wasabi_banking']:RemoveMoney('society', a, n) end,
        get    = function(a) return exports['wasabi_banking']:GetAccountBalance(a, 'society') end,
    },

    ['xnr-bossmenu'] = {
        add    = function(a, n) return exports['xnr-bossmenu']:addMoney(a, n) end,
        remove = function(a, n) return exports['xnr-bossmenu']:removeMoney(a, n) end,
        get    = function(a)
            local acc = exports['xnr-bossmenu']:getSociety(a)
            return acc and acc.balance or 0
        end,
    },

    ['esx_addonaccount'] = {
        add    = function(a, n)
            local acc = exports['esx_addonaccount']:GetSharedAccount(('society_%s'):format(a))
            if not acc then return false end
            acc.addMoney(n)
            return true
        end,
        remove = function(a, n)
            local acc = exports['esx_addonaccount']:GetSharedAccount(('society_%s'):format(a))
            if not acc then return false end
            acc.removeMoney(n)
            return true
        end,
        get    = function(a)
            local acc = exports['esx_addonaccount']:GetSharedAccount(('society_%s'):format(a))
            return acc and acc.money or 0
        end,
    },
}


local ALIASES = {
    ['esx'] = 'esx_addonaccount',
    ['nass_bosmenu'] = 'nass_bossmenu',
}

-- Detection order for 'auto'. First running resource wins.
local CANDIDATES = {
    'qb-banking', 'qb-management', 'Renewed-Banking', 'okokBanking',
    'fd_banking', 'tgg-banking', 'tgiann-bank', 'qs-banking',
    'wasabi_banking', 'snipe-banking', 'crm-banking', 'kartik-banking',
    'p_banking', 'nfs-banking', 'nfs-billing', 'RxBanking',
    'sd-multijob', 'vms_bossmenu', 'nass_bossmenu', 'xnr-bossmenu',
    'esx_addonaccount',
}

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

---Resolve the active banking provider (config override or auto-detect).
---@return string
local function provider()
    local cfg = (LibConfig.Society and LibConfig.Society.provider) or 'auto'
    cfg = ALIASES[cfg] or cfg
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'none'
end

---@return boolean
local function enabled()
    return LibConfig.Society ~= nil and LibConfig.Society.enabled == true
end

---Run a provider call, pcall-guarded. Returns ok, result.
---@param verb 'add'|'remove'|'get'
local function dispatch(verb, account, amount)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Society.%s: no banking provider for "%s" - set LibConfig.Society.provider')
            :format(verb, tostring(name)))
        return false
    end
    local ok, res = pcall(p[verb], account, amount)
    if not ok then
        print(('[codem-lib] Society.%s via "%s" failed: %s'):format(verb, name, tostring(res)))
        return false
    end
    return res ~= false, res
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Deposit into a society/job fund.
---@param account string society name (usually the mechanic job)
---@param amount number
---@return boolean
function Society.Pay(account, amount)
    if not enabled() or not account or type(amount) ~= 'number' or amount <= 0 then return false end
    return (dispatch('add', account, math.floor(amount + 0.5))) == true
end

---Withdraw from a society/job fund.
---@param account string
---@param amount number
---@return boolean
function Society.Remove(account, amount)
    if not enabled() or not account or type(amount) ~= 'number' or amount <= 0 then return false end
    return (dispatch('remove', account, math.floor(amount + 0.5))) == true
end

---Read a society/job fund balance.
---@param account string
---@return number
function Society.Balance(account)
    if not account then return 0 end
    local ok, res = dispatch('get', account, nil)
    return (ok and tonumber(res)) or 0
end

--------------------------------------------------------------------------------
-- Exports — consumer scripts call these (via the init.lua shim)
--------------------------------------------------------------------------------

exports('SocietyPay', Society.Pay)
exports('SocietyRemove', Society.Remove)
exports('SocietyBalance', Society.Balance)
