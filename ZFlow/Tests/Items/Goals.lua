local _, ns = ...

-- Tests for ZFlow/Items/Goals.lua: the player's goals list (the character's
-- settings.goals) as a Reservations source, and the goal word that fills it.
-- Offline: the fake client's reads, not the game's. Not tested in game.

local tests = {}

local LINEN, BOLT, POTION = 2589, 2996, 858
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [BOLT] = { name = "Bolt of Linen Cloth", quality = 1, sellPrice = 40, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}
local LINK = "|cffffffff|hitem:2589::::::::|h[linen cloth]|h|r"   -- lower-cased, as the slash command hands it over

local function snap(bags) return ns.Resources.Fake({ bags = bags or { [LINEN] = 20 } }) end

local function itemClaims(claims)
    local out = {}
    for _, c in ipairs(claims) do
        if c.kind == "item" then out[#out + 1] = c end
    end
    return out
end

-- The whole add-on on a fake client, logged in. goals: what settings.goals
-- holds for this character (nil: none saved).
local function start(goals, bagsUnread)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, goals ~= nil and { settings = { goals = goals } } or {})
    c.setItemInfo(INFO)
    if not bagsUnread then
        c.setBagItems({ { item = LINEN, count = 15 }, { item = LINEN, count = 5 }, { item = POTION, count = 5 } })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The whole add-on on a fake client, not logged in: its store is not open.
local function unopened(goals)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, goals ~= nil and { settings = { goals = goals } } or {})
    c.setItemInfo(INFO)
    return c, ns.offline.addon(c)
end

-- A read with the bags read: 20 Linen.
local READ = { items = function() return { [LINEN] = 20 } end }

local function saved(c)
    local db = c.saved(ns.id.charDB)
    local s = type(db) == "table" and db.settings or nil
    return type(s) == "table" and s.goals or nil
end

-- What one goal word prints, without the title.
local function say(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash]("goal" .. (rest ~= "" and (" " .. rest) or ""))
    local p = ns.id.title .. ": "
    local out = {}
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #p) == p then line = line:sub(#p + 1) end
        out[#out + 1] = line
    end
    return out
end

-------------------------------------------------------------------------------
-- The producer
-------------------------------------------------------------------------------

tests["goals: a goal with no recipe claims the item itself"] = function(t)
    local G = ns.ItemGoals
    local claims, skipped = G.Claims(snap(), { { item = LINEN, count = 8 } })
    t.eq(skipped, 0)
    t.eq(#claims, 1)
    local c = claims[1]
    t.eq(c.owner, "goal:" .. LINEN)
    t.eq(c.activity, "goal")
    t.eq(c.kind, "item")
    t.eq(c.key, LINEN)
    t.eq(c.amount, 8)
    t.eq(c.selected, true, "the player picked it")
    t.eq(c.bank, true, "the goal holds the item in the bank too")
end

tests["goals: a goal with a known recipe takes ItemPlan's claims, marked selected"] = function(t)
    local G = ns.ItemGoals
    local recipes = { ["bolt"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } } }
    local claims, skipped = G.Claims(snap(), { { item = BOLT, count = 3, recipe = "bolt" } }, recipes)
    t.eq(skipped, 0)
    local items = itemClaims(claims)
    t.eq(#items, 1)
    t.eq(items[1].key, LINEN, "the mats are claimed")
    t.eq(items[1].amount, 6, "2 a bolt, 3 bolts")
    t.eq(items[1].owner, "goal:" .. BOLT)
    t.eq(items[1].activity, "goal")
    for _, c in ipairs(claims) do t.eq(c.selected, true, "every claim is selected") end
end

tests["goals: a malformed goal is skipped and counted, the rest still claim"] = function(t)
    local G = ns.ItemGoals
    local goals = {
        { item = LINEN, count = 8 },
        "linen",                                    -- not a table
        { item = "nothing", count = 3 },            -- no item
        { item = LINEN, count = 0 },                -- no count
        { item = LINEN, count = 2.5 },              -- not a whole count
        { item = LINEN },                           -- no count at all
        { item = BOLT, count = 2, recipe = "unknown" },   -- recipe not known
    }
    local claims, skipped = G.Claims(snap(), goals)
    t.eq(skipped, 6)
    t.eq(#claims, 1)
    t.eq(claims[1].amount, 8)
end

tests["goals: no list, an empty list or a list that is not a table claims nothing"] = function(t)
    local G = ns.ItemGoals
    local a, sa = G.Claims(snap(), nil)
    local b, sb = G.Claims(snap(), {})
    local c, sc = G.Claims(snap(), "junk")
    t.eq(#a, 0); t.eq(sa, 0)
    t.eq(#b, 0); t.eq(sb, 0)
    t.eq(#c, 0); t.eq(sc, 1, "a saved value that is no list is counted")
end

tests["goals: the source is registered as \"goals\" and reads the saved list"] = function(t)
    local _, addon = start({ { item = LINEN, count = 8 } })
    local r = addon.reservations.Current()
    t.eq(r.status, addon.Reservations.OK)
    local held = addon.Reservations.HeldIn(addon.Reservations.Grants(r), "bags")
    t.eq(held:Held(LINEN), 8)
end

tests["goals: an empty saved list gives status none"] = function(t)
    local _, addon = start({})
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE)
    local _, addon2 = start(nil)
    t.eq(addon2.reservations.Current().status, addon2.Reservations.NONE, "nothing saved at all")
end

tests["goals: bags not read with no goal is none; with a goal it is unavailable"] = function(t)
    local _, addon = start(nil, true)
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE, "no goal: nothing reserved")
    local _, addon2 = start({ { item = LINEN, count = 8 } }, true)
    t.eq(addon2.reservations.Current().status, addon2.Reservations.UNAVAILABLE, "a goal: can't say")
    local _, addon3 = start({ "junk" }, true)
    t.eq(addon3.reservations.Current().status, addon3.Reservations.UNAVAILABLE, "only an unread entry: still can't say")
end

-- Section 220, G-1. Fails before the repair: the source read the store as
-- "nothing saved" and was idle, so the status was "none".
tests["goals: with the store not open the status is unavailable, never none"] = function(t)
    for _, goals in ipairs({ { { item = LINEN, count = 8 } }, false }) do
        local label = goals and "a goal saved" or "nothing saved"
        local _, addon = unopened(goals or nil)
        t.ok(not (type(addon.store) == "table" and addon.store.opened), label .. ": the store is not open")
        local r = addon.Reservations.Evaluate(READ)
        t.eq(type(r.snapshot.bags), "table", label .. ": the bags were read")
        t.eq(r.status, addon.Reservations.UNAVAILABLE, label .. ": the goals can't be read")
        t.eq(r.why, ns.ItemGoals.SOURCE, label)
        t.eq(addon.Reservations.Grants(r), nil, label .. ": no grants to sell on")
    end
end

-- Section 220, G-2. Fails before the repair: #raw == 0 read both lists as
-- no goals, so the status was "none".
tests["goals: a list with a hole at 1 or only named entries is not taken for no goals"] = function(t)
    local cases = {
        { label = "a hole at 1", goals = { [2] = { item = LINEN, count = 8 } } },
        { label = "only a named entry", goals = { linen = { item = LINEN, count = 8 } } },
    }
    for _, case in ipairs(cases) do
        local _, addon = start(case.goals)
        local r = addon.reservations.Current()
        t.eq(type(r.snapshot.bags), "table", case.label .. ": the bags were read")
        t.eq(r.status, addon.Reservations.UNAVAILABLE, case.label .. ": can't say")
    end
    local G = ns.ItemGoals
    local claims, skipped = G.Claims(snap(), { { item = LINEN, count = 8 }, extra = { item = POTION, count = 2 } })
    t.eq(#claims, 1, "the listed goal claims")
    t.eq(skipped, 1, "the named entry is counted")
    local _, skipped2 = G.Claims(snap(), { [2] = { item = LINEN, count = 8 } })
    t.eq(skipped2, 1, "the entry past the hole is counted")
end

-- Section 220, G-3. Fails before the repair: the skipped count was dropped,
-- so the first two were "none" and the third "ok" with only the Linen held.
tests["goals: a skipped goal gives no reservations to sell on, bags read"] = function(t)
    local cases = {
        { label = "only an entry that can't be read", goals = { "junk" } },
        { label = "a recipe goal", goals = { { item = BOLT, count = 2, recipe = "Bolt of Linen Cloth" } } },
        { label = "a goal and an entry that can't be read", goals = { { item = LINEN, count = 8 }, "junk" } },
    }
    for _, case in ipairs(cases) do
        local _, addon = start(case.goals)
        local r = addon.reservations.Current()
        t.eq(type(r.snapshot.bags), "table", case.label .. ": the bags were read")
        t.eq(r.status, addon.Reservations.UNAVAILABLE, case.label .. ": can't say")
        t.eq(r.why, ns.ItemGoals.SOURCE, case.label)
        t.eq(addon.Reservations.Grants(r), nil, case.label .. ": no grants")
    end
end

-- Section 220, G-9. Fails before the repair: the second registration was
-- taken and dropped the active test, so the raising source was asked.
tests["reservations: a source name is registered once; nil removes it"] = function(t)
    local _, addon = start(nil)
    local R = addon.Reservations
    local function raises() error("asked") end
    R.Source("g9", raises, function() return false end)
    local ok, err = pcall(R.Source, "g9", raises)
    t.eq(ok, false, "a second registration is refused")
    t.ok(tostring(err):find("already registered", 1, true), tostring(err))
    t.eq(addon.reservations.Current().status, R.NONE, "the first stays, with its active test: idle")
    R.Source("g9", nil)
    R.Source("g9", raises)
    local r = addon.reservations.Current()
    t.eq(r.status, R.UNAVAILABLE, "removed, then registered anew: asked, and it raised")
    t.eq(r.why, "g9")
end

-- Section 220, G-9. Fails before the repair: an active() that raised or
-- answered nil counted as active, the source gave {}, and the status was
-- "none".
tests["reservations: an active test that raises or answers neither true nor false is unavailable"] = function(t)
    local cases = {
        { label = "raises", active = function() error("no") end },
        { label = "answers nil", active = function() return nil end },
        { label = "answers a word", active = function() return "yes" end },
    }
    for _, case in ipairs(cases) do
        local _, addon = start(nil)
        addon.Reservations.Source("g9", function() return {} end, case.active)
        local r = addon.reservations.Current()
        t.eq(r.status, addon.Reservations.UNAVAILABLE, case.label)
        t.eq(r.why, "g9", case.label)
    end
    local _, addon = start(nil)
    addon.Reservations.Source("g9", function() error("asked") end, function() return false end)
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE, "false: idle, not asked")
    local _, addon2 = start(nil)
    addon2.Reservations.Source("g9", function() return {} end, function() return true end)
    t.eq(addon2.reservations.Current().status, addon2.Reservations.NONE, "true: asked, nothing claimed")
end

-- Section 220: the goals source reads the saved data of the kernel that
-- evaluates, not the add-on's own. A second kernel with a goal saved holds it.
tests["goals: the source reads the evaluating kernel's saved goals"] = function(t)
    local _, addon = start(nil)
    local _, other = start({ { item = LINEN, count = 8 } })
    local r = addon.Reservations.Evaluate(READ, other)
    t.eq(r.status, addon.Reservations.OK, "the other kernel's goal is read")
    t.eq(addon.Reservations.HeldIn(addon.Reservations.Grants(r), "bags"):Held(LINEN), 8)
    t.eq(addon.Reservations.Evaluate(READ).status, addon.Reservations.NONE, "the add-on's own: no goal")
end

-------------------------------------------------------------------------------
-- The goal word
-------------------------------------------------------------------------------

tests["goal add: an item link and a count are saved for this character"] = function(t)
    local c = start(nil)
    local lines = say(c, "add " .. LINK .. " 8")
    t.eq(lines, { "Goal set: keep 8 x Linen Cloth." })
    t.eq(saved(c), { { item = LINEN, count = 8 } })
end

tests["goal add: an item ID works; adding it again changes the count"] = function(t)
    local c = start(nil)
    say(c, "add 2589 8")
    local lines = say(c, "add 2589 5")
    t.eq(lines, { "Goal set: keep 5 x Linen Cloth." })
    t.eq(saved(c), { { item = LINEN, count = 5 } }, "one goal, not two")
end

tests["goal add: no count, a bad count or no item says how, and saves nothing"] = function(t)
    local c = start(nil)
    local usage = ns.ItemGoals.USAGE
    t.eq(say(c, "add 2589"), { usage })
    t.eq(say(c, "add 2589 0"), { usage })
    t.eq(say(c, "add 2589 2.5"), { usage })
    t.eq(say(c, "add linen 4"), { usage })
    t.eq(say(c, "frobnicate"), { usage })
    t.eq(saved(c), nil, "nothing written")
end

tests["goal remove: takes it off, and says when it was not there"] = function(t)
    local c = start({ { item = LINEN, count = 8 }, { item = POTION, count = 2 } })
    t.eq(say(c, "remove " .. LINK), { "Linen Cloth is off your goals." })
    t.eq(saved(c), { { item = POTION, count = 2 } })
    t.eq(say(c, "remove 2589"), { "Linen Cloth is not one of your goals." })
end

tests["goal list: the goals in the order set, and what could not be read"] = function(t)
    local c = start({ { item = POTION, count = 2 }, { item = LINEN, count = 8 }, "junk" })
    t.eq(say(c, "list"), { "Your goals (2):", "2 x Lesser Healing Potion", "8 x Linen Cloth",
                           "1 saved goal could not be read and is skipped." })
    t.eq(say(c, ""), say(c, "list"), "the bare word lists too")
end

tests["goal add/remove: a saved entry that can't be read is kept, not lost"] = function(t)
    local c = start({ "junk", { item = LINEN, count = 8 } })
    say(c, "add 858 2")
    t.eq(saved(c), { "junk", { item = LINEN, count = 8 }, { item = POTION, count = 2 } })
    say(c, "remove 2589")
    t.eq(saved(c), { "junk", { item = POTION, count = 2 } })
end

tests["goal list: an empty list says how to add one"] = function(t)
    local c = start(nil)
    t.eq(say(c, "list"), { ns.ItemGoals.EMPTY })
end

tests["goal: a change is seen by the next evaluation"] = function(t)
    local c, addon = start(nil)
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE)
    say(c, "add 2589 8")
    local r = addon.reservations.Current()
    t.eq(r.status, addon.Reservations.OK)
    t.eq(addon.Reservations.HeldIn(addon.Reservations.Grants(r), "bags"):Held(LINEN), 8)
    say(c, "remove 2589")
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE)
end

return tests
