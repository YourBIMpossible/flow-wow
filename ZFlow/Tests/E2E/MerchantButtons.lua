local _, ns = ...
-- The vendor button marks end to end (S20, lead sections 230 and 236), on
-- the whole add-on loaded on a fake client, with the real class packs: the
-- green arrow on an upgrade's button and the per-role up / down / same badge
-- on every piece of gear, kept in step with the merchant's pages through the
-- window's redraw; the advisor line with the price and "more than you have".
-- Every read the verdict needs is set in each fixture (class, level, dual
-- wield, the worn head and off hand, each item's kind, stats, class,
-- subclass, level and the game's own marks). The fake's pages
-- (setMerchantPage) are what the real client reads from MerchantFrame.page;
-- merchantButtons() is what was drawn on each button at the last mark.
-- Look only: nothing here buys. Made-up items. Not tested in game.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG, WEAK, BIG, LATE = "item:21", "item:23", "item:24", "item:25", "item:29"

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function row(index, link, price) return { index = index, item = link, price = price or 100, stack = 1 } end

-- Page 1: a worse helm, then an upgrade. Page 2: the helm you wear, then a
-- bigger upgrade. Two items a page.
local function fourRows()
    return { row(1, WEAK), row(2, STRONG, 2540), row(3, WORN), row(4, BIG) }
end

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: role (spec.role saved for the character), env (the fake's raw
-- names), account (the saved account table: a reload), prepare(c) before
-- the add-on is built.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = opts.env })
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(BIG, helm({ [STR] = 12 }))
    c.setWorn(1, WORN)
    c.setWorn(17, false)                -- nothing in the off hand
    c.setMerchant(fourRows())
    c.setMerchantPage(1, 2)
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function badge(role, state) return { role = role, state = state } end

local function prompts(addon)
    local out = {}
    for _, p in ipairs(addon.advisor.List()) do
        if type(p.id) == "string" and p.id:find("^gear%.merchant%.") then out[#out + 1] = p.text end
    end
    return out
end

tests["vendor marks: page 1 marked, the page change marks page 2, closing clears"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setMerchantOpen(true)
    t.eq(c.merchantButtons(), {
        [1] = { up = false, specs = { badge("dps", "down"), badge("tank", "down") } },
        [2] = { up = true, specs = { badge("dps", "up"), badge("tank", "up") } },
    }, "page 1: the worse helm down, the upgrade up and arrowed")
    c.setMerchantPage(2, 2)
    t.eq(c.merchantButtons()[2].up, true, "the page turned but not redrawn: the old marks still stand")
    c.merchantRedraw()
    t.eq(c.merchantButtons(), {
        [1] = { up = false, specs = { badge("dps", "same"), badge("tank", "same") } },
        [2] = { up = true, specs = { badge("dps", "up"), badge("tank", "up") } },
    }, "page 2 after the redraw: the worn helm same, the bigger upgrade up")
    c.setMerchantOpen(false)
    t.eq(c.merchantButtons(), {}, "closed: every mark gone")
    t.eq(newProblems(addon), 0, "no problem listed")
end

tests["vendor marks: the chosen role's badge comes first"] = function(t)
    local c = boot({ role = "tank" })
    c.setMerchantOpen(true)
    t.eq(c.merchantButtons()[2].specs, { badge("tank", "up"), badge("dps", "up") })
end

tests["vendor marks: item data late - no badge, then the badge"] = function(t)
    local c = boot({ role = "dps", prepare = function(cl)
        cl.setMerchant({ row(1, WEAK), row(2, LATE) })
        -- loaded without its class, subclass or level: no verdict yet
        cl.setItem(LATE, { kind = "INVTYPE_HEAD", stats = { [STR] = 10 } })
    end })
    c.setMerchantOpen(true)
    t.eq(c.merchantButtons()[2], nil, "no verdict: no badge and no arrow")
    c.setItem(LATE, helm({ [STR] = 10 }))
    c.advance(1, 4)
    t.eq(c.merchantButtons()[2], { up = true, specs = { badge("dps", "up"), badge("tank", "up") } },
        "the badge once the item is read")
end

tests["vendor marks: the advisor line gives the price, and says when it is more than you have"] = function(t)
    local c, addon = boot({ role = "dps", prepare = function(cl) cl.setMoney(1000) end })
    c.setMerchantOpen(true)
    local lines = prompts(addon)
    t.eq(lines[1], "2 upgrades on sale here")
    t.eq(lines[2]:find("25s 40c, more than you have", 1, true) ~= nil, true, lines[2])
    t.eq(lines[3]:find("; 1s", 1, true) ~= nil, true, lines[3])
    t.eq(lines[3]:find("more than you have", 1, true), nil, "the cheap one you can pay")
    c.setMerchantOpen(false)
    c.setMoney(100000)
    c.setMerchantOpen(true)
    t.eq(prompts(addon)[2]:find("more than you have", 1, true), nil, "enough money now")
end

tests["vendor marks: money not read - the price, no 'more than you have', no error"] = function(t)
    local c, addon = boot({ role = "dps", prepare = function(cl) cl.setMoney(nil) end })
    c.setMerchantOpen(true)
    local line = prompts(addon)[2]
    t.eq(line:find("25s 40c", 1, true) ~= nil, true, line)
    t.eq(line:find("more than you have", 1, true), nil)
    t.eq(newProblems(addon), 0, "no problem listed")

    local c2, addon2 = boot({ role = "dps", prepare = function(cl) cl.money = nil end })
    c2.setMerchantOpen(true)
    t.eq(prompts(addon2)[2]:find("more than you have", 1, true), nil, "no money read at all")
    t.eq(newProblems(addon2), 0, "no problem listed without the read")
end

tests["vendor marks: the money read raising, then recovering"] = function(t)
    local c, addon = boot({ role = "dps", prepare = function(cl) cl.setMoney(1000) end })
    c.setMoneyFails(true)
    c.setMerchantOpen(true)
    local line = prompts(addon)[2]
    t.eq(line:find("25s 40c", 1, true) ~= nil, true, "the price still said: " .. line)
    t.eq(line:find("more than you have", 1, true), nil, "nothing claimed while the read raises")
    t.eq(c.merchantButtons()[2].up, true, "the marks are not held up")
    c.setMerchantOpen(false)
    c.setMoneyFails(false)
    c.setMerchantOpen(true)
    t.eq(prompts(addon)[2]:find("more than you have", 1, true) ~= nil, true, "said once the read works")
end

tests["vendor marks: after a reload the setting holds and the marks come back"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.eq(addon.settings:set("gear.merchantButtons", false), true)
    local account = c.saved(ns.id.accountDB)
    local c2, addon2 = boot({ role = "dps", account = account })
    c2.setMerchantOpen(true)
    t.eq(c2.merchantButtons(), {}, "still off after the reload")
    c2.setMerchantOpen(false)
    t.eq(addon2.settings:set("gear.merchantButtons", true), true)
    c2.setMerchantOpen(true)
    t.eq(c2.merchantButtons()[2], { up = true, specs = { badge("dps", "up"), badge("tank", "up") } })
end

tests["vendor marks: switched off, no arrow and no badge"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.eq(addon.settings:set("gear.merchantButtons", false), true)
    c.setMerchantOpen(true)
    t.eq(c.merchantButtons(), {})
end

tests["vendor marks: look only - nothing is bought"] = function(t)
    local called = {}
    local env = {}
    for _, name in ipairs({ "BuyMerchantItem", "PickupMerchantItem", "BuybackItem", "EquipItemByName",
                            "UseContainerItem", "PickupItem" }) do
        env[name] = function() called[#called + 1] = name end
    end
    local c = boot({ role = "dps", env = env })
    c.setMerchantOpen(true)
    c.setMerchantPage(2, 2)
    c.merchantRedraw()
    c.setMerchantOpen(false)
    t.eq(called, {})
end

return tests
