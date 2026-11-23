-- Z-Flow offline test runner. Lua 5.1.
--   lua5.1 zflow-run.lua <repo root> <test list file> [--verbose] [--filter text]
--
-- Loads every file in ZFlow/manifest.lua, in order, as the game would:
-- loadfile(f)("ZFlow", ns), dev files included (the fake client). Then
-- loads every test file named in the list file (one path per line, relative
-- to ZFlow/) the same way. A test file returns
--   { ["test name"] = function(t) ... end }
-- and a test may use only t.ok(value, msg) and t.eq(got, want, msg).
--
--   PASS   every check held, and there was at least one
--   FAIL   a check did not hold, or the test made no check at all
--   ERROR  the test raised an error; also a file that does not load, a test
--          file that returns no table, and a problem the kernel recorded
--          while the manifest files loaded
--
-- Exit 0 only when at least one test ran and nothing failed or errored.
-- The last line is always "zflow: done, exit <n>". A PASS is this addon's
-- Lua on made-up inputs against a fake client: not a test in the game.
local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local L = dofile(here .. "/zflow-lib.lua")

local root, listFile = arg[1], arg[2]
local verbose, filter = false, nil
do
    local i = 3
    while arg[i] do
        if arg[i] == "--verbose" then verbose = true
        elseif arg[i] == "--filter" then i = i + 1; filter = arg[i] end
        i = i + 1
    end
end

local function finish(code)
    print("zflow: done, exit " .. code)
    os.exit(code)
end

if not root or not listFile then
    print("usage: zflow-run.lua <repo root> <test list file> [--verbose] [--filter text]")
    finish(2)
end

local manifest, merr = L.manifest(root)
if not manifest then
    print("zflow: " .. tostring(merr))
    finish(2)
end
local tests = L.readLines(listFile)
if not tests then
    print("zflow: cannot read the test list " .. listFile)
    finish(2)
end
table.sort(tests)

local ns = {}
local counts = { run = 0, pass = 0, fail = 0, error = 0 }
local loadErrors = 0

local function trace(err)
    return debug.traceback(tostring(err), 2)
end

local function loadOne(rel)
    local chunk, err = loadfile(L.join(root, L.ADDON .. "/" .. rel))
    if not chunk then return false, err end
    return xpcall(function() return chunk(L.ADDON, ns) end, trace)
end

-- The whole add-on, loaded again into a fresh table the way the game loads
-- it, on a fake client the test has set up: ns.offline.addon(c) returns the
-- add-on's table after Core/Kernel.lua booted it on c. The test then fires
-- ADDON_LOADED, PLAYER_LOGIN and the rest, and reads what c shows.
ns.offline = {}
function ns.offline.addon(client)
    local fresh = {}
    for _, f in ipairs(manifest.files) do
        local chunk, err = loadfile(L.join(root, L.ADDON .. "/" .. f.path))
        if not chunk then error(f.path .. ": " .. tostring(err), 2) end
        chunk(L.ADDON, fresh)
        if f.path == "Core/ClientFake.lua" then fresh.client = client end
    end
    return fresh
end

for _, f in ipairs(manifest.files) do
    local ok, err = loadOne(f.path)
    if not ok then
        loadErrors = loadErrors + 1
        print("ERROR  " .. f.path .. ": did not load: " .. tostring(err))
    end
end
print("zflow: loaded " .. (#manifest.files - loadErrors) .. " of " .. #manifest.files .. " manifest files")

-- What the kernel recorded while the files loaded (a duplicate setting
-- key, a row that does not fit its kind): real defects in shipped files.
if type(ns.problems) == "table" and type(ns.problems.list) == "function" then
    for _, p in ipairs(ns.problems:list()) do
        loadErrors = loadErrors + 1
        print("ERROR  load problem (" .. p.kind .. ") " .. p.owner .. ": " .. p.text)
    end
end

local function deepEq(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not deepEq(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for key in pairs(v) do keys[#keys + 1] = key end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for i = 1, math.min(#keys, 12) do parts[i] = tostring(keys[i]) .. "=" .. tostring(v[keys[i]]) end
    if #keys > 12 then parts[#parts + 1] = "..." end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function runTest(file, name, fn)
    local checks, failures = 0, {}
    local t = {}
    function t.ok(value, msg)
        checks = checks + 1
        if not value then failures[#failures + 1] = tostring(msg or "check " .. checks) end
        return value and true or false
    end
    function t.eq(got, want, msg)
        checks = checks + 1
        local same = deepEq(got, want)
        if not same then
            failures[#failures + 1] = tostring(msg or "check " .. checks) .. ": got " .. show(got) .. ", want " .. show(want)
        end
        return same
    end
    counts.run = counts.run + 1
    local ok, err = xpcall(function() fn(t) end, trace)
    local label = file .. ": " .. name
    if not ok then
        counts.error = counts.error + 1
        print("ERROR  " .. label .. "\n       " .. tostring(err):gsub("\n", "\n       "))
    elseif #failures > 0 then
        counts.fail = counts.fail + 1
        print("FAIL   " .. label)
        for _, text in ipairs(failures) do print("       " .. text) end
    elseif checks == 0 then
        counts.fail = counts.fail + 1
        print("FAIL   " .. label .. "\n       the test made no checks")
    else
        counts.pass = counts.pass + 1
        if verbose then print("PASS   " .. label .. " (" .. checks .. ")") end
    end
end

local fileCount = 0
for _, rel in ipairs(tests) do
    rel = rel:gsub("\\", "/")
    fileCount = fileCount + 1
    local ok, result = loadOne(rel)
    if not ok then
        loadErrors = loadErrors + 1
        print("ERROR  " .. rel .. ": did not load: " .. tostring(result))
    elseif type(result) ~= "table" then
        loadErrors = loadErrors + 1
        print("ERROR  " .. rel .. ": a test file must return a table of name -> function")
    else
        local names = {}
        for name in pairs(result) do names[#names + 1] = tostring(name) end
        table.sort(names)
        for _, name in ipairs(names) do
            local fn = result[name]
            if type(fn) ~= "function" then
                loadErrors = loadErrors + 1
                print("ERROR  " .. rel .. ": " .. name .. " is not a function")
            elseif not filter or (rel .. ": " .. name):lower():find(filter:lower(), 1, true) then
                runTest(rel, name, fn)
            end
        end
    end
end

counts.error = counts.error + loadErrors
print(string.format("zflow tests: %d files, %d run: %d pass, %d fail, %d error%s",
    fileCount, counts.run, counts.pass, counts.fail, counts.error,
    loadErrors > 0 and (" (" .. loadErrors .. " outside a test: see ERROR lines)") or ""))

local code = 0
if counts.fail > 0 or counts.error > 0 then code = 1
elseif counts.run == 0 then
    print("zflow: no test ran")
    code = 1
end
print("result: " .. (code == 0 and "OK" or "FAILED"))
finish(code)
