-- Perf (L6-L, G57): `<slash> perf` prints the timing rows the kernel's
-- meter keeps for each module (the rows a diag snapshot stores), slowest
-- first: how long its handlers, ticks and jobs have taken since the
-- interface loaded, in how many calls, and how many raised.
--
--   <slash> perf          the slowest Perf.DEFAULT_ROWS
--   <slash> perf <n>      the slowest n
--   <slash> perf all      every one
--
-- It only reads a copy of the rows (k.meter:report()) and prints. It
-- measures nothing itself, changes no row and no setting. Core/Diag.lua is
-- not changed: only its commands table is used.
--
--   rows  = Perf.Rows(report)          sorted; { owner, calls, ms, errors }
--   lines = Perf.Lines(report, limit)  what to say, without the title
--   lines = Perf.Run(k, rest)
--   Perf.Start(k, diag) -> { run = fn }
--
-- report: { [owner] = { calls, ms, errors } }. A row that is no table is
-- left out; a time that is not a number is "not known", never 0.
local _, ns = ...

local Perf = {}
ns.Perf = Perf

Perf.WORD = "perf"
Perf.DEFAULT_ROWS = 10
Perf.NONE = "No timing yet: nothing has run."

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function Perf.Rows(report)
    local rows = {}
    if type(report) ~= "table" then return rows end
    for owner, r in pairs(report) do
        if type(r) == "table" then
            rows[#rows + 1] = {
                owner = tostring(owner),
                calls = isCount(r.calls) and r.calls or 0,
                ms = isCount(r.ms) and r.ms or nil,
                errors = isCount(r.errors) and r.errors or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if (a.ms ~= nil) ~= (b.ms ~= nil) then return a.ms ~= nil end      -- a known time first
        if a.ms ~= b.ms then return a.ms > b.ms end
        if a.calls ~= b.calls then return a.calls > b.calls end
        return a.owner < b.owner
    end)
    return rows
end

local function count(n, one, many)
    return string.format("%.0f", n) .. " " .. (n == 1 and one or many)
end

local function rowText(r)
    local text
    if r.ms == nil then
        text = r.owner .. ": time not known, " .. count(r.calls, "call", "calls")
    else
        text = r.owner .. ": " .. string.format("%.1f", r.ms) .. " ms in " .. count(r.calls, "call", "calls")
        if r.calls > 0 then text = text .. " (" .. string.format("%.3f", r.ms / r.calls) .. " ms each)" end
    end
    if r.errors > 0 then text = text .. ", " .. count(r.errors, "error", "errors") end
    return text
end

function Perf.Lines(report, limit)
    local rows = Perf.Rows(report)
    if #rows == 0 then return { Perf.NONE } end
    local shown = #rows
    if isCount(limit) and limit >= 1 and limit < #rows then shown = math.floor(limit) end
    local lines = { "Time by module since load, slowest first:" }
    local ms, calls, unknown = 0, 0, 0
    for i = 1, #rows do
        local r = rows[i]
        if i <= shown then lines[#lines + 1] = rowText(r) end
        calls = calls + r.calls
        if r.ms == nil then unknown = unknown + 1 else ms = ms + r.ms end
    end
    if shown < #rows then
        lines[#lines + 1] = "and " .. (#rows - shown) .. " more; say perf all for every one."
    end
    local total = "In all: " .. string.format("%.1f", ms) .. " ms in " .. count(calls, "call", "calls")
    if unknown > 0 then
        total = total .. " (" .. unknown .. (unknown == 1 and " module's" or " modules'") .. " time not known)"
    end
    lines[#lines + 1] = total .. "."
    return lines
end

function Perf.Run(k, rest)
    rest = tostring(rest or ""):lower()
    local limit = Perf.DEFAULT_ROWS
    if rest:find("all", 1, true) then
        limit = nil
    else
        local n = tonumber(rest:match("%d+"))
        if n and n >= 1 then limit = n end
    end
    local ok, report = pcall(k.meter.report, k.meter)
    return Perf.Lines(ok and report or nil, limit)
end

function Perf.Start(k, diag)
    local function run(rest)
        local lines = Perf.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Perf.WORD] = run
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.perf = Perf.Start(ns, ns.diag)
