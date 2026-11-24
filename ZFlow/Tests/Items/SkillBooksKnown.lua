local _, ns = ...
-- E-47 skill books known by item ID (Items/SkillBoosters.lua). A row in
-- SkillBoosters.KNOWN is found by its ID on any client language: its
-- tooltip text is never read. An item not in the list is still read from
-- an English tooltip. Offline: the fake client's reads, not the game's.
-- Made-up items. Not tested in game.
local tests = {}

local KNOWN_BOOK, OTHER_BOOK = 990101, 990102
local ENGLISH = { "Angler's Notes", "Use: Increases your Fishing skill by 5, up to a maximum of 75." }
local GERMAN = { "Benutzen: Erhoeht Eure Fertigkeit in Angeln um 5." }
local ENTRY = { skill = "Fishing", amount = 5, cap = 75, source = "test record", seen = "2026-11-24" }

-- What the login alone leaves behind is not this module's: the problems and
-- the secure macros are counted after the boot, and each test asks only for
-- what came after it (as Tests/E2E/SellThese.lua does). said() names the
-- new problems when there are any.
local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - (atBoot[addon] or 0) end
local function said(addon)
    local out = {}
    for _, p in ipairs(addon.problems:list()) do
        local parts = {}
        for key, v in pairs(p) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(v) end
        table.sort(parts)
        out[#out + 1] = table.concat(parts, " ")
    end
    return "problems: " .. table.concat(out, " | ")
end

-- lines: { [item ID] = tooltip lines }. Gives the client, the add-on and
-- how often each item's tooltip text was asked for.
local function boot(lines)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [KNOWN_BOOK] = { name = "Anglerbuch", quality = 1 },
                    [OTHER_BOOK] = { name = "Angler's Notes", quality = 1 } })
    for id, l in pairs(lines) do c.setItemLines(id, l) end
    c.setBagItems({})
    c.setSkillRanks({ Fishing = { rank = 70, max = 75 } })
    local asked = {}
    local read = c.itemLines
    c.itemLines = function(item)
        local id = ns.Items.Id(item) or item
        asked[id] = (asked[id] or 0) + 1
        return read(item)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if type(addon.SkillBoosters) == "table" then addon.SkillBoosters.KNOWN[KNOWN_BOOK] = ENTRY end
    atBoot[addon] = addon.problems:count()
    return c, addon, asked
end

local function tip(c, item)
    local head = ns.id.title .. ": "
    for _, l in ipairs(c.showItemTooltip(item)) do
        if type(l.text) == "string" and l.text:sub(1, #head) == head then return l.text end
    end
    return nil
end

local USE = ns.id.title .. ": Use it now: Fishing is 70, the best moment for +5"

tests["skill books known: every row of the list names a skill, an amount, where and when"] = function(t)
    local SB = ns.SkillBoosters
    -- The list is empty until a book is read in game (the runner fails a
    -- test that makes no check), so the rule for a row is checked on rows
    -- made here too: a whole row is taken, one with a part missing is not.
    t.eq(type(SB.KNOWN), "table", "the list is there")
    local rows = {
        [1] = ENTRY,
        [2] = { amount = 5, source = "test record", seen = "2026-11-24" },
        [3] = { skill = "Fishing", source = "test record", seen = "2026-11-24" },
        [4] = { skill = "Fishing", amount = 0, source = "test record", seen = "2026-11-24" },
        [5] = { skill = "Fishing", amount = 5, seen = "2026-11-24" },
        [6] = { skill = "Fishing", amount = 5, source = "test record" },
    }
    local function get(id) return rows[id] end
    t.ok(SB.Known(1, get) == ENTRY, "a whole row is a row")
    t.eq(SB.Known(2, get), nil, "no skill: not a row")
    t.eq(SB.Known(3, get), nil, "no amount: not a row")
    t.eq(SB.Known(4, get), nil, "an amount of 0: not a row")
    t.eq(SB.Known(5, get), nil, "no source: not a row")
    t.eq(SB.Known(6, get), nil, "no date seen: not a row")
    t.eq(SB.Known(7, get), nil, "not in the list: not a row")
    for id, e in pairs(SB.KNOWN) do
        t.ok(type(id) == "number", "an item ID: " .. tostring(id))
        t.ok(SB.Known(id) == e, "a whole row: " .. tostring(id))
        local named = false
        for _, s in ipairs(SB.SKILLS) do named = named or s == e.skill end
        t.ok(named, "a skill the add-on knows: " .. tostring(e.skill))
        t.ok(e.cap == nil or (type(e.cap) == "number" and e.cap >= e.amount), "its cap: " .. tostring(id))
    end
end

tests["skill books known: a known item is found by ID under a tooltip in another language"] = function(t)
    local c, addon = boot({ [KNOWN_BOOK] = GERMAN })
    t.eq(tip(c, KNOWN_BOOK), USE)
    t.eq(newProblems(addon), 0, said(addon))
end

tests["skill books known: a known item is found by ID with no tooltip lines at all"] = function(t)
    local c, addon = boot({})
    t.eq(tip(c, KNOWN_BOOK), USE)
    t.eq(newProblems(addon), 0, said(addon))
end

tests["skill books known: a known item's tooltip text is never read"] = function(t)
    local c, _, asked = boot({ [KNOWN_BOOK] = ENGLISH, [OTHER_BOOK] = ENGLISH })
    asked[KNOWN_BOOK], asked[OTHER_BOOK] = nil, nil
    t.eq(tip(c, KNOWN_BOOK), USE)
    t.eq(asked[KNOWN_BOOK], nil, "found by ID: no text asked for")
    t.eq(tip(c, OTHER_BOOK), USE)
    t.ok((asked[OTHER_BOOK] or 0) > 0, "not in the list: its text is read")
end

tests["skill books known: an item not in the list is still read from an English tooltip only"] = function(t)
    local c, addon = boot({ [OTHER_BOOK] = ENGLISH })
    t.eq(tip(c, OTHER_BOOK), USE, "the fallback")
    t.eq(newProblems(addon), 0, said(addon))
    c, addon = boot({ [OTHER_BOOK] = GERMAN })
    t.eq(tip(c, OTHER_BOOK), nil, "not in the list, not English: unknown")
    t.eq(newProblems(addon), 0, said(addon))
end

return tests
