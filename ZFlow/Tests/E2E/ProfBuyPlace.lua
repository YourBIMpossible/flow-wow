local _, ns = ...
-- The profession plan's buy step has a place (lead, 2026-11-24): the whole
-- add-on on a fake client. The player opens a merchant window (the real
-- entry: MERCHANT_SHOW, saved by Items/VendorWares.lua and Nav/ServiceSeen.lua), walks off, and the
-- profession arrow's line names that vendor and its needle points there.
-- A vendor seen selling an item counts only with its vendor price seen
-- (A5), so each case that names a vendor has one. Every recipe, item, npc
-- and place is made up. Look only: nothing is
-- bought. Not tested in game.
local tests = {}

local BAR, THREAD = 2, 3
local BOOK = { ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [BAR] = 2 } } }
local COLOURS = { ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } } }
local SMITH = { guid = "Creature-0-1-2-3-61-0", name = "Test Smith Supplier" }
local TRADER = { guid = "Creature-0-1-2-3-62-0", name = "Test Trader" }

-- opts: prices (the account's price book)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true }, learned = { prices = opts.prices } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = 50, max = 75 } }, recipeBook = BOOK },
        recipeColors = COLOURS,
    } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setItemInfo({ [BAR] = { name = "Test Bar", classID = 7 }, [THREAD] = { name = "Test Thread", classID = 7 } })
    c.setBagItems({})
    c.setProfessions({ "Blacksmithing" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The player talks to a vendor where they stand, then closes the window.
local function visit(c, npc, x, y, wares)
    c.setPosition(1411, x, y)
    c.setServiceNpc(npc.guid, npc.name)
    c.setMerchant(wares)
    c.setMerchantOpen(true)
    c.fire("MERCHANT_SHOW")
    c.setMerchantOpen(false)
    c.fire("MERCHANT_CLOSED")
end

local function text(p)
    return table.concat(p and p.lines or {}, " | ")
end

local function has(p, words)
    return text(p):find(words, 1, true) ~= nil
end

tests["buy place: no vendor seen: the plain line, and the arrow does not point"] = function(t)
    local c, addon = start({ prices = { vendor = { [BAR] = { value = 50, basis = "observed" } } } })
    local step = addon.profPlan.plan("Blacksmithing")[1]
    t.eq(step and step.kind, "buy_vendor")
    t.eq(step and step.target, nil, "no place to give")
    local p = c.arrows[2]
    t.ok(has(p, "Buy 12 Test Bar from a trade goods vendor (50c each)"), text(p))
end

tests["buy place: a vendor seen selling it: the arrow names the vendor and points at it"] = function(t)
    local c, addon = start({ prices = { vendor = { [BAR] = { value = 50, basis = "observed" } } } })
    local money = c.money()
    visit(c, SMITH, 0.6, 0.5, { { item = "item:" .. BAR, price = 50, stack = 1 } })
    c.setPosition(1411, 0.5, 0.5)
    c.advance(5, 20)
    local step = addon.profPlan.plan("Blacksmithing")[1]
    t.eq(step and step.kind, "buy_vendor", "the plan starts at the vendor")
    t.eq(step and step.target, { map = 1411, x = 0.6, y = 0.5 }, "where the vendor stood")
    t.eq(step and step.npc, SMITH.name)
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession arrow is up")
    t.ok(has(p, "Buy 12 Test Bar from " .. SMITH.name), "its line names the vendor: " .. text(p))
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle points: the vendor is 100 yd away")
    local before = #c.printed
    c.slashes[ns.id.slash]("prof plan")
    local out = table.concat(c.printed, "\n", before + 1)
    t.ok(out:find("Buy 12 Test Bar from " .. SMITH.name, 1, true) ~= nil, out)
    t.eq(c.money(), money, "nothing was bought")
end

tests["buy place: only a trade goods vendor seen: the line says to try that one, and points"] = function(t)
    local c, addon = start({ prices = { vendor = { [BAR] = { value = 50, basis = "observed" } } } })
    visit(c, TRADER, 0.4, 0.5, { { item = "item:" .. THREAD, price = 10, stack = 1 } })
    c.setPosition(1411, 0.5, 0.5)
    c.advance(5, 20)
    local step = addon.profPlan.plan("Blacksmithing")[1]
    t.eq(step and step.target, { map = 1411, x = 0.4, y = 0.5 })
    t.eq(step and step.npc, nil, "it was not seen selling the bar")
    local p = c.arrows[2]
    t.ok(has(p, "Buy 12 Test Bar from a trade goods vendor (50c each): try " .. TRADER.name), text(p))
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle points at the trader")
end

tests["buy place: the one that sold it wins over a nearer trade goods vendor"] = function(t)
    local c, addon = start({ prices = { vendor = { [BAR] = { value = 50, basis = "observed" } } } })
    visit(c, TRADER, 0.51, 0.5, { { item = "item:" .. THREAD, price = 10, stack = 1 } })
    visit(c, SMITH, 0.9, 0.5, { { item = "item:" .. BAR, price = 50, stack = 1 } })
    c.setPosition(1411, 0.5, 0.5)
    c.advance(5, 20)
    local step = addon.profPlan.plan("Blacksmithing")[1]
    t.eq(step and step.npc, SMITH.name)
    t.eq(step and step.target, { map = 1411, x = 0.9, y = 0.5 })
end

return tests
