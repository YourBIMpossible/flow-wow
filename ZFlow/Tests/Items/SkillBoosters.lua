local _, ns = ...
-- Lead section 337 item 2, P-INV G6 (FEATURE-PLAN.md:64): skill boosters
-- are kept from the sell list while the skill can rise. Ported from Flow
-- F-086 (Modules/Items/SkillBoosters.lua): found by item ID (an entry with
-- where and when it was read), else from an English tooltip; the advice says
-- when to use it. Show and advise only: nothing is used, sold or moved.
-- Offline: the fake client's reads, not the game's. Made-up items.
local tests = {}

local BOOK = 990001
local LINK = "item:990001:0:0:0:0:0:0:0"
local ENGLISH = { "Mining Primer", "Use: Increases your Mining skill by 2, up to a maximum of 15." }
local GERMAN = { "Benutzen: Erhoeht Eure Fertigkeit in Bergbau um 2." }

local function SB() return ns.SkillBoosters end

tests["boosters: an English tooltip is read; a registered entry is found on any client"] = function(t)
    if type(SB()) ~= "table" then t.ok(false, "no ns.SkillBoosters"); return end
    local b = SB().Find(BOOK, ENGLISH, function() return nil end)
    t.eq(b and b.skill, "Mining"); t.eq(b and b.amount, 2); t.eq(b and b.cap, 15)
    t.eq(SB().Find(BOOK, GERMAN, function() return nil end), nil, "not registered, not English: unknown")
    local entry = { skill = "Mining", amount = 2, cap = 15, source = "test record", seen = "2026-11-23" }
    local got = SB().Find(BOOK, GERMAN, function(id) if id == BOOK then return entry end end)
    t.eq(got and got.skill, "Mining", "found by ID")
    t.eq(SB().Find(BOOK, GERMAN, function() return { skill = "Mining", amount = 2 } end), nil,
        "an entry without where and when it was read is ignored")
end

tests["boosters: the advice says when to use it"] = function(t)
    if type(SB()) ~= "table" then t.ok(false, "no ns.SkillBoosters"); return end
    local b = { skill = "Mining", amount = 2, cap = 15 }
    t.ok(SB().Advice(b, nil, nil):find("learn Mining", 1, true) ~= nil, "not learned: learn it first")
    t.ok(SB().Advice(b, 5, 75):find("until Mining is 13", 1, true) ~= nil, "low: hold it until 13")
    t.ok(SB().Advice(b, 13, 75):find("now", 1, true) ~= nil, "at 13: now")
    t.ok(SB().Advice(b, 15, 75):find("does nothing", 1, true) ~= nil, "at the cap: it does nothing")
end

local function decide(rank, max)
    local item = { key = tostring(BOOK), name = "Mining Primer", count = 1, quality = 1, sellPrice = 25, classID = 0 }
    local ctx = { boosters = { [tostring(BOOK)] = { skill = "Mining", amount = 2, cap = 15, rank = rank, max = max } } }
    return ns.Disposition.Decide(item, ctx)
end

tests["boosters: kept from the sell list while the skill can rise"] = function(t)
    local d = decide(12, 75)
    t.eq(d.action, "keep"); t.eq(d.rule, "skillBooster")
    t.ok(tostring(d.reason):find("Mining", 1, true) ~= nil, "the reason names the skill: " .. tostring(d.reason))
    d = decide(nil, nil)
    t.eq(d.rule, "skillBooster", "not learned yet: it can still rise, kept")
    d = decide(15, 75)
    t.ok(d.rule ~= "skillBooster", "at its cap: no longer kept for this")
end

local function start(rank)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [BOOK] = { name = "Mining Primer", quality = 1, sellPrice = 25, classID = 0 } })
    c.setItemLines(BOOK, ENGLISH)
    c.setBagItems({ { item = LINK, count = 1 } })
    if type(c.setSkillRanks) == "function" then
        c.setSkillRanks(rank and { Mining = { rank = rank, max = 75 } } or {})
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function keptReason(c)
    local listing = ns.SellList.Listing(c, nil, nil, nil)
    for _, row in ipairs(listing.kept and listing.kept.rows or {}) do
        if tostring(row.key) == tostring(BOOK) then return row.rule, row.reason end
    end
    return nil
end

tests["boosters: the sell list shows the booster as a kept row with the reason"] = function(t)
    local c = start(12)
    local rule, reason = keptReason(c)
    t.eq(rule, "skillBooster", "kept by the booster rule")
    t.ok(tostring(reason):find("Mining", 1, true) ~= nil, "with the reason: " .. tostring(reason))
    c = start(15)
    rule = keptReason(c)
    t.ok(rule ~= "skillBooster", "capped: not kept for this")
end

tests["boosters: the item tooltip says when to use it; nothing is used"] = function(t)
    local c = start(5)
    local said = {}
    for _, l in ipairs(c.showItemTooltip(LINK)) do said[#said + 1] = l.text end
    local all = table.concat(said, " / ")
    t.ok(all:find("until Mining is 13", 1, true) ~= nil, "the tooltip line: " .. all)
    t.eq(#c.secureMacros(), 0, "no macro")
end

return tests
