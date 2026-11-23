local _, ns = ...
-- The Need or Greed advice on a loot roll (S21, lead section 275), on the
-- whole add-on loaded on a fake client with the real class packs, through
-- the real roll entry point (c.offerRoll), the value on the roll's item
-- (c.rollValue), the chat line and the roll word. Per lead section 236:
-- item data late (no advice, then the advice), a read raising then
-- recovering, a reload keeping the settings. Problems are counted against
-- the count after boot. Every read the verdict needs is set (class, level,
-- dual wield, weapon skills, the worn head, main and off hand, each item's
-- kind, stats, class, subclass, level and the game's own marks). Made-up
-- items. Hint only: no roll is made for the player. Not tested in game.
--
-- Warrior weights (ZFlow/Classes/Warrior.lua): the strength helm is +7.3
-- for dps and +2.8 for a tank over the worn helm; the small sword is worse
-- than the worn one for both.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG, LATE = "item:4101", "item:4102", "item:4103"
local BIG, SMALL, MAIL = "item:4111", "item:4112", "item:4121"

local function R() return ns.GearRollHint end

local function helm(stats, unmet)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = unmet or {} }
end

local function sword(stats)
    return { kind = "INVTYPE_WEAPON", stats = stats, classID = 2, subclassID = 7, minLevel = 1, unmet = {},
             speed = 2.6 }
end

-- opts: role (spec.role), account / char (saved tables: a reload).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = opts.char or {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(MAIL, helm({ [STR] = 30 }, { "Mail" }))
    c.setItem(BIG, sword({ [STR] = 20 }))
    c.setItem(SMALL, sword({ [STR] = 5 }))
    c.setWorn(1, WORN)
    c.setWorn(16, BIG)
    c.setWorn(17, false)        -- the off hand read: empty
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function line(text) return ns.id.title .. ": " .. text end

-- How many chat lines since `from` are exactly `text` (with the title).
local function count(c, from, text)
    local want, n = line(text), 0
    for i = from, #c.printed do
        if c.printed[i] == want then n = n + 1 end
    end
    return n
end

-- How many chat lines since `from` name `link` at all.
local function naming(c, from, link)
    local n = 0
    for i = from, #c.printed do
        if string.find(c.printed[i], link, 1, true) then n = n + 1 end
    end
    return n
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function valueText(c, rollID)
    local v = c.rollValueOf(rollID)
    return v and v.text
end

tests["roll advice 236: an upgrade for the chosen role says Need on the roll and once in chat"] = function(t)
    local c = boot({ role = "tank" })
    local from = #c.printed + 1
    local shown = c.offerRoll(7, STRONG)
    t.eq(#shown, 1, "the hint above the roll, as before")
    t.eq(shown[1] and shown[1].text, "Upgrade")
    t.eq(valueText(c, 7), "Need +2.8")
    t.eq(count(c, from, STRONG .. ": Need: upgrade for tank"), 1)
    c.offerRoll(7, STRONG)
    t.eq(count(c, from, STRONG .. ": Need: upgrade for tank"), 1, "once per roll id")
end

tests["roll advice 236: usable and no upgrade is Greed; can't use is Greed (can't use)"] = function(t)
    local c = boot({ role = "dps" })
    local from = #c.printed + 1
    local shown = c.offerRoll(8, SMALL)
    t.eq(#shown, 1)
    t.eq(shown[1] and shown[1].text, "No upgrade", "the hint word is unchanged")
    t.eq(valueText(c, 8), "Greed")
    t.eq(count(c, from, SMALL .. ": Greed"), 1)
    c.offerRoll(9, MAIL)
    t.eq(valueText(c, 9), "Greed")
    t.eq(count(c, from, MAIL .. ": Greed (can't use)"), 1)
end

tests["roll advice 236: item data late - no advice, then the advice once it is read"] = function(t)
    local c, addon = boot({ role = "dps" })
    local base = addon.problems:count("gear")
    local from = #c.printed + 1
    c.offerRoll(10, LATE)
    t.eq(valueText(c, 10), nil, "no advice while the item is not loaded")
    t.eq(naming(c, from, LATE), 0, "no chat line while the item is not loaded")
    c.setItem(LATE, helm({ [STR] = 10 }))
    c.advance(3, 6)
    t.eq(valueText(c, 10), "Need +7.3")
    t.eq(count(c, from, LATE .. ": Need: upgrade for dps"), 1)
    c.advance(3, 6)
    t.eq(count(c, from, LATE .. ": Need: upgrade for dps"), 1, "still once")
    t.eq(addon.problems:count("gear"), base, "a late item is no problem")
end

tests["roll advice 236: the gear read raising, then recovering"] = function(t)
    local c, addon = boot({ role = "dps" })
    local base = addon.problems:count("gear")
    local from = #c.printed + 1
    local real = c.gear
    c.gear = function() error("gear read failed") end
    c.offerRoll(11, STRONG)
    t.eq(valueText(c, 11), nil, "nothing while the read raises")
    t.eq(naming(c, from, STRONG), 0)
    t.eq(addon.problems:count("gear"), base + 1, "one gear problem for that error")
    c.gear = real
    c.advance(3, 6)
    t.eq(valueText(c, 11), "Need +7.3", "the advice once the read works")
    t.eq(count(c, from, STRONG .. ": Need: upgrade for dps"), 1)
end

tests["roll advice 236: the chat setting off says nothing in chat; the hint setting off shows no value"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.eq(addon.settings:get(R().CHAT_SETTING), true, "on by default")
    t.eq(addon.settings:set(R().CHAT_SETTING, false), true)
    local from = #c.printed + 1
    c.offerRoll(12, STRONG)
    t.eq(valueText(c, 12), "Need +7.3", "the value still shows")
    t.eq(naming(c, from, STRONG), 0, "no chat line")
    t.eq(addon.settings:set(R().SETTING, false), true)
    c.offerRoll(13, SMALL)
    t.eq(valueText(c, 13), nil)
    t.eq(naming(c, from, SMALL), 0)
end

tests["roll advice 236: reload keeps the chat setting"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.eq(addon.settings:set(R().CHAT_SETTING, false), true)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(R().CHAT_SETTING), false, "still off after the reload")
    local from = #c2.printed + 1
    c2.offerRoll(14, STRONG)
    t.eq(naming(c2, from, STRONG), 0)
end

tests["roll advice 236: the roll word says the same advice for any item link"] = function(t)
    local c = boot({ role = "tank" })
    t.eq(said(c, "roll " .. STRONG), { line(STRONG .. ": Need: upgrade for tank") })
    t.eq(said(c, "roll " .. SMALL), { line(SMALL .. ": Greed") })
    local none = said(c, "roll " .. LATE)
    t.eq(#none, 1)
    t.ok(none[1] ~= line(LATE .. ": Greed") and not string.find(none[1], "Need", 1, true), "no guess: " .. tostring(none[1]))
    local how = said(c, "roll")
    t.eq(#how, 1)
    t.ok(string.find(how[1], ns.id.slash .. " roll", 1, true) ~= nil, "says how: " .. tostring(how[1]))
end

tests["roll advice 236: it never rolls or confirms a roll"] = function(t)
    local c = boot({ role = "dps" })
    local calls = 0
    for _, name in ipairs({ "RollOnLoot", "ConfirmLootRoll" }) do
        c[name] = function() calls = calls + 1 end
    end
    c.offerRoll(15, STRONG)
    c.offerRoll(16, SMALL)
    c.offerRoll(17, MAIL)
    said(c, "roll " .. STRONG)
    c.advance(3, 6)
    t.eq(calls, 0)
end

return tests
