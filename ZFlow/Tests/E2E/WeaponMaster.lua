local _, ns = ...
-- The weapon master step and G12's untrained wording end to end (G16), on
-- the whole add-on loaded on a fake client. A warrior hovers a sword it has
-- not trained: the gear line reads "not trained (a weapon master teaches
-- it)" and a words-only weapon master step is offered. Per lead section
-- 236: the skill read arriving late, the skill learned, a reload in the
-- middle, and the skill read raising. Look only: nothing trains or buys.
-- Made-up items and skill lines. Not tested in game.
local tests = {}

local STR = "ITEM_MOD_STRENGTH_SHORT"
local SWORD, WAND = "item:3001", "item:3002"
local UNTRAINED = "Can't use yet: not trained (a weapon master teaches it)"
local TODAY = "Can't use: the game marks in red: Swords"
local WORDS = "A weapon master in a capital city teaches Swords."

local function items(c, swordUnmet)
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 7,
                       minLevel = 1, unmet = swordUnmet })
    c.setItem(WAND, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 19,
                      minLevel = 1, unmet = { "Wands" } })
end

-- opts: account, char (saved tables), before(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setPosition(1454, 0.5, 0.5)
    items(c, { "Swords" })
    c.setWorn(16, false); c.setWorn(17, false)
    c.setDualWield(false)
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function reload(c, before)
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), before = before })
end

local function has(added, text)
    for _, a in ipairs(added or {}) do if a.text == text then return true end end
    return false
end

local function step(addon)
    local api = addon.use("weaponMasterStep")
    if type(api) ~= "table" or type(api.Step) ~= "function" then return nil end
    return api.Step()
end

local function lines(addon)
    local api = addon.use("weaponMasterStep")
    if type(api) ~= "table" or type(api.Lines) ~= "function" then return nil end
    return api.Lines()
end

tests["weapon master: untrained but learnable reads 'not trained' and offers the step"] = function(t)
    local c, addon = boot({ before = function(x) x.setWeaponSkills({ "Axes", "Maces", "Defense" }) end })
    local added = c.showItemTooltip(SWORD)
    t.ok(has(added, UNTRAINED), "the untrained line")
    t.ok(not has(added, TODAY), "not today's line")
    local s = step(addon)
    t.eq(s and s.skill, "Swords")
    t.eq(s and s.place, nil, "no weapon master saved: no needle")
    t.eq(lines(addon), { WORDS })
end

tests["weapon master: a kind the class can never use keeps today's line and gives no step"] = function(t)
    local c, addon = boot({ before = function(x) x.setWeaponSkills({ "Axes", "Defense" }) end })
    local added = c.showItemTooltip(WAND)
    t.ok(has(added, "Can't use: the game marks in red: Wands"), "today's line")
    t.eq(step(addon), nil)
end

tests["weapon master: the skill read late - today's line, then 'not trained'"] = function(t)
    local c, addon = boot()
    t.ok(has(c.showItemTooltip(SWORD), TODAY), "skills not read: today's line, no guess")
    t.eq(step(addon), nil, "and no step")
    c.setWeaponSkills({ "Axes", "Defense" })
    c.fire("SKILL_LINES_CHANGED")
    t.ok(has(c.showItemTooltip(SWORD), UNTRAINED), "read: the untrained line")
    t.ok(step(addon) ~= nil, "and the step")
end

tests["weapon master: learning the skill takes the line and the step away"] = function(t)
    local c, addon = boot({ before = function(x) x.setWeaponSkills({ "Axes", "Defense" }) end })
    c.showItemTooltip(SWORD)
    t.ok(step(addon) ~= nil)
    c.setWeaponSkills({ "Axes", "Swords", "Defense" })
    items(c, {})
    c.fire("SKILL_LINES_CHANGED")
    t.eq(step(addon), nil, "the step goes")
    t.eq(lines(addon), {})
    local added = c.showItemTooltip(SWORD)
    t.ok(not has(added, UNTRAINED), "the untrained line goes")
    t.ok(has(added, "Upgrade for your main hand (+5, dps)"), "the verdict as before")
end

tests["weapon master: a reload in the middle"] = function(t)
    local c, addon = boot({ before = function(x) x.setWeaponSkills({ "Axes", "Defense" }) end })
    c.showItemTooltip(SWORD)
    t.ok(step(addon) ~= nil)
    local skills = function(x) x.setWeaponSkills({ "Axes", "Defense" }) end
    local c2, addon2 = reload(c, skills)
    t.eq(step(addon2), nil, "what was shown is kept in memory only")
    t.ok(has(c2.showItemTooltip(SWORD), UNTRAINED), "the line after the reload")
    t.ok(step(addon2) ~= nil, "shown again: offered again")
end

tests["weapon master: the skill read raising keeps today's behaviour"] = function(t)
    local c, addon = boot({ before = function(x)
        x.setWeaponSkills({ "Axes", "Defense" }); x.setWeaponSkillsFails(true)
    end })
    local added = c.showItemTooltip(SWORD)
    t.ok(has(added, TODAY), "today's line")
    t.eq(step(addon), nil, "no step")
    c.setWeaponSkillsFails(false)
    t.ok(has(c.showItemTooltip(SWORD), UNTRAINED), "the read recovers: the untrained line")
end

-- G12 (lead section 275 item 3): the loot roll hint tells "not trained yet"
-- apart from "your class can't use this" (a plain "No upgrade").
tests["weapon master: the roll hint says not trained yet, apart from a kind the class can't use"] = function(t)
    local c = boot({ before = function(x) x.setWeaponSkills({ "Axes", "Defense" }) end })
    local sword = c.offerRoll(7, SWORD)
    t.eq(#sword, 1, "one hint")
    t.eq(sword[1] and sword[1].text, "Not trained yet")
    -- S21's chat advice says it too, apart from "Greed (can't use)".
    local notTrained, cantUse = 0, 0
    for i = 1, #c.printed do
        local said = c.printed[i]
        if string.find(said, SWORD, 1, true) then
            if string.find(said, "Greed (not trained yet)", 1, true) then notTrained = notTrained + 1 end
            if string.find(said, "Greed (can't use)", 1, true) then cantUse = cantUse + 1 end
        end
    end
    t.eq(notTrained, 1, "the chat advice for an untrained weapon")
    t.eq(cantUse, 0, "never the class can't-use words for it")
    local wand = c.offerRoll(8, WAND)
    t.eq(wand[1] and wand[1].text, "No upgrade", "a kind the class never uses stays a no")
    c.setWeaponSkills({ "Axes", "Swords", "Defense" })
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 7,
                       minLevel = 1, unmet = {} })
    local trained = c.offerRoll(9, SWORD)
    t.ok(trained[1] ~= nil and trained[1].text ~= "Not trained yet", "trained: " .. tostring(trained[1] and trained[1].text))
end

tests["weapon master: the setting row is on by default and filed under travel"] = function(t)
    local _, addon = boot()
    local row = addon.settings:row("nav.weaponMasterStep")
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "travel.route")
    t.eq(addon.settings:get("nav.weaponMasterStep"), true)
    local words = table.concat(row and row.synonyms or {}, " ")
    t.ok(words:find("weapon master", 1, true) ~= nil and words:find("train", 1, true) ~= nil
        and words:find("weapon skill", 1, true) ~= nil, "synonyms: " .. words)
end

return tests
