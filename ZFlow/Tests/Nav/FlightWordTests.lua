local _, ns = ...

-- Tests for ZFlow/Nav/FlightWord.lua (S30): the flight paths still to
-- learn, said in words. The pure lines, then the word on the whole add-on
-- with a fake client. Made-up masters and places; not tested in game.

local tests = {}

local function W() return ns.Nav.FlightWord end

tests["flight word: the lines name each master, the nearest first as given"] = function(t)
    local lines = W().Lines({
        { name = "Karos", yards = 28.4, onMap = true },
        { name = "Silva", onMap = true },
        { name = "Devrak" },
    })
    t.eq(lines[1], "Flight paths to learn: 3")
    t.eq(lines[2], "  Karos: about 30 yards away on this map")
    t.eq(lines[3], "  Silva: on this map")
    t.eq(lines[4], "  Devrak: on another map")
    t.eq(lines[5], W().TIP)
    t.eq(#lines, 5)
    t.eq(W().Lines({ { name = "Karos" } })[1], W().HEADER_ONE)
end

tests["flight word: more than it shows are counted, never cut silently"] = function(t)
    local goals = {}
    for i = 1, W().SHOWN + 3 do goals[i] = { name = "Master " .. i } end
    local lines = W().Lines(goals)
    t.eq(lines[1], "Flight paths to learn: " .. (W().SHOWN + 3))
    t.eq(lines[W().SHOWN + 2], "  and 3 more")
    goals[#goals], goals[#goals - 1] = nil, nil
    t.eq(W().Lines(goals)[W().SHOWN + 2], "  and 1 more")
end

tests["flight word: nothing, or odd things: the plain line, never an error"] = function(t)
    t.eq(W().Lines(nil), { W().NONE })
    t.eq(W().Lines({}), { W().NONE })
    t.eq(W().Lines({ "x", {}, { name = "" }, { name = 4 } }), { W().NONE })
    t.eq(W().Lines({ { name = "Karos", yards = 0 / 0 } })[2], "  Karos: on another map")
end

-- ------------------------------------------------------------ whole add-on

local MAP, OTHER = 1411, 1412

local function boot(npcs)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = npcs or {
        Karos = { kind = "flight", map = MAP, x = 0.50, y = 0.50, factions = { Horde = true } },
        Devrak = { kind = "flight", map = OTHER, x = 0.30, y = 0.30, factions = { Horde = true } },
        Aldric = { kind = "flight", map = MAP, x = 0.40, y = 0.40, factions = { Alliance = true } },
    } } } })
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(12)
    c.setZone(1, MAP); c.setPosition(MAP, 0.52, 0.50); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text, from)
    for i = (from or 0) + 1, #(c.printed or {}) do
        if tostring(c.printed[i]):find(text, 1, true) then return c.printed[i] end
    end
    return nil
end

local function problems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

tests["flight word: the word lists the player's own faction's masters not yet learned"] = function(t)
    local c, addon = boot()
    local before, base = #c.printed, problems(addon)
    c.slashes[ns.id.slash](W().WORD)
    t.ok(said(c, "Flight paths to learn: 2", before) ~= nil)
    t.ok(said(c, "Karos: about 20 yards away on this map", before) ~= nil)
    t.ok(said(c, "Devrak: on another map", before) ~= nil)
    t.eq(said(c, "Aldric", before), nil, "the other faction's master is not listed")
    t.ok(said(c, "Talk to one once", before) ~= nil)
    t.eq(problems(addon), base, "nothing new went wrong")
end

tests["flight word: none known, or the setting off, is said plainly"] = function(t)
    local c = boot({})
    local before = #c.printed
    c.slashes[ns.id.slash](W().WORD)
    t.ok(said(c, W().NONE, before) ~= nil)
    local addon
    c, addon = boot()
    addon.settings:set(ns.FlightPaths.SETTING, false)
    before = #c.printed
    c.slashes[ns.id.slash](W().WORD)
    t.ok(said(c, W().OFF, before) ~= nil)
    t.eq(said(c, "Karos", before), nil)
end

return tests
