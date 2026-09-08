Mdt = Mdt or {}

local cfg = (LibConfig and LibConfig.Mdt) or {}

local function warn(msg, ...)
    print(('^3[codem-lib mdt]^0 ' .. msg):format(...))
end

local function query(sql, params)
    local ok, rows = pcall(function() return MySQL.query.await(sql, params) end)
    if not ok then
        warn('query failed: %s', tostring(rows))
        return nil
    end
    return rows or {}
end

local function decodeDate(value)
    if value == nil then return nil end

    local num = tonumber(value)
    if num then
        if num > 1e11 then num = num / 1000 end
        return math.floor(num)
    end

    if type(value) ~= 'string' then return nil end
    local y, mo, d, h, mi, sec = value:match('^(%d%d%d%d)-(%d%d)-(%d%d)[ T](%d%d):(%d%d):?(%d?%d?)')
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) or 0 })
end

local function decodeCharges(raw)
    local list = raw
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        list = ok and decoded or nil
    end
    if type(list) ~= 'table' then return {} end
    if list.name then list = { list } end

    local out = {}
    for _, line in ipairs(list) do
        if type(line) == 'table' then
            out[#out + 1] = {
                name = tostring(line.name or line.label or 'Charge'),
                count = math.max(1, math.floor(tonumber(line.count) or 1)),
                amount = math.floor(tonumber(line.amount) or 0),
                jail = math.floor(tonumber(line.jailTime or line.jail_time) or 0),
                publicWork = math.floor(tonumber(line.publicWork or line.public_work) or 0),
                drivingScore = math.floor(tonumber(line.drivingScore or line.driving_score) or 0),
            }
        end
    end
    return out
end

local function chargeLabel(charges)
    local names = {}
    for _, charge in ipairs(charges) do
        names[#names + 1] = charge.count > 1 and ('%s x%d'):format(charge.name, charge.count) or charge.name
    end
    return #names > 0 and table.concat(names, ', ') or 'Charge'
end

local function str(value)
    return value ~= nil and tostring(value) or nil
end

local PROVIDERS = {
    ['codem-mdtv2'] = {
        penalties = function(identifier, limit)
            return query([[
                SELECT p.id, p.case_id, c.title AS case_title,
                       p.citizen_identifier, p.citizen_name, p.officer_identifier, p.officer_name,
                       p.charges, p.total_amount, p.total_jail, p.total_public_work, p.total_driving_score,
                       p.billing_status, p.invoice_id, p.created_at
                FROM `codem_mdtv2_penalties` p
                LEFT JOIN `codem_mdtv2_cases` c ON c.id = p.case_id
                WHERE p.citizen_identifier = ? AND p.deleted_at IS NULL
                ORDER BY p.created_at DESC
                LIMIT ?
            ]], { identifier, limit })
        end,

        summary = function(identifier)
            local rows = query([[
                SELECT
                    (SELECT COUNT(DISTINCT cc.case_id)
                       FROM `codem_mdtv2_case_citizens` cc
                       JOIN `codem_mdtv2_cases` c ON c.id = cc.case_id AND c.deleted_at IS NULL
                      WHERE cc.citizen_identifier = ?) AS cases,
                    (SELECT COUNT(DISTINCT rc.report_id)
                       FROM `codem_mdtv2_report_citizens` rc
                       JOIN `codem_mdtv2_reports` r ON r.id = rc.report_id AND r.deleted_at IS NULL
                      WHERE rc.citizen_identifier = ?) AS reports,
                    (SELECT COALESCE(SUM(total_amount), 0)
                       FROM `codem_mdtv2_penalties`
                      WHERE citizen_identifier = ? AND deleted_at IS NULL AND billing_status = 'paid') AS paid,
                    (SELECT COUNT(*)
                       FROM `codem_mdtv2_penalties`
                      WHERE citizen_identifier = ? AND deleted_at IS NULL AND billing_status <> 'paid') AS open,
                    (SELECT COUNT(*)
                       FROM `codem_mdtv2_penalties`
                      WHERE citizen_identifier = ? AND deleted_at IS NULL AND billing_status = 'paid') AS closed
            ]], { identifier, identifier, identifier, identifier, identifier })
            return rows and rows[1] or nil
        end,

        normalise = function(row)
            local charges = decodeCharges(row.charges)
            local paid = row.billing_status == 'paid'
            return {
                id = row.id,
                caseId = row.case_id,
                caseTitle = str(row.case_title),
                citizen = str(row.citizen_identifier),
                citizenName = str(row.citizen_name),
                officer = str(row.officer_identifier),
                officerName = str(row.officer_name),
                charges = charges,
                label = chargeLabel(charges),
                amount = math.floor(tonumber(row.total_amount) or 0),
                jail = math.floor(tonumber(row.total_jail) or 0),
                publicWork = math.floor(tonumber(row.total_public_work) or 0),
                drivingScore = math.floor(tonumber(row.total_driving_score) or 0),
                billingStatus = str(row.billing_status) or 'pending',
                paid = paid,
                invoiceId = str(row.invoice_id),
                date = decodeDate(row.created_at),
            }
        end,
    },
}

local CANDIDATES = { 'codem-mdtv2' }

local function enabled()
    return cfg.enabled ~= false and cfg.provider ~= false
end

local function provider()
    if not enabled() then return nil end

    local want = cfg.provider
    if want and want ~= 'auto' then return PROVIDERS[want] and want or nil end

    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return nil
end

local function active()
    local name = provider()
    return name and PROVIDERS[name] or nil, name
end

function Mdt.Provider()
    return provider()
end

function Mdt.Penalties(identifier, limit)
    local p = active()
    if not p or not MySQL then return nil end
    if type(identifier) ~= 'string' or identifier == '' then return {} end

    local rows = p.penalties(identifier, math.floor(tonumber(limit) or 200))
    if not rows then return nil end

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = p.normalise(row)
    end
    return out
end

function Mdt.Summary(identifier)
    local p = active()
    if not p or not MySQL then return nil end
    if type(identifier) ~= 'string' or identifier == '' then
        return { cases = 0, reports = 0, paid = 0, open = 0, closed = 0 }
    end

    local row = p.summary(identifier)
    if not row then return nil end

    return {
        cases = math.floor(tonumber(row.cases) or 0),
        reports = math.floor(tonumber(row.reports) or 0),
        paid = math.floor(tonumber(row.paid) or 0),
        open = math.floor(tonumber(row.open) or 0),
        closed = math.floor(tonumber(row.closed) or 0),
    }
end

exports('GetMdtPenalties', Mdt.Penalties)
exports('GetMdtSummary', Mdt.Summary)
exports('GetMdtProvider', Mdt.Provider)
