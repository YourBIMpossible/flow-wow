-- Z-Flow offline test runner. Lua 5.1.
--   lua5.1 zflow-run.lua <repo root> <test list file> [--verbose] [--filter text]
--
-- Loads every file in ZFlow/manifest.lua, in order, as the game would:
-- loadfile(f)("ZFlow", ns), dev files included (the fake client). Then
-- loads every test file named in the list file (one path per line, relative
-- to ZFlow/) the same way. A test file returns
--   { ["test name"] = function(t) ... end }
-- and a test may use only t.ok(value, msg), t.eq(got, want, msg) and
-- t.skip(reason) (it cannot run here: SKIP, never PASS).
--
--   PASS   every check held, and there was at least one
--   FAIL   a check did not hold, or the test made no check at all
--   SKIP   the test called t.skip and no check failed: not a pass, and
--          not counted against the exit code
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
local counts = { run = 0, pass = 0, fail = 0, error = 0, skip = 0 }
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

-- A real capture (lead section 188, 3): read only from a path outside the
-- repo, given in ZFLOW_CAPTURE (the account saved file) and, if wanted,
-- ZFLOW_CAPTURE_CHAR (the character saved file). nil when not given. Real
-- captures never enter the repo; a test that needs one calls t.skip when
-- there is none.
local function given(name)
    local v = os.getenv(name)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end
function ns.offline.capturePath() return given("ZFLOW_CAPTURE") end
function ns.offline.captureCharPath() return given("ZFLOW_CAPTURE_CHAR") end
-- Section 196: where the name-free summary of a real run goes (outside the repo).
function ns.offline.summaryPath() return given("ZFLOW_SUMMARY") end

-- True when path is inside the repo, or cannot be told (a relative path).
local function norm(p)
    return (tostring(p):gsub("\\", "/"):gsub("/+$", ""):lower())
end
function ns.offline.inRepo(path)
    local p = norm(path)
    if not (p:match("^%a:/") or p:sub(1, 1) == "/") then return true end
    local r = norm(root)
    return p == r or p:sub(1, #r + 1) == r .. "/"
end

-- Folder names that mean a game folder (lead section 199, MyBuddy S3): the
-- saved files, the add-ons, the game's own folder. Matched on the
-- lower-case path with forward slashes. A folder holding one of GAME_EXES
-- is a game folder too.
local GAME_PARTS = { "/wtf/", "/interface/addons/", "/savedvariables/", "world of warcraft" }
local GAME_EXES = { "Wow.exe", "WowClassic.exe", "Wow-64.exe", "WowT.exe", "WowB.exe" }

local function inGameFolder(path)
    local p = norm(path) .. "/"
    for _, part in ipairs(GAME_PARTS) do
        if p:find(part, 1, true) then return true end
    end
    local dir = tostring(path):gsub("\\", "/")
    while true do
        dir = dir:match("^(.*)/[^/]*$")
        if not dir or dir == "" or dir:match("^%a:$") then break end
        for _, exe in ipairs(GAME_EXES) do
            local fh = io.open(dir .. "/" .. exe, "rb")
            if fh then
                fh:close()
                return true
            end
        end
    end
    return false
end

-- Writes the summary text (Core/Capture.lua Capture.SummaryText) to path:
-- true, or nil and a short reason. Never inside the repo or a relative
-- path (it could be), never inside a game folder, never the same file as
-- one of `inputs` (the capture's saved files), never over a file that is
-- already there (S3: the summary can never overwrite a saved file).
function ns.offline.writeSummary(path, text, inputs)
    if type(path) ~= "string" or path == "" then return nil, "no path given" end
    if ns.offline.inRepo(path) then return nil, "inside the repo" end
    if inGameFolder(path) then return nil, "inside a game folder" end
    for _, input in ipairs(type(inputs) == "table" and inputs or {}) do
        if type(input) == "string" and norm(input) == norm(path) then return nil, "the same file as an input" end
    end
    local there = io.open(path, "rb")
    if there then
        there:close()
        return nil, "the file is already there"
    end
    local fh = io.open(path, "wb")
    if not fh then return nil, "the file did not open" end
    fh:write(tostring(text))
    fh:close()
    return true
end

-- Made-up files for tests that need a file to be there (lead section 208:
-- a test file names no file or system call; only this runner does). Made
-- in the system temp folder, never inside the repo.
--   tempFile(text) -> path of a new file holding text, or nil and a reason
--   readFile(path) -> its text, or nil
--   removeFile(path) -> true when it was removed
local made = 0
-- Where a temp folder is looked for (MyBuddy CS-5): these environment
-- names in order, then these folders; the first outside the repo where the
-- file opens is used.
ns.offline.TEMP_ENV = { "TEMP", "TMP", "TMPDIR", "TEMPDIR" }
ns.offline.TEMP_FALLBACK = { "/tmp", "/var/tmp" }
function ns.offline.tempFile(text)
    local dirs = {}
    for _, name in ipairs(ns.offline.TEMP_ENV) do
        local dir = os.getenv(name)
        if type(dir) == "string" and dir ~= "" then dirs[#dirs + 1] = dir end
    end
    for _, dir in ipairs(ns.offline.TEMP_FALLBACK) do dirs[#dirs + 1] = dir end
    local why = "no temp folder"
    for _, dir in ipairs(dirs) do
        if ns.offline.inRepo(dir) then
            why = "the temp folder is inside the repo"
        else
            made = made + 1
            local path = dir .. "/zflow-test-" .. tostring(os.time()) .. "-" .. made .. ".txt"
            local fh = io.open(path, "wb")
            if fh then
                fh:write(tostring(text))
                fh:close()
                return path
            end
            why = "the file did not open"
        end
    end
    return nil, why
end
function ns.offline.readFile(path)
    local fh = type(path) == "string" and io.open(path, "rb") or nil
    if not fh then return nil end
    local text = fh:read("*a")
    fh:close()
    return text
end
function ns.offline.removeFile(path)
    if type(path) ~= "string" or ns.offline.inRepo(path) then return false end
    return os.remove(path) and true or false
end

-- The add-on's own words (lead section 199, MyBuddy S1): every word inside a
-- quoted text in the files the game loads (the manifest, dev files left
-- out), lower case. A summary prints only these; any other word is counted.
-- Read once.
local ownWords
function ns.offline.ownWords()
    if ownWords then return ownWords end
    local words = {}
    for _, f in ipairs(manifest.files) do
        if not f.dev then
            local fh = io.open(L.join(root, L.ADDON .. "/" .. f.path), "rb")
            if fh then
                local text = fh:read("*a")
                fh:close()
                for _, quote in ipairs({ '"([^"\n]*)"', "'([^'\n]*)'" }) do
                    for literal in text:gmatch(quote) do
                        -- As written (MyBuddy CS-4): "Way" is not "way".
                        for word in literal:gmatch("%a+") do words[word] = true end
                    end
                end
            end
        end
    end
    ownWords = words
    return words
end

-- The sanitizer (Lazy's tools/offline/zflow-sanitize.lua), for its parser,
-- and its schema. Loaded as files beside this one; the sanitizer's own
-- command line runs only when it is the script given to lua.
local offlineDir = here   -- this file's folder, found at the top
local sanitizer
local function sanitize()
    if sanitizer == nil then
        local ok, S = pcall(dofile, offlineDir .. "/zflow-sanitize.lua")
        sanitizer = ok and type(S) == "table" and type(S.parse) == "function" and S or false
    end
    return sanitizer or nil
end
function ns.offline.schema()
    local ok, schema = pcall(dofile, offlineDir .. "/zflow-sanitize-schema.lua")
    return ok and type(schema) == "table" and schema or nil
end

-- A saved-variables file's text as the globals it assigns: { name = value }.
-- PARSED with the sanitizer's parser, never run (lead section 192, L3): only
-- Name = data is accepted; a call, a function or an expression is refused.
-- nil and a short reason that never quotes the text.
function ns.offline.parseSaved(text)
    local S = sanitize()
    if not S then return nil, "the sanitizer's parser is not there" end
    if type(text) ~= "string" then return nil, "not saved-variables data" end
    local ok, globals = pcall(S.parse, text)
    if not ok or type(globals) ~= "table" then
        local twice = type(globals) == "table" and type(globals.msg) == "string" and globals.msg:find("a global given twice", 1, true)
        return nil, twice and "a global given twice" or "not saved-variables data"
    end
    return globals
end

-- The globals of one or more saved files (the account file, the character
-- file), each parsed by ns.offline.parseSaved. A global in two files is
-- refused. nil and a short reason naming the file by its place only.
function ns.offline.readSaved(...)
    local vars = {}
    for i = 1, select("#", ...) do
        local path = select(i, ...)
        if path ~= nil then
            local fh = io.open(path, "rb")
            if not fh then return nil, "file " .. i .. " did not open" end
            local text = fh:read("*a")
            fh:close()
            local globals, why = ns.offline.parseSaved(text)
            if not globals then return nil, "file " .. i .. ": " .. why end
            for name, value in pairs(globals) do
                if vars[name] ~= nil then return nil, "file " .. i .. ": a global given twice" end
                vars[name] = value
            end
        end
    end
    return vars
end

-- The seen-result snapshot (zflow-seen.lua, lead section 188): one text
-- block of what the player sees on a fake client, and the compare of two.
-- Test tooling, never shipped. A file that does not load fails only the
-- tests that ask for it, with the reason.
do
    local chunk, err = loadfile(here .. "/zflow-seen.lua")
    local ok, seen = false, err
    if chunk then ok, seen = pcall(chunk) end
    if ok and type(seen) == "table" then
        ns.offline.seen, ns.offline.seenDiff, ns.offline.seenParts = seen.seen, seen.compare, seen
        seen.RUN_ROOT = root
    else
        local why = "tools/offline/zflow-seen.lua did not load: " .. tostring(seen)
        local function broken() error(why, 2) end
        ns.offline.seen, ns.offline.seenDiff = broken, broken
        ns.offline.seenParts = setmetatable({}, { __index = broken })
    end
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
    local checks, failures, skipped = 0, {}, nil
    local t = {}
    -- A test that cannot run here (no real capture given) says so: SKIP,
    -- with its reason, never PASS. Checks made before it still count.
    function t.skip(reason)
        skipped = tostring(reason or "skipped")
    end
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
    elseif skipped then
        counts.skip = counts.skip + 1
        print("SKIP   " .. label .. ": " .. skipped)
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
if counts.skip > 0 then print("zflow tests: " .. counts.skip .. " skipped (not passed; see SKIP lines)") end

local code = 0
if counts.fail > 0 or counts.error > 0 then code = 1
elseif counts.run == 0 then
    print("zflow: no test ran")
    code = 1
end
print("result: " .. (code == 0 and "OK" or "FAILED"))
finish(code)
