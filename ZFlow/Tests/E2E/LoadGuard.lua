local _, ns = ...
-- Core/Guard.lua through its real entry, on the whole add-on loaded on a
-- fake client: with the predecessor's saved data loaded, the login pauses
-- the add-on, copies the old add-on's flight points into this one's
-- character data once and says so; the slash command says it is paused.
-- Without the predecessor nothing is paused or said. The old tables are
-- never changed. Made-up flight points. Not tested in game.
local tests = {}

local COPY_WORDS = "copied the old add-on's flight points"

local function oldChar()
    return { data = { flights = {
        Stonegate = { cont = 1, wx = -4000.5, wy = 210 },
        Rivermouth = { cont = 1, wx = 150, wy = -3300.25 },
    } } }
end

-- opts: old (predecessor account table), oldChar, char, loaded.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if opts.old then c.setSaved(ns.id.predecessorDB, opts.old) end
    if opts.oldChar then c.setSaved(ns.id.predecessorCharDB, opts.oldChar) end
    if opts.loaded then c.setLoaded(ns.id.predecessor, true) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function copyLines(c)
    local n = 0
    for _, p in ipairs(c.printed) do
        if p:find(COPY_WORDS, 1, true) then n = n + 1 end
    end
    return n
end

local function has(c, line)
    for _, p in ipairs(c.printed) do
        if p == line then return true end
    end
    return false
end

local function nodes(c)
    local ch = c.saved(ns.id.charDB)
    local l = type(ch) == "table" and ch.learned
    local f = type(l) == "table" and l.flights
    return type(f) == "table" and f.nodes or nil
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

tests["load guard: the old add-on loaded pauses this one and copies its flight points once"] = function(t)
    local c, addon = boot({ old = {}, oldChar = oldChar(), loaded = true })
    t.eq(addon.paused, true, "paused")
    t.ok(has(c, ns.Guard.IMPORTED:format(ns.id.title, 2)), "the copy line is said")
    t.eq(nodes(c) and nodes(c).Stonegate, { cont = 1, wx = -4000.5, wy = 210 })
    t.eq(c.saved(ns.id.predecessorCharDB), oldChar(), "the old table is unchanged")
    local line = said(c, "")[1]
    t.ok(line ~= nil and line:find(ns.id.title .. ": paused.", 1, true) == 1, tostring(line))

    local again = boot({ old = {}, oldChar = oldChar(), loaded = true, char = c.saved(ns.id.charDB) })
    t.eq(copyLines(again), 0, "a second load copies nothing and says nothing")
end

tests["load guard: the old add-on's saved data alone is a sign it is loaded"] = function(t)
    local _, addon = boot({ old = {} })
    t.eq(addon.paused, true)
end

tests["load guard: without the old add-on nothing is paused or copied"] = function(t)
    local c, addon = boot()
    t.ok(addon.paused ~= true, "not paused")
    t.eq(addon.phase, "running")
    t.eq(nodes(c), nil)
    t.eq(copyLines(c), 0)
end

tests["load guard: old data at a version this importer does not know pauses but copies nothing"] = function(t)
    local c, addon = boot({ old = { version = 999 }, oldChar = oldChar(), loaded = true })
    t.eq(addon.paused, true)
    t.eq(nodes(c), nil, "nothing copied from data it cannot read")
    t.eq(copyLines(c), 0)
end

return tests
