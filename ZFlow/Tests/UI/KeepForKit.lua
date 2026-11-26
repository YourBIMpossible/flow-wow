local _, ns = ...

-- C-32 keep-for ticks (the drawing half): in the sell list window, under a
-- "Keeping" section, the gear.keepOffspec switch as a checkbox and one
-- tick per role of your class from GearOffSpec's facts, writing
-- state.gear.keepFor. The data half (Gear/OffSpec.lua's KeepFor) is
-- Zen-6's and has its own tests (Tests/E2E/GearOffSpec.lua). Fake client,
-- the real class packs, made-up items. Not tested in game.
--
-- Red before the code: SellList.KeepFor does not exist and no listing
-- carries keepFor, so every test here fails its first check.

local L = ns.SellList
local K = ns.Kit
local tests = {}

local NONE = { status = ns.Reservations.NONE }

local STR, DODGE = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_DODGE_RATING_SHORT"
local WORN = "item:4000:0:0:0:0:0:0:0"
local GUARD = "item:4001:0:0:0:0:0:0:0"      -- dodge: a tank upgrade, worse for dps
local CLOAK = "item:4002:0:0:0:0:0:0:0"
local INFO = {
    [4001] = { name = "Guard Helm", quality = 2, sellPrice = 50, classID = 4 },
    [4002] = { name = "Frayed Cloak", quality = 0, sellPrice = 4, classID = 4 },
}

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

-- A warrior whose chosen role is dps, at no merchant. opts: account,
-- char (saved tables), keep (the switch as saved), ticks (saved keepFor).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    if opts.keep ~= nil then account.settings = { gear = { keepOffspec = opts.keep } } end
    local char = opts.char or {}
    char.settings = { spec = { role = "dps" } }
    if opts.ticks ~= nil then char.state = { gear = { keepFor = opts.ticks } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItemInfo(INFO)
    c.setItem(WORN, helm({ [STR] = 4 }))
    c.setItem(GUARD, helm({ [DODGE] = 10 }))
    c.setWorn(1, WORN)
    c.setBagItems({ { item = GUARD, count = 1 }, { item = CLOAK, count = 1 } })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    -- The switch's Settings row, as Gear/OffSpec.lua declares it in the
    -- real addon: the window now writes the switch through
    -- ctx.settings:set (White's note on the approved build), which
    -- needs the row declared.
    k:Setting({ key = "gear.keepOffspec", scope = "account", type = "bool", default = true,
        label = "Keep gear for your other roles", group = "gear" })
    ns.Reservations.Declare(k)
    local api = L.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function partByKey(tree, key)
    local found
    K.Each(tree, function(p) if p.key == key then found = p end end)
    return found
end

local function hasText(tree, text)
    local found = false
    K.Each(tree, function(p) if p.text == text then found = true end end)
    return found
end

-- A listing drawn by hand for the tree tests: one junk row to sell, and
-- the keepFor block under test.
local function listingWith(keepFor)
    return {
        stacks = {},
        list = { ok = true, rows = { { key = "cloak", basis = "guess" } }, total = {} },
        kept = { rows = {} }, others = {},
        keepFor = keepFor,
    }
end

local KEEP_FOR_3 = {
    roles = { "dps", "heal", "tank" },
    names = { dps = "Retribution", heal = "Holy", tank = "Protection" },
    choices = nil, switch = true, role = "dps",
}

tests["keep-for: the listing carries your roles, the switch and your ticks"] = function(t)
    local k, c = boot()
    local listing = L.Listing(c, k.store, L.Held(NONE), NONE)
    t.eq(type(listing.keepFor), "table", "the listing carries keepFor")
    if type(listing.keepFor) ~= "table" then return end
    local kf = listing.keepFor
    t.ok(#kf.roles >= 2, "a warrior has roles to keep for")
    local sorted = {}
    for i, r in ipairs(kf.roles) do sorted[i] = r end
    table.sort(sorted)
    t.eq(kf.roles, sorted, "the roles stand in order")
    local hasTank, hasDps = false, false
    for _, r in ipairs(kf.roles) do
        if r == "tank" then hasTank = true end
        if r == "dps" then hasDps = true end
        t.eq(type(kf.names[r]), "string", "a name for " .. r)
    end
    t.ok(hasTank and hasDps, "tank and dps are among them")
    t.eq(kf.switch, true, "the switch reads on as made")
    t.eq(kf.choices, nil, "no ticks saved yet")

    local k2, c2 = boot({ keep = false, ticks = { tank = true } })
    local kf2 = L.Listing(c2, k2.store, L.Held(NONE), NONE).keepFor
    t.eq(kf2.switch, false, "a saved-off switch reads off")
    t.eq(kf2.choices, { tank = true }, "the saved ticks are carried")
end

tests["keep-for: a class with one role has no block, and no section is drawn"] = function(t)
    t.eq(type(L.KeepFor), "function", "SellList.KeepFor exists")
    if type(L.KeepFor) ~= "function" then return end
    local _, c = boot()
    local store = { get = function() return nil end }
    t.eq(L.KeepFor(store, { roleNames = { dps = "Arms" } }), nil, "one role: nothing to tick")
    t.eq(L.KeepFor(store, {}), nil, "no facts: no block")
    local tree = L.TreeOf(listingWith(nil), c, ns.id, nil)
    t.eq(hasText(tree, "Keeping"), false, "no Keeping section without the block")
end

tests["keep-for: the tree draws the switch, the ticks and the tick text"] = function(t)
    local _, c = boot()
    local tree = L.TreeOf(listingWith(KEEP_FOR_3), c, ns.id, nil)
    t.eq(hasText(tree, "Keeping"), true, "the Keeping section stands")
    local switch = partByKey(tree, "keep.switch")
    t.ok(switch ~= nil, "the switch is drawn")
    t.eq(switch.kind, "checkbox", "the switch is a checkbox")
    t.eq(switch.label, "Keep gear for your other roles", "the switch keeps its row's words")
    t.eq(switch.checked, true, "the switch is on")
    t.eq(switch.enabled, true, "the switch can be used while no tick is saved")
    t.eq(hasText(tree, "Keep gear for:"), true, "the ticks are headed")
    local order = {}
    K.Each(tree, function(p)
        if type(p.key) == "string" and p.key:sub(1, 5) == "keep." and p.key ~= "keep.switch" then
            order[#order + 1] = p
        end
    end)
    t.eq(#order, 3, "one tick per role")
    t.eq(order[1].label, "Retribution", "the first tick is named for its role")
    t.eq(order[2].label, "Holy", "the second tick")
    t.eq(order[3].label, "Protection", "the third tick")
    t.eq(order[1].checked, false, "nothing is ticked")
    t.eq(hasText(tree, "Tick the roles you want gear kept for. Once you tick any role, "
        .. "the ticks decide what is kept and the 'keep off-spec gear' switch is no longer read. "
        .. "With nothing ticked, the switch works as before."), true, "the tick text stands word for word")
    t.eq(hasText(tree, "Ticks above decide what is kept."), false, "no greyed note while nothing is ticked")
end

tests["keep-for: a saved tick greys the switch and checks its box"] = function(t)
    local _, c = boot()
    local kf = {
        roles = { "dps", "heal", "tank" },
        names = { dps = "Retribution", heal = "Holy", tank = "Protection" },
        choices = { tank = true }, switch = true, role = "dps",
    }
    local tree = L.TreeOf(listingWith(kf), c, ns.id, nil)
    local switch = partByKey(tree, "keep.switch")
    t.eq(switch.enabled, false, "the switch is greyed once a tick is saved")
    t.eq(hasText(tree, "Ticks above decide what is kept."), true, "the greyed note stands")
    t.eq(partByKey(tree, "keep.tank").checked, true, "the saved tick is checked")
    t.eq(partByKey(tree, "keep.heal").checked, false, "an unsaved role is not checked")
end

tests["keep-for: ticking writes the ticks, unticking the last one hands back to the switch"] = function(t)
    local k, c = boot()
    c.setMerchantOpen(true)
    t.eq(k.use(L.NAME).Show(), true, "the list opens at the merchant")
    local rec = c.kitWindows().SellList
    t.ok(rec ~= nil and rec.shown == true, "the window is shown")
    t.eq(c.kitClick("SellList", "keep.tank"), true, "the tank tick is clickable")
    t.eq(k.store:get("char", "state.gear.keepFor"), { tank = true }, "the tick was saved")
    t.eq(c.kitClick("SellList", "keep.tank"), true, "the tank tick is clickable again")
    local after = k.store:get("char", "state.gear.keepFor")
    t.ok(after == nil or next(after) == nil, "unticking the last tick clears the ticks")
    t.eq(c.kitClick("SellList", "keep.switch"), true, "the switch is clickable again")
    t.eq(k.store:get("account", "settings.gear.keepOffspec"), false, "the switch was saved off")
end

return tests
