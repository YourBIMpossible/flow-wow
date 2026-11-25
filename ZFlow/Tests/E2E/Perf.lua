local _, ns = ...
-- The perf word (L6-L, G57; UI/Perf.lua) on the whole add-on loaded on a
-- fake client, through its real entry: the slash word "perf", "perf <n>"
-- and "perf all", after the add-on has run its login. The player reads
-- what is said in chat. Unknown data: a timing read that raises, and words
-- that are not a count. Offline: the fake client's clock, not the game's.
-- Not tested in game.
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

local function rowsOf(addon)
    local n = 0
    for _ in pairs(addon.meter:report()) do n = n + 1 end
    return n
end

local HEAD = "Time by module since load, slowest first:"

tests["perf: the slash word lists the slowest modules, a number of them, or all, each with its time and calls"] = function(t)
    local c, addon = boot()
    local title = ns.id.title .. ": "
    local account = copy(c.saved(ns.id.accountDB))

    local out = said(c, "perf")
    local rows = rowsOf(addon)
    t.ok(rows > 2, "the add-on's login ran through the meter: " .. rows .. " rows")
    t.eq(out[1], title .. ns.Perf.NO_MEMORY, "memory first; the fake client has no memory read")
    t.eq(out[2], title .. HEAD, "the head")
    t.eq(tostring(out[#out]):sub(1, #title + 8), title .. "In all: ", "the total last: " .. tostring(out[#out]))
    local shown = math.min(rows, ns.Perf.DEFAULT_ROWS)
    local more = rows > shown and 1 or 0
    t.eq(#out, 1 + 1 + shown + more + 1, "memory, head, the slowest " .. shown .. ", the rest's count, the total")
    t.ok(tostring(out[3]):find(" ms in ", 1, true) ~= nil and tostring(out[3]):find(" call", 1, true) ~= nil,
        "a row has its time and calls: " .. tostring(out[3]))

    local two = said(c, "perf 2")
    rows = rowsOf(addon)
    t.eq(#two, 1 + 1 + 2 + 1 + 1, "memory, head, two rows, the rest's count, the total")
    t.eq(two[5], title .. "and " .. (rows - 2) .. " more; type " .. ns.id.slash .. " perf all to see every one.",
        "it says how to see the rest")

    local all = said(c, "perf all")
    rows = rowsOf(addon)
    t.eq(#all, 1 + 1 + rows + 1, "memory, head, every row, no rest line")
    for i = 3, #all - 1 do
        t.ok(not tostring(all[i]):find(" more; type ", 1, true), "no rest line: " .. tostring(all[i]))
    end

    -- Look only: no saved setting was changed.
    t.eq(copy(c.saved(ns.id.accountDB)), account, "the account's saved table is as it was")
end

tests["perf: unknown data: words that are no count get the usage, and a timing that cannot be read is not shown as rows"] = function(t)
    local c, addon = boot()
    local title = ns.id.title .. ": "
    local usage = { title .. ns.Perf.Usage(ns.id.slash) }
    t.eq(said(c, "perf small"), usage, "a word that is not all")
    t.eq(said(c, "perf 0"), usage, "0 is not guessed at")
    t.eq(said(c, "perf -3"), usage, "nor -3")

    addon.meter.report = function() error("meter read failed") end
    t.eq(said(c, "perf"), { title .. ns.Perf.NO_MEMORY, title .. ns.Perf.UNREAD }, "a read that raises: no rows made up, and not \"nothing has run\"")
end

return tests
