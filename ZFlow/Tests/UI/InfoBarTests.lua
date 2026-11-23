local _, ns = ...
-- N59 (lead section 243): the pure parts of the info bar. Which metrics the
-- player chose, in their order; the short words each shows on the bar; the
-- longer line each gives on hover; and a metric the client does not answer,
-- shown as not available, never as zero. Made-up values only. Not tested in
-- game.
local tests = {}

local function IB() return ns.InfoBar or {} end

local function call(name, ...)
    local fn = IB()[name]
    if type(fn) ~= "function" then return "no " .. name end
    return fn(...)
end

tests["info bar: nine metrics, four of them by default"] = function(t)
    local ids = {}
    for _, m in ipairs(IB().METRICS or {}) do ids[#ids + 1] = m.id end
    t.eq(ids, { "gold", "bags", "durability", "xp", "rep", "clock", "hearth", "fps", "latency" })
    t.eq(call("Parse", IB().DEFAULT), { "gold", "bags", "durability", "xp" })
end

tests["info bar: the chosen metrics in the order given, unknown words and repeats left out"] = function(t)
    t.eq(call("Parse", "latency gold"), { "latency", "gold" })
    t.eq(call("Parse", " rep, xp  rep nonsense CLOCK "), { "rep", "xp", "clock" })
    t.eq(call("Parse", ""), {})
    t.eq(call("Parse", nil), {})
    t.eq(call("Parse", 5), {})
end

tests["info bar: gold in gold, silver and copper"] = function(t)
    t.eq(call("Short", "gold", 12345), "1g 23s 45c")
    t.eq(call("Short", "gold", 2305), "23s 5c")
    t.eq(call("Short", "gold", 7), "7c")
    t.eq(call("Short", "gold", 0), "0c", "none is zero: the client said so")
    t.eq(call("Detail", "gold", 12345), "Gold: 1g 23s 45c")
end

tests["info bar: free bag slots count only the bags any item goes in"] = function(t)
    local bags = { { bag = 0, free = 4, total = 16 }, { bag = 1, free = 8, total = 20, family = 0 },
                   { bag = 2, free = 10, total = 28, family = 1 } }
    t.eq(call("Short", "bags", bags), "Bags 12")
    t.eq(call("Detail", "bags", bags), "Free bag slots: 12 of 36")
    t.eq(call("Short", "bags", {}), "Bags 0")
end

tests["info bar: durability is the most worn item"] = function(t)
    local worn = { [1] = { cur = 50, max = 100 }, [5] = { cur = 17, max = 20 } }
    t.eq(call("Short", "durability", worn), "Dur 50%")
    t.eq(call("Detail", "durability", worn), "Durability: 50% on the most worn item")
    t.eq(call("Short", "durability", {}), "Dur n/a", "nothing that wears: not zero")
end

tests["info bar: experience with the amount needed and rested"] = function(t)
    local xp = { cur = 450, max = 1000, rested = 200 }
    t.eq(call("Short", "xp", xp), "XP 45%")
    t.eq(call("Detail", "xp", xp), "Experience: 450 / 1000 (45%), rested 200")
    t.eq(call("Detail", "xp", { cur = 0, max = 400, rested = 0 }), "Experience: 0 / 400 (0%), not rested")
end

tests["info bar: the watched faction, its standing and progress"] = function(t)
    local rep = { name = "Test Faction", standing = 5, label = "Friendly", min = 3000, max = 9000, value = 6000 }
    t.eq(call("Short", "rep", rep), "Friendly 50%")
    t.eq(call("Detail", "rep", rep), "Reputation: Test Faction, Friendly, 3000 / 6000")
    t.eq(call("Short", "rep", false), "Rep none")
    t.eq(call("Detail", "rep", false), "Reputation: no faction watched")
    local noLabel = { name = "Test Faction", standing = 9, min = 0, max = 0, value = 0 }
    t.eq(call("Short", "rep", noLabel), "Rep 0%", "a standing with no width and no label")
end

tests["info bar: server time, hearthstone, frame rate and latency"] = function(t)
    t.eq(call("Short", "clock", { hour = 14, minute = 5 }), "14:05")
    t.eq(call("Detail", "clock", { hour = 9, minute = 30 }), "Server time: 09:30")
    t.eq(call("Short", "hearth", 0), "Hearth ready")
    t.eq(call("Short", "hearth", 61), "Hearth 2m")
    t.eq(call("Detail", "hearth", 720), "Hearthstone: 12 min")
    t.eq(call("Detail", "hearth", 0), "Hearthstone: ready")
    t.eq(call("Short", "fps", 60), "60 fps")
    t.eq(call("Detail", "fps", 60), "Frame rate: 60 fps")
    t.eq(call("Short", "latency", { home = 40, world = 45 }), "45 ms")
    t.eq(call("Detail", "latency", { home = 40, world = 45 }), "Latency: home 40 ms, world 45 ms")
end

-- A read the client does not answer (nil) is not available, never zero.
tests["info bar: every metric not answered shows as not available"] = function(t)
    for _, m in ipairs(IB().METRICS or {}) do
        t.eq(call("Short", m.id, nil), m.label .. " n/a", m.id)
        t.eq(call("Detail", m.id, nil), m.name .. ": not available", m.id)
    end
    t.eq(call("Short", "gold", "x"), "Gold n/a", "a value of the wrong kind")
    t.eq(call("Short", "xp", { cur = 1 }), "XP n/a", "a part missing")
end

tests["info bar: a strip on one line, a box one metric a line"] = function(t)
    local ids = { "gold", "fps" }
    local values = { gold = 7 }
    t.eq(call("Text", ids, values, "strip"), "7c  |  FPS n/a")
    t.eq(call("Text", ids, values, "box"), "7c\nFPS n/a")
    t.eq(call("Text", {}, values, "strip"), "")
end

tests["info bar: the tip has a line a metric and says what a click does"] = function(t)
    local lines = call("Tip", { "gold", "hearth" }, { gold = 7 })
    t.eq(lines, { "Gold: 7c", "Hearthstone: not available", IB().CLICK })
    t.ok(type(IB().CLICK) == "string" and not IB().CLICK:find("Flow"), "no add-on name in the words")
end

return tests
