local _, ns = ...
-- Parity rows E-01 and E-03 end to end, on the whole add-on loaded on a
-- fake client. E-01: a bag slot carries a mark for what would be done with
-- its item: a step holds it, the bank list would bank it, the auctions word
-- would list it, beside the quest, upgrade, sell and material marks there
-- were. E-03: gear in the bags carries, per role, better, worse or the same.
-- Look only: nothing is sold, banked, posted, equipped or moved (the fake
-- client has a sell and an equip call to count; it has none that banks or
-- posts). Made-up realm and items.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
--
-- Red before the code: the bag marks know nothing of holds, the bank list
-- or prices, and the bag badge marks upgrades only, with a bare letter.
local tests = {}

local PLANK, NAIL, TRINKET, BAUBLE, SHARD, NOTE, BOLT = 8001, 8002, 8003, 8004, 8005, 8006, 8007
local INFO = {
    [PLANK] = { name = "Rough Plank", quality = 1, sellPrice = 10, classID = 7 },
    [NAIL] = { name = "Bent Nail", quality = 1, sellPrice = 10, classID = 7 },
    [TRINKET] = { name = "Odd Trinket", quality = 1, sellPrice = 100, classID = 15 },
    [BAUBLE] = { name = "Dull Bauble", quality = 1, sellPrice = 100, classID = 15 },
    [SHARD] = { name = "Chipped Shard", quality = 0, sellPrice = 5, classID = 15 },
    [NOTE] = { name = "Sealed Note", quality = 1, sellPrice = 0, classID = 12 },
}
local NOW = 1700000000
local REALM = "Realm1-Horde"
local BAG = {
    { bag = 0, slot = 1, item = PLANK, count = 4 },
    { bag = 0, slot = 2, item = NAIL, count = 5 },
    { bag = 0, slot = 3, item = TRINKET, count = 1 },
    { bag = 0, slot = 4, item = BAUBLE, count = 1 },
    { bag = 1, slot = 1, item = SHARD, count = 2 },
    { bag = 1, slot = 2, item = NOTE, count = 1 },
}

-- Prices seen in the player's own searches (Items/AuctionLog.lua's saved
-- shape): 50s each for the trinket and the shard.
local function prices()
    return { learned = { prices = { auctionHistory = { [REALM] = {
        [TRINKET] = { h = { NOW - 60, 5000 } },
        [SHARD] = { h = { NOW - 60, 5000 } },
    } } } } }
end

-- A goal that holds `count` of `item`: a recipe planned by ItemPlan, as
-- Tests/E2E/BankReservations.lua's.
local function holds(addon, item, count)
    return function(snapshot)
        local key = addon.Items.Key(item)
        local recipes = { ["make:test"] = { makes = BOLT, yield = 1, mats = { [key] = 1 } } }
        local plan = addon.ItemPlan.Build({ recipe = "make:test", count = count },
            { recipes = recipes, snapshot = snapshot })
        local claims = {}
        for _, claim in ipairs(addon.ItemPlan.Claims(plan, "test", "tailoring")) do
            claim.selected = true
            claims[#claims + 1] = claim
        end
        return claims
    end
end

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: account (the saved account table), source(addon) -> a reservation
-- source, bag (default BAG).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(NOW)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setItemInfo(INFO)
    c.setBagItems({})
    local addon = ns.offline.addon(c)
    if opts.source then addon.Reservations.Source("test", opts.source(addon)) end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    c.setBagItems(opts.bag or BAG)
    c.fire("BAG_UPDATE_DELAYED")
    return c, addon
end

local function drawn(c) return c.bagMarksDrawn and c.bagMarksDrawn() or nil end

local function untouched(t, c, addon)
    t.eq(#(c.soldSlots or {}), 0, "nothing sold by the add-on")
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(newProblems(addon), 0, "no new problems")
end

tests["bag icons: trade goods nothing holds carry the bank mark"] = function(t)
    local c, addon = boot()
    t.eq(drawn(c), {
        [0] = { [1] = "bank", [2] = "bank" },
        [1] = { [1] = "sell", [2] = "quest" },
    }, "no prices seen: no auction mark, and the plain things none")
    untouched(t, c, addon)
end

tests["bag icons: what a goal holds carries the step mark, not the bank's"] = function(t)
    local c, addon = boot({ source = function(addon) return holds(addon, NAIL, 5) end })
    t.eq(drawn(c), {
        [0] = { [1] = "bank", [2] = "step" },
        [1] = { [1] = "sell", [2] = "quest" },
    })
    untouched(t, c, addon)
end

tests["bag icons: a thing worth the auction house carries the auction mark; junk keeps its coin"] = function(t)
    local c, addon = boot({ account = prices() })
    t.eq(drawn(c), {
        [0] = { [1] = "bank", [2] = "bank", [3] = "auction" },
        [1] = { [1] = "sell", [2] = "quest" },
    }, "the trinket has a price seen; the bauble none; the shard is junk first")
    untouched(t, c, addon)
end

tests["bag icons: reservations not known - no step, bank or auction mark"] = function(t)
    local c, addon = boot({ account = prices(), source = function() return function() error("no claims") end end })
    t.eq(drawn(c), { [1] = { [1] = "sell", [2] = "quest" } }, "the marks there were, and no more")
    untouched(t, c, addon)
end

tests["bag icons: bags.marks off draws none of them"] = function(t)
    local account = prices()
    account.settings = { bags = { marks = false } }
    local c, addon = boot({ account = account, source = function(addon) return holds(addon, NAIL, 5) end })
    t.eq(drawn(c), {})
    untouched(t, c, addon)
end

tests["bag icons: a goal dropped - the step mark goes on the next bag change"] = function(t)
    local on = true
    local c, addon = boot({ source = function(addon)
        local claims = holds(addon, NAIL, 5)
        return function(snapshot)
            if on then return claims(snapshot) end
            return {}
        end
    end })
    t.eq(drawn(c)[0], { [1] = "bank", [2] = "step" })
    on = false
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(drawn(c)[0], { [1] = "bank", [2] = "bank" })
    untouched(t, c, addon)
end

-- E-03. Warrior weights (ZFlow/Classes/Warrior.lua), dps: Strength 1.0,
-- Stamina 0.35. The worn helm (2 Stamina, 2 Strength) scores 2.7; the
-- strong one (10 Strength) 10, the weak one (1 Stamina) 0.35, the twin the
-- same 2.7. The role is chosen (spec.role), so one letter each.
local WORN, STRONG, WEAK, TWIN = "item:8101", "item:8102", "item:8103", "item:8104"
local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function bootGear(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, { settings = { spec = { role = "dps" } } })
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItemInfo({
        [8101] = { name = "Worn Cap", quality = 1, sellPrice = 5, classID = 4, minLevel = 1 },
        [8102] = { name = "Strong Cap", quality = 2, sellPrice = 9, classID = 4, minLevel = 1 },
        [8103] = { name = "Weak Cap", quality = 1, sellPrice = 4, classID = 4, minLevel = 1 },
        [8104] = { name = "Twin Cap", quality = 1, sellPrice = 5, classID = 4, minLevel = 1 },
    })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(TWIN, helm({ [STA] = 2, [STR] = 2 }))
    c.setWorn(1, WORN)
    c.setBagItems({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    c.setBagItems({
        { bag = 0, slot = 1, item = STRONG, count = 1 },
        { bag = 0, slot = 2, item = WEAK, count = 1 },
        { bag = 0, slot = 3, item = TWIN, count = 1 },
        { bag = 0, slot = 4, item = "item:8199", count = 1 },
    })
    c.fire("BAG_UPDATE_DELAYED")
    return c, addon
end

tests["bag icons: gear carries better, worse or the same for the role; an unread item nothing"] = function(t)
    local c, addon = bootGear()
    local P = addon.GearBagBadge.Piece
    if type(P) ~= "function" then return t.ok(false, "GearBagBadge.Piece") end
    t.eq(c.bagMarks(), {
        { bag = 0, slot = 1, text = P("dps", "up") },
        { bag = 0, slot = 2, text = P("dps", "down") },
        { bag = 0, slot = 3, text = P("dps", "same") },
    })
    untouched(t, c, addon)
end

tests["bag icons: gear.bagBadge off draws no letters"] = function(t)
    local c, addon = bootGear({ settings = { gear = { bagBadge = false } } })
    t.eq(c.bagMarks(), {})
    untouched(t, c, addon)
end

return tests
