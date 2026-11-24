local _, ns = ...
-- Chat part 2 (N60b): chat readability on the whole add-on loaded on a
-- fake client. Text size, fading, mouse-wheel scrolling, timestamps and
-- tabs kept visible, each its own row under General > Chat, each off at
-- first. The chat windows are the fake's (c.setChatFrame), a line goes in
-- through the client's chat filter (c.pushChat), a wheel notch through
-- c.wheelChat and the game's tab fade through c.fadeTab. Per lead section
-- 236: a read raising then recovering, a reload keeping the settings.
-- Problems are counted against the count after boot. Made-up lines. Not
-- tested in game.
-- Fails before: UI/Chat.lua has no readability part (addon.Chat.FONT is
-- nil) and the fake client has no chat window controls (c.setChatFrame is
-- nil).
local tests = {}

local PRAT = "Prat-3.0"
local SAY = "CHAT_MSG_SAY"
local SECRET_LINE = { secret = true }

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if type(c.setChatFrame) == "function" then
        c.setChatFrame(1, { font = 14, fading = true, time = 120 })
        c.setChatFrame(2, { font = 12, fading = true, time = 60 })
        c.setLocalTime(9, 5, 7)
    end
    if opts.stamps ~= nil then c.putGameSetting("showTimestamps", opts.stamps) end
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
    local ok = type(addon.Chat) == "table" and type(addon.Chat.FONT) == "string"
        and type(c.setChatFrame) == "function" and type(c.chatFrame) == "function"
        and type(c.wheelChat) == "function" and type(c.fadeTab) == "function"
    t.ok(ok, "the chat readability part is loaded and the fake client has chat window controls")
    return ok
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function fontsOf(c) return { c.chatFrame(1).font, c.chatFrame(2).font } end

tests["chat read 236: every readability row is off at first and changes nothing"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    local want = {
        [Ch.FONT] = { "number", 0 }, [Ch.KEEP] = { "bool", false }, [Ch.FADE] = { "number", 0 },
        [Ch.SCROLL] = { "number", 0 }, [Ch.STAMPS] = { "choice", "off" }, [Ch.TABS] = { "bool", false },
    }
    local Topics = addon.Settings.Topics
    for key, shape in pairs(want) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        if row then
            t.eq({ row.scope, row.type, row.default, row.group }, { "account", shape[1], shape[2], "general.chat" }, key)
            for _, word in ipairs({ "chat", "readability" }) do
                t.ok(Topics.Match(row, Topics.Words(word)) ~= nil, key .. " is found by " .. word)
            end
        end
    end
    t.eq(fontsOf(c), { 14, 12 }, "the game's text size")
    t.eq({ c.chatFrame(1).fading, c.chatFrame(1).time }, { true, 120 }, "the game's fading")
    t.eq(c.chatFilterCount(SAY), 1, "only the links filter")
    t.eq(c.pushChat(SAY, "hello"), "hello", "no stamp")
    c.wheelChat(1, 1)
    t.eq(c.chatFrame(1).moves, { "up" }, "the game's own one line")
    c.fadeTab(1, 0)
    t.eq(c.chatFrame(1).tabAlpha, 0, "the tab fades as the game says")
end

tests["chat read 236: text size applies to each window and gives the game's size back"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.FONT, 18), true)
    t.eq(fontsOf(c), { 18, 18 })
    t.eq(addon.settings:set(addon.Chat.FONT, 16), true)
    t.eq(fontsOf(c), { 16, 16 })
    t.eq(addon.settings:set(addon.Chat.FONT, 0), true)
    t.eq(fontsOf(c), { 14, 12 }, "each window's own size again")
    t.eq(addon.problems:count(), base)
end

tests["chat read 236: keep lines and fade time, each its own row, the game's back when off"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.KEEP, true), true)
    t.eq({ c.chatFrame(1).fading, c.chatFrame(2).fading }, { false, false })
    t.eq(addon.settings:set(addon.Chat.KEEP, false), true)
    t.eq({ c.chatFrame(1).fading, c.chatFrame(1).time }, { true, 120 })
    t.eq(addon.settings:set(addon.Chat.FADE, 300), true)
    t.eq({ c.chatFrame(1).fading, c.chatFrame(1).time, c.chatFrame(2).time }, { true, 300, 300 })
    t.eq(addon.settings:set(addon.Chat.FADE, 0), true)
    t.eq({ c.chatFrame(1).time, c.chatFrame(2).time }, { 120, 60 })
end

tests["chat read 236: wheel lines per notch, Ctrl to the top, Shift to the bottom"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.SCROLL, 3), true)
    c.wheelChat(1, 1)
    t.eq(c.chatFrame(1).moves, { "up", "up", "up" }, "three lines up in all")
    c.chatFrame(1).moves = {}
    c.wheelChat(1, -1)
    t.eq(c.chatFrame(1).moves, { "down", "down", "down" })
    c.chatFrame(1).moves = {}
    c.wheelChat(1, -1, { ctrl = true })
    t.eq(c.chatFrame(1).moves[#c.chatFrame(1).moves], "top")
    c.wheelChat(1, 1, { shift = true })
    t.eq(c.chatFrame(1).moves[#c.chatFrame(1).moves], "bottom")
    t.eq(addon.settings:set(addon.Chat.SCROLL, 0), true)
    c.chatFrame(1).moves = {}
    c.wheelChat(1, 1, { ctrl = true })
    t.eq(c.chatFrame(1).moves, { "up" }, "off: the game's own scrolling only")
end

tests["chat read 236: timestamps in each format, and none when off"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    t.eq(c.pushChat(SAY, "hello"), "[09:05] hello")
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM:SS"), true)
    t.eq(c.pushChat(SAY, "hello"), "[09:05:07] hello")
    t.eq(c.chatFilterCount(SAY), 2, "one stamp filter beside the links filter")
    t.eq(addon.settings:set(addon.Chat.STAMPS, "off"), true)
    t.eq(c.pushChat(SAY, "hello"), "hello")
    t.eq(c.chatFilterCount(SAY), 1)
end

tests["chat read 236: the game's own timestamps on - no second stamp, said why"] = function(t)
    local c, addon = boot({ stamps = "%H:%M " })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    t.eq(c.pushChat(SAY, "hello"), "hello", "the game stamps it, this add-on does not")
    t.eq(addon.chat.state("stamps"), "game")
    local c2, addon2 = boot({ stamps = "none" })
    t.eq(addon2.settings:set(addon2.Chat.STAMPS, "HH:MM"), true)
    t.eq(c2.pushChat(SAY, "hello"), "[09:05] hello", "the game's are off: this add-on stamps")
end

tests["chat read 236: Prat's Timestamps or Font on - no double stamp, the size left to Prat"] = function(t)
    local c, addon = boot({ prat = { Timestamps = true, Font = true, Fading = false } })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    t.eq(addon.settings:set(addon.Chat.FONT, 18), true)
    t.eq(addon.settings:set(addon.Chat.KEEP, true), true)
    local theirs = "[09:05] hello"
    t.eq(c.pushChat(SAY, theirs), theirs, "Prat's stamp, and no second one")
    t.eq(fontsOf(c), { 14, 12 }, "the size is Prat's")
    t.eq(c.chatFrame(1).fading, false, "Prat's Fading is off: keep lines works")
    t.eq(addon.chat.state("stamps"), "prat")
    t.eq(addon.chat.state("font"), "prat")
    local status = table.concat(said(c, "chat"), " / ")
    t.ok(string.find(status, "Timestamps", 1, true) ~= nil, "the chat word says why: " .. status)
end

tests["chat read 236: a hidden line passes through the stamp filter unread"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    t.eq(c.pushChat(SAY, SECRET_LINE), SECRET_LINE)
    t.eq(addon.problems:count(), base)
end

tests["chat read 236: the clock read raising, then recovering"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    local base = addon.problems:count("chat")
    local real = c.localTime
    c.localTime = function() error("clock read failed") end
    t.eq(c.pushChat(SAY, "one"), "one", "the line as it came")
    t.eq(c.pushChat(SAY, "two"), "two")
    t.eq(addon.problems:count("chat"), base + 1, "one problem for that error")
    c.localTime = real
    t.eq(c.pushChat(SAY, "three"), "[09:05] three")
    c.localTime = function() return nil end
    t.eq(c.pushChat(SAY, "four"), "four", "no time known: no stamp, no problem")
    t.eq(addon.problems:count("chat"), base + 1)
end

tests["chat read 236: tabs kept visible, the game's fade back when off"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    c.fadeTab(1, 0.2)
    t.eq(addon.settings:set(addon.Chat.TABS, true), true)
    t.eq({ c.chatFrame(1).tabAlpha, c.chatFrame(2).tabAlpha }, { 1, 1 })
    c.fadeTab(1, 0)
    t.eq(c.chatFrame(1).tabAlpha, 1, "held")
    t.eq(addon.settings:set(addon.Chat.TABS, false), true)
    t.eq(c.chatFrame(1).tabAlpha, 0, "what the game asked last")
end

tests["chat read 236: reload keeps every readability setting and applies it at login"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Ch = addon.Chat
    t.eq(addon.settings:set(Ch.FONT, 17), true)
    t.eq(addon.settings:set(Ch.KEEP, true), true)
    t.eq(addon.settings:set(Ch.SCROLL, 2), true)
    t.eq(addon.settings:set(Ch.STAMPS, "HH:MM:SS"), true)
    t.eq(addon.settings:set(Ch.TABS, true), true)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq({ addon2.settings:get(Ch.FONT), addon2.settings:get(Ch.KEEP), addon2.settings:get(Ch.SCROLL),
        addon2.settings:get(Ch.STAMPS), addon2.settings:get(Ch.TABS) }, { 17, true, 2, "HH:MM:SS", true })
    t.eq(fontsOf(c2), { 17, 17 })
    t.eq(c2.chatFrame(1).fading, false)
    t.eq(c2.pushChat(SAY, "hi"), "[09:05:07] hi")
    c2.wheelChat(1, 1)
    t.eq(c2.chatFrame(1).moves, { "up", "up" })
    t.eq(c2.chatFrame(1).tabAlpha, 1)
end

tests["chat read 236: repeated events apply once - one stamp filter, one stamp"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(addon.settings:set(addon.Chat.STAMPS, "HH:MM"), true)
    t.eq(addon.settings:set(addon.Chat.FONT, 18), true)
    for _ = 1, 3 do
        c.fire("PLAYER_ENTERING_WORLD")
        c.fire("ADDON_LOADED", "SomeOtherAddon")
    end
    t.eq(c.chatFilterCount(SAY), 2)
    t.eq(c.pushChat(SAY, "hi"), "[09:05] hi")
    t.eq(addon.settings:set(addon.Chat.FONT, 0), true)
    t.eq(fontsOf(c), { 14, 12 }, "the game's size, not one this add-on set")
    t.eq(addon.problems:count(), base)
end

return tests
