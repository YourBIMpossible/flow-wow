local _, ns = ...

-- Tests for ZFlow/UI/Perf.lua (L6-L, G57): `<slash> perf` prints the timing
-- rows the kernel's meter keeps (the ones a diag snapshot stores), slowest
-- first. It only reads and prints.

local P = ns.Perf
local tests = {}

local REPORT = {
    sellList = { calls = 40, ms = 12, errors = 0 },
    rotation = { calls = 1000, ms = 250, errors = 2 },
    priceWatch = { calls = 3, ms = 12, errors = 0 },
    idle = { calls = 0, ms = 0, errors = 0 },
}

tests["perf rows: slowest first, then the most calls, then the name"] = function(t)
    local rows = P.Rows(REPORT)
    local order = {}
    for i, r in ipairs(rows) do order[i] = r.owner end
    t.eq(order, { "rotation", "sellList", "priceWatch", "idle" })
    t.eq(rows[1], { owner = "rotation", calls = 1000, ms = 250, errors = 2 })
end

tests["perf rows: rows in the wrong shape are left out, never guessed"] = function(t)
    local rows = P.Rows({ good = { calls = 1, ms = 2, errors = 0 }, bad = "x", noMs = { calls = 4 },
                          nan = { calls = 1, ms = 0 / 0, errors = 0 } })
    t.eq(#rows, 3, "the text row is dropped")
    t.eq(rows[1].owner, "good")
    t.eq(rows[2].ms, nil, "a time that is not known stays unknown")
    t.eq(P.Rows(nil), {}, "no report: no rows")
end

tests["perf lines: each module with its time, calls and time per call"] = function(t)
    local lines = P.Lines(REPORT)
    t.eq(lines[1], "Time by module since load, slowest first:")
    t.eq(lines[2], "rotation: 250.0 ms in 1000 calls (0.250 ms each), 2 errors")
    t.eq(lines[3], "sellList: 12.0 ms in 40 calls (0.300 ms each)")
    t.eq(lines[4], "priceWatch: 12.0 ms in 3 calls (4.000 ms each)")
    t.eq(lines[5], "idle: 0.0 ms in 0 calls")
    t.eq(lines[6], "In all: 274.0 ms in 1043 calls.")
end

tests["perf lines: one call, one error, and a time that is not known"] = function(t)
    local lines = P.Lines({ a = { calls = 1, ms = 3, errors = 1 }, b = { calls = 2 } })
    t.eq(lines[2], "a: 3.0 ms in 1 call (3.000 ms each), 1 error")
    t.eq(lines[3], "b: time not known, 2 calls")
    t.eq(lines[4], "In all: 3.0 ms in 3 calls (1 module's time not known).")
end

tests["perf lines: a limit shows the slowest and says how many are left out"] = function(t)
    local lines = P.Lines(REPORT, 2)
    t.eq(#lines, 5)
    t.eq(lines[4], "and 2 more; say perf all for every one.")
    t.eq(lines[5], "In all: 274.0 ms in 1043 calls.", "the total is still of all of them")
end

tests["perf lines: nothing measured yet"] = function(t)
    t.eq(P.Lines({}), { P.NONE })
    t.eq(P.Lines(nil), { P.NONE })
end

-- ------------------------------------------------------------------ command

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    P.Start(k, diag)
    return k, c, diag
end

tests["perf command: the word is added and prints the meter's rows"] = function(t)
    local k, c, diag = start()
    t.eq(P.WORD, "perf")
    k.meter:run("slow", "handler", nil, function() c.burn(8) end)
    k.meter:run("fast", "handler", nil, function() c.burn(2) end)
    diag.commands[P.WORD]("")
    local said = {}
    for _, p in ipairs(c.printed) do said[#said + 1] = p end
    t.eq(said[#said - 3], ns.id.title .. ": Time by module since load, slowest first:")
    t.eq(said[#said - 2], ns.id.title .. ": slow: 8.0 ms in 1 call (8.000 ms each)")
    t.eq(said[#said - 1], ns.id.title .. ": fast: 2.0 ms in 1 call (2.000 ms each)")
    t.eq(said[#said], ns.id.title .. ": In all: 10.0 ms in 2 calls.")
end

tests["perf command: a number limits the rows, all shows every one"] = function(t)
    local k = start()
    for i = 1, 14 do k.meter:run("m" .. i, "handler", nil, function() end) end
    t.eq(#P.Run(k, ""), 1 + P.DEFAULT_ROWS + 2, "the default limit, the 'more' line and the total")
    t.eq(#P.Run(k, "3"), 1 + 3 + 2)
    t.eq(#P.Run(k, "all"), 1 + 14 + 1)
    t.eq(P.DEFAULT_ROWS, 10)
end

tests["perf command: running it changes no timing row"] = function(t)
    local k = start()
    k.meter:run("m", "handler", nil, function() end)
    local before = k.meter:report()
    P.Run(k, "")
    t.eq(k.meter:report(), before, "it reads a copy and measures nothing itself")
end

return tests
