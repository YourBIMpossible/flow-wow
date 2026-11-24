local _, ns = ...
-- Chat part 5 (N60e): word filters, repeated-line hiding, word
-- substitutions. Run on the whole add-on loaded on a fake client; a line
-- goes in through the client's chat filter (c.pushChat, the author as its
-- fourth argument, { line = } as its fifth: the game's line id). A hidden
-- line comes back nil. Per lead section 236: the name read raising then
-- recovering, a reload keeping the settings. Problems are counted against
-- the count after boot. Made-up names and lines. Not tested in game.
-- Fails before: UI/Chat.lua has no part 5 (addon.Chat.FILTERS is nil), so
-- ready() gets false; and the fake client shows every line (a hidden line
-- would come back as its text, not nil).
local tests = {}

local PRAT = "Prat-3.0"
local SAY = "CHAT_MSG_SAY"
local CHANNEL = "CHAT_MSG_CHANNEL"
local WHISPER = "CHAT_MSG_WHISPER"
local WHISPER_SENT = "CHAT_MSG_WHISPER_INFORM"
local ME = "Zerian"
local OTHER = "Thrall-Realm"
local SECRET_LINE = { secret = true }
local ITEM = "|cff1eff00|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setPlayerName(ME)
    if type(opts.prat) == "table" then
        c.setLoaded(PRAT, true)
        for name, on in pairs(opts.prat) do c.setPratModule(name, on) end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function ready(t, c, addon)
    local ok = type(addon.Chat) == "table" and type(addon.Chat.FILTERS) == "string"
        and type(addon.Chat.REPEATS) == "string" and type(addon.Chat.SUBS) == "string"
    t.ok(ok, "the chat part 5 is loaded")
    return ok
end

local function filtering(t, addon, words)
    t.eq(addon.settings:set(addon.Chat.FILTER_WORDS, words), true, "words set")
    t.eq(addon.settings:set(addon.Chat.FILTERS, true), true, "filters on")
end

local function status(addon)
    return table.concat(addon.chat.lines(), "\n")
end

tests["chat filters 236: the rows are under General > Chat, account-wide, off at first"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    local want = {
        [Ch.FILTERS] = { "bool", false }, [Ch.FILTER_WORDS] = { "string", "" },
        [Ch.FILTER_SCOPE] = { "choice", "channels" }, [Ch.FILTER_WHISPERS] = { "bool", false },
        [Ch.REPEATS] = { "choice", "off" }, [Ch.SUBS] = { "bool", false }, [Ch.SUB_PAIRS] = { "string", "" },
    }
    local Topics = addon.Settings.Topics
    for key, shape in pairs(want) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        if row then
            t.eq({ row.scope, row.type, row.default, row.group }, { "account", shape[1], shape[2], "general.chat" }, key)
            t.ok(Topics.Match(row, Topics.Words("chat")) ~= nil, key .. " is found by chat")
        end
    end
    t.ok(Topics.Match(addon.settings:row(Ch.FILTERS), Topics.Words("filter")) ~= nil, "found by filter")
    t.ok(Topics.Match(addon.settings:row(Ch.REPEATS), Topics.Words("spam")) ~= nil, "found by spam")
    t.ok(Topics.Match(addon.settings:row(Ch.SUBS), Topics.Words("replace")) ~= nil, "found by replace")
    t.eq(c.pushChat(CHANNEL, "wts gold"), "wts gold", "all off: the line as it came")
end

tests["chat filters 236: filters on - a line with a word is hidden, whole words only, counted"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.FILTER_WORDS, "wts, boost"), true)
    t.eq(c.pushChat(CHANNEL, "WTS gold", nil, OTHER), "WTS gold", "filters still off")
    filtering(t, addon, "wts, boost")
    t.eq(c.pushChat(CHANNEL, "WTS gold", nil, OTHER), nil, "hidden, any case")
    t.eq(c.pushChat(CHANNEL, "cheap boost!", nil, OTHER), nil, "the second word")
    t.eq(c.pushChat(CHANNEL, "boosting nothing", nil, OTHER), "boosting nothing", "not a whole word")
    t.eq(c.pushChat(CHANNEL, "wts%a (.*)", nil, OTHER), nil, "chat text is no pattern")
    t.eq(c.pushChat(SAY, "wts gold", nil, OTHER), "wts gold", "say is outside the channels scope")
    t.eq(addon.settings:set(addon.Chat.FILTER_SCOPE, "every kind"), true)
    t.eq(c.pushChat(SAY, "wts gold", nil, OTHER), nil, "every kind: say too")
    t.ok(status(addon):find("4 chat lines hidden this session", 1, true) ~= nil, "the count in chat status")
    t.eq(addon.settings:set(addon.Chat.FILTERS, false), true)
    t.eq(c.pushChat(CHANNEL, "WTS gold", nil, OTHER), "WTS gold", "off again: shown")
end

tests["chat filters 236: a word made of pattern letters is found as plain text"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    filtering(t, addon, "%d+, [x")
    t.eq(c.pushChat(CHANNEL, "sell 100 ore", nil, OTHER), "sell 100 ore", "%d+ is no pattern")
    t.eq(c.pushChat(CHANNEL, "a %d+ b", nil, OTHER), nil, "the very letters hide it")
    t.eq(addon.problems:count(), base)
end

tests["chat filters 236: whispers and the player's own lines are never hidden unless the whisper row says"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    filtering(t, addon, "wts")
    t.eq(addon.settings:set(addon.Chat.FILTER_SCOPE, "every kind"), true)
    t.eq(c.pushChat(WHISPER, "wts gold", nil, OTHER), "wts gold", "a whisper to the player")
    t.eq(c.pushChat(WHISPER_SENT, "wts gold", nil, OTHER), "wts gold", "a whisper the player sent")
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, ME), "wts gold", "the player's own line")
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, ME .. "-Realm"), "wts gold", "own line with a realm")
    t.eq(addon.settings:set(addon.Chat.FILTER_WHISPERS, true), true)
    t.eq(c.pushChat(WHISPER, "wts gold", nil, OTHER), nil, "the whisper row on: hidden")
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, ME), "wts gold", "own lines still never")
end

tests["chat filters 236: a word inside an item link hides the line, and a shown line keeps its link bytes"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    filtering(t, addon, "wts")
    local line = "lf " .. ITEM .. " cheap"
    t.eq(c.pushChat(CHANNEL, line, nil, OTHER), line, "no word: the very bytes")
end

tests["chat filters 236: more than 20 words - the first 20 count"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local words = {}
    for i = 1, 21 do words[i] = "w" .. i end
    filtering(t, addon, table.concat(words, ","))
    t.eq(c.pushChat(CHANNEL, "x w20 y", nil, OTHER), nil, "the 20th counts")
    t.eq(c.pushChat(CHANNEL, "x w21 y", nil, OTHER), "x w21 y", "the 21st does not")
end

tests["chat filters 236: repeats - the same line from the same author within the window is hidden"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER), "lfg rfc")
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER), "lfg rfc", "off: shown twice")
    t.eq(addon.settings:set(addon.Chat.REPEATS, "10"), true)
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER, { line = 1 }), "lfg rfc", "first: shown")
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER, { line = 1 }), "lfg rfc", "same line in a second window: shown")
    c.advance(4)
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER, { line = 2 }), nil, "again within 10 s: hidden")
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, "Jaina-Realm", { line = 3 }), "lfg rfc", "another author: shown")
    t.eq(c.pushChat(CHANNEL, "lfg rfd", nil, OTHER, { line = 4 }), "lfg rfd", "another line: shown")
    t.eq(c.pushChat(WHISPER, "hey", nil, OTHER, { line = 5 }), "hey")
    t.eq(c.pushChat(WHISPER, "hey", nil, OTHER, { line = 6 }), "hey", "whispers never")
    t.eq(c.pushChat(SAY, "hey", nil, ME, { line = 7 }), "hey")
    t.eq(c.pushChat(SAY, "hey", nil, ME, { line = 8 }), "hey", "own lines never")
    c.advance(11)
    t.eq(c.pushChat(CHANNEL, "lfg rfc", nil, OTHER, { line = 9 }), "lfg rfc", "after the window: shown")
    t.ok(status(addon):find("1 chat lines hidden this session", 1, true) ~= nil, "counted once")
end

tests["chat filters 236: repeats - memory stays capped"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.REPEATS, "60"), true)
    for i = 1, addon.Chat.REPEAT_MAX * 3 do c.pushChat(CHANNEL, "line " .. i, nil, OTHER) end
    t.ok(addon.chat.remembered() <= addon.Chat.REPEAT_MAX, "at most REPEAT_MAX lines kept")
    t.eq(addon.problems:count(), base)
end

tests["chat filters 236: substitutions - whole words in others' lines, never in links or own lines"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.SUB_PAIRS, "lol=haha, brb = back soon, x|y=z, to=a|Hb"), true)
    t.eq(c.pushChat(SAY, "lol ok", nil, OTHER), "lol ok", "off: as it came")
    t.eq(addon.settings:set(addon.Chat.SUBS, true), true)
    t.eq(c.pushChat(SAY, "LOL ok, brb", nil, OTHER), "haha ok, back soon")
    t.eq(c.pushChat(SAY, "lollipop", nil, OTHER), "lollipop", "whole words only")
    t.eq(c.pushChat(SAY, "lol", nil, ME), "lol", "the player's own line")
    local link = "|cffffffff|Hitem:1|h[lol]|h|r"
    t.eq(c.pushChat(SAY, "see " .. link .. " lol", nil, OTHER), "see " .. link .. " haha", "the link's bytes kept")
    t.eq(c.pushChat(SAY, "go to it", nil, OTHER), "go a||Hb it", "a bar in the new word is shown, never a code")
end

tests["chat filters 236: more than 10 pairs - the first 10 count"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local pairsText = {}
    for i = 1, 11 do pairsText[i] = "p" .. i .. "=q" .. i end
    t.eq(addon.settings:set(addon.Chat.SUB_PAIRS, table.concat(pairsText, ",")), true)
    t.eq(addon.settings:set(addon.Chat.SUBS, true), true)
    t.eq(c.pushChat(SAY, "p10 p11", nil, OTHER), "q10 p11")
end

tests["chat filters 236: a hidden (secret) line passes through unread"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    filtering(t, addon, "wts")
    t.eq(addon.settings:set(addon.Chat.REPEATS, "10"), true)
    t.eq(addon.settings:set(addon.Chat.SUB_PAIRS, "wts=x"), true)
    t.eq(addon.settings:set(addon.Chat.SUBS, true), true)
    t.eq(c.pushChat(CHANNEL, SECRET_LINE, nil, OTHER), SECRET_LINE)
    t.eq(c.pushChat(CHANNEL, SECRET_LINE, nil, OTHER), SECRET_LINE, "not a repeat either")
    t.eq(addon.problems:count(), base)
end

tests["chat filters 236: Prat's Filtering on - filters and repeats stand down; Substitutions on - subs stand down"] = function(t)
    local c, addon = boot({ prat = { Filtering = true, Substitutions = true } })
    if not ready(t, c, addon) then return end
    filtering(t, addon, "wts")
    t.eq(addon.settings:set(addon.Chat.REPEATS, "10"), true)
    t.eq(addon.settings:set(addon.Chat.SUB_PAIRS, "lol=haha"), true)
    t.eq(addon.settings:set(addon.Chat.SUBS, true), true)
    t.eq(c.pushChat(CHANNEL, "wts lol", nil, OTHER), "wts lol")
    t.eq(c.pushChat(CHANNEL, "wts lol", nil, OTHER), "wts lol")
    t.eq({ addon.chat.state("filters"), addon.chat.state("repeats"), addon.chat.state("subs") },
        { "prat", "prat", "prat" })
end

tests["chat filters 236: the name read raising, then recovering"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    filtering(t, addon, "wts")
    local base = addon.problems:count("chat")
    c.setPlayerNameFails(true)
    c.setPlayerName(nil)
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, OTHER), "wts gold", "own lines not known: nothing hidden")
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, OTHER), "wts gold")
    t.eq(addon.problems:count("chat"), base + 1, "one problem for that error")
    c.setPlayerNameFails(false)
    c.setPlayerName(ME)
    t.eq(c.pushChat(CHANNEL, "wts gold", nil, OTHER), nil, "recovered: hidden")
    t.eq(addon.problems:count("chat"), base + 1)
end

tests["chat filters 236: reload keeps every part 5 setting"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    filtering(t, addon, "wts")
    t.eq(addon.settings:set(Ch.FILTER_SCOPE, "every kind"), true)
    t.eq(addon.settings:set(Ch.FILTER_WHISPERS, true), true)
    t.eq(addon.settings:set(Ch.REPEATS, "30"), true)
    t.eq(addon.settings:set(Ch.SUB_PAIRS, "lol=haha"), true)
    t.eq(addon.settings:set(Ch.SUBS, true), true)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq({ addon2.settings:get(Ch.FILTERS), addon2.settings:get(Ch.FILTER_WORDS), addon2.settings:get(Ch.FILTER_SCOPE),
        addon2.settings:get(Ch.FILTER_WHISPERS), addon2.settings:get(Ch.REPEATS), addon2.settings:get(Ch.SUBS),
        addon2.settings:get(Ch.SUB_PAIRS) }, { true, "wts", "every kind", true, "30", true, "lol=haha" })
    t.eq(c2.pushChat(SAY, "wts gold", nil, OTHER), nil)
    t.eq(c2.pushChat(SAY, "lol", nil, OTHER), "haha")
end

return tests
