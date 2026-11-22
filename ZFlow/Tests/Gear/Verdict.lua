local _, ns = ...

-- Tests for ZFlow/Gear/Verdict.lua: from what client.gear(link) answers to
-- the tooltip lines, in one step. The items go in through the fake client
-- (setItem, setWorn, setDualWield) and come out through its gear().
--
-- client.gear does not give an item's class, subclass or needed level yet
-- (a patch asked of Core/Client.lua). `typed` adds them to its answer here,
-- as that patch will; the tests that leave them out show today's answer.

local V = ns.GearVerdict
local tests = {}

local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"
local HELM, PLATE, SWORD, DAGGER, NEW, POTION = "item:1", "item:2", "item:3", "item:4", "item:5", "item:6"

-- A class pack of the shape ZFlow/Classes has: weights per role under
-- `values`, and what the class can equip. Leather (4/2), swords (2/7).
local function pack()
    return {
        weights = {
            dps = { evidence = "first guess", values = { [STR] = 2, [STA] = 1 } },
            tank = { evidence = "first guess", values = { [STA] = 3 } },
        },
        proficiency = { evidence = "first guess", [4] = { [2] = true }, [2] = { [7] = true } },
    }
end

local function client()
    local c = ns.make.fakeClient()
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { [STA] = 40 } })
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } })
    c.setItem(DAGGER, { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } })
    c.setItem(NEW, { kind = "INVTYPE_WEAPON", stats = { [STR] = 6 } })
    c.setItem(POTION, { stats = {} })
    return c
end

local function typed(gear, classId, subclassId, minLevel)
    gear.classId, gear.subclassId, gear.minLevel = classId, subclassId, minLevel
    return gear
end

local function who(role, level)
    return { pack = pack(), role = role, level = level }
end

tests["verdict: an upgrade for an empty slot, through the fake client"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local lines, detail = V.Lines(typed(c.gear(HELM), 4, 2, 1), who("dps", 10))
    t.eq(lines, { { text = "Upgrade for your head piece (+4, dps)", tone = "good" } })
    t.eq(detail.use.can, true)
    t.eq(detail.result.verdict, "upgrade")
    t.eq(detail.unmapped, {})
    t.eq(detail.weights, "first guess", "what the weights rest on is handed on")
end

tests["verdict: the role picks the weights"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local lines = V.Lines(typed(c.gear(HELM), 4, 2, 1), who("tank", 10))
    t.eq(lines[1].text, "Upgrade for your head piece (+12, tank)")
end

tests["verdict F-006: a dual wielder's one-hander is held up to the off hand too"] = function(t)
    local c = client()
    c.setWorn(16, SWORD)
    c.setWorn(17, DAGGER)
    c.setDualWield(true)
    local lines = V.Lines(typed(c.gear(NEW), 2, 7, 1), who("dps", 10))
    t.eq(lines, { { text = "Upgrade for your off hand (+6, dps)", tone = "good" } })
    c.setDualWield(nil)
    lines = V.Lines(typed(c.gear(NEW), 2, 7, 1), who("dps", 10))
    t.eq(lines[1], { text = "Not an upgrade for your main hand (-8, dps)", tone = "bad" })
    t.eq(#lines, 2, "and the note that dual wield is not known")
end

tests["verdict G12: gear the class cannot wear says can't use, never upgrade"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local lines, detail = V.Lines(typed(c.gear(PLATE), 4, 4, 1), who("dps", 60))
    t.eq(lines, { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } })
    t.eq(detail.result.verdict, "upgrade", "the scorer would have called it one")
    t.ok(not lines[1].text:lower():find("upgrade", 1, true))
end

tests["verdict G12: below the level it needs is a can't use that names the level"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local lines = V.Lines(typed(c.gear(HELM), 4, 2, 20), who("dps", 19))
    t.eq(lines, { { text = "Can't use: needs level 20", tone = "bad" } })
end

tests["verdict: today's client answer has no item type, so the line is no verdict, not an upgrade"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local lines, detail = V.Lines(c.gear(HELM), who("dps", 10))
    t.eq(lines, { { text = "No verdict: " .. ns.GearCanUse.REASON.type, tone = "none" } })
    t.eq(detail.use.can, nil)
end

tests["verdict: a slot nobody read is no verdict, where an empty one is an upgrade"] = function(t)
    local c = client()
    local lines = V.Lines(typed(c.gear(HELM), 4, 2, 1), who("dps", 10))
    t.eq(lines[1].tone, "none")
    t.eq(lines[1].text, "No verdict: " .. ns.GearScore.REASON.worn .. ": head")
end

tests["verdict: a role the pack has no weights for is no verdict, with the reason"] = function(t)
    local c = client()
    c.setWorn(1, false)
    for _, role in ipairs({ "heal", false, 3 }) do
        local lines, detail = V.Lines(typed(c.gear(HELM), 4, 2, 1), who(role or nil, 10))
        t.eq(lines, { { text = "No verdict: " .. ns.GearScore.REASON.weights, tone = "none" } })
        t.eq(detail.weights, nil)
    end
end

tests["verdict: no pack is no verdict"] = function(t)
    local c = client()
    c.setWorn(1, false)
    for _, w in ipairs({ false, {}, { pack = "DRUID", role = "dps", level = 10 } }) do
        local lines = V.Lines(typed(c.gear(HELM), 4, 2, 1), w or nil)
        t.eq(#lines, 1)
        t.eq(lines[1].tone, "none")
    end
end

tests["verdict: what is not gear gets no line at all"] = function(t)
    local c = client()
    local lines, detail = V.Lines(c.gear(POTION), who("dps", 10))
    t.eq(lines, nil, "no equip location: nothing is said")
    t.eq(detail.why, V.REASON.notGear)
    lines = V.Lines(c.gear("item:999"), who("dps", 10))
    t.eq(lines, nil, "an item nothing is known about")
    for _, gear in ipairs({ false, "x", {} }) do
        t.eq(V.Lines(gear or nil, who("dps", 10)), nil)
    end
    c.setItem("item:7", { kind = "INVTYPE_BAG", stats = {} })
    lines, detail = V.Lines(typed(c.gear("item:7"), 1, 0, 1), who("dps", 10))
    t.eq(lines, nil, "a kind that is not compared")
    t.eq(detail.why, V.REASON.notGear)
end

tests["verdict: a stat not read is no verdict, and a stat key no weights name is handed on"] = function(t)
    local c = client()
    c.setWorn(1, false)
    c.setItem("item:8", { kind = "INVTYPE_HEAD", stats = { [STA] = "?", ITEM_MOD_NEW_THING_SHORT = 5 } })
    local lines, detail = V.Lines(typed(c.gear("item:8"), 4, 2, 1), who("dps", 10))
    t.eq(lines, { { text = "No verdict: " .. ns.GearScore.REASON.stat .. ": " .. STA, tone = "none" } })
    t.eq(detail.unmapped, { "ITEM_MOD_NEW_THING_SHORT" })
end

tests["verdict: the real class packs have the shape this reads"] = function(t)
    local seen = 0
    for name, real in pairs(ns.Packs or {}) do
        seen = seen + 1
        t.eq(type(real.proficiency), "table", name .. ": proficiency")
        t.eq(type(real.weights), "table", name .. ": weights")
        for role, w in pairs(real.weights) do
            t.eq(type(w.values), "table", name .. " " .. tostring(role) .. ": values")
            local n, why = ns.GearScore.Score({}, w.values)
            t.eq(n, 0, name .. " " .. tostring(role) .. ": its weights score: " .. tostring(why))
        end
    end
    t.ok(seen >= 1, "at least one pack is loaded")
end

tests["verdict: nothing handed in is changed"] = function(t)
    local c = client()
    c.setWorn(1, false)
    local gear, w = typed(c.gear(HELM), 4, 2, 1), who("dps", 10)
    V.Lines(gear, w)
    t.eq(gear, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 }, worn = { [1] = false },
        classId = 4, subclassId = 2, minLevel = 1 })
    t.eq(w.role, "dps")
    t.eq(w.pack.weights.dps.values, { [STR] = 2, [STA] = 1 })
end

return tests
