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
--     ("needs the client: <name>"), never PASS, whatever its checks said.
--
-- So a PASS here means: the test ran to the end on Flow's own Lua and made-up
-- inputs, and touched nothing of the game. It is not a gameplay test.

local S = {}

local rawset, setmetatable, type, tostring, error = rawset, setmetatable, type, tostring, error

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
-- A millisecond clock for timing only (no game state).
function lib.debugprofilestop() return os.clock() * 1000 end
S.lib = lib

-- Blizzard tables Flow adds its own entries to (luacheck "globals"): empty tables.
local BLIZZARD_TABLES = { "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames" }

-- Flow's own globals: nil until Flow sets them (saved variables start empty,
-- as on a fresh install), never a "missing" marker.
local function flowOwned(k)
    return type(k) == "string" and (k:match("^Flow") or k:match("^SLASH_FLOW") or k:match("^BINDING_"))
end

-- Installs the environment on _G. Returns nothing; S.phase drives behaviour.
function S.Install(G)
    S.G = G
    for k, v in pairs(lib) do rawset(G, k, v) end
    for _, k in ipairs(BLIZZARD_TABLES) do rawset(G, k, {}) end
    rawset(G, "CreateFrame", S.CreateFrame)
    setmetatable(G, {
        __index = function(_, k)
            if flowOwned(k) then return nil end
            if type(k) ~= "string" then return nil end
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
