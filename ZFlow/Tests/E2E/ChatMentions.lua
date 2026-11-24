local _, ns = ...
-- Chat part 3 (N60c): mentions. A chat line holding the player's own name,
-- or a word of the player's keyword list, has that word shown in a chosen
-- colour; an optional sound, at most once in Chat.SOUND_GAP seconds. Run on
-- the whole add-on loaded on a fake client; a line goes in through the
-- client's chat filter (c.pushChat, the author as its fourth argument).
-- Per lead section 236: the name read raising then recovering, a reload
-- keeping the settings. Problems are counted against the count after
-- boot. Made-up names and lines. Not tested in game.
-- Fails before: UI/Chat.lua has no mentions part (addon.Chat.MENTIONS is
-- nil) and the fake client has no player name control (c.setPlayerName is
-- nil).
local tests = {}

local PRAT = "Prat-3.0"
local SAY = "CHAT_MSG_SAY"
local WHISPER = "CHAT_MSG_WHISPER"
local CHANNEL = "CHAT_MSG_CHANNEL"
local ME = "Zerian"
local OTHER = "Thrall-Realm"
local SECRET_LINE = { secret = true }
local GOLD = "|cffffd100"

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if type(c.setPlayerName) == "function" then c.setPlayerName(ME) end
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
    local ok = type(addon.Chat) == "table" and type(addon.Chat.MENTIONS) == "string"
        and type(c.setPlayerName) == "function" and type(c.setPlayerNameFails) == "function"
    t.ok(ok, "the chat mentions part is loaded and the fake client has a player name control")
    return ok
end

local function on(t, addon)
    t.eq(addon.settings:set(addon.Chat.MENTIONS, true), true, "mentions on")
end

tests["chat mentions 236: every mentions row is under General > Chat, mentions off at first"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    local want = {
        [Ch.MENTIONS] = { "bool", false }, [Ch.KEYWORDS] = { "string", "" },
        [Ch.MENTION_COLOUR] = { "choice", "gold" }, [Ch.MENTION_SOUND] = { "choice", "off" },
        [Ch.SCOPE.say] = { "bool", true }, [Ch.SCOPE.party] = { "bool", true },
        [Ch.SCOPE.raid] = { "bool", true }, [Ch.SCOPE.guild] = { "bool", true },
        [Ch.SCOPE.whisper] = { "bool", true }, [Ch.SCOPE.channel] = { "bool", false },
    }
    local Topics = addon.Settings.Topics
    for key, shape in pairs(want) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        if row then
            t.eq({ row.scope, row.type, row.default, row.group }, { "account", shape[1], shape[2], "general.chat" }, key)
            for _, word in ipairs({ "chat", "mention" }) do
                t.ok(Topics.Match(row, Topics.Words(word)) ~= nil, key .. " is found by " .. word)
            end
        end
    end
    t.eq(c.pushChat(SAY, "hi zerian", nil, OTHER), "hi zerian", "off: the line as it came")
end

tests["chat mentions 236: the player's name is shown in the colour, case kept, whole word only"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    on(t, addon)
    t.eq(c.pushChat(SAY, "hi zerian, ready?", nil, OTHER), "hi " .. GOLD .. "zerian|r, ready?")
    t.eq(c.pushChat(SAY, "Zerianna is not me", nil, OTHER), "Zerianna is not me", "part of a longer word")
    t.eq(addon.settings:set(addon.Chat.MENTION_COLOUR, "green"), true)
    t.eq(c.pushChat(SAY, "ZERIAN!", nil, OTHER), "|cff1eff00ZERIAN|r!")
    t.eq(addon.problems:count(), base)
end

tests["chat mentions 236: a keyword from the list is shown, each word of the list"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(addon.settings:set(addon.Chat.KEYWORDS, " Onyxia , tank%,"), true)
    t.eq(c.pushChat(SAY, "LF1M onyxia need tank%", nil, OTHER),
        "LF1M " .. GOLD .. "onyxia|r need " .. GOLD .. "tank%|r", "a keyword is plain text, never a pattern")
    t.eq(c.pushChat(SAY, "tanks wanted", nil, OTHER), "tanks wanted")
end

tests["chat mentions 236: inside an item link nothing is touched"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(addon.settings:set(addon.Chat.KEYWORDS, "linen"), true)
    local item = "|cff1eff00|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"
    local line = "selling " .. item .. " cheap"
    t.eq(c.pushChat(SAY, line, nil, OTHER), line, "the very bytes")
    local player = "|Hplayer:Zerian-Realm:1:WHISPER|h[Zerian]|h"
    t.eq(c.pushChat(SAY, player .. " says linen", nil, OTHER), player .. " says " .. GOLD .. "linen|r")
end

tests["chat mentions 236: the player's own lines never count"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(addon.settings:set(addon.Chat.MENTION_SOUND, "alert"), true)
    t.eq(c.pushChat(SAY, "I am zerian", nil, ME), "I am zerian")
    t.eq(c.pushChat(SAY, "I am zerian", nil, ME .. "-Realm"), "I am zerian", "with the realm")
    t.eq(c.pushChat("CHAT_MSG_WHISPER_INFORM", "zerian here", nil, OTHER), "zerian here", "a whisper sent")
    t.eq(#c.alertsPlayed(), 0, "no sound")
end

tests["chat mentions 236: the sound once, then not again within the gap"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(#c.alertsPlayed(), 0)
    c.pushChat(SAY, "zerian?", nil, OTHER)
    t.eq(#c.alertsPlayed(), 0, "sound off at first")
    t.eq(addon.settings:set(addon.Chat.MENTION_SOUND, "alert"), true)
    c.pushChat(SAY, "zerian?", nil, OTHER)
    t.eq(#c.alertsPlayed(), 1)
    c.pushChat(WHISPER, "zerian!!", nil, OTHER)
    t.eq(#c.alertsPlayed(), 1, "within the gap")
    c.advance(addon.Chat.SOUND_GAP + 1, 1)
    c.pushChat(WHISPER, "zerian!!", nil, OTHER)
    t.eq(#c.alertsPlayed(), 2, "after the gap")
end

tests["chat mentions 236: only the chat kinds turned on count, whispers by default"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(c.pushChat(CHANNEL, "zerian wts", nil, OTHER), "zerian wts", "channels off at first")
    t.eq(c.pushChat(WHISPER, "zerian", nil, OTHER), GOLD .. "zerian|r")
    t.eq(addon.settings:set(addon.Chat.SCOPE.whisper, false), true)
    t.eq(c.pushChat(WHISPER, "zerian", nil, OTHER), "zerian")
    t.eq(addon.settings:set(addon.Chat.SCOPE.channel, true), true)
    t.eq(c.pushChat(CHANNEL, "zerian wts", nil, OTHER), GOLD .. "zerian|r wts")
end

tests["chat mentions 236: Prat's CustomFilters on - no second colour; Sounds on - no second sound"] = function(t)
    local c, addon = boot({ prat = { CustomFilters = true, Sounds = true } })
    if not ready(t, c, addon) then return end
    on(t, addon)
    t.eq(addon.settings:set(addon.Chat.MENTION_SOUND, "alert"), true)
    t.eq(c.pushChat(SAY, "hi zerian", nil, OTHER), "hi zerian")
    t.eq(#c.alertsPlayed(), 0)
    t.eq(addon.chat.state("mentions"), "prat")
    local c2, addon2 = boot({ prat = { CustomFilters = false, Sounds = false } })
    on(t, addon2)
    t.eq(c2.pushChat(SAY, "hi zerian", nil, OTHER), "hi " .. GOLD .. "zerian|r", "Prat's are off: ours works")
end

tests["chat mentions 236: a hidden line passes through unread"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    on(t, addon)
    t.eq(c.pushChat(SAY, SECRET_LINE, nil, OTHER), SECRET_LINE)
    t.eq(addon.problems:count(), base)
end

tests["chat mentions 236: the name read raising, then recovering"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    on(t, addon)
    local base = addon.problems:count("chat")
    c.setPlayerNameFails(true)
    t.eq(c.pushChat(SAY, "zerian one", nil, OTHER), "zerian one", "the line as it came")
    t.eq(c.pushChat(SAY, "zerian two", nil, OTHER), "zerian two")
    t.eq(addon.problems:count("chat"), base + 1, "one problem for that error")
    c.setPlayerNameFails(false)
    t.eq(c.pushChat(SAY, "zerian three", nil, OTHER), GOLD .. "zerian|r three")
    t.eq(addon.problems:count("chat"), base + 1)
end

tests["chat mentions 236: reload keeps every mentions setting"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    on(t, addon)
    t.eq(addon.settings:set(Ch.KEYWORDS, "onyxia"), true)
    t.eq(addon.settings:set(Ch.MENTION_COLOUR, "orange"), true)
    t.eq(addon.settings:set(Ch.MENTION_SOUND, "alert"), true)
    t.eq(addon.settings:set(Ch.SCOPE.channel, true), true)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq({ addon2.settings:get(Ch.MENTIONS), addon2.settings:get(Ch.KEYWORDS), addon2.settings:get(Ch.MENTION_COLOUR),
        addon2.settings:get(Ch.MENTION_SOUND), addon2.settings:get(Ch.SCOPE.channel) },
        { true, "onyxia", "orange", "alert", true })
    t.eq(c2.pushChat(CHANNEL, "onyxia", nil, OTHER), "|cffff8000onyxia|r")
    t.eq(#c2.alertsPlayed(), 1)
end

return tests
