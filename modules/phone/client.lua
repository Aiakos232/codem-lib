--[[
    Phone (client) — refresh hook. Some phone resources cache the number on
    the client; after the server rewrites it, the phone has to reload its own
    data or it keeps showing the old number until the next relog.
]]

RegisterNetEvent('codem-lib:phone:reload', function()
    if GetResourceState('lb-phone') == 'started' then
        pcall(function() exports['lb-phone']:ReloadPhone() end)
    end
end)
