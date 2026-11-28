local _, ns = ...

-- The info bar as tiles (all-windows row 4; the modernization
-- assessment's section 9). The bar the client draws today is one
-- line of text; the tile drawing is the lead's client work. What
-- the module owes it: for each chosen metric, its icon, its full
-- label in plain words, its value in plain words, and whether it
-- could be read at all — a metric that cannot be read says "Not
-- available" in its tile instead of vanishing. The strip's own
-- words take the same rule: no abbreviations that need the
-- tooltip ("Dur", "Rep", "Hearth", "XP" become their full
-- names), and an unread metric says so in words, not "n/a".
-- Red before the code: there are no tiles, and the strip still
-- abbreviates.

local IB = ns.InfoBar
local tests = {}
local function call(name, ...) return IB[name](...) end

tests["info bar tiles: each metric gives its icon, label and value"] = function(t)
    local bags = { { family = 0, free = 12, total = 20 } }
    local worn = { { cur = 50, max = 100 } }
    local tiles = IB.Tiles({ "gold", "bags", "durability" },
        { gold = 12345, bags = bags, durability = worn })
    t.eq(#tiles, 3)
    t.eq(tiles[1].id, "gold")
    t.eq(tiles[1].label, "Gold")
    t.eq(tiles[1].text, "1.23g", "the value in plain words")
    t.eq(tiles[1].available, true)
    t.ok(type(tiles[1].icon) == "string" and tiles[1].icon ~= "", "an icon of its own")
    t.eq(tiles[2].label, "Free bag slots")
    t.eq(tiles[2].text, "12")
    t.eq(tiles[3].label, "Durability")
    t.eq(tiles[3].text, "50%")
    for _, tile in ipairs(tiles) do
        t.eq(IB.Icon(tile.id), tile.icon, "the icon table backs the tile: " .. tile.id)
    end
    t.eq(IB.Icon("nope"), nil, "an unknown metric has no icon")
end

tests["info bar tiles: a metric that cannot be read says so in its tile"] = function(t)
    local tiles = IB.Tiles({ "gold", "xp", "rep" }, { rep = false })
    t.eq(tiles[1].text, IB.NOT_AVAILABLE)
    t.eq(tiles[1].available, false, "not read: the tile says so, it does not vanish")
    t.eq(tiles[2].available, false)
    t.eq(tiles[3].available, true, "no faction watched was read, and says so")
    t.eq(tiles[3].text, "None watched")
    t.eq(IB.NOT_AVAILABLE, "Not available")
end

tests["info bar tiles: every metric has an icon, and the hearth and clock read plainly"] = function(t)
    for _, m in ipairs(IB.METRICS) do
        t.ok(type(IB.Icon(m.id)) == "string", "an icon for " .. m.id)
    end
    local tiles = IB.Tiles({ "hearth", "clock", "fps", "latency" },
        { hearth = 0, clock = { hour = 9, minute = 7 }, fps = 59.6, latency = { home = 30, world = 44 } })
    t.eq(tiles[1].text, "Ready")
    t.eq(tiles[2].text, "09:07")
    t.eq(tiles[3].text, "59")
    t.eq(tiles[4].text, "44 ms")
end

tests["info bar: the strip's own words are plain, with nothing abbreviated away"] = function(t)
    local worn = { { cur = 50, max = 100 } }
    t.eq(call("Short", "durability", worn), "Durability 50%")
    t.eq(call("Short", "xp", { cur = 45, max = 100 }), "Experience 45%")
    t.eq(call("Short", "rep", false), "Reputation: none")
    t.eq(call("Short", "hearth", 0), "Hearthstone ready")
    t.eq(call("Short", "hearth", 61), "Hearthstone 2 min")
    t.eq(call("Short", "durability", {}), "Durability: not available", "unread says so in words")
    t.eq(call("Short", "gold", "x"), "Gold: not available")
end

return tests
