--[[
    Billing (server) — sends an invoice to a player through whichever billing
    resource the server runs, and reports back when it is paid. One module,
    provider-agnostic: the resource is picked by LibConfig.Billing.provider
    ('auto' detects a running one).

    Global API:
      Billing.Send(data)        -> invoiceId | false, reason
      Billing.IsPaid(invoiceId) -> boolean
      Billing.Provider()        -> active provider name | nil

    `data` fields:
      identifier   citizenid / identifier of the player being billed (required)
      amount       invoice total (required)
      reason       label shown on the invoice
      senderSource server id of the player sending it (used for the job + commission)
      job          override the sender job name (defaults to the sender's job)
      jobLabel     override the displayed sender name
      maxDistance  override LibConfig.Billing.maxDistance for this call

    Paid invoices fire the server event `codem-lib:billing:invoicePaid`
    (invoiceId, provider) on every consumer script, whichever provider is used.
]]

Billing = Billing or {}

local PROVIDERS = {
    ['codem-phone'] = {
        paidEvent = 'codem-phone:server:billing:invoicePaid',

        send = function(target, data)
            return exports['codem-phone']:CreateBillingCustom(
                target,
                data.amount,
                data.reason,
                'job_' .. data.job,
                data.jobLabel,
                data.senderIdentifier
            )
        end,

        isPaid = function(invoiceId)
            local row = MySQL.query.await(
                'SELECT status FROM codem_mphone_newbilling_bills WHERE invoiceid = ? LIMIT 1',
                { tostring(invoiceId) }
            )
            return row and row[1] and row[1].status == 'paid'
        end,
    },

    ['codem-billingv2'] = {
        paidEvent = 'codem-billingv2:server:billing:invoicePaid',

        send = function(target, data)
            return exports['codem-billingv2']:CreateBillingCustom(
                target,
                data.amount,
                data.reason,
                false,
                'job_' .. data.job,
                data.jobLabel,
                data.senderIdentifier,
                data.job
            )
        end,

        isPaid = function(invoiceId)
            local row = MySQL.query.await(
                'SELECT status FROM codem_billing_data WHERE invoiceid = ? LIMIT 1',
                { tostring(invoiceId) }
            )
            return row and row[1] and row[1].status == 'paid'
        end,
    },
}

local cfg = (LibConfig and LibConfig.Billing) or {}

local function warn(msg, ...)
    print(('^3[codem-lib billing]^0 ' .. msg):format(...))
end

local function enabled()
    return cfg.enabled ~= false and cfg.provider ~= false
end

local resolved

---Active provider name, or nil when billing is off / nothing is running.
---@return string|nil
function Billing.Provider()
    if not enabled() then return nil end
    if resolved ~= nil then return resolved or nil end

    local want = cfg.provider
    if want and want ~= 'auto' then
        resolved = PROVIDERS[want] and want or false
        if resolved == false then
            print(('^3[codem-lib]^0 unknown billing provider: %s'):format(tostring(want)))
        end
        return resolved or nil
    end

    for name in pairs(PROVIDERS) do
        if GetResourceState(name) == 'started' then
            resolved = name
            return name
        end
    end

    return nil
end

---The framework bridge loaded by framework.lua (server side).
---@return table|nil
local function fw()
    return CodemLib and CodemLib.Framework or nil
end

---Server id of an online player by citizenid / identifier.
---@param identifier string
---@return number|nil
local function sourceFromIdentifier(identifier)
    local framework = fw()
    if not framework or type(identifier) ~= 'string' or identifier == '' then return nil end
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        if src and framework.GetIdentifier(src) == identifier then return src end
    end
    return nil
end

---@param senderSource number|nil
---@param targetSource number
---@param maxDistance number|nil
---@return boolean ok, string|nil reason
local function withinRange(senderSource, targetSource, maxDistance)
    local maxDist = tonumber(maxDistance) or tonumber(cfg.maxDistance) or 0
    if maxDist <= 0 or not senderSource then return true end

    local a, b = GetPlayerPed(senderSource), GetPlayerPed(targetSource)
    if not a or a == 0 or not b or b == 0 then return false, 'player not found' end

    local dist = #(GetEntityCoords(a) - GetEntityCoords(b))
    if dist > maxDist then
        return false, ('too far away (%.1fm / %.1fm)'):format(dist, maxDist)
    end
    return true
end

---Send an invoice. Returns the provider's invoice id on success.
---@param data table
---@return string|false invoiceId
---@return string|nil reason
function Billing.Send(data)
    if type(data) ~= 'table' then return false, 'invalid request' end

    local provider = Billing.Provider()
    if not provider then
        warn('no billing resource running (LibConfig.Billing.provider = %s)', tostring(cfg.provider))
        return false, 'no billing resource'
    end

    local amount = math.floor(tonumber(data.amount) or 0)
    if amount <= 0 then
        warn('invalid amount: %s', tostring(data.amount))
        return false, 'invalid amount'
    end

    local target = tonumber(data.targetSource) or sourceFromIdentifier(data.identifier)
    if not target then
        warn('player not online for identifier %s (framework bridge: %s)',
            tostring(data.identifier), fw() and 'ok' or 'MISSING')
        return false, 'player not online'
    end

    local ok, reason = withinRange(data.senderSource, target, data.maxDistance)
    if not ok then
        warn('distance check failed: %s', tostring(reason))
        return false, reason
    end

    local job, jobLabel = data.job, data.jobLabel
    local senderIdentifier
    local framework = fw()
    if data.senderSource and framework then
        senderIdentifier = framework.GetIdentifier(data.senderSource)
        local senderJob = framework.GetPlayerJob(data.senderSource)
        if senderJob then
            job = job or senderJob.name
            jobLabel = jobLabel or senderJob.label
        end
    end
    job = job or 'unemployed'
    jobLabel = jobLabel or job:upper()

    local sent, invoiceId = pcall(PROVIDERS[provider].send, target, {
        amount = amount,
        reason = tostring(data.reason or 'Invoice'),
        job = job,
        jobLabel = jobLabel,
        senderIdentifier = senderIdentifier,
    })

    if not sent then
        warn('%s export error: %s', provider, tostring(invoiceId))
        return false, 'billing error'
    end
    if not invoiceId then
        warn('%s returned no invoice id (target %s, $%d)', provider, tostring(target), amount)
        return false, 'billing rejected'
    end

    if cfg.debug or (LibConfig and LibConfig.Debug) then
        warn('invoice %s sent via %s to src %s ($%d)', tostring(invoiceId), provider, tostring(target), amount)
    end

    return tostring(invoiceId)
end

---Has an invoice been settled?
---@param invoiceId string|number
---@return boolean
function Billing.IsPaid(invoiceId)
    local provider = Billing.Provider()
    if not provider or not invoiceId then return false end
    local ok, paid = pcall(PROVIDERS[provider].isPaid, invoiceId)
    return ok and paid == true
end

for name, provider in pairs(PROVIDERS) do
    if provider.paidEvent then
        AddEventHandler(provider.paidEvent, function(invoiceId)
            if not invoiceId then return end
            TriggerEvent('codem-lib:billing:invoicePaid', tostring(invoiceId), name)
        end)
    end
end

exports('SendInvoice', Billing.Send)
exports('IsInvoicePaid', Billing.IsPaid)
exports('GetBillingProvider', Billing.Provider)
