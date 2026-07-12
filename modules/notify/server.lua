--[[
    Notifications (server) — forwards to the target player's client, where the
    configured provider (modules/notify/client.lua) renders it.

    Exports:
      Notify(src, message, type?, duration?)   -- src = -1 notifies everyone
]]

local function notify(src, message, nType, duration)
    if not src then return false end
    TriggerClientEvent('codem-lib:notify', src, message, nType, duration)
    return true
end

exports('Notify', notify)
