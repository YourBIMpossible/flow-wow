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
    local lines = P.Lines({ a = { calls = 1, ms = 3, errors = 1 }, b = { calls = 2, errors = 0 } })
    t.eq(lines[2], "a: 3.0 ms in 1 call (3.000 ms each), 1 error")
    t.eq(lines[3], "b: time not known, 2 calls")
    t.eq(lines[4], "In all: 3.0 ms in 3 calls (1 module's time not known).")
end

-- L6-P (review of e1351c9, low 1; F-086): a call or error count that was not
-- read is "not known", never 0.
tests["perf lines: unknown call and error counts are said, never shown as 0"] = function(t)
    local rows = P.Rows({ a = { ms = 5 }, b = { calls = 2 }, c = { ms = 1, calls = "x", errors = -1 } })
    t.eq(rows[1], { owner = "a", ms = 5 }, "no calls and no errors made up")
    local lines = P.Lines({ a = { ms = 5 }, b = { calls = 2 }, c = {} })
    t.eq(lines[2], "a: 5.0 ms, calls not known, errors not known")
    t.eq(lines[3], "b: time not known, 2 calls, errors not known")
    t.eq(lines[4], "c: time not known, calls not known, errors not known")
    t.eq(lines[5], "In all: 5.0 ms in 2 calls (2 modules' time not known; 2 modules' calls not known).")
    for _, l in ipairs(lines) do
        t.ok(not l:find(" 0 calls", 1, true), "no '0 calls' for a count nobody read: " .. l)
    end
    t.eq(P.Lines({ idle = { calls = 0, ms = 0, errors = 0 } })[2], "idle: 0.0 ms in 0 calls", "a read 0 is still 0")
end

tests["perf lines: a limit shows the slowest and says how many are left out"] = function(t)
    local lines = P.Lines(REPORT, 2)
    t.eq(#lines, 5)
    t.eq(lines[4], "and 2 more; type " .. ns.id.slash .. " perf all to see every one.", "the hint names the whole command")
    t.eq(lines[5], "In all: 274.0 ms in 1043 calls.", "the total is still of all of them")
    t.eq(P.Lines(REPORT, 2, "/other")[4], "and 2 more; type /other perf all to see every one.", "the slash is the one given")
end

-- L6-P (lows 2 and 6): the words after perf are read whole, through the
-- real slash command.
local function router()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    P.Start(k, diag)
    for i = 1, 14 do k.meter:run("m" .. i, "handler", nil, function() end) end
    local function count(typed)
        local before = #c.printed
        c.slashes[ns.id.slash](typed)
        return #c.printed - before, c.printed[#c.printed]
    end
    return count, k
end

tests["perf command: 'all' is the whole word, in any capitals, through the slash command"] = function(t)
    local count = router()
    t.eq((count("perf")), 1 + P.DEFAULT_ROWS + 2, "the default")
    t.eq((count("PERF ALL")), 1 + 14 + 1, "all, however it is typed")
    t.eq((count("perf 3")), 1 + 3 + 2)
    local n, last = count("perf small")
    t.eq(n, 1, "a word that only contains 'all' is not 'all'")
    t.eq(last, ns.id.title .. ": " .. P.Usage(ns.id.slash))
    t.eq(P.Usage("/zflow"), "Type /zflow perf, /zflow perf <number>, or /zflow perf all.")
end

tests["perf command: 0, a negative number and other words are refused, not guessed"] = function(t)
    local _, k = router()
    for _, typed in ipairs({ "0", "-3", "3 4", "ten", "all of them", "1.5" }) do
        t.eq(P.Run(k, typed), { P.Usage(ns.id.slash) }, "'" .. typed .. "' gets the usage line")
    end
    t.eq(#P.Run(k, "  2  "), 1 + 2 + 2, "spaces around a number are fine")
end

tests["perf lines: nothing measured yet"] = function(t)
    t.eq(P.Lines({}), { P.NONE })
end

-- Lead section 403 (c): timings that could not be read are not "nothing has
-- run". No report, or one whose every row is in the wrong shape, says so.
tests["perf lines: timings that could not be read say so, not 'nothing has run'"] = function(t)
    t.eq(P.UNREAD, "Could not read the timings: nothing to show.")
    t.ok(P.UNREAD ~= P.NONE)
    t.eq(P.Lines(nil), { P.UNREAD })
    t.eq(P.Lines("x"), { P.UNREAD })
    t.eq(P.Lines({ a = "x", b = 3 }), { P.UNREAD }, "every row in the wrong shape")
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

tests["perf command: a meter whose report fails or is missing says the timings could not be read"] = function(t)
    local k = start()
    k.meter = { report = function() error("broken", 0) end }
    t.eq(P.Run(k, ""), { P.UNREAD }, "a report that raises")
    k.meter = { report = function() return nil end }
    t.eq(P.Run(k, ""), { P.UNREAD }, "a report that answers nothing")
    k.meter = nil
    t.eq(P.Run(k, ""), { P.UNREAD }, "no meter at all")
    k.meter = {}
    t.eq(P.Run(k, "all"), { P.UNREAD }, "a meter with no report")
end

tests["perf command: running it changes no timing row"] = function(t)
    local k = start()
    k.meter:run("m", "handler", nil, function() end)
    local before = k.meter:report()
    P.Run(k, "")
    t.eq(k.meter:report(), before, "it reads a copy and measures nothing itself")
end

-- F-07 (lead section 557): the perf word also says the memory the add-on
-- holds, read through client.addonMemory() (KB). A client that has no such
-- read, or one that raises or answers no number, says it is not known.
tests["perf memory: the line in MB, and unknown when not read"] = function(t)
    t.eq(P.MemoryLine(2560), "Memory in use: 2.5 MB.")
    t.eq(P.MemoryLine(0), "Memory in use: 0.0 MB.")
    t.eq(P.MemoryLine(nil), P.NO_MEMORY)
    t.eq(P.MemoryLine(0 / 0), P.NO_MEMORY, "not a number: not known, never 0")
    t.eq(P.MemoryLine(-5), P.NO_MEMORY)
    t.eq(P.MemoryLine("12"), P.NO_MEMORY)
end

tests["perf command: the memory line comes first, from the client's read"] = function(t)
    local k, c, diag = start()
    c.addonMemory = function() return 1536 end
    k.meter:run("slow", "handler", nil, function() c.burn(8) end)
    local before = #c.printed
    diag.commands[P.WORD]("")
    t.eq(c.printed[before + 1], ns.id.title .. ": Memory in use: 1.5 MB.")
    t.eq(c.printed[before + 2], ns.id.title .. ": Time by module since load, slowest first:")
end

tests["perf command: no memory read, or one that raises, says memory is not known"] = function(t)
    local k, c, diag = start()
    c.addonMemory = nil
    local before = #c.printed
    diag.commands[P.WORD]("")
    t.eq(c.printed[before + 1], ns.id.title .. ": " .. P.NO_MEMORY)
    c.addonMemory = function() error("broken", 0) end
    before = #c.printed
    diag.commands[P.WORD]("")
    t.eq(c.printed[before + 1], ns.id.title .. ": " .. P.NO_MEMORY)
    t.ok(k ~= nil)
end

return tests
