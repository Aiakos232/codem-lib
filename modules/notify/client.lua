--[[
    Notifications (client) — every provider in one file. Selection via LibConfig.Notify.provider
    ('auto' picks the first running notify script, then ox_lib if it is running,
    otherwise the framework native notification). ox_lib is optional.

    Exports:
      Notify(message, type?, duration?)   -- type: 'info'|'success'|'error'|'warning'
]]

-- m = message, t = type, d = duration (ms).
local PROVIDERS = {
    ['codem-notification'] = {
        notify = function(m, t, d) TriggerEvent('codem-notification:Create', m, t, nil, d) end,
    },

    -- Argument order is (type, text, duration) on this one.
    ['codem-supreme-notification'] = {
        notify = function(m, t, d) exports['codem-supreme-notification']:SendNotification(t, m, d) end,
    },

    ['okokNotify'] = {
        notify = function(m, t, d) exports['okokNotify']:Alert('', m, d, t, false) end,
    },

    ['brutal_notify'] = {
        notify = function(m, t, d) exports['brutal_notify']:SendAlert('Notification', m, d, t) end,
    },

    ['g-notifications'] = {
        notify = function(m, t)
            if t == 'inform' then t = 'info' end
            exports['g-notifications']:Notify({ title = 'Notification', description = m, type = t or 'info' })
        end,
    },

    ['is_ui'] = {
        notify = function(m, t, d) exports['is_ui']:Notify(m, nil, d, t) end,
    },

    ['lation_ui'] = {
        notify = function(m, t) exports.lation_ui:notify({ message = m, type = t or 'inform' }) end,
    },

    ['vms_notifyv2'] = {
        notify = function(m) exports['vms_notifyv2']:Notification({ description = m }) end,
    },

    ['wasabi_uikit'] = {
        notify = function(m, t) exports.wasabi_uikit:Notify({ title = m, type = t }) end,
    },

    ['mythic_notify'] = {
        notify = function(m, t) exports['mythic_notify']:DoHudText(t, m) end,
    },

    ['17mov_Hud'] = {
        notify = function(m, t) exports['17mov_Hud']:ShowNotification(m, t) end,
    },

    ['gs-notify'] = {
        notify = function(m, t, d)
            exports['gs-notify']:Notify(nil, { type = t, message = m, duration = d })
        end,
    },

    ['ox'] = {
        notify = function(m, t, d) exports.ox_lib:notify({ title = m, type = t, duration = d }) end,
    },

    -- Core framework notifications (event/export based).
    ['framework'] = {
        notify = function(m, t, d)
            if GetResourceState('qbx_core') == 'started' then
                exports.qbx_core:Notify(m, t, d)
            elseif GetResourceState('qb-core') == 'started' then
                TriggerEvent('QBCore:Notify', m, t, d)
            elseif GetResourceState('es_extended') == 'started' then
                TriggerEvent('esx:showNotification', m)
            elseif CodemOxReady() then
                exports.ox_lib:notify({ title = m, type = t, duration = d })
            else
                print(('[codem-lib] Notify: no provider available for "%s"'):format(m))
            end
        end,
    },
}

-- 'auto' detection order — dedicated notify scripts win; then ox_lib (if
-- running), else the framework native notification.
local CANDIDATES = {
    'codem-supreme-notification',
    'codem-notification', 'okokNotify', 'brutal_notify', 'g-notifications',
    'is_ui', 'lation_ui', 'vms_notifyv2', 'wasabi_uikit',
    'mythic_notify', '17mov_Hud', 'gs-notify',
}

local function provider()
    local cfg = (LibConfig.Notify and LibConfig.Notify.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    -- ox_lib when running, otherwise the framework native notification.
    if CodemOxReady() then return 'ox' end
    return 'framework'
end


local NTYPE_ALIAS = {
    info = 'inform', inform = 'inform',
    warn = 'warning', warning = 'warning',
    error = 'error', success = 'success',
}

local function notify(message, nType, duration)
    nType = NTYPE_ALIAS[nType or 'inform'] or 'inform'
    duration = duration or 4000

    local p = PROVIDERS[provider()]
    if not p then
        print(('[codem-lib] Notify: unknown provider "%s" - check LibConfig.Notify.provider'):format(provider()))
        return false
    end
    local ok, err = pcall(p.notify, message, nType, duration)
    if not ok then
        print(('[codem-lib] Notify via "%s" failed: %s'):format(provider(), tostring(err)))
        return false
    end
    return true
end

exports('Notify', notify)

-- The server export lands here.
RegisterNetEvent('codem-lib:notify', function(message, nType, duration)
    notify(message, nType, duration)
end)
