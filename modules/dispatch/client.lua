RegisterNetEvent('codem-lib:client:dispatchBlip', function(coords, b)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end
    local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, (coords.z or 0.0) + 0.0)
    SetBlipSprite(blip, b.sprite or 161)
    SetBlipColour(blip, b.colour or 1)
    SetBlipScale(blip, (b.scale or 1.0) + 0.0)
    SetBlipAsShortRange(blip, false)
    if b.flash ~= false then SetBlipFlashes(blip, true) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.text or 'Alert')
    EndTextCommandSetBlipName(blip)
    SetTimeout(math.floor((b.length or 5) * 60000), function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)
