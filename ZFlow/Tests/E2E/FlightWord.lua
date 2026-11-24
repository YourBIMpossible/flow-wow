local _, ns = ...

-- End to end (lead section 398 item 5): FlightPaths Goals through the word
-- that says them. The player types `flights` after the slash; the flight
-- masters their own play recorded and whose path this character lacks are
-- listed, the nearest on this map first. On the whole add-on with a fake
-- client; made-up places and names. Not tested in game.

local tests = {}

local MAP = 1436
local OTHER = 1437

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    if opts.npcs ~= false then
        addon.store:set("account", ns.FlightPaths.NPCS, {
            Karos = { map = MAP, x = 0.6, y = 0.5, roles = { flight = true }, factions = { Alliance = true } },
            Vey = { map = OTHER, x = 0.5, y = 0.5, roles = { flight = true }, factions = { Alliance = true } },
            Gorth = { map = MAP, x = 0.4, y = 0.5, roles = { flight = true }, factions = { Horde = true } },
        })
    end
    if opts.talked then addon.store:set("char", ns.FlightPaths.TALKED, opts.talked) end
    return c, addon
end

local function slash(c, text)
    c.printed = {}
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

local function lines(c)
    local out, prefix = {}, ns.id.title .. ": "
    for _, line in ipairs(c.printed or {}) do
        local s = tostring(line)
        if s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1) end
        out[#out + 1] = s
    end
    return out
end

tests["flight word e2e: /zflow flights lists the paths to learn, nearest on this map first"] = function(t)
    local c = boot()
    slash(c, "flights")
    local W = ns.Nav.FlightWord
    t.eq(lines(c), {
        W.HEADER:format(2),
        W.NEAR:format("Karos", 100),
        W.AWAY:format("Vey"),
        W.TIP,
    }, "the other faction's master is no target")
end

tests["flight word e2e: a path talked to is learned and leaves the list"] = function(t)
    local c = boot({ talked = { Karos = true } })
    slash(c, "flights")
    local W = ns.Nav.FlightWord
    t.eq(lines(c), { W.HEADER_ONE, W.AWAY:format("Vey"), W.TIP })
end

tests["flight word e2e: no master recorded: the plain none line"] = function(t)
    local c = boot({ npcs = false })
    slash(c, "flights")
    t.eq(lines(c), { ns.Nav.FlightWord.NONE })
end

tests["flight word e2e: the setting off: says it is off"] = function(t)
    local c, addon = boot()
    addon.settings:set(ns.FlightPaths.SETTING, false)
    slash(c, "flights")
    t.eq(lines(c), { ns.Nav.FlightWord.OFF })
end

return tests
