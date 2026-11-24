local _, ns = ...
-- The gear tooltip's score lines out of the box (parity row C-26: the
-- predecessor always showed them), on the whole add-on loaded on a fake
-- client with the real class packs, through the real tooltip entry point
-- (c.showItemTooltip). A fresh account gets the score per role and the gain
-- or loss on what is worn; an account that saved the setting off keeps it
-- off; a worn slot that was not read is "not known", never a number. Made-up
-- items. Not tested in game.
--
-- Warrior weights (ZFlow/Classes/Warrior.lua, marked first guess): dps
-- Strength 1.0, Stamina 0.35; tank Stamina 1.0, Strength 0.6. The worn helm
-- (2 Stamina, 2 Strength) scores 2.7 for dps and 3.2 for a tank; the
-- strength helm (10 Strength) 10 and 6: +7.3 and +2.8.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG = "item:4201", "item:4202"
local GUESS = "Scores use first-guess stat weights."

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

-- opts: account (the saved account table), prepare(c) before the add-on is
-- built. gear.tooltipScore is never set here: each test reads what the
-- account starts with.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, { settings = { spec = { role = "dps" } } })
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setWorn(1, WORN)
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

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

-- The first line that begins with `head`, or nil.
local function begins(list, head)
    for i = 1, #list do
        if list[i]:sub(1, #head) == head then return list[i] end
    end
    return nil
end

tests["gear score default: a fresh account sees the score per role and the gain on what is worn"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get("gear.tooltipScore"), true, "on by default")
    local lines = hover(c, STRONG)
    local all = table.concat(lines, " | ")
    t.eq(lines[1], "Upgrade for your head piece (+7.3, dps)", "the verdict stays the first line")
    local score = at(lines, "Score 10 (dps), 6 (tank)")
    local vs = at(lines, "vs your head piece: +7.3 (dps), +2.8 (tank)")
    local guess = at(lines, GUESS)
    t.ok(score ~= nil, "a score per role: " .. all)
    t.ok(vs ~= nil, "the difference to worn per role: " .. all)
    t.ok(guess ~= nil, "the weights are a first guess, and the tooltip says so: " .. all)
    t.ok(score ~= nil and vs ~= nil and guess ~= nil and score < vs and vs < guess, "score, vs, then the note")
    t.eq(at(lines, "vs your head piece: 2.7 (dps), 3.2 (tank)"), nil, "the difference, not the worn item's score")
end

tests["gear score default: a loss is a minus, per role"] = function(t)
    local c = boot({ prepare = function(c) c.setWorn(1, STRONG) end })
    local lines = hover(c, WORN)
    t.eq(lines[1], "Not an upgrade for your head piece (-7.3, dps)")
    t.ok(at(lines, "vs your head piece: -7.3 (dps), -2.8 (tank)") ~= nil, table.concat(lines, " | "))
end

tests["gear score default: an account that saved it off stays off"] = function(t)
    local c, addon = boot({ account = { settings = { gear = { tooltipScore = false } } } })
    t.eq(addon.settings:get("gear.tooltipScore"), false, "the saved choice stands")
    local lines = hover(c, STRONG)
    t.eq(lines[1], "Upgrade for your head piece (+7.3, dps)", "the verdict is its own setting")
    t.eq(begins(lines, "Score "), nil, "no score line")
    t.eq(begins(lines, "vs "), nil, "no vs line")
    t.eq(at(lines, GUESS), nil, "no note about scores that are not shown")
end

tests["gear score default: an account that saved it on stays on"] = function(t)
    local c, addon = boot({ account = { settings = { gear = { tooltipScore = true } } } })
    t.eq(addon.settings:get("gear.tooltipScore"), true)
    t.ok(at(hover(c, STRONG), "Score 10 (dps), 6 (tank)") ~= nil)
end

tests["gear score default: the worn slot not read says not known, never a number"] = function(t)
    local c = boot({ prepare = function(c) c.setWorn(1, nil) end })
    local lines = hover(c, STRONG)
    local all = table.concat(lines, " | ")
    t.eq(lines[1], "No verdict: " .. ns.GearScore.REASON.worn .. ": head", "no verdict without the worn item")
    t.ok(at(lines, "Score 10 (dps), 6 (tank)") ~= nil, "the item's own score needs no worn item: " .. all)
    t.eq(begins(lines, "vs "), "vs your head piece: not known", all)
    t.eq(at(lines, "vs your head piece: nothing worn"), nil, "not read is not empty")
    t.eq(at(lines, "vs your head piece: +10 (dps), +6 (tank)"), nil, "not read is not a worn score of 0")
    for i = 1, #lines do
        t.ok(lines[i]:sub(1, 3) ~= "vs " or not lines[i]:find("%d"),
             "no number against what was not read: " .. lines[i])
    end
end

tests["gear score default: the worn item's stats not read says not known too"] = function(t)
    local c = boot({ prepare = function(c) c.setItem(WORN, { kind = "INVTYPE_HEAD" }) end })
    local lines = hover(c, STRONG)
    t.eq(lines[1], "No verdict: " .. ns.GearScore.REASON.wornStat .. ": head")
    t.eq(begins(lines, "vs "), "vs your head piece: not known", table.concat(lines, " | "))
end

tests["gear score default: the worn item still says you are wearing it, with no vs line"] = function(t)
    local c = boot()
    local lines = hover(c, WORN)
    t.ok(at(lines, "Score 2.7 (dps), 3.2 (tank)") ~= nil, table.concat(lines, " | "))
    t.ok(at(lines, "You're wearing this.") ~= nil, "worn")
    t.eq(begins(lines, "vs "), nil, "nothing to hold it up to")
    t.ok(at(lines, GUESS) ~= nil, "the note stays with the score")
end

tests["gear score default: it only shows; nothing is equipped or sold"] = function(t)
    local c = boot()
    hover(c, STRONG)
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(#c.soldSlots, 0, "nothing sold")
end

return tests
