local _, ns = ...

-- Tests for ZFlow/Gear/RewardMark.lua (G14): the quest reward choice that is
-- the best upgrade for the chosen role carries a mark; the player picks.
-- Fake client (setQuestChoices, setItem, setWorn, markRewardChoice,
-- rewardMarked) and a real kernel. Made-up items; not tested in game.

local RM = ns.GearRewardMark
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, TOUGH, STRONG, WEAK, PLATE = "item:11", "item:12", "item:13", "item:14", "item:15"

local function packs()
    return { WARRIOR = {
        weights = {
            dps = { evidence = "first guess", values = { [STR] = 1, [STA] = 0.35 } },
            tank = { evidence = "first guess", values = { [STA] = 1, [STR] = 0.6 } },
        },
        proficiency = { evidence = "first guess", [4] = { [0] = true, [1] = true, [2] = true, [3] = true } },
    } }
end

local function helm(stats, unmet)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = unmet or {} }
end

-- Every read the verdict needs: class, level, the worn head, the items.
local function client()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(TOUGH, helm({ [STA] = 10 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(PLATE, helm({ [STR] = 30 }, { "Plate" }))
    c.setWorn(1, WORN)
    return c
end

local function choices(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { index = i, link = link } end
    return out
end

tests["reward mark: the best upgrade for the chosen role is the pick"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, STRONG, TOUGH))
    t.eq(RM.Pick(c, packs(), "dps"), 2, "strength for dps")
    t.eq(RM.Pick(c, packs(), "tank"), 3, "stamina for a tank")
end

tests["reward mark: no role chosen - the biggest upgrade for any role"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, TOUGH, STRONG))
    t.eq(RM.Pick(c, packs(), ""), 3)
end

tests["reward mark: none an upgrade - no pick"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, WORN))
    local pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.none)
end

tests["reward mark: an item you cannot use is never the pick"] = function(t)
    local c = client()
    c.setQuestChoices(choices(PLATE, TOUGH))
    t.eq(RM.Pick(c, packs(), "dps"), 2, "the usable upgrade, not the bigger plate one")
    c.setQuestChoices(choices(PLATE, WEAK))
    local pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.none)
end

tests["reward mark: a choice not read yet - no pick, never a guess"] = function(t)
    local c = client()
    c.setQuestChoices({ { index = 1, link = STRONG }, { index = 2 } })
    local pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.waiting)
    c.setQuestChoices(choices(STRONG, "item:99"))    -- a link, the item not loaded
    pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.waiting)
end

tests["reward mark: the choices not readable - no pick"] = function(t)
    local c = client()
    c.setQuestChoices(nil)
    local pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.unread)
    pick, why = RM.Pick({}, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.unread)
end

tests["reward mark: one choice only, or two equal upgrades - no pick"] = function(t)
    local c = client()
    c.setQuestChoices(choices(STRONG))
    local pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.single)
    c.setItem("item:16", helm({ [STR] = 10 }))
    c.setQuestChoices(choices(STRONG, "item:16"))
    pick, why = RM.Pick(c, packs(), "dps")
    t.eq(pick, nil)
    t.eq(why, RM.WHY.tie)
end

tests["reward mark: the module marks on QUEST_COMPLETE and clears on QUEST_FINISHED"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, STRONG))
    local k = ns.Kernel({}, c)
    local api = RM.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(k:ModuleState(RM.NAME), "started")
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2)
    t.eq(api.marked(), 2)
    c.fire("QUEST_FINISHED")
    t.eq(c.rewardMarked(), nil)
    t.eq(api.marked(), nil)
end

-- RM-2 (lead section 275): with fewer than 2 choices there is nothing to
-- choose between: no 1 s repeat is kept. Two choices still repeat.
tests["reward mark: one choice - no repeat after QUEST_COMPLETE; two choices repeat"] = function(t)
    local function reads(rows)
        local c = client()
        c.setQuestChoices(rows)
        local read, n = c.questChoices, 0
        c.questChoices = function(...)
            n = n + 1
            return read(...)
        end
        local k = ns.Kernel({}, c)
        RM.Declare(k, packs())
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
        c.fire("QUEST_COMPLETE")
        local before = n
        c.advance(3, 6)
        return n - before
    end
    t.eq(reads(choices(STRONG)), 0, "one choice: nothing read again")
    t.ok(reads(choices(WEAK, STRONG)) > 0, "two choices: read again each second")
end

-- LF-1: one choice read at QUEST_COMPLETE, two read once an item's data
-- arrives (GET_ITEM_INFO_RECEIVED): the mark follows and the repeat starts.
tests["reward mark: a choice count that grows later - marked, and the repeat starts"] = function(t)
    local c = client()
    c.setQuestChoices(choices(STRONG))
    local read, n = c.questChoices, 0
    c.questChoices = function(...)
        n = n + 1
        return read(...)
    end
    local k = ns.Kernel({}, c)
    RM.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), nil, "one choice: no mark")
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("GET_ITEM_INFO_RECEIVED")
    t.eq(c.rewardMarked(), 2, "two choices read late: the upgrade is marked")
    local before = n
    c.advance(3, 6)
    t.ok(n - before > 0, "the repeat started")
    c.fire("QUEST_FINISHED")
    c.fire("GET_ITEM_INFO_RECEIVED")
    t.eq(c.rewardMarked(), nil, "closed: item data does not mark")
end

tests["reward mark: switched off, nothing is marked"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, STRONG))
    local k = ns.Kernel({}, c)
    RM.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(k.settings:set(RM.SETTING, false), true)
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), nil)
end

-- G14 coin (section 393): no choice is an upgrade - the choice that sells
-- for the most carries a coin instead ("take this to sell"). Prices from
-- itemInfo().sellPrice; any price not read, a tie, or nothing sells: no coin.
local function prices(c, rows)
    c.setItemInfo(rows)
end

tests["reward coin: none an upgrade - the best sell price is the coin"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, WORN))
    prices(c, { [14] = { sellPrice = 30 }, [11] = { sellPrice = 75 } })
    t.eq(type(RM.Coin), "function", "GearRewardMark.Coin")
    if type(RM.Coin) ~= "function" then return end
    t.eq(RM.Coin(c), 2)
end

tests["reward coin: a price not read, a tie, or nothing sells - no coin"] = function(t)
    if type(RM.Coin) ~= "function" then return t.ok(false, "GearRewardMark.Coin") end
    local c = client()
    c.setQuestChoices(choices(WEAK, WORN))
    prices(c, { [14] = { sellPrice = 30 } })
    t.eq(RM.Coin(c), nil, "one price not read: never a guess")
    prices(c, { [14] = { sellPrice = 30 }, [11] = { sellPrice = 30 } })
    t.eq(RM.Coin(c), nil, "a tie")
    prices(c, { [14] = { sellPrice = 0 }, [11] = { sellPrice = 0 } })
    t.eq(RM.Coin(c), nil, "nothing sells")
    c.setQuestChoices(nil)
    t.eq(RM.Coin(c), nil, "the choices not readable")
end

tests["reward coin: the module shows the coin when nothing is an upgrade"] = function(t)
    local c = client()
    c.setQuestChoices(choices(WEAK, WORN))
    prices(c, { [14] = { sellPrice = 30 }, [11] = { sellPrice = 75 } })
    local k = ns.Kernel({}, c)
    RM.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2)
    t.eq(c.rewardMarkKind and c.rewardMarkKind(), "coin")
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2)
    t.eq(c.rewardMarkKind and c.rewardMarkKind(), "upgrade", "an upgrade: the arrow, not the coin")
end

return tests
