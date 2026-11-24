local _, ns = ...

-- Quest advice (lead section 354 item 4, P-QUEST groundwork): words about
-- the player's own quest log, shown as advisor prompts.
--   ready to hand in   one prompt naming the quests that are complete in
--                      the log: "Ready to hand in: A, B". It goes when the
--                      player has handed them in, or the setting is off.
--   share              in a group, one prompt naming the quests the client
--                      says can be shared: "You can share with your group:
--                      A, B". Only while you are known to be in a group; a
--                      quest not known to be shareable is never named.
--                      The line ends with the word that offers one
--                      (Nav/QuestShare.lua, the player's own word).
-- TEXT ONLY. Nothing here accepts, shares, hands in or abandons a quest,
-- picks a reward or talks to anyone: the player does all of that. Sharing
-- is in Nav/QuestShare.lua, on the player's own word only.
--
-- A log that cannot be read says nothing new: the prompt stays as it was,
-- and none is made up.
--
-- Pure parts:
--   A.Ready(rows)          the titles complete and not failed, log order,
--                          each title once
--   A.Names(titles[, max]) "A, B, C and 2 more"; nil for none
--   A.TurnInText(rows)     the hand-in line, or nil when none is ready
--   A.ShareRows(rows, can) { id, title } of each quest not complete, not
--                          failed, for which can(id) is a plain true; log
--                          order, each title once
--   A.Shareable(rows, can) the titles of those rows
--   A.ShareText(rows, can, grouped)  the share line, or nil
--
-- Reads: client.questLog() through ns.Nav.QuestLogRows, client.grouped(),
-- client.questShareable(id) (a first guess, Core/Client.lua). Writes: none.
-- Not seen in game: whether the client answers questShareable at all; where
-- it does not, there is no share prompt.
-- Settings (char, on by default): general.questTurnIn "Quests ready to hand
-- in", general.questShare "Quests you can share".

local A = {}
ns.QuestAdvice = A

A.NAME = "questAdvice"
A.TURN_IN_SETTING = "general.questTurnIn"
A.TURN_IN_PROMPT = "quest.turnIn"
A.SHARE_SETTING = "general.questShare"
A.SHARE_PROMPT = "quest.share"
A.PRIORITY = 1
-- No more titles than this are named in one line.
A.MAX_NAMES = 3

A.TURN_IN = "Ready to hand in: %s"
-- The names, then the slash word that offers one (Nav/QuestShare.lua).
A.SHARE = "You can share with your group: %s. Type %s share to offer one."
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

function A.ShareRows(rows, can)
    local out, seen = {}, {}
    if type(rows) ~= "table" or type(can) ~= "function" then return out end
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.complete ~= true and r.failed ~= true
            and type(r.title) == "string" and r.title ~= "" and not seen[r.title] then
            local ok, yes = pcall(can, r.id)
            if ok and yes == true then
                seen[r.title] = true
                out[#out + 1] = { id = r.id, title = r.title }
            end
        end
    end
    return out
end

function A.Shareable(rows, can)
    local out = {}
    for i, r in ipairs(A.ShareRows(rows, can)) do out[i] = r.title end
    return out
end

function A.ShareText(rows, can, grouped)
    if grouped ~= true then return nil end
    local names = A.Names(A.Shareable(rows, can))
    if names == nil then return nil end
    return A.SHARE:format(names, ns.id.slash)
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD",
    "GROUP_ROSTER_UPDATE",
}

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
        }, {
            key = A.SHARE_SETTING, scope = "char", type = "bool", default = true,
            label = "Quests you can share",
            help = "In a group, names the quests in your log that can be shared, so you remember to offer them. "
                .. "It reads your quest log only and shares nothing.",
            group = "party",
            synonyms = { "quest", "quests", "share", "group", "party", "advice" },
        } },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(advisor) ~= "table" then return end
            local client = ctx.client
            -- The last log read that answered, and the line shown for each prompt.
            local last
            local shown = {}

            local function show(id, text)
                if text == shown[id] then return end
                if text then advisor.Add(id, text, A.PRIORITY) else advisor.Remove(id) end
                shown[id] = text
            end

            local function can(id) return ask(client, "questShareable", id) end

            local function refresh()
                local rows = ns.Nav.QuestLogRows(client)
                if type(rows) == "table" then last = rows end
                local turnIn, share
                if ctx.settings:get(A.TURN_IN_SETTING) ~= false then turnIn = A.TurnInText(last) end
                if ctx.settings:get(A.SHARE_SETTING) ~= false then
                    local grouped = ask(client, "grouped")
                    -- Asked only in a group: alone, no quest is asked about.
                    if grouped == true then share = A.ShareText(last, can, grouped) end
                end
                show(A.TURN_IN_PROMPT, turnIn)
                show(A.SHARE_PROMPT, share)
            end

            for _, ev in ipairs(EVENTS) do
                ctx.bus:on(A.NAME, ev, refresh)
            end
            for _, key in ipairs({ A.TURN_IN_SETTING, A.SHARE_SETTING }) do
                local row = ctx.settings:row(key)
                if type(row) == "table" then
                    local cancel = ctx.store:watch(row.scope, row.path or ("settings." .. key), refresh)
                    if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
                end
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
