local _, ns = ...
-- Chat part 4 (N60d): class-coloured names, short channel labels, edit-box
-- arrows. Run on the whole add-on loaded on a fake client; a line goes in
-- through the client's chat filter (c.pushChat, the author as its fourth
-- argument, the line's GUID and channel text as its fifth). Per lead
-- section 236: the GUID read raising then recovering, a reload keeping the
-- settings. Problems are counted against the count after boot. Made-up
-- names, GUIDs and lines. Not tested in game.
-- Fails before: UI/Chat.lua has no part 4 (addon.Chat.CLASS_NAMES is nil)
-- and the fake client has no GUID class control (c.setGuidClass is nil).
local tests = {}

local PRAT = "Prat-3.0"
local SAY = "CHAT_MSG_SAY"
local CHANNEL = "CHAT_MSG_CHANNEL"
local OTHER = "Thrall-Realm"
local JAINA = "Jaina-Realm"
local JAINA_GUID = "Player-1-00000001"
local THRALL_GUID = "Player-1-00000002"
local MAGE = "|cff3fc7eb"
local SECRET_LINE = { secret = true }
local LINK = "|Hplayer:Jaina-Realm:5:SAY|h"
local GENERAL = "1. General - Elwynn Forest"

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if type(c.setPlayerName) == "function" then c.setPlayerName("Zerian") end
    if type(c.setGuidClass) == "function" then
        c.setGuidClass(JAINA_GUID, "MAGE")
    end
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
    local ok = type(addon.Chat) == "table" and type(addon.Chat.CLASS_NAMES) == "string"
        and type(c.setGuidClass) == "function" and type(c.setGuidClassFails) == "function"
        and type(c.chatHeader) == "function" and type(c.editBoxState) == "function"
    t.ok(ok, "the chat part 4 is loaded and the fake client has its controls")
    return ok
end

-- Jaina's line, so her class is learnt from its GUID.
local function learn(c)
    return c.pushChat(SAY, "hello", nil, JAINA, { guid = JAINA_GUID })
end

local function asked(c)
    return c.pushChat(SAY, "ask " .. LINK .. "[Jaina]|h now", nil, OTHER, { guid = THRALL_GUID })
end

tests["chat polish 236: the three rows are under General > Chat, account-wide, off at first"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    local Topics = addon.Settings.Topics
    for _, key in ipairs({ Ch.CLASS_NAMES, Ch.SHORT_CHANNELS, Ch.EDIT_ARROWS }) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        if row then
            t.eq({ row.scope, row.type, row.default, row.group }, { "account", "bool", false, "general.chat" }, key)
            t.ok(Topics.Match(row, Topics.Words("chat")) ~= nil, key .. " is found by chat")
        end
    end
    t.ok(Topics.Match(addon.settings:row(Ch.CLASS_NAMES), Topics.Words("class")) ~= nil, "found by class")
    t.ok(Topics.Match(addon.settings:row(Ch.SHORT_CHANNELS), Topics.Words("channel")) ~= nil, "found by channel")
    t.ok(Topics.Match(addon.settings:row(Ch.EDIT_ARROWS), Topics.Words("arrow")) ~= nil, "found by arrow")
end

tests["chat polish 236: class names off - nothing coloured, the game's option untouched"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    learn(c)
    t.eq(asked(c), "ask " .. LINK .. "[Jaina]|h now", "the line as it came")
    t.eq(c.nameByClass("GUILD"), false)
end

tests["chat polish 236: class names on - a known player's link shown in the class colour, link bytes kept"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, true), true)
    t.eq(c.nameByClass("GUILD"), true, "the game colours the author's name by class")
    t.eq(c.nameByClass("CHANNEL1"), true)
    t.eq(learn(c), "hello")
    local shown = asked(c)
    t.eq(shown, "ask " .. LINK .. MAGE .. "[Jaina]|r|h now")
    -- Byte check: the |H...|h opener and the closing |h are the very bytes;
    -- taking our colour out gives back the line as it came.
    t.eq(shown:sub(5, 4 + #LINK), LINK, "the link's opener is the same bytes")
    local plain = shown:gsub("|cff3fc7eb", "", 1):gsub("|r|h", "|h", 1)
    t.eq(plain, "ask " .. LINK .. "[Jaina]|h now")
    t.eq(addon.problems:count(), base)
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, false), true)
    t.eq(c.nameByClass("GUILD"), false, "off gives the game's option back")
    t.eq(asked(c), "ask " .. LINK .. "[Jaina]|h now")
end

tests["chat polish 236: class names - an unknown class leaves the link as it was"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, true), true)
    c.pushChat(SAY, "hi", nil, JAINA, { guid = "Player-1-0000FFFF" })
    t.eq(asked(c), "ask " .. LINK .. "[Jaina]|h now")
end

tests["chat polish 236: Prat's PlayerNames on - class names stand down"] = function(t)
    local c, addon = boot({ prat = { PlayerNames = true } })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, true), true)
    learn(c)
    t.eq(asked(c), "ask " .. LINK .. "[Jaina]|h now", "no second colour")
    t.eq(c.nameByClass("GUILD"), false)
    t.eq(addon.chat.state("names"), "prat")
end

tests["chat polish 236: the GUID read raising, then recovering"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, true), true)
    local base = addon.problems:count("chat")
    c.setGuidClassFails(true)
    t.eq(learn(c), "hello", "the line as it came")
    learn(c)
    t.eq(asked(c), "ask " .. LINK .. "[Jaina]|h now")
    t.eq(addon.problems:count("chat"), base + 1, "one problem for that error")
    c.setGuidClassFails(false)
    learn(c)
    t.eq(asked(c), "ask " .. LINK .. MAGE .. "[Jaina]|r|h now")
    t.eq(addon.problems:count("chat"), base + 1)
end

tests["chat polish 236: a hidden line passes through unread"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.CLASS_NAMES, true), true)
    t.eq(addon.settings:set(addon.Chat.SHORT_CHANNELS, true), true)
    local shown = c.pushChat(CHANNEL, SECRET_LINE, nil, OTHER, { guid = JAINA_GUID, channel = GENERAL })
    t.eq(shown, SECRET_LINE)
    t.eq(addon.problems:count(), base)
end

tests["chat polish 236: short channel labels - numbered channels to their number, Guild to G, Say untouched"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local guild, say = c.chatHeader("GUILD"), c.chatHeader("SAY")
    local line = "wts |cff1eff00|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"
    local text, channel = c.pushChat(CHANNEL, line, nil, OTHER, { channel = GENERAL })
    t.eq({ text, channel }, { line, GENERAL }, "off: as it came")
    t.eq(addon.settings:set(addon.Chat.SHORT_CHANNELS, true), true)
    text, channel = c.pushChat(CHANNEL, line, nil, OTHER, { channel = GENERAL })
    t.eq({ text, channel }, { line, "1" }, "the label shortened, the line's bytes kept")
    t.eq(c.chatHeader("GUILD"), "|Hchannel:GUILD|h[G]|h %s: ")
    t.eq(c.chatHeader("RAID"), "|Hchannel:RAID|h[R]|h %s: ")
    t.eq(c.chatHeader("SAY"), say, "say untouched")
    t.eq(addon.settings:set(addon.Chat.SHORT_CHANNELS, false), true)
    t.eq(c.chatHeader("GUILD"), guild, "off gives the game's label back")
    text, channel = c.pushChat(CHANNEL, line, nil, OTHER, { channel = GENERAL })
    t.eq(channel, GENERAL)
end

tests["chat polish 236: Prat's ChannelNames on - short labels stand down"] = function(t)
    local c, addon = boot({ prat = { ChannelNames = true } })
    if not ready(t, c, addon) then return end
    local guild = c.chatHeader("GUILD")
    t.eq(addon.settings:set(addon.Chat.SHORT_CHANNELS, true), true)
    local _, channel = c.pushChat(CHANNEL, "wts", nil, OTHER, { channel = GENERAL })
    t.eq(channel, GENERAL)
    t.eq(c.chatHeader("GUILD"), guild)
    t.eq(addon.chat.state("short"), "prat")
end

tests["chat polish 236: edit box - arrows without Alt and a history of 20, given back when off"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(c.editBoxState(), { alt = true, history = 32 }, "the game's own at first")
    t.eq(addon.settings:set(addon.Chat.EDIT_ARROWS, true), true)
    t.eq(c.editBoxState(), { alt = false, history = 20 })
    t.eq(addon.chat.state("edit"), "on")
    t.eq(addon.settings:set(addon.Chat.EDIT_ARROWS, false), true)
    t.eq(c.editBoxState(), { alt = true, history = 32 })
end

tests["chat polish 236: Prat's EditBox on - the edit box is left alone"] = function(t)
    local c, addon = boot({ prat = { EditBox = true } })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.EDIT_ARROWS, true), true)
    t.eq(c.editBoxState(), { alt = true, history = 32 })
    t.eq(addon.chat.state("edit"), "prat")
end

tests["chat polish 236: reload keeps every part 4 setting"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    for _, key in ipairs({ Ch.CLASS_NAMES, Ch.SHORT_CHANNELS, Ch.EDIT_ARROWS }) do
        t.eq(addon.settings:set(key, true), true, key)
    end
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq({ addon2.settings:get(Ch.CLASS_NAMES), addon2.settings:get(Ch.SHORT_CHANNELS),
        addon2.settings:get(Ch.EDIT_ARROWS) }, { true, true, true })
    t.eq(c2.editBoxState(), { alt = false, history = 20 })
    t.eq(c2.chatHeader("GUILD"), "|Hchannel:GUILD|h[G]|h %s: ")
    learn(c2)
    t.eq(asked(c2), "ask " .. LINK .. MAGE .. "[Jaina]|r|h now")
end

return tests
