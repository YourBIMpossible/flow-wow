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

-- P-QOL: Flow showed the best pick when you were offered the quest as
-- well as when you turned it in (Modules/Gear/QuestRewards.lua header).
tests["reward mark: the quest offered (detail window) - the best pick is marked there too"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_DETAIL")
    t.eq(c.rewardMarked(), 2, "marked on the offer")
    t.eq(newProblems(addon), 0)
    c.fire("QUEST_FINISHED")
    t.eq(c.rewardMarked(), nil, "cleared when the window closes")
end

tests["reward mark: the offer accepted - the mark goes with the window"] = function(t)
    local c = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_DETAIL")
    t.eq(c.rewardMarked(), 2)
    c.fire("QUEST_ACCEPTED", 1, 101)
    t.eq(c.rewardMarked(), nil, "cleared on accept")
    later(c)
    t.eq(c.rewardMarked(), nil, "and stays cleared")
end

tests["reward mark: the setting off - nothing on the offer either"] = function(t)
    local c, addon = boot({ role = "dps" })
    addon.settings:set("gear.rewardMark", false)
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_DETAIL")
    later(c)
    t.eq(c.rewardMarked(), nil)
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

-- Parity row C-37, the data half (lead section 668): for each reward
-- choice, what it is for each of your class's specs, and its sell price,
-- with the best seller marked. As Flow's Modules/Gear/QuestRewards.lua
-- (:147-149) and SpecBadge.lua (:35, :100): a badge for each spec on each
-- choice, and a coin on the best to sell. The marks are the drawing
-- lane's. Fails before: there is no Board.
local function board(addon) return addon.use(ns.GearRewardMark.NAME).Board() end

tests["reward board: each choice's verdict for each spec, and its sell price"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setItemInfo({ [22] = { sellPrice = 40 }, [23] = { sellPrice = 90 }, [24] = { sellPrice = 15 } })
    c.setQuestChoices(choices(WEAK, STRONG, TOUGH))
    c.fire("QUEST_COMPLETE")
    local b = board(addon)
    t.ok(type(b) == "table", "a board while the window is open")
    if type(b) ~= "table" then return end
    t.eq(b.roles, { "dps", "tank" }, "the class's specs, sorted")
    t.eq(b.chosen, "dps")
    t.eq(#b.choices, 3)
    t.eq(b.choices[1].index, 1)
    t.eq(b.choices[1].roles, { dps = "worse", tank = "worse" }, "the weak helm is worse for both")
    t.eq(b.choices[2].roles.dps, "upgrade", "strength for dps")
    t.eq(b.choices[3].roles.tank, "upgrade", "stamina for a tank")
    t.eq(b.choices[2].sell, 90)
    t.eq(b.bestSell, 2, "the strength helm sells for the most")
    t.eq(newProblems(addon), 0)
end

-- Zen-3's review of C-37 (lead section 701): a choice's verdict follows the
-- tooltip's rule (Gear/Tooltip.lua T.Lines): an upgrade or a worse that
-- would print as 0.0 is "same"; with no finite delta there is no verdict,
-- and the spec is left out. Fails before: a tiny worse stayed "worse".
tests["reward board: the verdict follows the tooltip's rule"] = function(t)
    local V = ns.GearRewardMark.Verdict
    local same = ns.GearTooltip.SAME
    t.eq(V({ verdict = "worse", delta = -0.01 }), "same", "a tiny worse")
    t.eq(V({ verdict = "upgrade", delta = 0.01 }), "same", "a tiny upgrade")
    t.eq(V({ verdict = "upgrade", delta = same }), "upgrade")
    t.eq(V({ verdict = "worse", delta = -same }), "worse")
    t.eq(V({ verdict = "same", delta = 0 }), "same")
    t.eq(V({ verdict = "upgrade" }), nil, "no delta: no verdict")
    t.eq(V({ verdict = "worse", delta = 0 / 0 }), nil, "not a number: no verdict")
    t.eq(V({ verdict = "none", delta = 1 }), nil)
    t.eq(V(nil), nil)
end

tests["reward board: a price not read, or two the same, marks no best seller"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setItemInfo({ [23] = { sellPrice = 90 } })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_COMPLETE")
    t.eq(board(addon).bestSell, nil, "one price not read")
    t.eq(board(addon).choices[1].sell, nil)
    c.setItemInfo({ [23] = { sellPrice = 90 }, [24] = { sellPrice = 90 } })
    t.eq(board(addon).bestSell, nil, "a tie")
end

tests["reward board: a choice not read yet has no verdict, and no window has no board"] = function(t)
    local c, addon = boot({ role = "dps" })
    t.eq(board(addon), nil, "no reward window open")
    c.setQuestChoices({ { index = 1, link = WEAK }, { index = 2 } })
    c.fire("QUEST_COMPLETE")
    local b = board(addon)
    t.eq(b.choices[2].roles, {}, "not read: no verdict, never a guess")
    t.eq(b.choices[1].roles.dps, "worse")
    c.setQuestChoices(nil)
    t.eq(board(addon), nil, "the choices not read")
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_FINISHED")
    t.eq(board(addon), nil, "the window closed")
end

-- Parity row C-03 (lead section 704), as Flow's Modules/Quests/
-- AutoTurnIn.lua (:190-201): at a reward choice the add-on stops and asks;
-- nothing is picked. One chat line, once a window, with the board's words.
-- Fails before: nothing is said.
local function asked(c)
    local out = {}
    for _, l in ipairs(c.printed) do
        if tostring(l):find("Pick your reward", 1, true) then out[#out + 1] = l end
    end
    return out
end

tests["reward ask: a choice at the turn-in is said once, with the best for your spec and the best to sell"] = function(t)
    local c = boot({ role = "dps" })
    c.setItemInfo({ [23] = { name = "Strong Helm", sellPrice = 90 }, [24] = { name = "Weak Helm", sellPrice = 15 } })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.printed = {}
    c.fire("QUEST_COMPLETE")
    later(c)
    later(c)
    local lines = asked(c)
    t.eq(#lines, 1, "once")
    t.ok(lines[1] ~= nil and lines[1]:find(ns.GearRewardMark.ASK_BEST:format("Strong Helm", "damage"), 1, true) ~= nil,
        tostring(lines[1]))
    t.ok(lines[1] ~= nil and lines[1]:find(ns.GearRewardMark.ASK_SELL:format("Strong Helm"), 1, true) ~= nil,
        "and to sell")
end

tests["reward ask: the offer, one reward, or the mark switched off says nothing"] = function(t)
    local c, addon = boot({ role = "dps" })
    c.setQuestChoices(choices(WEAK, STRONG))
    c.printed = {}
    c.fire("QUEST_DETAIL")
    later(c)
    t.eq(asked(c), {}, "the offer is no turn-in")
    c.fire("QUEST_FINISHED")
    c.setQuestChoices(choices(WEAK))
    c.fire("QUEST_COMPLETE")
    later(c)
    t.eq(asked(c), {}, "one reward: nothing to choose")
    c.fire("QUEST_FINISHED")
    addon.settings:set(ns.GearRewardMark.SETTING, false)
    c.setQuestChoices(choices(WEAK, STRONG))
    c.fire("QUEST_COMPLETE")
    later(c)
    t.eq(asked(c), {}, "switched off")
end

tests["reward ask: the line names no choice it cannot read, and never picks"] = function(t)
    local RM = ns.GearRewardMark
    t.eq(RM.AskLine(nil, function() return nil end, "dps"), RM.ASK)
    local board = { chosen = "dps", choices = { { index = 1, roles = { dps = "worse" } },
        { index = 2, roles = { dps = "upgrade" } } }, bestSell = 1 }
    t.eq(RM.AskLine(board, function() return nil end, "dps"), RM.ASK, "names not read: the plain ask")
    t.eq(RM.AskLine(board, function(i) return ({ "A", "B" })[i] end, "dps"),
        RM.ASK .. " " .. RM.ASK_BEST:format("B", "damage") .. " " .. RM.ASK_SELL:format("A"))
end

-- C-03 follow-up (lead sections 720/721): the line says the role's word
-- from Rotation/Role.lua's Ro.WORDS ("damage", "healing", "tanking"),
-- never its key ("dps"). Fails before: "for dps".
tests["reward ask: the role is named by its word, not its key"] = function(t)
    local RM = ns.GearRewardMark
    local function line(role)
        local board = { chosen = role, choices = { { index = 1, roles = { [role] = "upgrade" } } } }
        return RM.AskLine(board, function() return "Helm" end, role)
    end
    t.eq(line("dps"), RM.ASK .. " Helm is the best upgrade for damage.")
    t.eq(line("heal"), RM.ASK .. " Helm is the best upgrade for healing.")
    t.eq(line("tank"), RM.ASK .. " Helm is the best upgrade for tanking.")
    t.eq(line("dps"):find("for dps", 1, true), nil, "never the key")
    t.eq(line("odd"), RM.ASK, "a role with no word: no best line")
end

return tests
