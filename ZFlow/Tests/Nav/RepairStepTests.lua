-- Repair step (S6): a guide step to the nearest repair vendor this player
-- has seen, while the repair warning (Items/Repair.lua) is on. Made-up
-- places and readings, test only. Nothing here repairs, buys or clicks.
-- Not seen in game.
local _, ns = ...

local RS = ns.RepairStep
local R = ns.Repair
local N = ns.Nav

local T = {}

local LOW = { worst = { pct = 0.10, slot = 5, low = 1 },
              lines = { "An item you wear is at 10% durability.", "No repair vendor is known yet." } }
local NEAR = { kind = "repair", key = "Creature-0-1-2-3-54-0", name = "Kaita Deepforge",
               map = 1411, x = 0.5, y = 0.3, cont = 1, yards = 100 }

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

-- ------------------------------------------------------------------ pure

T["repair step: the names agreed"] = function(t)
    t.eq(RS.NAME, "repairStep")
    t.eq(RS.SETTING, "nav.repairStep")
    t.eq(RS.KIND, "repair")
    t.eq(RS.RADIUS, 10)
    t.eq(RS.KEEP, 10)
end

T["repair step: no warning, no step, whatever is near"] = function(t)
    t.eq(RS.Of(nil, NEAR), nil)
    t.eq(RS.Of("low", NEAR), nil)
    t.eq(RS.Of({}, NEAR), nil, "a warning with nothing low in it is none")
end

T["repair step: the nearest seen repair vendor, as the arrow takes a step"] = function(t)
    local step = RS.Of(LOW, NEAR)
    t.eq(step.kind, "repair")
    t.eq(step.label, "Repair: Kaita Deepforge")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    t.eq(step.radius, RS.RADIUS)
    t.eq(step.yards, 100)
    t.eq(step.from, "seen")
end

T["repair step: no name, or a name too long for a label, is the kind alone, never cut"] = function(t)
    local bare = RS.Of(LOW, { kind = "repair", map = 1411, x = 0.5, y = 0.3 })
    t.eq(bare.label, "Repair")
    t.eq(bare.yards, nil, "a distance not known is left out, never 0")
    local long = RS.Of(LOW, { kind = "repair", name = string.rep("n", 60), map = 1411, x = 0.5, y = 0.3 })
    t.eq(long.label, "Repair")
end

T["repair step: a near place that is no place is not pointed at"] = function(t)
    t.eq(RS.Of(LOW, { kind = "repair", name = "X", map = 1411, x = 2, y = 0.3 }), nil)
    t.eq(RS.Of(LOW, { kind = "repair", name = "X", x = 0.5, y = 0.3 }), nil)
    t.eq(RS.Of(LOW, { kind = "vendor", name = "X", map = 1411, x = 0.5, y = 0.3 }), nil, "another kind")
end

T["repair step: nothing seen, the vendor the warning already knows"] = function(t)
    local warning = { worst = LOW.worst, lines = LOW.lines,
                      step = { label = "Repair at Smith Near", place = { cont = 1, map = 1411, x = 0.4, y = 0.4 }, radius = 10 } }
    local step = RS.Of(warning, nil)
    t.eq(step.kind, "repair")
    t.eq(step.label, "Repair at Smith Near")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.4, y = 0.4 })
    t.eq(step.from, "imported")
    step.place.x = 9
    t.eq(warning.step.place.x, 0.4, "the warning is not changed")
    t.eq(RS.Of(LOW, nil), nil, "none known anywhere: text only")
end

T["repair step: the lines say the share and the nearest vendor"] = function(t)
    local lines = RS.Lines(LOW, RS.Of(LOW, NEAR))
    t.eq(lines[1], "An item you wear is at 10% durability.")
    t.eq(lines[2], "Nearest repair vendor you have seen: Kaita Deepforge, about 100 yd.")
    t.eq(#lines, 2)
    local noYards = RS.Lines(LOW, RS.Of(LOW, { kind = "repair", name = "Kaita Deepforge", map = 1411, x = 0.5, y = 0.3 }))
    t.eq(noYards[2], "Nearest repair vendor you have seen: Kaita Deepforge.")
    local noName = RS.Lines(LOW, RS.Of(LOW, { kind = "repair", map = 1411, x = 0.5, y = 0.3, yards = 40.4 }))
    t.eq(noName[2], "Nearest repair vendor you have seen: about 40 yd.")
end

T["repair step: with no step the lines of the warning stand"] = function(t)
    t.eq(RS.Lines(LOW, nil), LOW.lines)
    t.eq(RS.Lines(nil, nil), {})
end

T["repair step: a place for the route planner, of the kind repair"] = function(t)
    local place = RS.Place(RS.Of(LOW, NEAR))
    t.eq(place, { kind = "repair", name = "Repair: Kaita Deepforge", map = 1411, x = 0.5, y = 0.3 })
    t.eq(RS.Place(nil), nil)
    local route = N.RoutePlan({ place, { kind = "vendor", map = 1411, x = 0.9, y = 0.9 } }, 1411,
        { w = 1000, h = 500 }, { map = 1411, x = 0.5, y = 0.5 })
    t.eq(route.stops[1].place.kind, "repair", "the planner orders it like any place")
    t.eq(route.straight, true)
end

-- ---------------------------------------------------------------- module

local function service(x, y, name)
    return { map = 1411, x = x, y = y, name = name, kinds = { vendor = true, repair = true } }
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services } } })
    c.setDurability(opts.durability)
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setFaction("Horde")
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    R.Declare(k)
    local api = RS.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local WORN = { [5] = { cur = 10, max = 100 } }
local FINE = { [5] = { cur = 90, max = 100 } }

T["repair step module: low gear and a seen vendor give the step"] = function(t)
    local k, _, api = start({ durability = WORN, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.eq((k:ModuleState(RS.NAME)), "started")
    local step = api.step()
    t.eq(step.label, "Repair: Kaita Deepforge")
    t.eq(step.yards, 100)
    t.ok(has(api.lines(), "Nearest repair vendor you have seen: Kaita Deepforge, about 100 yd."))
    t.eq(k.use(RS.NAME).Step().label, "Repair: Kaita Deepforge", "others ask for it by name")
end

T["repair step module: gear that is fine gives nothing"] = function(t)
    local _, _, api = start({ durability = FINE, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.eq(api.step(), nil)
    t.eq(api.lines(), {})
end

T["repair step module: durability not read gives nothing, never a guess"] = function(t)
    local _, _, api = start({ durability = nil, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.eq(api.step(), nil)
end

T["repair step module: low gear, no vendor seen: no step, the words of the warning"] = function(t)
    local _, _, api = start({ durability = WORN })
    t.eq(api.step(), nil)
    t.ok(has(api.lines(), R.NO_VENDOR))
end

T["repair step module: the step goes when the gear is repaired"] = function(t)
    local _, c, api = start({ durability = WORN, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.ok(api.step() ~= nil)
    c.setDurability(FINE)
    c.fire(R.EVENT)
    t.eq(api.step(), nil)
end

T["repair step module: the nearest is looked up again only after RS.KEEP seconds"] = function(t)
    local _, c, api = start({ durability = WORN, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.eq(api.step().yards, 100)
    c.setPosition(1411, 0.5, 0.3)
    t.eq(api.step().yards, 100, "kept")
    c.advance(RS.KEEP + 1)
    t.eq(api.step().yards, 0, "asked again")
end

T["repair step module: the setting turns the step off, not the warning"] = function(t)
    local k, _, api = start({ durability = WORN, services = { a = service(0.5, 0.3, "Kaita Deepforge") } })
    t.ok(api.step() ~= nil, "on by default")
    t.eq(k.settings:row(RS.SETTING).type, "bool", "the module declares its own row")
    k.settings:set(RS.SETTING, false)
    t.eq(api.step(), nil)
    t.ok(#api.lines() > 0, "the words stay")
    k.settings:set(RS.SETTING, true)
    t.ok(api.step() ~= nil)
end

T["repair step: look only - nothing repairs, buys or clicks"] = function(t)
    for name in pairs(RS) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^repair$") or n:find("buy") or n:find("click") or n:find("auto") or n:find("sell")),
            "no acting function: " .. n)
    end
end

return T
