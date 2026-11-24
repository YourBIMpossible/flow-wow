local _, ns = ...

-- Skill boosters (Items/SkillBoosters.lua), end to end, on the whole add-on
-- loaded on a fake client. The real entry: the item tooltip. A "+N skill"
-- book is read from its English tooltip text (client.itemLines; no item is
-- registered by ID yet) and the player's skill from client.skillRanks; the
-- tooltip gets one line of advice on when to use it. Advice only: nothing
-- is used, sold or moved. Made-up items. Not tested in game.
--
-- The numbers: +2 Mining up to a maximum of 15, so the best rank to use it
-- at is 15 - 2 = 13.

local tests = {}

local BOOK, ROCK = 9001, 9002
local INFO = {
    [BOOK] = { name = "Miner's Notes", quality = 1, sellPrice = 10 },
    [ROCK] = { name = "Plain Rock", quality = 1, sellPrice = 1 },
}
local NOW = 1700000000
local COLOUR = { 1, 0.82, 0.25 }

-- ranks: the skillRanks map, or false for skills not read.
local function boot(ranks)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(NOW)
    c.setItemInfo(INFO)
    c.setBagItems({ { item = BOOK, count = 1 }, { item = ROCK, count = 1 } })
    c.setItemLines(BOOK, { "Miner's Notes", "Use: Increases your Mining skill by 2, up to a maximum of 15." })
    c.setItemLines(ROCK, { "Plain Rock", "A rock." })
    if ranks ~= false then c.setSkillRanks(ranks) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The booster's line on an item's tooltip (the title's, in its colour), or nil.
local function tip(c, item)
    local head = ns.id.title .. ": "
    for _, l in ipairs(c.showItemTooltip(item)) do
        if type(l.text) == "string" and l.text:sub(1, #head) == head
            and l.r == COLOUR[1] and l.g == COLOUR[2] and l.b == COLOUR[3] then return l end
    end
    return nil
end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(#c.bagItems(), 2, "the bags as they were")
end

tests["skill boosters e2e: at the best rank the tooltip says use it now"] = function(t)
    local c = boot({ Mining = { rank = 13, max = 75 } })
    local l = tip(c, BOOK)
    t.eq(l and l.text, ns.id.title .. ": Use it now: Mining is 13, the best moment for +2")
    t.eq(l and { l.r, l.g, l.b }, COLOUR)
    noneActs(t, c)
end

tests["skill boosters e2e: below the best rank the tooltip says keep it"] = function(t)
    local c = boot({ Mining = { rank = 5, max = 75 } })
    local l = tip(c, BOOK)
    t.eq(l and l.text, ns.id.title .. ": Keep it until Mining is 13 (now 5): the last points are the slow ones")
    noneActs(t, c)
end

tests["skill boosters e2e: at the cap the tooltip says it does nothing"] = function(t)
    local c = boot({ Mining = { rank = 15, max = 75 } })
    local l = tip(c, BOOK)
    t.eq(l and l.text, ns.id.title .. ": It does nothing now: Mining 15 is at its cap")
end

tests["skill boosters e2e: a skill not learned says learn it first"] = function(t)
    local c = boot({ Herbalism = { rank = 40, max = 75 } })
    local l = tip(c, BOOK)
    t.eq(l and l.text, ns.id.title .. ": Keep it: learn Mining first")
end

tests["skill boosters e2e: an item that is no booster gets no line"] = function(t)
    local c = boot({ Mining = { rank = 13, max = 75 } })
    t.eq(tip(c, ROCK), nil, "plain text: no advice")
    t.eq(tip(c, 9999), nil, "an item never read: no advice")
    noneActs(t, c)
end

-- With the skills not read at all (skillRanks gives nil, a first guess not
-- seen in game), "learn Mining first" would be wrong for a player who has
-- Mining. SB.Facts keeps nothing on unread skills; the tooltip says nothing.
tests["skill boosters e2e: skills not read give no advice, never \"learn first\""] = function(t)
    local c = boot(false)
    t.eq(tip(c, BOOK), nil, "no guess about the skill")
end

return tests
