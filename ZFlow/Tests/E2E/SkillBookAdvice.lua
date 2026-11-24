local _, ns = ...
-- E-48 skill books in the bags, end to end on the whole add-on loaded on a
-- fake client: one advisor prompt (UI/Advisor.lua) for each skill book in
-- the bags, "<item>: " and then the words of SkillBoosters.Advice. Advice
-- text only: nothing is used, sold, moved or bound, and the prompt has
-- nothing to press. Skills or bags not read: nothing is said. Offline: fake
-- client reads, not the game. Made-up items. Not tested in game.
--
-- The numbers: +5 Fishing up to a maximum of 75, so the best rank to use it
-- at is 75 - 5 = 70.
local tests = {}

local BOOK, ROCK, KNOWN_BOOK, NAMELESS = 9101, 9102, 9103, 9104
local INFO = {
    [BOOK] = { name = "Angler's Notes", quality = 1, sellPrice = 10 },
    [ROCK] = { name = "Plain Rock", quality = 1, sellPrice = 1 },
    [KNOWN_BOOK] = { name = "Anglerbuch", quality = 1, sellPrice = 10 },
}
local LINES = { "Angler's Notes", "Use: Increases your Fishing skill by 5, up to a maximum of 75." }
local BAGS = { { item = BOOK, count = 1 }, { item = ROCK, count = 1 } }

-- ranks: the skillRanks map, or false for skills not read. bags: the bag
-- stacks, or false for bags not read.
local function boot(ranks, bags)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    if bags ~= false then c.setBagItems(bags or BAGS) end
    c.setItemLines(BOOK, LINES)
    c.setItemLines(NAMELESS, LINES)
    c.setItemLines(ROCK, { "Plain Rock", "A rock." })
    if ranks ~= false then c.setSkillRanks(ranks) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The skill book prompts now in the advisor, in shown order.
local function cards(addon)
    local SB = addon.SkillBoosters
    local out = {}
    if type(SB) ~= "table" or type(SB.PROMPT) ~= "string" then return out end
    for _, p in ipairs(addon.advisor.List()) do
        if p.id:sub(1, #SB.PROMPT) == SB.PROMPT then out[#out + 1] = p end
    end
    return out
end

local function text(addon)
    local list = cards(addon)
    return list[1] and list[1].text or nil
end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(#c.secureMacros(), 0, "no macro, no button that uses it")
    t.eq(#c.bagItems(), 2, "the bags as they were")
end

tests["skill book advice e2e: at the best rank the card says use it now"] = function(t)
    local c, addon = boot({ Fishing = { rank = 70, max = 75 } })
    t.eq(text(addon), "Angler's Notes: Use it now: Fishing is 70, the best moment for +5")
    t.eq(#cards(addon), 1, "one card for the book, none for the rock")
    noneActs(t, c)
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: past the best rank the card still says use it now"] = function(t)
    local _, addon = boot({ Fishing = { rank = 73, max = 75 } })
    t.eq(text(addon), "Angler's Notes: Use it now: Fishing is 73; waiting wastes more of it")
end

tests["skill book advice e2e: below the best rank the card says keep it, and until when"] = function(t)
    local c, addon = boot({ Fishing = { rank = 20, max = 75 } })
    t.eq(text(addon), "Angler's Notes: Keep it until Fishing is 70 (now 20): the last points are the slow ones")
    noneActs(t, c)
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: a skill not learned says keep it and learn it first"] = function(t)
    local _, addon = boot({ Mining = { rank = 40, max = 75 } })
    t.eq(text(addon), "Angler's Notes: Keep it: learn Fishing first")
end

tests["skill book advice e2e: at the cap the card says it does nothing"] = function(t)
    local _, addon = boot({ Fishing = { rank = 75, max = 75 } })
    t.eq(text(addon), "Angler's Notes: It does nothing now: Fishing 75 is at its cap")
end

tests["skill book advice e2e: the card is the tooltip's own words after the item's name"] = function(t)
    local c, addon = boot({ Fishing = { rank = 20, max = 75 } })
    local head, tipped = ns.id.title .. ": ", nil
    for _, l in ipairs(c.showItemTooltip(BOOK)) do
        if type(l.text) == "string" and l.text:sub(1, #head) == head then tipped = l.text:sub(#head + 1) end
    end
    t.ok(tipped ~= nil, "the tooltip line is there")
    t.eq(text(addon), "Angler's Notes: " .. tostring(tipped))
end

tests["skill book advice e2e: skills not read say nothing, never \"learn first\""] = function(t)
    local _, addon = boot(false)
    t.ok(type(addon.SkillBoosters.PROMPT) == "string", "the prompt has a name")
    t.eq(#cards(addon), 0, "no guess about the skill")
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: bags not read say nothing"] = function(t)
    local _, addon = boot({ Fishing = { rank = 70, max = 75 } }, false)
    t.ok(type(addon.SkillBoosters.PROMPT) == "string", "the prompt has a name")
    t.eq(#cards(addon), 0)
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: no skill book in the bags, no card"] = function(t)
    local _, addon = boot({ Fishing = { rank = 70, max = 75 } }, { { item = ROCK, count = 1 } })
    t.ok(type(addon.SkillBoosters.PROMPT) == "string", "the prompt has a name")
    t.eq(#cards(addon), 0)
end

tests["skill book advice e2e: the card follows the skill and goes when the book leaves the bags"] = function(t)
    local c, addon = boot({ Fishing = { rank = 20, max = 75 } })
    c.setSkillRanks({ Fishing = { rank = 70, max = 75 } })
    c.advance(10, 40)
    t.eq(text(addon), "Angler's Notes: Use it now: Fishing is 70, the best moment for +5", "the skill rose")
    c.setSkillRanks(nil)
    c.advance(10, 40)
    t.eq(#cards(addon), 0, "skills no longer read: the card goes")
    c.setSkillRanks({ Fishing = { rank = 70, max = 75 } })
    c.advance(10, 40)
    t.eq(#cards(addon), 1, "read again: back")
    c.setBagItems({ { item = ROCK, count = 1 } })
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(#cards(addon), 0, "gone from the bags")
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: two stacks of one book make one card"] = function(t)
    local _, addon = boot({ Fishing = { rank = 70, max = 75 } },
        { { item = BOOK, count = 1 }, { item = BOOK, count = 1 } })
    t.eq(#cards(addon), 1)
end

tests["skill book advice e2e: a book known by ID gets its card with no English tooltip"] = function(t)
    local c, addon = boot({ Fishing = { rank = 70, max = 75 } }, { { item = KNOWN_BOOK, count = 1 } })
    t.eq(#cards(addon), 0, "not in the list, no text: unknown")
    addon.SkillBoosters.KNOWN[KNOWN_BOOK] = { skill = "Fishing", amount = 5, cap = 75,
        source = "test record", seen = "2026-11-24" }
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(text(addon), "Anglerbuch: Use it now: Fishing is 70, the best moment for +5")
    t.eq(addon.problems:count(), 0)
end

tests["skill book advice e2e: a book whose name is not read gets no card"] = function(t)
    local _, addon = boot({ Fishing = { rank = 70, max = 75 } }, { { item = NAMELESS, count = 1 } })
    t.ok(type(addon.SkillBoosters.PROMPT) == "string", "the prompt has a name")
    t.eq(#cards(addon), 0, "no name to say")
    t.eq(addon.problems:count(), 0)
end

-- The card is words only: the advisor's row is { id, text, priority } and
-- nothing else, so there is nothing on it to press.
tests["skill book advice e2e: the card carries no action and nothing is used"] = function(t)
    local c, addon = boot({ Fishing = { rank = 70, max = 75 } })
    local list = cards(addon)
    t.eq(#list, 1)
    for key in pairs(list[1] or {}) do
        t.ok(key == "id" or key == "text" or key == "priority", "only words on the card: " .. tostring(key))
    end
    t.eq(list[1] and list[1].action, nil, "no action")
    noneActs(t, c)
    t.eq(addon.problems:count(), 0)
end

return tests
