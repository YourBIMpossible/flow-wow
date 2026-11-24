local _, ns = ...

-- Share a quest with the group (CAPABILITY-RECONCILE 2026-11-24 row G50).
-- ACTING: the one place a quest is shared, and only on the player's own
-- word:
--   <slash> share    offers ONE quest from the log to the group, the first
--                    the client says can be shared that this word has not
--                    offered yet, and says which. Type it again for the
--                    next. When all were offered it starts over.
-- One quest for each word typed, because a group member can answer only one
-- offer at a time. Never by itself: no event, timer or login shares a
-- quest; only the word's own function calls client.shareQuest. Alone, or
-- with no shareable quest, it says so and shares nothing. Leaving the group
-- forgets what was offered.
--
-- What it says is that the game was asked: whether a member took the quest
-- is the game's own line, not read here.
--
--   S.Pick(rows, offered) -> row, left, again
--     rows: QuestAdvice.ShareRows'; offered: { [id] = true }.
--     row: the first not offered; left: how many not offered remain after
--     it; again: true when all were offered and it started over.
--     nil when rows is empty.
--
-- Reads: client.grouped(), client.questLog() through ns.Nav.QuestLogRows,
-- client.questShareable(id). Calls: client.shareQuest(id) (ACTING, a first
-- guess, Core/Client.lua). Writes: none; nothing is saved.
-- Not tested in game.

local S = {}
ns.QuestShare = S

S.NAME = "questShare"
S.WORD = "share"
S.HELP = "offer one quest from your log to your group"
S.USAGE = "%s offers one quest from your log to your group."
S.ALONE = "you are not in a group, so there is no one to share with."
S.NO_LOG = "your quest log could not be read."
S.NONE = "no quest in your log can be shared."
S.SHARING = 'sharing "%s" with your group.'
S.MORE = " %d more: type %s again."
S.LAST = " That was the last one."
S.FAILED = 'could not share "%s": %s.'
-- Why the share call did not go through, in the player's words.
S.WHY = {
    noCall = "this game client can't share quests",
    notInLog = "it is no longer in your quest log",
    raised = "the game refused",
    bad = "it has no quest number",
}
S.WHY_OTHER = "the game did not answer"

function S.Pick(rows, offered)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    if type(offered) ~= "table" then offered = {} end
    local pick, left = nil, 0
    for _, r in ipairs(rows) do
        if not offered[r.id] then
            if pick == nil then pick = r else left = left + 1 end
        end
    end
    if pick ~= nil then return pick, left end
    return rows[1], #rows - 1, true
end

function S.Declare(k, diag)
    local api = {}
    local ctx
    local offered = {}

    local function client()
        return ctx and ctx.client or k.client
    end

    local function ask(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function say(line)
        local c = client()
        if type(c) == "table" and type(c.print) == "function" then
            c.print((k.id or ns.id).title .. ": " .. line)
        end
    end

    local function word()
        return (k.id or ns.id).slash .. " " .. S.WORD
    end

    -- The player's word. -> true when the game was asked to share a quest.
    function api.Word(rest)
        rest = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
        if rest ~= "" then
            say(S.USAGE:format(word()))
            return false
        end
        if ask("grouped") ~= true then
            offered = {}
            say(S.ALONE)
            return false
        end
        local c = client()
        local log = ns.Nav.QuestLogRows(c)
        if type(log) ~= "table" then
            say(S.NO_LOG)
            return false
        end
        local rows = ns.QuestAdvice.ShareRows(log, function(id) return ask("questShareable", id) end)
        local pick, left, again = S.Pick(rows, offered)
        if pick == nil then
            say(S.NONE)
            return false
        end
        if again then offered = {} end
        local ok, why
        if type(c) ~= "table" or type(c.shareQuest) ~= "function" then
            ok, why = nil, "noCall"
        else
            local ran, a, b = pcall(c.shareQuest, pick.id)
            if ran then ok, why = a, b else ok, why = nil, "raised" end
        end
        if ok ~= true then
            say(S.FAILED:format(pick.title, S.WHY[why] or S.WHY_OTHER))
            return false
        end
        offered[pick.id] = true
        say(S.SHARING:format(pick.title) .. (left > 0 and S.MORE:format(left, word()) or S.LAST))
        return true
    end

    k:Module({
        name = S.NAME,
        needs = { "client" },
        start = function(c) ctx = c end,
        stop = function() offered = {} end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[S.WORD] = function(rest) api.Word(rest) end
        if type(diag.help) == "table" then diag.help[S.WORD] = S.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.questShare = S.Declare(ns, ns.diag)
