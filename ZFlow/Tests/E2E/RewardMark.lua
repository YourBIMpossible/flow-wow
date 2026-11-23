local _, ns = ...
-- The quest reward mark end to end (G14), on the whole add-on loaded on a
-- fake client, with the real class packs. Per lead section 236: a reward
-- choice with one upgrade; none an upgrade; item data late; the reads
-- absent; a read raising, then recovering; the window closed; the role
-- changed. Every read the verdict needs is set in each fixture (class,
-- level, dual wield, the worn head, each item's kind, stats, class,
-- subclass, level and the game's own marks). Look only: the last test puts
-- every acting call in place before the add-on is built and counts them.
-- Made-up items. Not tested in game.
local tests = {}

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, TOUGH, STRONG, WEAK = "item:21", "item:22", "item:23", "item:24"

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function choices(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { index = i, link = link } end
    return out
end

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: env (the fake's raw names), prepare(c) before the add-on is built,
-- role (spec.role saved for the character).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = opts.env })
    c.setSaved(ns.id.accountDB, {})
    local char = {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(TOUGH, helm({ [STA] = 10 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setWorn(1, WORN)
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function later(c) c.advance(2, 4) end

tests["reward mark: a choice with one upgrade - that one is marked"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2, "the strength helm for dps")
    t.eq(newProblems(addon), 0, "no problem listed")
end

tests["reward mark: none an upgrade - no mark"] = function(t)
    local c = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, WORN))
    c.fire("QUEST_COMPLETE")
    later(c)
    t.eq(c.rewardMarked(), nil)
end

tests["reward mark: item data late - the mark appears once it is read"] = function(t)
    local c = boot({ role = "dps" })
    c.setQuestChoices({ { index = 1, link = WEAK }, { index = 2 } })    -- the link not given yet
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), nil, "nothing while a choice is not read")
    c.setQuestChoices(choices(WEAK, "item:29"))                       -- a link, the item not loaded
    later(c)
    t.eq(c.rewardMarked(), nil, "nothing while an item is not loaded")
    c.setItem("item:29", helm({ [STR] = 10 }))
    later(c)
    t.eq(c.rewardMarked(), 2, "marked once loaded")
end

tests["reward mark: the reads absent - nothing, no error"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(nil)
    c.fire("QUEST_COMPLETE")
    later(c)
    t.eq(c.rewardMarked(), nil)
    c.fire("QUEST_FINISHED")
    t.eq(newProblems(addon), 0, "no problem listed")

    local c2, addon2 = boot({ role = "dps", prepare = function(cl)
        cl.questChoices = nil
        cl.markRewardChoice = nil
    end })
    c2.fire("QUEST_COMPLETE")
    later(c2)
    c2.fire("QUEST_FINISHED")
    t.eq(newProblems(addon2), 0, "no problem listed without the reads")
    t.eq(addon2:ModuleState(addon2.GearRewardMark.NAME), "started")
end

tests["reward mark: a read raising, then recovering"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.setQuestChoicesFails(true)
    c.fire("QUEST_COMPLETE")
    later(c)
    t.eq(c.rewardMarked(), nil, "no mark while the read raises")
    t.eq(addon.gearRewardMark.errors() > 0, true, "the failure is counted")
    t.eq(newProblems(addon), 1, "one problem for the one distinct error")
    c.setQuestChoicesFails(false)
    later(c)
    t.eq(c.rewardMarked(), 2, "marked once the read works again")
end

tests["reward mark: the window closed - the mark is cleared"] = function(t)
    local c = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2)
    c.fire("QUEST_FINISHED")
    t.eq(c.rewardMarked(), nil, "cleared")
    later(c)
    t.eq(c.rewardMarked(), nil, "and stays cleared")
end

tests["reward mark: the role changes - the mark follows it"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG, TOUGH))
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2, "strength for dps")
    t.eq(addon.settings:set("spec.role", "tank"), true)
    later(c)
    t.eq(c.rewardMarked(), 3, "stamina for a tank")
end

-- Look only (as SR-6, lead section 220): every acting call is in place
-- BEFORE the add-on is built. The game's own names that would take a
-- reward, complete or accept a quest, or click its buttons are put in the
-- fake's env and count their calls; every client function whose name holds
-- an acting word counts its calls; any acting name looked up on the client
-- is noted.
local ACTING_GAME = { "GetQuestReward", "CompleteQuest", "AcceptQuest", "DeclineQuest",
    "QuestRewardCompleteButton_OnClick", "QuestFrameCompleteQuestButton", "QuestInfoItem_OnClick",
    "QuestFrameRewardPanel_OnClick", "UseContainerItem", "EquipItemByName", "PickupItem" }
local ACTING_WORDS = { "getquestreward", "completequest", "acceptquest", "declinequest", "selectreward",
    "choosereward", "pickreward", "takereward", "clickreward", "rewardclick", "equipreward" }

local function acting(name)
    local low = name:lower()
    for _, word in ipairs(ACTING_WORDS) do
        if low:find(word, 1, true) then return true end
    end
    return false
end

tests["reward mark: look only - no acting call from any path"] = function(t)
    local called, looked = {}, {}
    local function record(name) return function() called[#called + 1] = name end end
    local env = { QuestInfoFrame = { rewardsFrame = { OnClick = record("QuestInfoFrame.rewardsFrame.OnClick") } } }
    for _, name in ipairs(ACTING_GAME) do env[name] = record(name) end
    local function prepare(c)
        for _, name in ipairs({ "getQuestReward", "selectReward", "chooseReward", "clickReward", "completeQuest",
                                "acceptQuest", "equipReward" }) do
            c[name] = record("client." .. name)
        end
        for name, value in pairs(c) do
            if type(name) == "string" and type(value) == "function" and acting(name) then
                c[name] = record("client." .. name)
            end
        end
        setmetatable(c, { __index = function(_, name)
            if type(name) == "string" and acting(name) then looked[#looked + 1] = name end
            return nil
        end })
    end
    local c, addon = boot({ role = "dps", env = env, prepare = prepare })
    c.setQuestChoices(choices(WEAK, STRONG, TOUGH))
    c.fire("QUEST_COMPLETE")
    t.eq(c.rewardMarked(), 2, "the mark was made")
    later(c)
    addon.settings:set("spec.role", "tank")
    later(c)
    c.fire("QUEST_FINISHED")
    t.eq(called, {}, "no acting call")
    t.eq(looked, {}, "no acting name looked up on the client")
end

return tests
