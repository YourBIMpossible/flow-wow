-- Tests for ZFlow/Nav/Errand.lua (F2): the errand stop the player asks
-- for, as a step on the quest arrow, over the fake client. Every place and
-- name is made up by hand, test only. Not tested in game.
local _, ns = ...

local E, N, A = ns.Errand, ns.Nav, ns.Arrow

-- The player in the middle of map 1411, 1000 by 500 yards.
local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }

local function service(kinds, x, y, name)
    local e = { map = 1411, x = x, y = y, kinds = {}, name = name }
    for _, kind in ipairs(kinds) do e.kinds[kind] = true end
    return e
end

local function trainer(x, y, more)
    local e = { map = 1411, x = x, y = y, roles = { trainer = true } }
    for key, v in pairs(more or {}) do e[key] = v end
    return e
end

-- A vendor who repairs 100 yd north, a banker 250 yd east.
local function services()
    return {
        ["Creature-0-1-2-3-54-0"] = service({ "vendor", "repair" }, 0.5, 0.3, "Kaita Deepforge"),
        ["Banker Olivia"] = service({ "banker" }, 0.75, 0.5, "Banker Olivia"),
    }
end

-- opts: services (char rows), npcs (account rows), size (false: not
-- known), position (false: not known), faction.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {
        layout = { arrowIntroSeen = true },
        learned = { places = { npcs = opts.npcs } },
    })
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    if opts.position ~= false then c.setPosition(1411, 0.5, 0.5) end
    if opts.size ~= false then c.setMapSize(1411, 1000, 500) end
    if opts.faction then c.setFaction(opts.faction) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    local e = E.Declare(k, d, function() return a end)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, e, a
end

local function say(c, text) c.slashes[ns.id.slash](E.WORD .. (text and (" " .. text) or "")) end
local function last(c) return c.printed[#c.printed] or "" end
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end

local T = {}

T["errand: the names are the ones agreed"] = function(t)
    t.eq(E.NAME, "errand")
    t.eq(E.WORD, "stop")
    t.eq(E.NPCS, "learned.places.npcs")
    t.eq(E.ORDER, { "vendor", "repair", "bank", "inn", "flight", "mail", "trainer" })
    for _, word in ipairs(E.ORDER) do
        t.ok(E.LABELS[E.KINDS[word]] ~= nil, word .. " has a kind and a label")
    end
    for _, kind in ipairs(N.SERVICE_KINDS) do
        t.ok(E.LABELS[kind] ~= nil, kind .. " of the saved kinds has a label")
    end
end

T["errand trainer: nothing known, nothing given: nil"] = function(t)
    t.eq(E.TrainerOf(nil, HERE), nil)
    t.eq(E.TrainerOf({}, HERE), nil)
    t.eq(E.TrainerOf({ Bob = trainer(0.5, 0.4) }, nil), nil)
    t.eq(E.TrainerOf({ Bob = trainer(0.5, 0.4) }, { map = 1411 }), nil, "where the player is, is not known")
    t.eq(E.TrainerOf({ Bob = "junk", Al = 5 }, HERE), nil)
end

T["errand trainer: the one seen trainer on this map, with its distance"] = function(t)
    t.eq(E.TrainerOf({ ["Tognus Flintfire"] = trainer(0.5, 0.3) }, HERE), {
        kind = "trainer", key = "Tognus Flintfire", name = "Tognus Flintfire",
        map = 1411, x = 0.5, y = 0.3, cont = 1, yards = 100,
    })
end

T["errand trainer: the nearest of several, in yards when the size is known"] = function(t)
    -- 0.15 of 1000 yd east is 150 yd; 0.2 of 500 yd north is 100 yd.
    local npcs = { East = trainer(0.65, 0.5), North = trainer(0.5, 0.3) }
    t.eq(E.TrainerOf(npcs, HERE).key, "North")
    local got = E.TrainerOf(npcs, { map = 1411, x = 0.5, y = 0.5 })
    t.eq(got.key, "East", "with no size, by shares of the map")
    t.eq(got.yards, nil, "and no yards are said")
end

T["errand trainer: a tie goes to the lower key"] = function(t)
    local npcs = { Zed = trainer(0.5, 0.3), Abe = trainer(0.5, 0.7) }
    t.eq(E.TrainerOf(npcs, HERE).key, "Abe")
end

T["errand trainer: other maps, npcs that are no trainer and broken rows are left out"] = function(t)
    local npcs = {
        Far = { map = 1433, x = 0.5, y = 0.5, roles = { trainer = true } },
        Vendor = { map = 1411, x = 0.5, y = 0.5, roles = { vendor = true } },
        NoRoles = { map = 1411, x = 0.5, y = 0.5 },
        Off = trainer(1.5, 0.5),
        NoPlace = { map = 1411, roles = { trainer = true } },
        Real = trainer(0.9, 0.9),
    }
    t.eq(E.TrainerOf(npcs, HERE).key, "Real")
end

T["errand trainer: an npc saved for the other faction is left out"] = function(t)
    local npcs = {
        Near = trainer(0.5, 0.45, { factions = { Horde = true } }),
        Mine = trainer(0.5, 0.3, { factions = { Alliance = true } }),
    }
    local here = { map = 1411, x = 0.5, y = 0.5, faction = "Alliance" }
    t.eq(E.TrainerOf(npcs, here).key, "Mine")
    here.faction = nil
    t.eq(E.TrainerOf(npcs, here).key, "Near", "the faction of the player is not known: it stays in")
    here.faction = "Alliance"
    npcs.Near.factions = {}
    t.eq(E.TrainerOf(npcs, here).key, "Near", "no faction saved: it stays in")
end

T["errand step: the place as an arrow step, with the kind and the name"] = function(t)
    local place = { kind = "vendor", name = "Kaita Deepforge", map = 1411, x = 0.5, y = 0.3, cont = 1, yards = 100 }
    t.eq(E.Step(place), {
        label = "Vendor: Kaita Deepforge",
        place = { cont = 1, map = 1411, x = 0.5, y = 0.3 },
        radius = E.RADIUS,
    })
    place.name = nil
    t.eq(E.Step(place).label, "Vendor", "no name: the kind alone")
    place.kind = "banker"
    t.eq(E.Step(place).label, "Bank")
end

T["errand step: a label that would be too long is the kind alone, never cut"] = function(t)
    local long = string.rep("x", N.Waypoint.LABEL_MAX)
    local step = E.Step({ kind = "flight", name = long, map = 1411, x = 0.5, y = 0.3 })
    t.eq(step.label, "Flight master")
    local fits = string.rep("x", N.Waypoint.LABEL_MAX - #"Inn: ")
    t.eq(E.Step({ kind = "innkeeper", name = fits, map = 1411, x = 0.5, y = 0.3 }).label, "Inn: " .. fits)
end

T["errand step: no place, no step"] = function(t)
    t.eq(E.Step(nil), nil)
    t.eq(E.Step({}), nil)
    t.eq(E.Step({ kind = "vendor", map = 1411, x = 0.5 }), nil)
    t.eq(E.Step({ kind = "vendor", x = 0.5, y = 0.5 }), nil)
    t.eq(E.Step({ kind = "vendor", map = 1411, x = 1.2, y = 0.5 }), nil)
    t.eq(E.Step({ kind = "quest", map = 1411, x = 0.5, y = 0.5 }), nil, "a kind that is no stop")
end

T["errand: no stop until one is asked for, and the arrow shows none"] = function(t)
    local k, c, e = start({ services = services() })
    t.eq(e.stop(), nil)
    t.eq(e.step(), nil)
    -- Lead section 294 item 5: no step, the quest arrow says why.
    t.eq(c.arrows[1].shown, true)
    t.eq(c.arrows[1].lines, { ns.Arrow.NO_QUEST })
    t.eq(k.use(E.NAME).Step(), nil)
    t.eq(k.problems:count(), 0)
end

T["errand: stop vendor points the quest arrow at the nearest vendor seen"] = function(t)
    local k, c, e = start({ services = services() })
    say(c, "vendor")
    t.eq(e.stop().name, "Kaita Deepforge")
    t.eq(c.arrows[1].shown, true)
    t.eq(c.arrows[1].lines, { "Vendor: Kaita Deepforge", "100 yd N" })
    t.ok(has(last(c), "Vendor Kaita Deepforge"), last(c))
    t.ok(has(last(c), "100 yd"), last(c))
    t.eq(k.use(E.NAME).Stop().kind, "vendor")
    t.eq(k.problems:count(), 0)
end

T["errand: each word asks for its kind"] = function(t)
    local _, c, e = start({ services = services() })
    say(c, "bank")
    t.eq(e.stop().name, "Banker Olivia")
    t.eq(c.arrows[1].lines, { "Bank: Banker Olivia", "250 yd E" })
    say(c, "REPAIR")
    t.eq(e.stop().kind, "repair")
    t.eq(c.arrows[1].lines, { "Repair: Kaita Deepforge", "100 yd N" })
end

T["errand: stop trainer points at the nearest trainer seen"] = function(t)
    local _, c, e = start({ npcs = { ["Tognus Flintfire"] = trainer(0.5, 0.3, { trains = { Blacksmithing = true } }) } })
    say(c, "trainer")
    t.eq(e.stop().key, "Tognus Flintfire")
    t.eq(c.arrows[1].lines, { "Trainer: Tognus Flintfire", "100 yd N" })
end

T["errand: a kind never seen on this map changes nothing and says so"] = function(t)
    local _, c, e = start({ services = services() })
    say(c, "vendor")
    say(c, "flight")
    t.eq(e.stop().kind, "vendor", "the stop chosen before stays")
    t.ok(has(last(c), "no flight"), last(c))
    t.ok(has(last(c), "Nothing changed"), last(c))
    t.eq(c.arrows[1].lines, { "Vendor: Kaita Deepforge", "100 yd N" })
end

T["errand: stop off takes the stop off the arrow"] = function(t)
    local _, c, e = start({ services = services() })
    say(c, "vendor")
    say(c, "off")
    t.eq(e.stop(), nil)
    t.eq(c.arrows[1].lines, { ns.Arrow.NO_QUEST }, "the stop is off the arrow; it says why")
    t.ok(has(last(c), "no stop chosen"), last(c))
end

T["errand: the bare word says the stop chosen, or how to choose one"] = function(t)
    local _, c = start({ services = services() })
    say(c)
    t.ok(has(last(c), "no stop chosen"), last(c))
    say(c, "vendor")
    say(c)
    t.ok(has(last(c), "Vendor Kaita Deepforge"), last(c))
    t.ok(has(last(c), E.WORD .. " off"), last(c))
end

T["errand: a word that is no stop says so and changes nothing"] = function(t)
    local _, c, e = start({ services = services() })
    say(c, "vendor")
    say(c, "castle")
    t.ok(has(last(c), "\"castle\" is no stop"), last(c))
    t.eq(e.stop().kind, "vendor")
end

T["errand: the own waypoint of the player wins over the stop"] = function(t)
    local _, c = start({ services = services() })
    say(c, "bank")
    c.slashes[ns.id.slash]("way 50 30 mine")
    t.eq(c.arrows[1].lines, { "mine", "100 yd N" })
    c.slashes[ns.id.slash]("way clear")
    t.eq(c.arrows[1].lines, { "Bank: Banker Olivia", "250 yd E" }, "the stop again")
end

T["errand: the stop is kept in memory only"] = function(t)
    local k, c = start({ services = services() })
    local before = k.store:get("char", "learned.places.services")
    say(c, "vendor")
    t.eq(k.store:get("char", "learned.places.services"), before)
    local char = c.saved(ns.id.charDB)
    t.eq(char.errand, nil)
    t.eq(char.stop, nil)
    local account = c.saved(ns.id.accountDB)
    t.eq(account.errand, nil)
    t.eq(account.stop, nil)
end

T["errand: stop hearth says the bind place and when the stone is ready"] = function(t)
    local _, c, e = start()
    say(c, "hearth")
    t.ok(has(last(c), "where your hearthstone is set is not known"), last(c))
    t.ok(has(last(c), "whether it is ready is not known"), last(c))
    c.setBindLocation("Goldshire")
    c.setHearthCooldown(0)
    say(c, "hearth")
    t.ok(has(last(c), "set to Goldshire; it is ready."), last(c))
    c.setHearthCooldown(601)
    say(c, "hearth")
    t.ok(has(last(c), "ready in 11 min."), last(c))
    t.eq(e.stop(), nil, "the hearthstone is said, not pointed at")
    t.eq(c.arrows[1].lines, { ns.Arrow.NO_QUEST }, "not pointed at: the quest arrow says why (lead section 294 item 5)")
end

T["errand hearth: the words, from the reads alone"] = function(t)
    t.eq(E.Hearth(nil), "where your hearthstone is set is not known; whether it is ready is not known.")
    t.eq(E.Hearth({ bindLocation = function() return "Goldshire" end, hearthCooldown = function() return 60 end }),
        "your hearthstone is set to Goldshire; ready in 1 min.")
    t.eq(E.Hearth({ bindLocation = function() error("no") end, hearthCooldown = function() return 0 end }),
        "where your hearthstone is set is not known; it is ready.")
end

T["errand route: the nearest of each kind once, in a short order, as straight lines"] = function(t)
    local k, c = start({ services = services() })
    local plan = E.Route(c, k.store)
    t.eq(#plan.stops, 2, "the vendor who repairs is one stop")
    t.eq(plan.stops[1].place.name, "Kaita Deepforge")
    t.eq(plan.stops[2].place.name, "Banker Olivia")
    t.eq(plan.stops[1].leg, 100)
    t.eq(plan.label, N.ROUTE_STRAIGHT)
    local from = #c.printed
    say(c, "route")
    t.eq(#c.printed - from, 3)
    t.ok(has(c.printed[from + 1], "1. Vendor Kaita Deepforge, 100 yd"), c.printed[from + 1])
    t.ok(has(c.printed[from + 2], "2. Bank Banker Olivia, 269 yd"), c.printed[from + 2])
    t.ok(has(last(c), "about 369 yd in all"), last(c))
    t.ok(has(last(c), N.ROUTE_STRAIGHT), last(c))
end

T["errand route: nothing seen, no size or no position is said plainly"] = function(t)
    local k, c = start()
    t.eq(select(2, E.Route(c, k.store)), "no places")
    say(c, "route")
    t.ok(has(last(c), "no stop you have seen is on this map"), last(c))
    k, c = start({ services = services(), size = false })
    t.eq(select(2, E.Route(c, k.store)), "size unknown")
    say(c, "route")
    t.ok(has(last(c), "the size of this map is not known"), last(c))
    k, c = start({ services = services(), position = false })
    t.eq(select(2, E.Route(c, k.store)), "position unknown")
    say(c, "route")
    t.ok(has(last(c), "where you are is not known"), last(c))
end

T["errand: every line said starts with the title and none spells the old name"] = function(t)
    local _, c = start({ services = services() })
    local from = #c.printed
    for _, text in ipairs({ "", "vendor", "flight", "castle", "hearth", "route", "off" }) do say(c, text) end
    t.ok(#c.printed > from, "something was said")
    for i = from + 1, #c.printed do
        t.eq(c.printed[i]:sub(1, #ns.id.title + 2), ns.id.title .. ": ", c.printed[i])
    end
end

T["errand: the help of the command is listed"] = function(t)
    local k = ns.Kernel({}, ns.make.fakeClient())
    local d = ns.Diag.Start(k)
    E.Declare(k, d)
    t.eq(d.help[E.WORD], E.HELP)
    t.ok(type(d.commands[E.WORD]) == "function", "the command is there")
end

T["errand: a store that fails or a client that says nothing gives no stop"] = function(t)
    t.eq(E.Find("trainer", nil, nil), nil)
    t.eq(E.Find("vendor", {}, {}), nil)
    t.eq(E.Find("trainer", { position = function() return { map = 1411, x = 0.5, y = 0.5 } end },
        { get = function() error("broken") end }), nil)
    t.eq(E.Find("trainer", { position = function() error("no") end }, { get = function() return {} end }), nil)
end

return T
