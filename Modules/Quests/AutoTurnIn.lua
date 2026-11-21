-- Finished quests are turned in for you when you talk to the NPC: Flow picks
-- the finished quest from their list, presses Complete, and takes the reward.
--   * Several rewards to choose from: Flow stops and lets you pick (the big
--     green arrow marks its pick, Gear/QuestRewards.lua).
--   * A quest that takes gold from you: left to you.
--   * A hand-in your route holds (it waits for a step off the route, or a
--     need you don't have yet): left to you, saying why.
--   * Hold Shift while you talk to the NPC to do it yourself this time.
-- On by default; the box in /flow settings, or /flow turnin on|off.
--
-- New quests are accepted for you too (since 0.35.106; before, only quests
-- your party shared were): after any turn-ins, Flow opens the NPC's first
-- new quest (not grey, not repeatable) and accepts it. A quest offered any
-- other way (an item that starts one) is accepted too. Not with your quest
-- log full, and not quests another player offers (QuestShare.lua does your
-- party's). Hold Shift to do it yourself. /flow accept on|off.

local _, ns = ...
local AT = {}
ns.autoTurnIn = AT

function AT.AcceptEnabled()
    if ns.db.quests.autoAccept == false then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    return true
end

-- The first new quest worth opening in an NPC's list
-- ({ { id, trivial, repeatable }, ... }): its position and id, or nil.
-- Grey (trivial) and repeatable quests are left to you.
function AT.PickAvailable(list)
    for i, q in ipairs(list or {}) do
        if not q.trivial and not q.repeatable then return i, q.id end
    end
end

-- Accept the quest on screen? Only when it's on, not one another player
-- offers, and with room in your quest log (nil: can't tell, go ahead).
function AT.ShouldAccept(enabled, fromPlayer, freeSlots)
    return (enabled and not fromPlayer and (freeSlots == nil or freeSlots > 0)) and true or false
end

local function freeSlots() return ns.quests and ns.quests.FreeSlots and ns.quests:FreeSlots() end
local function canTakeMore() return AT.ShouldAccept(AT.AcceptEnabled(), false, freeSlots()) end

function AT.Enabled()
    if ns.db.quests.autoTurnIn == false then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    return true
end

-- Which reward to take: 0 when there's nothing to choose, 1 when there's
-- only one, nil (you choose) when there are several.
function AT.Reward(nChoices)
    nChoices = nChoices or 0
    if nChoices == 0 then return 0 end
    if nChoices == 1 then return 1 end
    return nil
end

-- Pure: the hand-ins your route holds (N.blockedGoals: a hand-in waiting for
-- a hard need, or for a step that's off the route; a soft need never holds)
-- -> { ids = { [questID] = why }, titles = { [title] = why } }. Not your
-- party's hand-ins (helping): those are theirs.
function AT.Held(blocked)
    local held = { ids = {}, titles = {} }
    for _, g in ipairs(blocked or {}) do
        local id = type(g.key) == "string" and g.key:match("(%d+):done$")
        if id and g.blockedBy and not g.helping then
            held.ids[tonumber(id)] = g.blockedBy
            if g.title then held.titles[g.title] = g.blockedBy end
        end
    end
    return held
end

-- Pure: why the route holds this quest's hand-in, or nil.
--   q: { qid (the quest's id, when the client gives it), title }
function AT.HeldWhy(q, held)
    if not (q and held) then return nil end
    return (q.qid and held.ids[q.qid]) or (q.title and held.titles[q.title]) or nil
end

-- The first finished quest in an NPC's list ({ { id, complete, qid, title }, ... })
-- that your route doesn't hold (held: AT.Held): its position and id, or nil.
function AT.PickFinished(list, held)
    for i, q in ipairs(list or {}) do
        if q.complete and not AT.HeldWhy(q, held) then return i, q.id end
    end
end

local function routeHeld() return AT.Held(ns.nav and ns.nav.blockedGoals) end

local function log(what) ns:Log("quests", "auto turn-in: " .. what) end

local function logAccept(what) ns:Log("quests", "auto accept: " .. what) end

-- Gossip NPC (the chat window with several options): open a finished quest;
-- with none, open a new one (accepted on the next page, QUEST_DETAIL).
local function gossipTurnIn(G)
    if G and G.GetActiveQuests and G.SelectActiveQuest then
        local list = {}
        for _, q in ipairs(G.GetActiveQuests() or {}) do
            list[#list + 1] = { id = q.questID, qid = q.questID, complete = q.isComplete, title = q.title }
        end
        local i, id = AT.PickFinished(list, routeHeld())
        if id then log("opening " .. tostring(list[i].title)); G.SelectActiveQuest(id); return true end
    elseif GetGossipActiveQuests and SelectGossipActiveQuest then
        -- Older clients: name, level, trivial, complete, ... (6 values per quest).
        local raw, list = { GetGossipActiveQuests() }, {}
        for k = 1, #raw, 6 do list[#list + 1] = { id = (k + 5) / 6, complete = raw[k + 3], title = raw[k] } end
        local i = AT.PickFinished(list, routeHeld())
        if i then log("opening " .. tostring(list[i].title)); SelectGossipActiveQuest(i); return true end
    end
end
local function gossipNew(G)
    if G and G.GetAvailableQuests and G.SelectAvailableQuest then
        local list = {}
        for _, q in ipairs(G.GetAvailableQuests() or {}) do
            list[#list + 1] = { id = q.questID, title = q.title, trivial = q.isTrivial,
                                repeatable = q.repeatable or (q.frequency and q.frequency > 0) }
        end
        local i, id = AT.PickAvailable(list)
        if id then logAccept("opening " .. tostring(list[i].title)); G.SelectAvailableQuest(id) end
    elseif GetGossipAvailableQuests and SelectGossipAvailableQuest then
        -- Older clients: name, level, trivial, frequency, repeatable, legendary, ignored (7 per quest).
        local raw, list = { GetGossipAvailableQuests() }, {}
        for k = 1, #raw, 7 do
            list[#list + 1] = { id = (k + 6) / 7, title = raw[k], trivial = raw[k + 2], repeatable = raw[k + 4] }
        end
        local i = AT.PickAvailable(list)
        if i then logAccept("opening " .. tostring(list[i].title)); SelectGossipAvailableQuest(i) end
    end
end
ns:On("GOSSIP_SHOW", function()
    local G = C_GossipInfo
    if AT.Enabled() and gossipTurnIn(G) then return end
    if canTakeMore() then gossipNew(G) end
end)

-- Quest NPC with a plain list of quests (no gossip): a finished one, else a new one.
ns:On("QUEST_GREETING", function()
    if AT.Enabled() and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        local list = {}
        for i = 1, GetNumActiveQuests() or 0 do
            local title, complete = GetActiveTitle(i)
            list[#list + 1] = { id = i, complete = complete, title = title }
        end
        local i = AT.PickFinished(list, routeHeld())
        if i then log("opening " .. tostring(list[i].title)); SelectActiveQuest(i); return end
    end
    if not (canTakeMore() and GetNumAvailableQuests and GetAvailableTitle and SelectAvailableQuest) then return end
    local list = {}
    for i = 1, GetNumAvailableQuests() or 0 do
        local trivial, frequency, repeatable
        if GetAvailableQuestInfo then trivial, frequency, repeatable = GetAvailableQuestInfo(i) end
        list[#list + 1] = { id = i, title = GetAvailableTitle(i), trivial = trivial,
                            repeatable = repeatable or (type(frequency) == "number" and frequency > 0) }
    end
    local i = AT.PickAvailable(list)
    if i then logAccept("opening " .. tostring(list[i].title)); SelectAvailableQuest(i) end
end)

-- A quest offered to you (from an NPC, or an item that starts one): accept it.
ns:On("QUEST_DETAIL", function()
    local fromPlayer = UnitExists("npc") and UnitIsPlayer("npc") and true or false
    if not AT.ShouldAccept(AT.AcceptEnabled(), fromPlayer, freeSlots()) then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then return end   -- the game took it already
    logAccept("accepted " .. tostring(GetTitleText and GetTitleText()))
    AcceptQuest()
end)

-- "Have you finished?": press Complete (not for quests that take your gold).
ns:On("QUEST_PROGRESS", function()
    if not (AT.Enabled() and IsQuestCompletable and IsQuestCompletable()) then return end
    -- A hand-in your route holds (an NPC with one quest opens it straight away): left to you.
    local why = AT.HeldWhy({ qid = GetQuestID and GetQuestID() or nil, title = GetTitleText and GetTitleText() }, routeHeld())
    if why then
        ns:Print("not handing in " .. tostring(GetTitleText and GetTitleText()) .. " for you: your route holds it (" .. why .. ")")
        log("left to you (the route holds it): " .. tostring(GetTitleText and GetTitleText()))
        return
    end
    if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then
        log("left to you (it takes gold): " .. tostring(GetTitleText and GetTitleText()))
        return
    end
    CompleteQuest()
end)

-- The reward page: take it, unless there's a choice to make.
ns:On("QUEST_COMPLETE", function()
    if not AT.Enabled() then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    local pick = AT.Reward(n)
    local title = GetTitleText and GetTitleText()
    if not pick then
        ns:Print("pick your reward for " .. tostring(title) .. " (the green arrow is Flow's pick for you)")
        log("waiting for you to pick a reward: " .. tostring(title))
        return
    end
    log("turned in " .. tostring(title))
    GetQuestReward(pick)
end)

ns.commands.accept = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.autoAccept = (arg == "on") end
    ns:Print("accept new quests for you: " .. (ns.db.quests.autoAccept == false and "off" or "on")
        .. "  (not grey or repeatable ones; hold Shift at the NPC to do it yourself; /flow accept on|off)")
end

ns.commands.turnin = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.autoTurnIn = (arg == "on") end
    ns:Print("turn in finished quests for you: " .. (ns.db.quests.autoTurnIn == false and "off" or "on")
        .. "  (hold Shift at the NPC to do it yourself; /flow turnin on|off)")
end
