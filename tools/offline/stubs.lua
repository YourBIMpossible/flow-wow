-- Offline runner environment (tools/run-tests.ps1). Lua 5.1, outside the game.
--
-- EVERYTHING HERE IS A FIXTURE. None of it is the game, and none of it claims
-- to behave like the game. The rule it follows:
--
--   * Pure Lua library functions the game also provides (strsplit, wipe,
--     tinsert, format, ...) are given as plain-Lua equivalents. They are
--     string/table helpers with no game state behind them.
--   * CreateFrame gives an inert fixture frame, only so files that build
--     their windows at load time can finish loading. It draws nothing, sizes
--     nothing, and fires no events (the runner fires ADDON_LOADED once, the
--     way a fresh install starts).
--   * Every other global the game would provide (UnitLevel, C_Map, GameTooltip,
--     issecretvalue, C_Timer, ...) is MISSING. Reading one gives a "missing"
--     marker. While files load, calling a marker does nothing and returns
--     another marker, so the file can finish. While a test runs, touching a
--     marker (reading the global, indexing or calling it, or calling a method
--     on a fixture frame) records the name, and the test is reported SKIP
--     ("needs the client: <name>"), never PASS, whatever its checks said
--     (unless a check had already failed before that first touch: then it
--     is a SKIP-FAIL, listed and counted, failing the run with --strict; see run.lua).
--   * debugprofilestop is the one exception: a timing fixture, with rules of
--     its own so that no test passes on what it measured (see below).
--
-- So a PASS here means: the test ran to the end on Flow's own Lua and made-up
-- inputs, and touched nothing of the game. It is not a gameplay test.

local S = {}

local rawset, setmetatable, type, tostring, error = rawset, setmetatable, type, tostring, error
local io_open = io.open

S.MARK = "<<FLOW-OFFLINE-NEEDS-CLIENT>>"
S.phase = "load"              -- "load" while files load, "test" while a test runs
S.touched = {}                -- names touched in this test (test phase)
S.touchedOrder = {}
S.loadTouched = {}            -- name -> true, while the current file loaded

local function touch(name)
    if S.phase == "test" then
        if not S.touched[name] then
            S.touched[name] = true
            S.touchedOrder[#S.touchedOrder + 1] = name
            -- The runner notes how many checks had already failed at the
            -- first touch: those failures can't be the client's doing.
            if #S.touchedOrder == 1 and S.onFirstTouch then S.onFirstTouch(name) end
        end
    else
        S.loadTouched[name] = true
    end
end
S.touch = touch

local function needs(name)
    touch(name)
    error(S.MARK .. name, 0)
end

-------------------------------------------------------------------------------
-- Missing-global markers
-------------------------------------------------------------------------------
local markerName = setmetatable({}, { __mode = "k" })
local markerCache = {}
local Marker = {}

local function marker(name)
    local m = markerCache[name]
    if m then return m end
    m = setmetatable({}, Marker)
    markerName[m] = name
    markerCache[name] = m
    return m
end
S.marker = marker
function S.IsMarker(v) return type(v) == "table" and markerName[v] ~= nil end

Marker.__index = function(self, k)
    local name = markerName[self] .. "." .. tostring(k)
    touch(name)
    return marker(name)
end
Marker.__newindex = function(self, k)
    local name = markerName[self] .. "." .. tostring(k)
    if S.phase == "test" then needs(name) end
    touch(name)
end
Marker.__call = function(self, ...)
    local name = markerName[self]
    if S.phase == "test" then needs(name) end
    touch(name)
    return marker(name .. "()")
end
Marker.__tostring = function(self) touch(markerName[self]); return "<missing " .. markerName[self] .. ">" end
-- Arithmetic, joining and comparing: in a test, the test needs the client.
-- While files load (a pattern built from one of the game's strings at file
-- level), the result is one more marker, so the file finishes loading; a
-- comparison is false. Whatever a file keeps from it stays a marker, and a
-- test that touches it later is a SKIP.
local function opMarker(a, b)
    local m = (S.IsMarker(a) and a) or b
    if S.phase == "test" then needs(markerName[m]) end
    touch(markerName[m])
    return marker(markerName[m] .. "(op)")
end
local function cmpMarker(a, b)
    local m = (S.IsMarker(a) and a) or b
    if S.phase == "test" then needs(markerName[m]) end
    touch(markerName[m])
    return false
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len" }) do
    Marker[op] = opMarker
end
Marker.__lt, Marker.__le = cmpMarker, cmpMarker

-------------------------------------------------------------------------------
-- Fixture frames (CreateFrame). Inert: methods store scripts and return nil.
-------------------------------------------------------------------------------
local Frame = {}
local frameData = setmetatable({}, { __mode = "k" })
S.frames = {}                 -- every fixture frame, in creation order

local makeFrame
-- Methods that hand back a child object: a child fixture frame.
local CHILD = { CreateTexture = true, CreateFontString = true, CreateAnimationGroup = true,
                CreateAnimation = true, CreateLine = true, CreateMaskTexture = true }

-- Getters whose number Flow does arithmetic on while it builds its windows
-- (f:GetFrameLevel() + 2). They give 0: a made-up number, there only so an
-- ns:OnLoad can finish and leave Flow's own state set up as in the game.
-- No test can pass on it: in a test, any frame method is a touch (SKIP).
local NUMBER = { GetFrameLevel = true }

local function method(name)
    return function(self, a, b)
        if S.phase == "test" then needs("CreateFrame:" .. name) end
        local d = frameData[self]
        if not d then return nil end
        if CHILD[name] then return makeFrame(name, nil, self) end
        if name == "SetScript" then d.scripts[a] = b; return end
        if name == "HookScript" then d.hooks[#d.hooks + 1] = { a, b }; return end
        if name == "GetScript" then return d.scripts[a] end
        if name == "RegisterEvent" or name == "RegisterUnitEvent" then d.events[a] = true; return end
        if name == "UnregisterEvent" then d.events[a] = nil; return end
        if name == "GetName" then return d.name end
        if name == "GetParent" then return d.parent end
        if NUMBER[name] then return 0 end
        return nil
    end
end
local methodCache = {}
Frame.__index = function(self, k)
    -- Only CamelCase names are frame methods; anything else is a field Flow
    -- put on the frame itself (f.title), which is nil until set.
    if type(k) == "string" and k:match("^[A-Z]") then
        local fn = methodCache[k]
        if not fn then fn = method(k); methodCache[k] = fn end
        return fn
    end
    return nil
end

makeFrame = function(kind, name, parent)
    local f = setmetatable({}, Frame)
    frameData[f] = { kind = kind, name = name, parent = parent, scripts = {}, hooks = {}, events = {} }
    S.frames[#S.frames + 1] = f
    if type(name) == "string" and name ~= "" then rawset(S.G, name, f) end
    return f
end

function S.CreateFrame(kind, name, parent)
    if S.phase == "test" then needs("CreateFrame") end
    touch("CreateFrame")
    return makeFrame(kind, name, parent)
end

-- The runner's one event: deliver it to every fixture frame that registered it,
-- through the OnEvent script that frame set (Core.lua's event bus).
function S.Fire(event, ...)
    local n = 0
    for _, f in ipairs(S.frames) do
        local d = frameData[f]
        if d and d.events[event] and d.scripts.OnEvent then
            d.scripts.OnEvent(f, event, ...)
            n = n + 1
        end
    end
    return n
end

-------------------------------------------------------------------------------
-- Plain-Lua equivalents of library functions the game provides (fixtures).
-------------------------------------------------------------------------------
local lib = {}

function lib.strsplit(delim, str, pieces)
    local out, start, set = {}, 1, "[" .. delim:gsub("[%]%^%-%%]", "%%%0") .. "]"
    while true do
        if pieces and #out == pieces - 1 then out[#out + 1] = str:sub(start); break end
        local a, b = str:find(set, start)
        if not a then out[#out + 1] = str:sub(start); break end
        out[#out + 1] = str:sub(start, a - 1)
        start = b + 1
    end
    return unpack(out)
end
function lib.strtrim(s, chars)
    local set = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "[ \t\r\n]"
    s = s:gsub("^" .. set .. "+", "")
    return (s:gsub(set .. "+$", ""))
end
function lib.strjoin(sep, ...) return table.concat({ ... }, sep) end
lib.strlower, lib.strupper, lib.format = string.lower, string.upper, string.format
lib.floor, lib.ceil, lib.max, lib.min, lib.abs, lib.sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
lib.tinsert, lib.tremove = table.insert, table.remove
function lib.wipe(t) for k in pairs(t) do t[k] = nil end return t end
function lib.tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
lib.date, lib.time = os.date, os.time
S.lib = lib

-------------------------------------------------------------------------------
-- debugprofilestop: the one client API given a stand-in. A TIMING FIXTURE.
--
-- It is the game's millisecond timer, not a string/table helper, so it is not
-- in `lib`. Flow's modules pick it up at file level (local clock =
-- debugprofilestop) to time their own work (Modules/Perf.lua), and a planner
-- test that happens to run through timed code is still a test of the planner.
-- Making every call a "needs the client" turns 20 tests into SKIP, 17 of them
-- tests of routing and planning that check no time at all. So:
--
--   * Reading the GLOBAL while a test runs is a client touch like any other:
--     the test (or the code it runs) asked the game for its timer. SKIP.
--   * Calling a clock picked up at load time is counted (S.timerCalls), not a
--     touch. The runner runs any test that passed with timer calls again on
--     two made-up clocks (S.SetClock: one where every reading is 1000 ms
--     after the last, one where it is a millionth of a millisecond after). A
--     test that doesn't pass on all three clocks depends on what the timer
--     said, which offline is this fixture and not the game: SKIP, never PASS.
--
-- The real reading is os.clock (CPU time of this process), in milliseconds.
-------------------------------------------------------------------------------
S.TIMER = "debugprofilestop"
S.timerCalls = 0
local os_clock = os.clock
local clockStep, clockNow = nil, 0
-- step = nil: os.clock. A number: each reading is that many ms after the last.
function S.SetClock(step)
    clockStep = step
    if step then clockNow = os_clock() * 1000 end
end
local function timingFixture()
    if S.phase == "test" then S.timerCalls = S.timerCalls + 1 end
    if clockStep then clockNow = clockNow + clockStep; return clockNow end
    return os_clock() * 1000
end

-- Blizzard tables Flow adds its own entries to (luacheck "globals"): empty tables.
local BLIZZARD_TABLES = { "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames" }

-- Flow's own globals: nil until Flow sets them (saved variables start empty,
-- as on a fresh install), never a "missing" marker.
local function flowOwned(k)
    return type(k) == "string" and (k:match("^Flow") or k:match("^SLASH_FLOW") or k:match("^BINDING_"))
end

-------------------------------------------------------------------------------
-- Which missing globals are the game's: tools/offline/client-globals.txt.
-- A global that is not Flow's, not a fixture and not on that list is not
-- "something the game must have": it is a typo or a missing "ns.". Reading it
-- raises a plain Lua error (no marker, so no SKIP) and is noted in S.unknown,
-- so the runner can fail the file or the test even when Flow's own pcall
-- swallowed the error.
-------------------------------------------------------------------------------
S.unknown = {}                -- names, in the order first read; reset by the runner
local unknownSeen = {}
local knownNames, knownPatterns

-- Reads the list. Returns names (set), patterns (Lua patterns, anchored) and
-- the count of lines used; nil, message if the file can't be read or a line is malformed.
function S.ReadClientGlobals(file)
    local fh = io_open(file, "r")
    if not fh then return nil, "can't read " .. file end
    local names, patterns, n = {}, {}, 0
    for l in fh:lines() do
        l = l:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" and not l:match("^#") then
            local viaG = l:match("^_G:%s*(.+)$")
            local name = viaG or l
            if name:find("*", 1, true) then
                if not viaG then fh:close(); return nil, file .. ": a pattern line must start with \"_G: \": " .. l end
                patterns[#patterns + 1] = "^" .. name:gsub("[^%w_ *]", "%%%0"):gsub("%*", "[%%w_ ]*") .. "$"
            elseif not name:match("^[%a_][%w_]*$") then
                fh:close(); return nil, file .. ": not a global's name: " .. l
            else
                names[name] = true
            end
            n = n + 1
        end
    end
    fh:close()
    return names, patterns, n
end

function S.IsClientGlobal(k)
    if not knownNames then return true end       -- no list given: every name passes (the old behaviour)
    if knownNames[k] then return true end
    for _, p in ipairs(knownPatterns) do if k:match(p) then return true end end
    return false
end

function S.ResetUnknown() S.unknown, unknownSeen = {}, {} end

-- Installs the environment on _G. names/patterns: from S.ReadClientGlobals
-- (nil = no list: every missing global counts as the game's). S.phase drives behaviour.
function S.Install(G, names, patterns)
    S.G = G
    knownNames, knownPatterns = names, patterns or {}
    for k, v in pairs(lib) do rawset(G, k, v) end
    for _, k in ipairs(BLIZZARD_TABLES) do rawset(G, k, {}) end
    rawset(G, "CreateFrame", S.CreateFrame)
    setmetatable(G, {
        __index = function(_, k)
            if flowOwned(k) then return nil end
            if type(k) ~= "string" then return nil end
            if k == S.TIMER then
                -- Read while a test runs: a client touch. At load: the fixture, uncounted.
                if S.phase == "test" then touch(k) end
                return timingFixture
            end
            if not S.IsClientGlobal(k) then
                if not unknownSeen[k] then unknownSeen[k] = true; S.unknown[#S.unknown + 1] = k end
                error("unknown global '" .. k .. "': not Flow's, and not in tools/offline/client-globals.txt"
                    .. " (a typo, or a missing \"ns.\"? If the game has it, add it to that list)", 2)
            end
            touch(k)
            return marker(k)
        end,
    })
end

-- What a test touched, first name first.
function S.ResetTouched() S.touched, S.touchedOrder = {}, {} end
function S.Touched() return S.touchedOrder end
function S.ResetLoadTouched() S.loadTouched = {} end
function S.LoadTouched()
    local list = {}
    for k in pairs(S.loadTouched) do list[#list + 1] = k end
    table.sort(list)
    return list
end

return S
