local _, ns = ...
-- Bag upgrades as advice (parity rows C-30 and C-31), on the whole add-on
-- loaded on a fake client with the real class packs: "Equip <item> from
-- your bags" on the advisor panel for each bag item that is an upgrade the
-- character can wear now for the chosen role, and the words
-- `<slash> gear check`, `gear on` and `gear off`. Advice and display only:
-- nothing is equipped, used, moved or bound. Booted as
-- Tests/E2E/GearTooltipScore.lua (class, level, dual wield, weapon skills,
-- the worn head, main and off hand, each item's kind, stats, class,
-- subclass, level and the game's own marks). Made-up items. Not tested in
-- game.
--
-- Warrior weights (ZFlow/Classes/Warrior.lua, marked "first guess"): dps
-- Strength 1.0, Stamina 0.35; tank Stamina 1.0, Strength 0.6. The worn
-- helm (2 Stamina, 2 Strength) scores 2.7 for dps and 3.2 for a tank; the
-- strength helm (10 Strength) 10 and 6.
--
-- Red before the code: Gear/BagUpgrades.lua is absent, so no such prompt
-- and no such sub-word.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG, SIDE, PLATE, HIGH, UNREAD, LEGS = "item:4101", "item:4102", "item:4103", "item:4104",
    "item:4105", "item:4106", "item:4107"
local BIG = "item:4111"

local function armour(kind, stats, unmet, minLevel)
    return { kind = kind, stats = stats, classID = 4, subclassID = 3, minLevel = minLevel or 1, unmet = unmet or {} }
end

local function helm(stats, unmet, minLevel) return armour("INVTYPE_HEAD", stats, unmet, minLevel) end

local function sword(stats)
    return { kind = "INVTYPE_WEAPON", stats = stats, classID = 2, subclassID = 7, minLevel = 1, unmet = {},
             speed = 2.6 }
end

local function bags(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { item = link, count = 1 } end
    return out
end

-- opts: role (spec.role saved for the character), bag (the bag links),
-- account (the saved account settings).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    -- 0.035 better for dps: under the mark's own threshold (GearTooltip.SAME).
    c.setItem(SIDE, helm({ [STA] = 2.1, [STR] = 2 }))
    c.setItem(PLATE, helm({ [STR] = 30 }, { "Plate" }))
    c.setItem(HIGH, helm({ [STR] = 40 }, { "Requires Level 40" }, 40))
    -- UNREAD is never set: the item was not read.
    c.setItem(LEGS, armour("INVTYPE_LEGS", { [STR] = 9 }))   -- the legs slot is not read
    c.setItem(BIG, sword({ [STR] = 20 }))
    c.setWorn(1, WORN)
    c.setWorn(16, BIG)
    c.setWorn(17, false)
    c.setBagItems(opts.bag or {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function line(text) return ns.id.title .. ": " .. text end

-- The advisor's lines that are bag upgrade prompts, in shown order.
local function prompts(addon)
    local out = {}
    for _, p in ipairs(addon.advisor.List()) do
        if p.id:sub(1, 9) == "gear.bag." then out[#out + 1] = p.text end
    end
    return out
end

local STRONG_LINE = "Equip " .. STRONG .. " from your bags: +7.3 for dps over your head piece (first-guess weights)"

tests["bag upgrades: an upgrade in the bags is an advisor line with the item, role, slot and gain"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(STRONG) })
    t.eq(addon:ModuleState("gearBagUpgrades"), "started")
    for _, area in ipairs({ "gear", "setting", "diag" }) do
        t.eq(addon.problems:count(area), 0, "no " .. area .. " problem from the boot")
    end
    t.eq(prompts(addon), { STRONG_LINE }, "shown from login, with the weights said to be a first guess")
    t.eq(prompts(addon)[1] ~= nil and prompts(addon)[1]:lower():find("clear", 1, true) or nil, nil,
         "a first guess is not called a clear upgrade")
    t.eq(c.equipCalls, 0, "nothing was equipped")
    t.eq(c.equips, {})
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["bag upgrades: for the chosen role only, with that role's gain"] = function(t)
    local _, addon = boot({ role = "tank", bag = bags(STRONG) })
    t.eq(prompts(addon),
         { "Equip " .. STRONG .. " from your bags: +2.8 for tank over your head piece (first-guess weights)" })
end

tests["bag upgrades: no line for what is not known to be a wearable upgrade"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(PLATE, HIGH, SIDE, UNREAD, LEGS) })
    t.eq(prompts(addon), {}, "unusable, level too high, a sidegrade, an item not read, a worn slot not read")
    c.setBagItems(bags(PLATE, HIGH, SIDE, UNREAD, LEGS, STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(prompts(addon), { STRONG_LINE }, "the one real upgrade among them")
    t.eq(addon.problems:count(), base, "no new problem")
    t.eq(c.equipCalls, 0)
end

tests["bag upgrades: no role chosen - no line, and the word says why"] = function(t)
    local c, addon, base = boot({ bag = bags(STRONG) })
    t.eq(prompts(addon), {})
    t.eq(said(c, "gear check"),
         { line("Bag upgrades cannot be checked: choose a role (say " .. ns.id.slash .. " role).") })
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["bag upgrades: the line goes when the item leaves the bags, is worn, or is no upgrade any more"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(STRONG) })
    t.eq(#prompts(addon), 1)
    c.setBagItems({})
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(prompts(addon), {}, "it left the bags")
    c.setBagItems(bags(STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#prompts(addon), 1, "and comes back with it")
    -- The player puts it on: the old helm is in the bags now.
    c.setWorn(1, STRONG)
    c.setBagItems(bags(WORN))
    c.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(prompts(addon), {}, "worn now; the old helm is no upgrade")
    -- Still in the bags, but what is worn got as good.
    c.setWorn(1, WORN)
    c.setBagItems(bags(STRONG))
    c.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    t.eq(#prompts(addon), 1)
    c.setItem("item:4199", helm({ [STR] = 10 }))
    c.setWorn(1, "item:4199")
    c.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    t.eq(prompts(addon), {}, "the same as what is worn now")
    t.eq(addon.problems:count(), base, "no new problem")
    t.eq(c.equipCalls, 0, "the test changed what is worn; the add-on equipped nothing")
end

tests["bag upgrades: a worn slot not read gives no line, and alone it is the word's reason"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(LEGS) })
    t.eq(prompts(addon), {})
    t.eq(said(c, "gear check"), { line("Bag upgrades cannot be checked: what you wear was not read.") })
    c.setWorn(7, false)
    c.fire("PLAYER_EQUIPMENT_CHANGED", 7)
    t.eq(prompts(addon),
         { "Equip " .. LEGS .. " from your bags: +9 for dps over nothing worn (your legs) (first-guess weights)" },
         "read, and empty")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["gear check: the same rows as the advisor; none says so"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(SIDE) })
    t.eq(said(c, "gear check"), { line("No upgrades in your bags.") })
    c.setBagItems(bags(SIDE, STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(said(c, "gear check"), { line("Upgrades in your bags, for dps:"), line(STRONG_LINE) })
    t.eq(prompts(addon), { STRONG_LINE })
    c.setBagItems(nil)
    t.eq(said(c, "gear check"), { line("Bag upgrades cannot be checked: your bags could not be read.") })
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["gear off stops the advice; gear on brings it back; the setting is on by default"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(STRONG) })
    t.eq(addon.settings:get("gear.bagAdvice"), true, "on by default")
    t.eq(#prompts(addon), 1)
    t.eq(said(c, "gear off"), { line("Bag upgrade advice is off.") })
    t.eq(addon.settings:get("gear.bagAdvice"), false)
    t.eq(prompts(addon), {})
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(prompts(addon), {}, "and it stays off")
    t.eq(said(c, "gear check"), { line("Upgrades in your bags, for dps:"), line(STRONG_LINE) },
         "asked for, the list is still given")
    t.eq(said(c, "gear on"), { line("Bag upgrade advice is on.") })
    t.eq(addon.settings:get("gear.bagAdvice"), true)
    t.eq(prompts(addon), { STRONG_LINE })
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["bag upgrades: saved off - nothing from login"] = function(t)
    local _, addon = boot({ role = "dps", bag = bags(STRONG),
                            account = { settings = { gear = { bagAdvice = false } } } })
    t.eq(prompts(addon), {})
end

tests["gear why still works, and the bare word says every sub-word"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(STRONG) })
    local why = said(c, "gear why")
    t.eq(why[1], line("Gear in your bags, for dps:"))
    t.eq(why[2], line(STRONG .. ": Upgrade for your head piece (+7.3, dps); score 10"))
    t.eq(#why, 2)
    local usage = said(c, "gear")
    t.eq(#usage, 1)
    for _, word in ipairs({ " gear check", " gear on", " gear off", " gear why" }) do
        t.ok((usage[1] or ""):find(ns.id.slash .. word, 1, true) ~= nil,
             "the usage names" .. word .. ": " .. tostring(usage[1]))
    end
    local keep = addon.settings:row("gear.keepOffspec")
    t.ok(keep ~= nil and (usage[1] or ""):find(keep.label, 1, true) ~= nil,
         "and the keep off-spec setting by its label: " .. tostring(usage[1]))
    t.eq(said(c, "help gear"), { line(ns.id.slash .. " gear - " .. tostring(addon.diag.help.gear)) })
    t.ok(tostring(addon.diag.help.gear):find("check", 1, true) ~= nil, "the help line names check")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["bag upgrades: the words and the prompts equip nothing and bind nothing"] = function(t)
    local c, addon, base = boot({ role = "dps", bag = bags(STRONG) })
    local secure, binds = #c.secureGiven, #c.bindingCalls()
    said(c, "gear check")
    said(c, "gear off")
    said(c, "gear on")
    said(c, "gear")
    t.eq(c.equipCalls, 0, "no equip call")
    t.eq(c.equips, {})
    t.eq(#c.secureGiven, secure, "no secure attribute written by the words")
    t.eq(#c.bindingCalls(), binds, "no key bound by the words")
    t.eq(c.soldSlots, {})
    t.eq(addon.problems:count(), base, "no new problem")
end

return tests
