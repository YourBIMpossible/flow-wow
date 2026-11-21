-- Offline test driver (Lua 5.1). Started by tools/run-tests.ps1:
--   lua5.1 tools/offline/run.lua <repo root> [--verbose] [--filter <text>] [--list-modules]
--
-- 1. Installs the fixtures of tools/offline/stubs.lua on _G (read that file
--    first: anything the game provides is missing, not imitated).
-- 2. Loads every file of Flow.toc, in toc order, as the game does: the chunk
--    gets ("Flow", ns). A file that errors while loading is reported and the
--    rest still load (the game does the same).
-- 3. Fires ADDON_LOADED("Flow") once, as on a fresh install (saved data empty).
-- 4. Runs each registered test through the harness's own seam,
--    ns.tests.Spread (Modules/Tests.lua), one test at a time, and reports
--    PASS, FAIL, ERROR or SKIP (it touched something only the client has).
-- Exit code: 0 = no FAIL and no ERROR outside the known list; 1 = some;
-- 2 = the runner itself broke.
--
-- --known <file>: tests already failing on the base branch, one exact test
-- name per line (# comments). Such a test is still reported FAIL (KNOWN), but
-- doesn't fail the run; a known test that now passes is reported so it can be
-- taken off the list. Anything else that fails, fails the run.

local root = arg[1]
if not root then io.stderr:write("usage: run.lua <repo root> [--verbose] [--filter text]\n"); os.exit(2) end
root = root:gsub("[\\/]$", "")
local verbose, filter, listModules, knownPath = false, nil, false, nil
do
    local i = 2
    while arg[i] do
        if arg[i] == "--verbose" then verbose = true
        elseif arg[i] == "--list-modules" then listModules = true
        elseif arg[i] == "--filter" then i = i + 1; filter = arg[i]
        elseif arg[i] == "--known" then i = i + 1; knownPath = arg[i]
        end
        i = i + 1
    end
end

local SEP = package.config:sub(1, 1)
local function path(rel) return root .. SEP .. rel:gsub("[\\/]", SEP) end

local G = _G
local io_write, os_exit, string_format, print_real = io.write, os.exit, string.format, print
local S = dofile(path("tools/offline/stubs.lua"))

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
    local fh = io.open(path("Flow.toc"), "r")
    if not fh then io.stderr:write("no Flow.toc under " .. root .. "\n"); os_exit(2) end
    for line in fh:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
    end
    fh:close()
end

-- Known failures (exact names).
local known = {}
if knownPath then
    local fh = io.open(knownPath, "r")
    if not fh then io.stderr:write("no known-failures file " .. knownPath .. "\n"); os_exit(2) end
    for l in fh:lines() do
        l = l:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" and not l:match("^#") then known[l] = true end
    end
    fh:close()
end

S.Install(G)
G.print = capture

local ns = {}
local loaded, failed, absent, loadedClean = {}, {}, {}, 0
for _, rel in ipairs(files) do
    local chunk, err = loadfile(path(rel))
    if not chunk then
        if err and err:find("No such file", 1, true) or (err and err:find("cannot open", 1, true)) then
            absent[#absent + 1] = rel
        else
            failed[#failed + 1] = { rel, "syntax: " .. tostring(err) }
        end
    else
        S.ResetLoadTouched()
        S.phase = "load"
        local ok, e = pcall(chunk, "Flow", ns)
        local uses = S.LoadTouched()
        if ok then
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
S.phase = "load"
local delivered = S.Fire("ADDON_LOADED", "Flow")

local tests = ns.tests
if not (tests and tests.Spread and ns.Each) then
    print_real("offline: the harness (ns.tests.Spread in Modules/Tests.lua) didn't load; nothing to run")
    for _, f in ipairs(failed) do print_real("  load error " .. f[1] .. ": " .. f[2]) end
    os_exit(2)
end

local clock = function() return os.clock() * 1000 end
local counts = { PASS = 0, FAIL = 0, SKIP = 0, ERROR = 0 }
local results = {}
local skipBy = {}

for name, fn in ns:Each("test") do
    if not filter or name:lower():find(filter:lower(), 1, true) then
        S.ResetTouched()
        S.phase = "test"
        local acc
        local okRun, runErr = pcall(function()
            acc = tests.Spread({ { name, fn } }, 1e9, function() end, function() end, clock, nil)
        end)
        S.phase = "load"
        local touched = S.Touched()
        local status, detail
        local out = acc and acc.out or {}
        local text = table.concat(out, "\n")
        if not okRun then
            status, detail = "ERROR", "runner: " .. tostring(runErr)
        elseif #touched > 0 or text:find(S.MARK, 1, true) then
            local first = touched[1] or text:match(S.MARK:gsub("%p", "%%%0") .. "([^\n]*)") or "?"
            status, detail = "SKIP", "needs the client: " .. first
            skipBy[first] = (skipBy[first] or 0) + 1
        elseif acc.passed == 1 then
            status = "PASS"
        elseif text:find("\n    error: ", 1, true) then
            status, detail = "ERROR", (text:match("\n    error: ([^\n]*)"))
        else
            status, detail = "FAIL", (text:gsub("^FAIL [^\n]*\n", ""))
        end
        counts[status] = counts[status] + 1
        results[#results + 1] = { status, name, detail }
    end
end

-- Report.
local function line(s) io_write(s, "\n") end
for _, r in ipairs(results) do
    if verbose or r[1] == "FAIL" or r[1] == "ERROR" then
        line(r[1] .. (known[r[2]] and " (KNOWN)" or "") .. " " .. r[2] .. (r[3] and (": " .. r[3]:gsub("\n", "\n      ")) or ""))
    elseif r[1] == "SKIP" and verbose then
        line("SKIP " .. r[2] .. ": " .. r[3])
    end
end

line("")
line(string_format("modules: %d of %d files in Flow.toc loaded (%d without touching any client global), %d failed, %d absent",
    #loaded, #files, loadedClean, #failed, #absent))
for _, f in ipairs(failed) do line("  did not load: " .. f[1] .. " (" .. f[2] .. ")") end
for _, a in ipairs(absent) do line("  absent: " .. a) end
if listModules then
    for _, m in ipairs(loaded) do
        line(string_format("  loaded: %s%s", m[1], #m[2] > 0 and (" (touched at load: " .. #m[2] .. " client names)") or " (pure)"))
    end
end
line(string_format("ADDON_LOADED delivered to %d frame(s)", delivered))

local skips = {}
for k, v in pairs(skipBy) do skips[#skips + 1] = { k, v } end
table.sort(skips, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
line("most common reasons to skip (first client name each skipped test touched):")
for i = 1, math.min(15, #skips) do line(string_format("  %4d  %s", skips[i][2], skips[i][1])) end

if verbose then
    line("Flow's chat output while loading and testing:")
    for _, p in ipairs(printed) do line("  | " .. p) end
end

local newBad, knownBad = 0, 0
for _, r in ipairs(results) do
    if r[1] == "FAIL" or r[1] == "ERROR" then
        if known[r[2]] then knownBad = knownBad + 1 else newBad = newBad + 1 end
    elseif known[r[2]] then
        line(string_format("known failure no longer fails (%s): take it off the list: %s", r[1], r[2]))
    end
end

local total = counts.PASS + counts.FAIL + counts.SKIP + counts.ERROR
line(string_format("offline tests: %d run, %d pass, %d fail, %d skip (need the client), %d error%s",
    total, counts.PASS, counts.FAIL, counts.SKIP, counts.ERROR,
    knownPath and string_format(" (%d of the fails/errors known, %d new)", knownBad, newBad) or ""))
os_exit(newBad > 0 and 1 or 0)
