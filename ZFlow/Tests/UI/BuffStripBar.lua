local _, ns = ...

-- The Your Buffs strip as a buff bar (all-windows row 2; the
-- modernization assessment's section 2). One row per buff with
-- the spell's own icon, the time left at the right, and a thin
-- bar under a timed buff that drains as it runs out — the bar's
-- full length is the longest time the buff has been seen with,
-- so a freshly cast buff starts full. A buff that ran out says
-- "Cast it again." where its timer was, dimmed; an aura stands
-- faded with "on". No repeated "Your buffs" line under the
-- title; the line that says what the strip is stands last,
-- faded. Red before the code: rows are bare lines, there are
-- no icons, no bars, and the header part still repeats the
-- title.

local B = ns.BuffStrip
local tests = {}

local ICONS = { ["Test Intellect"] = "tex.intellect", ["Test Armor"] = "tex.armor",
    ["Test Ward"] = "tex.ward", ["Test Shield"] = "tex.shield" }

tests["buff bar: a timed buff is a row with its icon, and a bar that drains"] = function(t)
    local kids = B.Children({
        { name = "Test Intellect", left = 750, full = 1500, soon = false },
        { name = "Test Armor", left = 30, full = 1800, soon = true },
    }, nil, ICONS)
    t.eq(kids[1].kind, "line")
    t.eq(kids[1].text, "Test Intellect")
    t.eq(kids[1].icon, "tex.intellect", "the spell's own icon")
    t.eq(kids[1].right, "13 min")
    t.eq(kids[2].kind, "bar", "a bar under the row")
    t.eq(kids[2].value, 750)
    t.eq(kids[2].max, 1500, "the full length is the longest seen")
    t.eq(kids[3].right, "30 s")
    t.eq(kids[3].tone, "warn")
    t.eq(kids[3].sub, B.SOON_TEXT)
    t.eq(kids[4].kind, "bar")
    t.eq(kids[4].tone, "warn", "the bar takes the row's tone")
    local tree = ns.Kit.Window({ id = B.ID, title = "t", children = kids })
    t.ok(tree ~= nil, "the kit takes it")
    if tree then
        local share
        ns.Kit.Each(tree, function(p) if p.kind == "bar" and share == nil then share = p.share end end)
        t.eq(share, 0.5, "the kit works out how much is left")
    end
end

tests["buff bar: an aura stands faded, a run-out buff says cast it again, dimmed"] = function(t)
    local kids = B.Children({
        { name = "Test Ward", soon = false },
        { name = "Test Shield", gone = true },
    }, nil, ICONS)
    t.eq(kids[1].kind, "fadedLine", "an aura is a state, not a timer: faded")
    t.eq(kids[1].right, B.ON)
    t.eq(kids[1].icon, "tex.ward")
    t.eq(kids[2].kind, "line")
    t.eq(kids[2].right, B.GONE_TEXT, "cast it again, where the timer was")
    t.eq(kids[2].sub, nil)
    t.eq(kids[2].tone, "bad")
    t.eq(kids[2].enabled, false, "dimmed")
    t.eq(kids[2].icon, "tex.shield")
    t.eq(#kids, 2, "no bars for either")
end

tests["buff bar: no header repeats the title, and the about line stands last, faded"] = function(t)
    local kids = B.Children({ { name = "Test Ward", soon = false } }, B.ABOUT, ICONS)
    for _, p in ipairs(kids) do t.ok(p.kind ~= "header", "no header part: the title already says it") end
    local last = kids[#kids]
    t.eq(last.kind, "fadedLine")
    t.eq(last.key, "about")
    t.eq(last.text, B.ABOUT)
end

tests["buff bar: rows carry the longest time seen, as their full length"] = function(t)
    local rows = B.Rows({ "Test Armor" }, { ["Test Armor"] = 300 }, nil, { ["Test Armor"] = 1800 })
    t.eq(rows[1].full, 1800)
    local plain = B.Rows({ "Test Armor" }, { ["Test Armor"] = 300 })
    t.eq(plain[1].full, nil, "not seen longer: no full length claimed")
end

tests["buff bar: the strip's height counts a bar under each timed buff"] = function(t)
    local timed = B.Height({ { name = "A", left = 10, soon = false } })
    local aura = B.Height({ { name = "A", soon = false } })
    t.eq(timed - aura, B.BAR, "a timed buff stands a bar taller")
    t.ok(type(B.BAR) == "number" and B.BAR > 0, "BuffStrip.BAR")
end

tests["buff bar: a numeric texture is kept as the buff's icon (Zen's changes)"] = function(t)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setFrameRect(B.FRAME, { l = 20, r = 250, b = 640, t = 740 })
    c.setClass("MAGE")
    local addon = ns.offline.addon(c)
    local lastTree
    local realKit = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        lastTree = tree
        return realKit(id, tree, extra)
    end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    -- The client answers spellTexture with a file number first
    -- (Core/Client.lua:1760-1770); the kit takes numbers.
    c.setSpellId("Frost Armor", 7302)
    c.setSpellTexture(7302, 123456)
    c.setPlayerBuffs({ ["Frost Armor"] = 1800 })
    c.advance(B.EVERY + 0.1, 2)
    t.ok(lastTree ~= nil, "the strip drew")
    if not lastTree then return end
    local icon
    ns.Kit.Each(lastTree, function(p)
        if p.kind == "line" and p.text == "Frost Armor" then icon = p.icon end
    end)
    t.eq(icon, 123456, "the number is the icon, not dropped")
    t.eq(B.GONE, nil, "the dead 'ran out' string is gone (Zen's changes)")
end

return tests
