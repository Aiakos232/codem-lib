local PROVIDERS = {}

PROVIDERS['ps-dispatch'] = function(src, jobs, coords, data, blip, flash)
    TriggerEvent('ps-dispatch:server:notify', {
        jobs = jobs,
        coords = coords,
        code = data.code,
        message = data.title,
        length = data.length or blip.length,
        flash = flash,
        alert = {
            sound = (data.sound and (data.sound.alert or data.sound.name)) or 'Lose_1st',
            sound2 = (data.sound and data.sound.ref) or 'GTAO_FM_Events_Soundset',
            sprite = blip.sprite,
            scale = blip.scale,
            color = blip.colour,
            flashes = blip.flash,
            text = blip.text,
            length = blip.length,
        },
    })
end

PROVIDERS['cd_dispatch'] = function(src, jobs, coords, data, blip, flash)
    TriggerEvent('cd_dispatch:AddNotification', {
        job_table = jobs,
        coords = coords,
        title = data.title,
        message = data.description,
        flash = flash and 1 or 0,
        unique_id = tostring(math.random(0, 9999999)),
        sound = 1,
        blip = {
            sprite = blip.sprite,
            scale = blip.scale,
            colour = blip.colour,
            flashes = blip.flash,
            text = blip.text,
            time = blip.length,
            radius = 0,
        },
    })
end

PROVIDERS['codem-dispatch'] = function(src, jobs, coords, data, blip, flash)
    exports['codem-dispatch']:CustomDispatch({
        type = data.code or 'General',
        header = data.title,
        text = data.description,
        code = data.code,
    })
end

PROVIDERS['core_dispatch'] = function(src, jobs, coords, data, blip, flash)
    for _, job in ipairs(jobs) do
        exports['core_dispatch']:sendAlert({
            code = data.code,
            message = data.description,
            extraInfo = {},
            coords = coords,
            priority = flash or false,
            job = job,
            time = (data.length or blip.length or 5) * 60000,
            blip = blip.sprite,
            color = blip.colour,
        })
    end
end

PROVIDERS['aty_dispatch'] = function(src, jobs, coords, data, blip, flash)
    TriggerEvent('aty_dispatch:server:customDispatch',
        data.title or 'Alert', data.code or '10-11', { street = '', road = '' }, coords,
        nil, nil, nil, nil, blip.sprite, jobs)
end

PROVIDERS['rcore_dispatch'] = function(src, jobs, coords, data, blip, flash)
    TriggerEvent('rcore_dispatch:server:sendAlert', {
        code = data.code,
        default_priority = 'high',
        coords = coords,
        job = jobs,
        text = data.title,
        type = 'alerts',
        blip_time = (data.length or blip.length or 5) * 60,
        blip = { sprite = blip.sprite, colour = blip.colour, scale = blip.scale, text = blip.text },
    })
end

PROVIDERS['tk_dispatch'] = function(src, jobs, coords, data, blip, flash)
    exports.tk_dispatch:addCall({
        title = data.title,
        code = data.code,
        message = data.description,
        coords = coords,
        flash = flash,
        playSound = true,
        jobs = jobs,
        blip = { sprite = blip.sprite, scale = blip.scale, color = blip.colour, flash = blip.flash },
    })
end

PROVIDERS['lb-tablet'] = function(src, jobs, coords, data, blip, flash)
    for i = 1, #jobs do
        exports['lb-tablet']:AddDispatch({
            priority = 'high',
            code = data.code,
            title = data.title,
            description = data.description,
            location = { label = blip.text or data.title, coords = vector2(coords.x, coords.y) },
            time = (data.length or blip.length or 5) * 60,
            job = jobs[i],
            blip = { sprite = blip.sprite, color = blip.colour, size = blip.scale, label = blip.text },
        })
    end
end

PROVIDERS['origen_police'] = function(src, jobs, coords, data, blip, flash)
    for i = 1, #jobs do
        exports['origen_police']:SendAlert({
            coords = coords,
            title = data.title,
            type = 'GENERAL',
            message = data.description,
            job = jobs[i],
        })
    end
end

PROVIDERS['tgiann-policealert'] = function(src, jobs, coords, data, blip, flash)
    exports['tgiann-policealert']:Alert(src, {
        jobs = jobs,
        label = data.title,
        coords = coords,
        code = data.code,
        bgAnimate = false,
        vehicle = { label = true, plate = true, color = true },
        gender = true,
        sound = true,
        blip = blip.sprite,
    })
end

local function jobOf(p)
    local job = Framework.Server.GetPlayerJob(p)
    return type(job) == 'table' and job.name or job
end

PROVIDERS['native'] = function(src, jobs, coords, data, blip, flash)
    local set = {}
    for _, j in ipairs(jobs) do set[j] = true end
    for _, pid in ipairs(GetPlayers()) do
        local p = tonumber(pid)
        if set[jobOf(p)] then
            exports[GetCurrentResourceName()]:Notify(p, ('%s%s'):format(data.title or 'Alert', data.description and (' - ' .. data.description) or ''), 'error')
            TriggerClientEvent('codem-lib:client:dispatchBlip', p, coords, {
                sprite = blip.sprite, colour = blip.colour, scale = blip.scale, text = blip.text or data.title,
                flash = blip.flash, length = blip.length or data.length or 5,
            })
        end
    end
end

local CANDIDATES = {
    'ps-dispatch', 'cd_dispatch', 'codem-dispatch', 'core_dispatch', 'aty_dispatch', 'rcore_dispatch',
    'tk_dispatch', 'lb-tablet', 'origen_police', 'tgiann-policealert',
}

local function provider()
    local cfg = (LibConfig.Dispatch and LibConfig.Dispatch.provider) or 'auto'
    if cfg and cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'native'
end

local DEFAULT_BLIP = { sprite = 161, colour = 1, scale = 1.0, flash = true, length = 5, text = nil }

local function send(src, jobs, coords, data, blip, flash)
    if type(jobs) == 'string' then jobs = { jobs } end
    if type(jobs) ~= 'table' or #jobs == 0 then return false end
    if type(coords) == 'table' then coords = vector3(coords.x + 0.0, coords.y + 0.0, (coords.z or 0.0) + 0.0) end
    data = data or {}
    data.title = data.title or 'Alert'
    data.code = data.code or '10-11'
    blip = blip or {}
    for k, v in pairs(DEFAULT_BLIP) do if blip[k] == nil then blip[k] = v end end
    blip.text = blip.text or data.title
    local name = provider()
    local fn = PROVIDERS[name]
    if not fn then
        print(('[codem-lib] Dispatch: unknown provider "%s" - check LibConfig.Dispatch.provider'):format(name))
        fn = PROVIDERS['native']
    end
    local ok, err = pcall(fn, src or 0, jobs, coords, data, blip, flash == true)
    if not ok then
        print(('[codem-lib] Dispatch via "%s" failed: %s'):format(name, tostring(err)))
        return false
    end
    return true
end

exports('SendDispatch', send)
exports('GetDispatchProvider', provider)
