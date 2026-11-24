local _, ns = ...
-- The gear tooltip's score lines and the gear why word (G11 remaining, lead
-- sections 230, 275 item 2), on the whole add-on loaded on a fake client
-- with the real class packs, through the real tooltip entry point
-- (c.showItemTooltip) and the slash command. Per lead section 236: item
-- data late, the worn read late, a read raising then recovering, the role
-- changed. Regression (G15): the roll hint still says "No upgrade" for a
-- weapon that is none with the new lines on its tooltip. Every read the
-- verdict needs is set (class, level, dual wield, the worn head, main and
-- off hand, each item's kind, stats, class, subclass, level and the game's
-- own marks). Made-up items. Not tested in game.
--
-- Warrior weights (ZFlow/Classes/Warrior.lua): dps Strength 1.0, Stamina
-- 0.35; tank Stamina 1.0, Strength 0.6. So the worn helm (2 Stamina,
-- 2 Strength) scores 2.7 for dps and 3.2 for a tank; the strength helm
-- (10 Strength) 10 and 6.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG, LATE = "item:4101", "item:4102", "item:4103"
local BIG, SMALL = "item:4111", "item:4112"
local RING_A, RING_B, RING_NEW = "item:4121", "item:4122", "item:4123"
local GREAT = "item:4131"

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function ring(stats)
    return { kind = "INVTYPE_FINGER", stats = stats, classID = 4, subclassID = 0, minLevel = 1, unmet = {} }
end

-- A two-handed sword (Warrior proficiency 2/8, skill "Two-Handed Swords").
local function greatsword(stats)
    return { kind = "INVTYPE_2HWEAPON", stats = stats, classID = 2, subclassID = 8, minLevel = 1, unmet = {},
             speed = 3.5 }
end

local function sword(stats)
    return { kind = "INVTYPE_WEAPON", stats = stats, classID = 2, subclassID = 7, minLevel = 1, unmet = {},
             speed = 2.6 }
end

-- opts: role (spec.role saved for the character), score (gear.tooltipScore,
-- default on here), prepare(c) before the add-on is built.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local char = {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(BIG, sword({ [STR] = 20 }))
    c.setItem(SMALL, sword({ [STR] = 5 }))
    c.setWorn(1, WORN)
    c.setWorn(16, BIG)
    c.setWorn(17, false)        -- the off hand read: empty (the G15 lesson)
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.score ~= false then addon.settings:set("gear.tooltipScore", true) end
    return c, addon
end

-- What the hovered item's tooltip got, as text, in order.
local function hover(c, link)
    local out = {}
    for _, a in ipairs(c.showItemTooltip(link)) do out[#out + 1] = a.text end
    return out
end

local function at(list, text)
    for i = 1, #list do
        if list[i] == text then return i end
    end
    return nil
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function line(text) return ns.id.title .. ": " .. text end

tests["gear tooltip score: a score per role, the chosen role first, then vs the worn slot"] = function(t)
    local c = boot({ role = "tank" })
    local lines = hover(c, STRONG)
    t.eq(lines[1], "Upgrade for your head piece (+2.8, tank)", "the chosen role's verdict is the first line")
    t.eq(at(lines, "Upgrade for your head piece (+7.3, dps)"), nil, "G31: no verdict for a role not chosen")
    local score = at(lines, "Score 6 (tank), 10 (dps)")
    local vs = at(lines, "vs your head piece: 3.2 (tank), 2.7 (dps)")
    t.ok(score ~= nil, "no score line: " .. table.concat(lines, " | "))
    t.ok(vs ~= nil, "no vs line: " .. table.concat(lines, " | "))
    local verdict = at(lines, "Upgrade for your head piece (+2.8, tank)")
    t.ok(verdict ~= nil and score ~= nil and vs ~= nil and verdict < score and score < vs,
         "verdicts, then the score, then vs")
    t.eq(at(lines, "You're wearing this."), nil, "not worn")
end

tests["gear tooltip score: the worn item says you are wearing it, with no vs line"] = function(t)
    local c = boot({ role = "dps" })
    local lines = hover(c, WORN)
    t.eq(lines[1], "Same as your head piece (dps)")
    t.ok(at(lines, "Score 2.7 (dps), 3.2 (tank)") ~= nil, "score: " .. table.concat(lines, " | "))
    t.ok(at(lines, "You're wearing this.") ~= nil, "worn: " .. table.concat(lines, " | "))
    t.eq(at(lines, "vs your head piece: 2.7 (dps), 3.2 (tank)"), nil, "no vs line for the worn item")
end

tests["gear tooltip score: off, the tooltip has the verdict and no score lines"] = function(t)
    local c, addon = boot({ role = "dps", score = false })
    t.eq(addon.settings:get("gear.tooltipScore"), false, "off by default")
    local lines = hover(c, STRONG)
    t.eq(lines[1], "Upgrade for your head piece (+7.3, dps)")
    t.eq(at(lines, "Score 10 (dps), 6 (tank)"), nil)
    t.eq(at(lines, "vs your head piece: 2.7 (dps), 3.2 (tank)"), nil)
end

tests["gear tooltip score: item data late - the lines appear once it is read"] = function(t)
    local c = boot({ role = "dps" })
    local lines = hover(c, LATE)
    t.eq(at(lines, "Score 10 (dps), 6 (tank)"), nil, "nothing while the item is not loaded")
    c.setItem(LATE, helm({ [STR] = 10 }))
    lines = hover(c, LATE)
    t.ok(at(lines, "Score 10 (dps), 6 (tank)") ~= nil, "score once loaded: " .. table.concat(lines, " | "))
    t.ok(at(lines, "vs your head piece: 2.7 (dps), 3.2 (tank)") ~= nil, "vs once loaded")
end

tests["gear tooltip score: the worn read late - wearing is said once it is read"] = function(t)
    local c = boot({ role = "dps" })
    c.setWornUnread(true)
    local lines = hover(c, WORN)
    t.ok(at(lines, "Score 2.7 (dps), 3.2 (tank)") ~= nil, "the score does not need the worn links")
    t.eq(at(lines, "You're wearing this."), nil, "not said while the worn links are not read")
    c.setWornUnread(false)
    lines = hover(c, WORN)
    t.ok(at(lines, "You're wearing this.") ~= nil, "said once read: " .. table.concat(lines, " | "))
end

tests["gear tooltip score: the worn read raising, then recovering"] = function(t)
    local c, addon = boot({ role = "dps" })
    local real = c.wornLinks
    c.wornLinks = function() error("worn read failed") end
    local lines = hover(c, WORN)
    t.eq(lines[1], "Same as your head piece (dps)", "the verdict is kept")
    t.ok(at(lines, "Score 2.7 (dps), 3.2 (tank)") ~= nil, "the score is kept")
    t.eq(at(lines, "You're wearing this."), nil, "not said while the read raises")
    t.eq(addon.gearTooltip.errors(), 0, "a worn read that raises is not known, not a tooltip error")
    c.wornLinks = real
    lines = hover(c, WORN)
    t.ok(at(lines, "You're wearing this.") ~= nil, "said once the read works: " .. table.concat(lines, " | "))
end

tests["gear tooltip score: the role changes - the score line follows it"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.ok(at(hover(c, STRONG), "Score 10 (dps), 6 (tank)") ~= nil, "dps first")
    t.eq(addon.settings:set("spec.role", "tank"), true)
    local lines = hover(c, STRONG)
    t.eq(lines[1], "Upgrade for your head piece (+2.8, tank)", "G31: the verdict follows the role too")
    t.ok(at(lines, "Score 6 (tank), 10 (dps)") ~= nil, "tank first: " .. table.concat(lines, " | "))
    t.ok(at(lines, "vs your head piece: 3.2 (tank), 2.7 (dps)") ~= nil, "vs, tank first")
end

-- Regression (G15): any "none" line made the roll hint "Unknown". The new
-- lines are "info": the hint for a weapon that is no upgrade stays "No upgrade".
tests["gear tooltip score: the roll hint still says No upgrade with the new lines on the tooltip"] = function(t)
    local c = boot({ role = "dps" })
    local lines = hover(c, SMALL)
    t.eq(lines[1], "Not an upgrade for your main hand (-15, dps)")
    t.ok(at(lines, "Score 5 (dps), 3 (tank)") ~= nil, "score: " .. table.concat(lines, " | "))
    t.ok(at(lines, "vs your main hand: 20 (dps), 12 (tank)") ~= nil, "vs: " .. table.concat(lines, " | "))
    local shown = c.offerRoll(7, SMALL)
    t.eq(#shown, 1, "one hint")
    t.eq(shown[1] and shown[1].text, "No upgrade")
end

-- MerchantMarks reads lines[1] and the "good" lines: the new lines change
-- neither, so an item that is no upgrade is not marked.
tests["gear tooltip score: merchant marks unchanged by the new lines"] = function(t)
    local c, addon = boot({ role = "dps" })
    local M = addon.GearMerchantMarks
    c.setMerchant({ { index = 1, item = SMALL }, { index = 2, item = STRONG } })
    c.setMerchantOpen(true)
    local marks, info = M.Marks(c, addon.Packs)
    t.eq(#(marks or {}), 1, "only the strength helm")
    t.eq(marks and marks[1] and marks[1].link, STRONG)
    t.eq(info and info.noVerdict, 0, "no line made the sword a no-verdict")
end

tests["gear why: each piece of gear in the bags, its verdict and score for the chosen role"] = function(t)
    local c, addon = boot({ role = "tank" })
    c.setBagItems({ { item = STRONG, count = 1 }, { item = 2589, count = 5 }, { item = "item:9999", count = 1 },
                    { item = SMALL, count = 1 }, { item = STRONG, count = 1 } })
    local out = said(c, "gear why")
    t.eq(out[1], line("Gear in your bags, for tank:"))
    t.eq(out[2], line(STRONG .. ": Upgrade for your head piece (+2.8, tank); score 6"))
    t.eq(out[3], line(SMALL .. ": Not an upgrade for your main hand (-9, tank); score 3"))
    t.eq(#out, 3, "nothing for what is not gear, each item once: " .. table.concat(out, " | "))
    t.eq(type(addon.diag.help.gear), "string", "the word has a help line")
    t.eq(said(c, "help gear"), { line(ns.id.slash .. " gear - " .. tostring(addon.diag.help.gear)) })
end

tests["gear why: more than the cap - the rest are counted"] = function(t)
    local c, addon = boot({ role = "dps" })
    local cap = addon.GearTooltipModule.WHY_CAP
    t.eq(type(cap), "number", "there is a cap")
    if type(cap) ~= "number" then return end
    local stacks = {}
    for i = 1, cap + 3 do
        local link = "item:" .. (5000 + i)
        c.setItem(link, helm({ [STR] = i }))
        stacks[i] = { item = link, count = 1 }
    end
    c.setBagItems(stacks)
    local out = said(c, "gear why")
    t.eq(#out, cap + 2, "the title, the cap, and one more line")
    t.eq(out[#out], line("and 3 more"))
end

tests["gear why: no gear, bags not read, another word"] = function(t)
    local c = boot({ role = "dps" })
    c.setBagItems({ { item = 2589, count = 5 } })
    t.eq(said(c, "gear why"), { line("No gear in your bags.") })
    c.setBagItems(nil)
    t.eq(said(c, "gear why"), { line("Your bags could not be read.") })
    local usage = said(c, "gear")
    t.eq(#usage, 1)
    t.ok((usage[1] or ""):find(ns.id.slash .. " gear why", 1, true) ~= nil, "says how: " .. tostring(usage[1]))
end

-- GT2-1: a slot known to be empty is "nothing worn", not a score of 0.
tests["gear tooltip score: an empty slot says nothing worn"] = function(t)
    local c = boot({ role = "dps", prepare = function(c) c.setWorn(1, false) end })
    local lines = hover(c, STRONG)
    t.eq(lines[1], "Upgrade for your head piece (+10, dps)")
    t.ok(at(lines, "vs your head piece: nothing worn") ~= nil, "empty: " .. table.concat(lines, " | "))
    t.eq(at(lines, "vs your head piece: 0 (dps), 0 (tank)"), nil, "no score of 0 for an empty slot")
end

-- GT2-2: a ring is held up to both ring slots; the one it gains most on is
-- named (dps: 6 vs 4 and 2; tank: 3.6 vs 2.4 and 1.2).
tests["gear tooltip score: a ring, vs the ring it beats most"] = function(t)
    local c = boot({ role = "dps", prepare = function(c)
        c.setItem(RING_A, ring({ [STR] = 4 }))
        c.setItem(RING_B, ring({ [STR] = 2 }))
        c.setItem(RING_NEW, ring({ [STR] = 6 }))
        c.setWorn(11, RING_A)
        c.setWorn(12, RING_B)
    end })
    local lines = hover(c, RING_NEW)
    t.eq(lines[1], "Upgrade for your second ring (+4, dps)")
    t.ok(at(lines, "Score 6 (dps), 3.6 (tank)") ~= nil, "score: " .. table.concat(lines, " | "))
    t.ok(at(lines, "vs your second ring: 2 (dps), 1.2 (tank)") ~= nil, "vs: " .. table.concat(lines, " | "))
end

-- GT2-2: a two-hander is held up to the main hand and the off hand together
-- (the main hand's 20 dps / 12 tank, the off hand empty: 0).
tests["gear tooltip score: a two-hander, vs your main hand and off hand"] = function(t)
    local c = boot({ role = "dps", prepare = function(c)
        c.setWeaponSkills({ "Swords", "Two-Handed Swords", "Defense" })
        c.setItem(GREAT, greatsword({ [STR] = 30 }))
    end })
    local lines = hover(c, GREAT)
    t.eq(lines[1], "Upgrade for your main hand and off hand (+10, dps)")
    t.ok(at(lines, "Score 30 (dps), 18 (tank)") ~= nil, "score: " .. table.concat(lines, " | "))
    t.ok(at(lines, "vs your main hand and off hand: 20 (dps), 12 (tank)") ~= nil,
         "vs: " .. table.concat(lines, " | "))
end

-- GT2-3: one item's read raising is skipped and counted; the rest are listed.
tests["gear why: an item read that raises is skipped and counted"] = function(t)
    local c = boot({ role = "dps" })
    local real = c.gear
    c.gear = function(link)
        if link == SMALL then error("gear read failed (test)") end
        return real(link)
    end
    c.setBagItems({ { item = STRONG, count = 1 }, { item = SMALL, count = 1 } })
    local out = said(c, "gear why")
    t.eq(out[1], line("Gear in your bags, for dps:"))
    t.eq(out[2], line(STRONG .. ": Upgrade for your head piece (+7.3, dps); score 10"))
    t.eq(out[3], line("1 item could not be read."))
    t.eq(#out, 3, table.concat(out, " | "))
    c.setBagItems({ { item = SMALL, count = 1 } })
    t.eq(said(c, "gear why"), { line("1 item could not be read.") }, "only a failed read: no 'no gear'")
end

return tests
