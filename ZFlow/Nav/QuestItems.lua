local _, ns = ...
-- Z-Flow quest item on the quest arrow (S42, lead sections 169 and 172):
-- a quest that hands the player something to use (a totem for a well,
-- dust for a stone) gets one line on its quest arrow step:
-- "Use <item> (in your bags)". Ported from legacy Flow 0.35.377
-- (Modules/Nav/QuestItems.lua), whose Flow Tracker had a button for it.
-- Research: WoW/from-zen/RESEARCH-S42.md.
--
-- LOOK ONLY (lead section 169 A). Legacy Flow's item was a secure button:
-- a click used the item. Using an item is a protected action, so here the
-- item is only named. Nothing uses, clicks or binds anything, no secure
-- frame is made, and UseQuestLogSpecialItem is never called. The click is
-- parked behind G23. Z-Flow has no tracker (169 B): the host is the arrow.
--
-- Which item, as legacy Flow's QI.ItemOf, the game's own part only (169 C:
-- no Questie fallback): the quest's own item as the game gives it, shown
-- only when it is in the bags and using it does something (legacy Flow
-- 0.35.332: an item used on something else is not shown). Unknown stays
-- unknown: a count, a use or a name the client does not give is never
-- read as 0, as "no use" or as an item number.
--
-- The client reads (Core/Client.lua, S42) are FIRST GUESSES, not seen in
-- game on 1.60.1 and not seen in an installed addon (169 D):
--   client.questItem(questID) -> { id, link } or nil
--   client.itemCount(item)    -> a whole number, or nil
--   client.itemUse(item)      -> true / false, or nil
--   client.itemInfo(item).name (F5)
--
-- N.QuestItemOf(special, count, use) -> item id, or nil and why:
--   "no quest item", "count unknown", "not in your bags", "use unknown",
--   "no use"
-- N.QuestItemLine(name) -> "Use <name> (in your bags)", or QI.PLAIN when
--   the name is not known or cannot be shown as it is
-- N.QuestItemWith(step, line) -> a copy of step with use = line; step
--   itself when there is no line. UI/Arrow.lua shows `use` as one line
--   under the step's detail (for a step in words: last).
--
-- QI.Declare(k, diag) -> api
--   api.forQuest(questID) -> { id, name, count, line }, or nil and why.
--                       Kept QI.KEEP seconds; read again when the bags
--                       change (BAG_UPDATE_DELAYED), as legacy Flow.
--   api.with(step)     the quest step with its item's line, or the step
--                       itself (no quest, or no item to name)
--   api.lines()        what the word QI.WORD prints
--   ns.use("questItems") -> { With = api.with, For = api.forQuest }
-- No setting is read.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.QuestItems = N.QuestItems or {}
local QI = N.QuestItems

QI.NAME = "questItems"
QI.WORD = "questitems"
QI.HELP = "the quests' own items named on the quest arrow"
QI.KEEP = 2            -- seconds one quest's answer is kept (legacy Flow)
QI.LINE = "Use %s (in your bags)"
QI.PLAIN = "Use the quest's item (in your bags)"

function N.QuestItemOf(special, count, use)
    if special == nil then return nil, "no quest item" end
    if type(count) ~= "number" then return nil, "count unknown" end
    if count <= 0 then return nil, "not in your bags" end
    if use == nil then return nil, "use unknown" end
    if use ~= true then return nil, "no use" end
    return special
end

function N.QuestItemLine(name)
    if type(name) == "string" and name ~= "" and not name:find("[%c|]") then
        return QI.LINE:format(name)
    end
    return QI.PLAIN
end

function N.QuestItemWith(step, line)
    if type(step) ~= "table" or type(line) ~= "string" then return step end
    local out = {}
    for key, v in pairs(step) do out[key] = v end
    out.use = line
    return out
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function QI.Declare(k, diag)
    local api = {}
    local ctx
    local cache = {}           -- [questID] = { at, item (false: none), why }

    function api.forQuest(questID)
        if not ctx or questID == nil then return nil end
        local client = ctx.client
        local now = ask(client, "uptime")
        local kept = cache[questID]
        if kept and type(now) == "number" and type(kept.at) == "number"
            and now >= kept.at and now - kept.at < QI.KEEP then
            return kept.item or nil, kept.why
        end
        local special = ask(client, "questItem", questID)
        local id = type(special) == "table" and special.id or nil
        local count, use
        if id ~= nil then
            count = ask(client, "itemCount", id)
            use = ask(client, "itemUse", id)
        end
        local got, why = N.QuestItemOf(id, count, use)
        local item
        if got then
            local info = ask(client, "itemInfo", got)
            local name = type(info) == "table" and type(info.name) == "string" and info.name or nil
            item = { id = got, name = name, count = count, line = N.QuestItemLine(name) }
        end
        cache[questID] = { at = now, item = item or false, why = why }
        return item, why
    end

    function api.with(step)
        if type(step) ~= "table" or step.quest == nil then return step end
        local item = api.forQuest(step.quest)
        if not item then return step end
        return N.QuestItemWith(step, item.line)
    end

    function api.lines()
        if not ctx then return { "not started" } end
        local rows = N.QuestLogRows and N.QuestLogRows(ctx.client) or nil
        if type(rows) ~= "table" then return { "your quest log could not be read" } end
        local out = { "quests with their own item:" }
        for _, row in ipairs(rows) do
            local item, why = api.forQuest(row.id)
            if item then
                out[#out + 1] = ("  %s: %s (%d in your bags)"):format(row.title, item.name or "the quest's item", item.count)
            elseif why ~= "no quest item" then
                out[#out + 1] = ("  %s: not shown (%s)"):format(row.title, tostring(why))
            end
        end
        if #out == 1 then out[#out + 1] = "  none in your log" end
        return out
    end

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    k:Module({
        name = QI.NAME,
        needs = { "client", "bus" },
        provides = {
            With = function(step) return api.with(step) end,
            For = function(questID) return api.forQuest(questID) end,
        },
        start = function(c)
            ctx = c
            -- The bags changed: the quest handed its item over, or it was used up.
            c.bus:on(QI.NAME, "BAG_UPDATE_DELAYED", function() cache = {} end)
        end,
        stop = function() cache = {} end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[QI.WORD] = function()
            if not ctx then return end
            local lines = api.lines()
            say(lines[1])
            for i = 2, #lines do ctx.client.print(lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[QI.WORD] = QI.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.questItems = QI.Declare(ns, ns.diag)
