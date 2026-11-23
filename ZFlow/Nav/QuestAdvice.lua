local _, ns = ...

-- Quest advice (lead section 354 item 4, P-QUEST groundwork): words about
-- the player's own quest log, shown as advisor prompts.
--   ready to hand in   one prompt naming the quests that are complete in
--                      the log: "Ready to hand in: A, B". It goes when the
--                      player has handed them in, or the setting is off.
-- TEXT ONLY. Nothing here accepts, shares, hands in or abandons a quest,
-- picks a reward or talks to anyone: the player does all of that. The rows
-- that act stay held for the owner.
--
-- A log that cannot be read says nothing new: the prompt stays as it was,
-- and none is made up.
--
-- Pure parts:
--   A.Ready(rows)          the titles complete and not failed, log order,
--                          each title once
--   A.Names(titles[, max]) "A, B, C and 2 more"; nil for none
--   A.TurnInText(rows)     the hand-in line, or nil when none is ready
--
-- Reads: client.questLog() through ns.Nav.QuestLogRows. Writes: none.
-- Setting (char, on by default): general.questTurnIn "Quests ready to hand in".

local A = {}
ns.QuestAdvice = A

A.NAME = "questAdvice"
A.TURN_IN_SETTING = "general.questTurnIn"
A.TURN_IN_PROMPT = "quest.turnIn"
A.PRIORITY = 1
-- No more titles than this are named in one line.
A.MAX_NAMES = 3

A.TURN_IN = "Ready to hand in: %s"
A.MORE = "%s and %d more"

function A.Ready(rows)
    local out, seen = {}, {}
    if type(rows) ~= "table" then return out end
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.complete == true and r.failed ~= true
            and type(r.title) == "string" and r.title ~= "" and not seen[r.title] then
            seen[r.title] = true
            out[#out + 1] = r.title
        end
    end
    return out
end

function A.Names(titles, max)
    if type(titles) ~= "table" or #titles == 0 then return nil end
    if type(max) ~= "number" or max < 1 then max = A.MAX_NAMES end
    local shown = {}
    for i = 1, math.min(#titles, max) do shown[i] = tostring(titles[i]) end
    local line = table.concat(shown, ", ")
    if #titles > #shown then return A.MORE:format(line, #titles - #shown) end
    return line
end

function A.TurnInText(rows)
    local names = A.Names(A.Ready(rows))
    if names == nil then return nil end
    return A.TURN_IN:format(names)
end

local LOG_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }

function A.Declare(k)
    local api = {}
    local cancels = {}

    k:Module({
        name = A.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = { {
            key = A.TURN_IN_SETTING, scope = "char", type = "bool", default = true,
            label = "Quests ready to hand in",
            help = "Names the quests in your log that are complete, so you remember to hand them in. "
                .. "It reads your quest log only and hands nothing in.",
            group = "general",
            synonyms = { "quest", "quests", "turn in", "hand in", "complete", "advice" },
        } },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(advisor) ~= "table" then return end
            -- The last log read that answered, and the line shown for it.
            local last, shown

            local function refresh()
                local rows = ns.Nav.QuestLogRows(ctx.client)
                if type(rows) == "table" then last = rows end
                local text
                if ctx.settings:get(A.TURN_IN_SETTING) ~= false then text = A.TurnInText(last) end
                if text == shown then return end
                if text then advisor.Add(A.TURN_IN_PROMPT, text, A.PRIORITY) else advisor.Remove(A.TURN_IN_PROMPT) end
                shown = text
            end

            for _, ev in ipairs(LOG_EVENTS) do
                ctx.bus:on(A.NAME, ev, refresh)
            end
            local row = ctx.settings:row(A.TURN_IN_SETTING)
            if type(row) == "table" then
                local cancel = ctx.store:watch(row.scope, row.path or ("settings." .. A.TURN_IN_SETTING), refresh)
                if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            refresh()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.questAdvice = A.Declare(ns)
