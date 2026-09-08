--[[
    Billing (server) — sends an invoice to a player through whichever billing
    resource the server runs, and reports back when it is paid. One module,
    provider-agnostic: the resource is picked by LibConfig.Billing.provider
    ('auto' detects a running one).

    Global API:
      Billing.Send(data)        -> invoiceId | false, reason
      Billing.IsPaid(invoiceId) -> boolean
      Billing.BillsTable()      -> provider's invoice table name | nil
      Billing.Provider()        -> active provider name | nil

    `data` fields:
      identifier   citizenid / identifier of the player being billed (required)
      amount       invoice total (required)
      reason       label shown on the invoice
      senderSource server id of the player sending it (used for the job + commission)
      job          override the sender job name (defaults to the sender's job)
      jobLabel     override the displayed sender name
      senderAccount override which account the provider pays out to once the
                   invoice is settled. Default 'job_<job>' = the billing
                   resource's own job vault (it splits commission / vault
                   itself). Pass 'SYSTEM' for a charge that must not pay anyone
                   - e.g. a cost line the customer covers but nobody earns.
      maxDistance  override LibConfig.Billing.maxDistance for this call

    Paid invoices fire the server event `codem-lib:billing:invoicePaid`
    (invoiceId, provider) on every consumer script, whichever provider is used.

    Cancellations are not evented - a cancelled invoice is simply gone from the
    provider's table. Ask Billing.BillsTable() and look the id up yourself when
    you need to know, so any removal path (cancel, admin delete, manual SQL) is
    covered by one check.
]]

Billing = Billing or {}

local cfg = (LibConfig and LibConfig.Billing) or {}

local function warn(msg, ...)
    print(('^3[codem-lib billing]^0 ' .. msg):format(...))
end

local function query(sql, params)
    local ok, rows = pcall(function() return MySQL.query.await(sql, params) end)
    if not ok then
        warn('query failed: %s', tostring(rows))
        return nil
    end
    return rows or {}
end

local function update(sql, params)
    local ok, affected = pcall(function() return MySQL.update.await(sql, params) end)
    if not ok then
        warn('update failed: %s', tostring(affected))
        return nil
    end
    return tonumber(affected) or 0
end

local function marks(n)
    local out = {}
    for i = 1, n do out[i] = '?' end
    return table.concat(out, ', ')
end

local function withTail(list, extra)
    local out = { table.unpack(list) }
    out[#out + 1] = extra
    return out
end

local function decodeDate(value)
    if value == nil then return nil, nil end

    local num = tonumber(value)
    if num then
        if num > 1e11 then num = num / 1000 end
        return math.floor(num), nil
    end

    if type(value) ~= 'string' then return nil, tostring(value) end

    local y, mo, d, h, mi, sec = value:match('^(%d%d%d%d)-(%d%d)-(%d%d)[ T](%d%d):(%d%d):?(%d?%d?)')
    if y then
        return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) or 0 }), nil
    end
    y, mo, d = value:match('^(%d%d%d%d)-(%d%d)-(%d%d)$')
    if y then
        return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }), nil
    end
    return nil, value
end

local function decodeReason(raw)
    if raw == nil then return nil end
    local text = tostring(raw)
    local first = text:match('^%s*(.)')
    if first ~= '[' and first ~= '{' then return text end

    local ok, decoded = pcall(json.decode, text)
    if not ok or type(decoded) ~= 'table' then return text end
    if decoded.reason or decoded.name then decoded = { decoded } end

    local parts = {}
    for _, line in ipairs(decoded) do
        local label = type(line) == 'table' and (line.reason or line.name or line.label) or line
        if label ~= nil and tostring(label) ~= '' then parts[#parts + 1] = tostring(label) end
    end
    return #parts > 0 and table.concat(parts, ', ') or text
end

local function societyOf(sender)
    if type(sender) == 'string' and sender:sub(1, 4) == 'job_' then return sender end
    return nil
end

local function str(value)
    return value ~= nil and tostring(value) or nil
end

local function billsQueries(tbl)
    return {
        list = function(ids, limit)
            return query(('SELECT * FROM `%s` WHERE `targetidentifier` IN (%s) ORDER BY `id` DESC LIMIT ?')
                :format(tbl, marks(#ids)), withTail(ids, limit))
        end,
        get = function(invoiceId)
            local rows = query(('SELECT * FROM `%s` WHERE `invoiceid` = ? LIMIT 1'):format(tbl), { invoiceId })
            return rows and rows[1] or nil
        end,
        markPaid = function(invoiceId)
            return update(("UPDATE `%s` SET `status` = 'paid' WHERE `invoiceid` = ?"):format(tbl), { invoiceId })
        end,
        cancel = function(invoiceId)
            return update(('DELETE FROM `%s` WHERE `invoiceid` = ?'):format(tbl), { invoiceId })
        end,
        cancelUnpaid = function(ids)
            return update(("DELETE FROM `%s` WHERE `targetidentifier` IN (%s) AND `status` <> 'paid'")
                :format(tbl, marks(#ids)), ids)
        end,
    }
end

local PROVIDERS = {
    ['codem-phone'] = {
        paidEvent = 'codem-phone:server:billing:invoicePaid',
        billsTable = 'codem_mphone_newbilling_bills',

        send = function(target, data)
            return exports['codem-phone']:CreateBillingCustom(
                target,
                data.amount,
                data.reason,
                data.senderAccount or ('job_' .. data.job),
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

        bills = billsQueries('codem_mphone_newbilling_bills'),

        normalise = function(row)
            local paid = row.status == 'paid'
            local date, dateText = decodeDate(row.created_date)
            return {
                id = row.id,
                invoiceId = str(row.invoiceid or row.id),
                receiver = str(row.targetidentifier),
                receiverName = str(row.targetname),
                sender = str(row.identifier),
                senderName = str(row.identifiername),
                creator = str(row.creator_identifier),
                creatorName = str(row.creator_name),
                amount = math.floor(tonumber(row.amount) or 0),
                reason = decodeReason(row.charges),
                status = paid and 'paid' or 'unpaid',
                rawStatus = str(row.status),
                paid = paid,
                tax = row.tax_id ~= nil,
                system = row.identifier == 'SYSTEM',
                society = societyOf(row.identifier),
                kind = nil,
                date = date,
                dateText = dateText,
                overdueDate = (decodeDate(row.overdue_date)),
            }
        end,
    },

    ['codem-billingv2'] = {
        paidEvent = 'codem-billingv2:server:billing:invoicePaid',
        billsTable = 'codem_billing_data',

        send = function(target, data)
            return exports['codem-billingv2']:CreateBillingCustom(
                target,
                data.amount,
                data.reason,
                false,
                data.senderAccount or ('job_' .. data.job),
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

        bills = billsQueries('codem_billing_data'),

        pay = function(src, invoiceId)
            local result = exports['codem-billingv2']:PayBilling(src, invoiceId)
            return type(result) == 'table' and result.success == true
        end,

        normalise = function(row)
            local paid = row.status == 'paid'
            local kind = row.billtype ~= nil and tostring(row.billtype):lower() or nil
            local date, dateText = decodeDate(row.date)
            return {
                id = row.id,
                invoiceId = str(row.invoiceid or row.id),
                receiver = str(row.targetidentifier),
                receiverName = str(row.targetname),
                sender = str(row.identifier),
                senderName = str(row.identifiername),
                creator = str(row.creator_identifier),
                creatorName = nil,
                amount = math.floor(tonumber(row.amount) or 0),
                reason = decodeReason(row.reason),
                status = paid and 'paid' or 'unpaid',
                rawStatus = str(row.status),
                paid = paid,
                tax = row.identifier == 'systemtax' or (kind ~= nil and kind:find('tax', 1, true) ~= nil),
                system = row.identifier == 'system' or row.identifier == 'systemtax',
                society = societyOf(row.identifier),
                kind = kind,
                date = date,
                dateText = dateText,
                overdueDate = (decodeDate(row.overduedate)),
            }
        end,
    },
}

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

local function active()
    local name = Billing.Provider()
    return name and PROVIDERS[name] or nil, name
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

local function identifierList(identifiers)
    local out = {}
    if type(identifiers) == 'string' then
        if identifiers ~= '' then out[1] = identifiers end
    elseif type(identifiers) == 'table' then
        for _, id in ipairs(identifiers) do
            if type(id) == 'string' and id ~= '' then out[#out + 1] = id end
        end
    end
    return out
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
        senderAccount = data.senderAccount,
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
    if not provider or not invoiceId or not MySQL then return false end
    local ok, paid = pcall(PROVIDERS[provider].isPaid, invoiceId)
    return ok and paid == true
end

function Billing.List(identifiers, limit)
    local p = active()
    if not p or not MySQL then return nil end

    local ids = identifierList(identifiers)
    if #ids == 0 then return {} end

    local rows = p.bills.list(ids, math.floor(tonumber(limit) or 200))
    if not rows then return nil end

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = p.normalise(row)
    end
    return out
end

function Billing.Get(invoiceId)
    local p = active()
    if not p or not MySQL or invoiceId == nil then return nil end

    local row = p.bills.get(tostring(invoiceId))
    return row and p.normalise(row) or nil
end

function Billing.ForcePay(invoiceId, opts)
    opts = type(opts) == 'table' and opts or {}

    local p, name = active()
    if not p or not MySQL then return { ok = false, charged = false, reason = 'no billing resource' } end

    local row = Billing.Get(invoiceId)
    if not row then return { ok = false, charged = false, reason = 'not found' } end
    if row.paid then return { ok = false, charged = false, reason = 'already paid' } end

    local framework = fw()
    local src = row.receiver and sourceFromIdentifier(row.receiver) or nil
    local charge = opts.charge ~= false and row.amount > 0

    if charge and src and p.pay then
        local ok, settled = pcall(p.pay, src, row.invoiceId)
        if ok and settled then
            if cfg.debug or (LibConfig and LibConfig.Debug) then
                warn('invoice %s force-paid through %s', row.invoiceId, name)
            end
            return { ok = true, charged = true, account = 'provider' }
        end
    end

    local charged, account = false, nil
    if charge and src and framework and framework.RemoveMoney then
        for _, acc in ipairs({ 'bank', 'cash' }) do
            local ok, removed = pcall(framework.RemoveMoney, src, row.amount, acc)
            if ok and removed then
                charged, account = true, acc
                break
            end
        end
    end

    if not charged and opts.force == false then
        return { ok = false, charged = false, reason = 'insufficient funds' }
    end

    if (p.bills.markPaid(row.invoiceId) or 0) == 0 then
        if charged and framework and framework.AddMoney then
            pcall(framework.AddMoney, src, row.amount, account)
        end
        return { ok = false, charged = false, reason = 'update failed' }
    end

    if charged and row.society and Society and Society.Pay then
        pcall(Society.Pay, row.society:gsub('^job_', ''), row.amount)
    end

    TriggerEvent(p.paidEvent, row.invoiceId)

    if cfg.debug or (LibConfig and LibConfig.Debug) then
        warn('invoice %s force-paid (%s)', row.invoiceId, charged and ('charged ' .. account) or 'not charged')
    end

    return { ok = true, charged = charged, account = account }
end

function Billing.Cancel(invoiceId)
    local p = active()
    if not p or not MySQL or invoiceId == nil then return false end
    return (p.bills.cancel(tostring(invoiceId)) or 0) > 0
end

function Billing.CancelUnpaid(identifiers)
    local p = active()
    if not p or not MySQL then return nil end

    local ids = identifierList(identifiers)
    if #ids == 0 then return 0 end

    return p.bills.cancelUnpaid(ids)
end

---Where the active provider keeps its invoices - one row per invoice, keyed by
---an `invoiceid` column. A cancelled invoice is deleted from it, so a consumer
---that stored an invoice id can check whether it is still there.
---@return string|nil table name, nil when billing is off / provider unknown
function Billing.BillsTable()
    local provider = Billing.Provider()
    return provider and PROVIDERS[provider].billsTable or nil
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
exports('GetInvoices', Billing.List)
exports('GetInvoice', Billing.Get)
exports('ForcePayInvoice', Billing.ForcePay)
exports('CancelInvoice', Billing.Cancel)
exports('CancelUnpaidInvoices', Billing.CancelUnpaid)
exports('GetBillingTable', Billing.BillsTable)
exports('GetBillingProvider', Billing.Provider)
