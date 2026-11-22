-- Offline test driver (Lua 5.1). Started by tools/run-tests.ps1:
--   lua5.1 tools/offline/run.lua <add-on root> [--verbose] [--filter <text>]
--          [--list-modules] [--known <file>] [--strict]
--          [--client-globals <file>] [--min-tests <n>]
--
-- The fixtures (stubs.lua) always come from this file's own folder, so the
-- runner can test another checkout of the add-on (run-tests.ps1 -Root).
--
-- 1. Installs the fixtures of stubs.lua on _G (read that file first: anything
--    the game provides is missing, not imitated). The Lua libraries the game
--    doesn't have go too: `io` is missing and `os` keeps only time, date,
--    clock and difftime, so no test can end the run (os.exit) or write
--    a result line of its own.
-- 2. Loads every file of Flow.toc, in toc order, as the game does: the chunk
--    gets ("Flow", ns). A file that errors while loading is reported and the
--    rest still load (the game does the same), but the run fails: the tests
--    of that file were never registered.
-- 3. Fires ADDON_LOADED("Flow") once, as on a fresh install (saved data empty).
--    Errors that Core's OnLoad loop catches are listed, always.
-- 4. Runs each registered test through the harness's own seam,
--    ns.tests.Spread (Modules/Tests.lua), one test at a time:
--      PASS       every check held, nothing of the client touched
--                 (one with no checks at all is still a PASS, counted apart)
--      FAIL       a check failed, nothing of the client touched
--      ERROR      a Lua error, nothing of the client touched
--                 A test that read the timing fixture (debugprofilestop,
--                 see stubs.lua) is a PASS only if it also passes on two
--                 made-up clocks; if not, it is a SKIP.
--      SKIP       touched the client before any check failed (checks that
--                 fail after that are counted, but can't be told apart from
--                 the client's doing offline)
--      SKIP-FAIL  a check failed before the test touched the client. Always
--                 listed and counted apart. It fails the run only with
--                 --strict: on the base branch the ones there are come from
--                 load-time fixture effects (an ns:OnLoad that errored on a
--                 fixture frame left state unset), which offline can't tell
--                 apart from a real failure.
-- 5. Prints the summary, then "offline: done, exit <n>" as its very last line.
--    run-tests.ps1 treats a run without that line as broken (exit 2).
--
-- Exit code: 0 = no FAIL or ERROR (or SKIP-FAIL, with --strict) outside the known list, every
-- file loaded, every known name still exists, at least one test ran;
-- 1 = one of those; 2 = the runner itself broke.
--
-- --known <file>: tests already failing on the base branch, one exact test
-- name per line (# comments). Such a test is still reported (KNOWN) and
-- counted as an allowance in the summary, but doesn't fail the run. A known
-- test that now passes is reported so it can be taken off the list; a known
-- name no registered test has (renamed, removed, misspelled) fails the run.

local root = arg[1]
if not root then io.stderr:write("usage: run.lua <add-on root> [--verbose] [--filter text] [--known file]\n"); os.exit(2) end
root = root:gsub("[\\/]$", "")
local verbose, filter, listModules, knownPath, strict = false, nil, false, nil, false
local globalsPath, minTests
do
    local i = 2
    while arg[i] do
        if arg[i] == "--verbose" then verbose = true
        elseif arg[i] == "--list-modules" then listModules = true
        elseif arg[i] == "--strict" then strict = true
        elseif arg[i] == "--filter" then i = i + 1; filter = arg[i]
        elseif arg[i] == "--known" then i = i + 1; knownPath = arg[i]
        elseif arg[i] == "--client-globals" then i = i + 1; globalsPath = arg[i]
        elseif arg[i] == "--min-tests" then
            i = i + 1; minTests = tonumber(arg[i])
            if not minTests then io.stderr:write("run.lua: --min-tests needs a number\n"); os.exit(2) end
        else io.stderr:write("run.lua: unknown argument " .. tostring(arg[i]) .. "\n"); os.exit(2)
        end
        i = i + 1
    end
end

local SEP = package.config:sub(1, 1)
local function path(rel) return root .. SEP .. rel:gsub("[\\/]", SEP) end
local here = (arg[0] or ""):match("^(.*)[\\/][^\\/]*$") or "."

local G = _G
local io_write, io_open, io_stderr = io.write, io.open, io.stderr
local os_exit, os_clock, string_format, print_real = os.exit, os.clock, string.format, print
local S = dofile(here .. SEP .. "stubs.lua")

-- Files Flow.toc may list that aren't in a checkout: generated on the player's PC.
local MAY_BE_ABSENT = { ["Learned/ClaudeInbox.lua"] = true }

-- Flow's chat output during loading and tests goes to a buffer, shown with --verbose.
local printed = {}
local function capture(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

-- Read Flow.toc.
local files = {}
do
    local fh = io_open(path("Flow.toc"), "r")
    if not fh then io_stderr:write("no Flow.toc under " .. root .. "\n"); os_exit(2) end
    for line in fh:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
    end
    fh:close()
end

-- Known failures (exact names), in file order.
local known, knownList = {}, {}
if knownPath then
    local fh = io_open(knownPath, "r")
    if not fh then io_stderr:write("no known-failures file " .. knownPath .. "\n"); os_exit(2) end
    for l in fh:lines() do
        l = l:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" and not l:match("^#") and not known[l] then
            known[l] = true
            knownList[#knownList + 1] = l
        end
    end
    fh:close()
end

-- The game's globals Flow may read (client-globals.txt). Anything else that is
-- missing is an unknown name: an error, not a SKIP.
local clientNames, clientPatterns, clientCount
if globalsPath then
    clientNames, clientPatterns, clientCount = S.ReadClientGlobals(globalsPath)
    if not clientNames then io_stderr:write("run.lua: " .. tostring(clientPatterns) .. "\n"); os_exit(2) end
end
S.Install(G, clientNames, clientPatterns)
G.print = capture
-- The game's Lua has no io and only these four of os.
G.io = nil
G.os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }

local ns = {}
local loaded, failed, absent, allowedAbsent, loadedClean = {}, {}, {}, {}, 0
local unknownAtLoad = 0
for _, rel in ipairs(files) do
    local chunk, err = loadfile(path(rel))
    if not chunk then
        if err and (err:find("No such file", 1, true) or err:find("cannot open", 1, true)) then
            if MAY_BE_ABSENT[(rel:gsub("\\", "/"))] then allowedAbsent[#allowedAbsent + 1] = rel
            else absent[#absent + 1] = rel end
        else
            failed[#failed + 1] = { rel, "syntax: " .. tostring(err) }
        end
    else
        S.ResetLoadTouched()
        S.ResetUnknown()
        S.phase = "load"
        local ok, e = pcall(chunk, "Flow", ns)
        local uses = S.LoadTouched()
        if #S.unknown > 0 then
            -- Even if the file finished (its own pcall caught the error): the name is wrong.
            failed[#failed + 1] = { rel, "unknown global: " .. table.concat(S.unknown, ", ")
                .. " (not Flow's, not in client-globals.txt: a typo or a missing \"ns.\"?)" }
            unknownAtLoad = unknownAtLoad + #S.unknown
        elseif ok then
            loaded[#loaded + 1] = { rel, uses }
            if #uses == 0 then loadedClean = loadedClean + 1 end
        else
            local msg = tostring(e)
            if msg:find(S.MARK, 1, true) then msg = "needs the client: " .. msg:gsub(".*" .. S.MARK:gsub("%p", "%%%0"), "") end
            failed[#failed + 1] = { rel, msg }
        end
    end
end

-- A fresh install's first load: empty saved data, every ns:OnLoad runs.
-- Core prints the errors its OnLoad loop catches ("Flow load error").
S.phase = "load"
local printedBefore = #printed
S.ResetUnknown()
local delivered = S.Fire("ADDON_LOADED", "Flow")
if #S.unknown > 0 then
    failed[#failed + 1] = { "(an ns:OnLoad)", "unknown global: " .. table.concat(S.unknown, ", ")
        .. " (not Flow's, not in client-globals.txt: a typo or a missing \"ns.\"?)" }
    unknownAtLoad = unknownAtLoad + #S.unknown
end
local onLoadErrors = {}
for i = printedBefore + 1, #printed do
    if printed[i]:find("Flow load error", 1, true) then onLoadErrors[#onLoadErrors + 1] = printed[i] end
end

local tests = ns.tests
if not (tests and tests.Spread and ns.Each) then
    print_real("offline: the harness (ns.tests.Spread in Modules/Tests.lua) didn't load; nothing to run")
    for _, f in ipairs(failed) do print_real("  load error " .. f[1] .. ": " .. f[2]) end
    os_exit(2)
end

local clock = function() return os_clock() * 1000 end
local counts = { PASS = 0, FAIL = 0, SKIP = 0, ERROR = 0, ["SKIP-FAIL"] = 0 }
local results = {}
local skipBy = {}
local registered = {}
local noChecks, skipAfterFail = 0, 0
local markPattern = S.MARK:gsub("%p", "%%%0")

-- One run of one test through the harness's own seam. Returns what the
-- harness gathered, the test's check object, the names touched, how many
-- checks had failed at the first touch, and how often the timing fixture was read.
local function runTest(name, fn)
    S.ResetTouched()
    S.ResetUnknown()
    S.timerCalls = 0
    S.phase = "test"
    -- The harness's own check object (Tests.lua's runOne makes one per test),
    -- and how many of its checks had failed when the client was first touched.
    local checker, failedBeforeTouch
    S.onFirstTouch = function() failedBeforeTouch = checker and checker.fails and #checker.fails or 0 end
    local acc
    local okRun, runErr = pcall(function()
        acc = tests.Spread({ { name, function(t) checker = t; return fn(t) end } },
            1e9, function() end, function() end, clock, nil)
    end)
    S.onFirstTouch = nil
    S.phase = "load"
    return okRun, runErr, acc, checker, S.Touched(), failedBeforeTouch, S.timerCalls, S.unknown
end
local function cleanPass(okRun, acc, touched)
    return okRun and acc and #touched == 0 and acc.passed == 1 and #(acc.out or {}) == 0
end
-- The made-up clocks a test that read the timing fixture must also pass on
-- (stubs.lua, "debugprofilestop"): ms between one reading and the next.
local CLOCKS = {
    { "every reading 1000 ms after the last", 1000 },
    { "every reading 0.000001 ms after the last", 1e-6 },
}
local timerPass, timerSkip = 0, 0
local unknownInTests = 0

for name, fn in ns:Each("test") do
    registered[name] = true
    if not filter or name:lower():find(filter:lower(), 1, true) then
        local okRun, runErr, acc, checker, touched, failedBeforeTouch, timerCalls, unknown = runTest(name, fn)
        local timerDepends
        if timerCalls > 0 and cleanPass(okRun, acc, touched) then
            for _, c in ipairs(CLOCKS) do
                S.SetClock(c[2])
                local ok2, _, acc2, _, touched2 = runTest(name, fn)
                S.SetClock(nil)
                if not cleanPass(ok2, acc2, touched2) then timerDepends = c[1]; break end
            end
            if timerDepends then timerSkip = timerSkip + 1 else timerPass = timerPass + 1 end
        end
        local status, detail
        local out = acc and acc.out or {}
        local text = table.concat(out, "\n")
        if not okRun then
            status, detail = "ERROR", "runner: " .. tostring(runErr)
        elseif #unknown > 0 then
            -- Before anything else: whatever the checks said, and whether or not the
            -- client was touched too, the code read a name that is nobody's.
            status = "ERROR"
            detail = "unknown global: " .. table.concat(unknown, ", ")
                .. " (not Flow's, not in client-globals.txt: a typo or a missing \"ns.\"?)"
            unknownInTests = unknownInTests + 1
        elseif timerDepends then
            -- Passed on os.clock but not on a made-up clock: its result is what the timer said.
            status = "SKIP"
            detail = "needs the client: " .. S.TIMER .. " (passes on the timing fixture's own clock, not with " .. timerDepends .. ")"
            skipBy[S.TIMER] = (skipBy[S.TIMER] or 0) + 1
        elseif #touched > 0 or text:find(S.MARK, 1, true) then
            local first = touched[1] or text:match(markPattern .. "([^\n]*)") or "?"
            local fails = checker and checker.fails or {}
            local before = {}
            for i = 1, math.min(failedBeforeTouch or 0, #fails) do before[#before + 1] = fails[i] end
            if #before > 0 then
                -- Failed on Flow's own Lua before anything of the client was touched.
                status, detail = "SKIP-FAIL", "failed before touching the client (" .. first .. "): " .. table.concat(before, "\n")
            else
                local after = 0
                for _, f in ipairs(fails) do if not tostring(f):find(S.MARK, 1, true) then after = after + 1 end end
                status, detail = "SKIP", "needs the client: " .. first
                if after > 0 then
                    skipAfterFail = skipAfterFail + 1
                    detail = detail .. string_format(" (%d check(s) failed after that; can't tell offline whether the client caused them)", after)
                end
                skipBy[first] = (skipBy[first] or 0) + 1
            end
        elseif acc.passed == 1 and #out == 0 then
            status = "PASS"
            if acc.checks == 0 then noChecks = noChecks + 1; detail = "no checks ran" end
        elseif text:find("\n    error: ", 1, true) then
            status, detail = "ERROR", (text:match("\n    error: ([^\n]*)"))
        else
            status, detail = "FAIL", (text:gsub("^FAIL [^\n]*\n", ""))
        end
        counts[status] = counts[status] + 1
        results[#results + 1] = { status, name, detail }
    end
end

-- Listed in full, always; SKIP-FAIL fails the run only with --strict.
local SHOWN = { FAIL = true, ERROR = true, ["SKIP-FAIL"] = true }
local BAD = { FAIL = true, ERROR = true, ["SKIP-FAIL"] = strict }

-- Report.
local function line(s) io_write(s, "\n") end
for _, r in ipairs(results) do
    if SHOWN[r[1]] then
        line(r[1] .. (known[r[2]] and " (KNOWN)" or "") .. " " .. r[2] .. (r[3] and (": " .. r[3]:gsub("\n", "\n      ")) or ""))
    elseif verbose then
        line(r[1] .. " " .. r[2] .. (r[3] and (": " .. r[3]) or ""))
    end
end

line("")
line(string_format("modules: %d of %d files in Flow.toc loaded (%d without touching any client global), %d failed, %d absent (%d allowed: generated on the player's PC)",
    #loaded, #files, loadedClean, #failed, #absent + #allowedAbsent, #allowedAbsent))
for _, f in ipairs(failed) do line("  did not load (its tests never registered): " .. f[1] .. " (" .. f[2] .. ")") end
for _, a in ipairs(absent) do line("  absent: " .. a) end
for _, a in ipairs(allowedAbsent) do line("  absent (allowed): " .. a) end
if listModules then
    for _, m in ipairs(loaded) do
        line(string_format("  loaded: %s%s", m[1], #m[2] > 0 and (" (touched at load: " .. #m[2] .. " client names)") or " (pure)"))
    end
end
line(string_format("ADDON_LOADED delivered to %d frame(s); %d OnLoad error(s) caught by Core (fixture frames return nil, so these don't fail the run; check new ones):",
    delivered, #onLoadErrors))
for _, e in ipairs(onLoadErrors) do line("  " .. e:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local skips = {}
for k, v in pairs(skipBy) do skips[#skips + 1] = { k, v } end
table.sort(skips, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
line("most common reasons to skip (first client name each skipped test touched):")
for i = 1, math.min(15, #skips) do line(string_format("  %4d  %s", skips[i][2], skips[i][1])) end

if verbose then
    line("Flow's chat output while loading and testing:")
    for _, p in ipairs(printed) do line("  | " .. p) end
end

local newBad, knownUsed, knownPassing, knownMissing = 0, 0, 0, {}
for _, r in ipairs(results) do
    if BAD[r[1]] then
        if known[r[2]] then knownUsed = knownUsed + 1 else newBad = newBad + 1 end
    elseif known[r[2]] then
        knownPassing = knownPassing + 1
        line(string_format("known failure no longer fails (%s): take it off the list: %s", r[1], r[2]))
    end
end
for _, k in ipairs(knownList) do
    if not registered[k] then
        knownMissing[#knownMissing + 1] = k
        line("known-failures lists a test that doesn't exist (renamed, removed or misspelled): " .. k)
    end
end

local total = 0
for _, n in pairs(counts) do total = total + n end
line(string_format("offline tests: %d run: %d pass (%d with no checks), %d fail, %d error, %d skip (need the client; %d of them with checks failing after that), %d skip-fail (a check failed before it touched the client; %s)",
    total, counts.PASS, noChecks, counts.FAIL, counts.ERROR, counts.SKIP, skipAfterFail, counts["SKIP-FAIL"],
    strict and "counted against the run: --strict" or "listed above, not counted against the run without -Strict"))
line(globalsPath
    and string_format("client globals: %d names and patterns in %s; unknown globals read: %d while loading, %d test(s)",
        clientCount, globalsPath, unknownAtLoad, unknownInTests)
    or "client globals: NO LIST (--client-globals not given): every missing global counts as the game's, so a typo is a SKIP")
line(string_format("timing fixture (debugprofilestop): %d passing test(s) read it through timed code and pass on both made-up clocks too; %d depend on what it said (SKIP)",
    timerPass, timerSkip))
line(knownPath
    and string_format("known failures: %d listed, %d known allowed (failing, not counted against the run), %d now passing, %d not found; %d new failure(s)",
        #knownList, knownUsed, knownPassing, #knownMissing, newBad)
    or string_format("known failures: none used (-NoKnown or no list), 0 known allowed; %d failure(s)", newBad))

local reasons = {}
if newBad > 0 then reasons[#reasons + 1] = newBad .. " new FAIL/ERROR" .. (strict and "/SKIP-FAIL" or "") end
if #failed > 0 then reasons[#reasons + 1] = #failed .. " file(s) did not load" end
if #absent > 0 then reasons[#reasons + 1] = #absent .. " file(s) in Flow.toc absent" end
if #knownMissing > 0 then reasons[#reasons + 1] = #knownMissing .. " known-failures name(s) not found" end
if total == 0 then reasons[#reasons + 1] = "no test ran" .. (filter and (" (filter '" .. filter .. "' matched none)") or "") end
local code = #reasons > 0 and 1 or 0
line(code == 0 and "result: OK" or ("result: FAILED: " .. table.concat(reasons, "; ")))
line("offline: done, exit " .. code)
os_exit(code)
