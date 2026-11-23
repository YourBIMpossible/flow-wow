local _, ns = ...
-- Chat part 1 (N60a): copying chat text and links, on the whole add-on
-- loaded on a fake client. A chat line goes in through the client's chat
-- filter (c.pushChat), a link is clicked through the client's link click
-- (c.clickLink), the text to copy stands in the client's copy box and the
-- button is the client's window button on the chat window. Per lead
-- section 236: a read raising then recovering, a reload keeping the
-- settings, the filter registered once over repeated events. Problems are
-- counted against the count after boot. Look only: nothing is sent, no
-- browser is opened and no link of the game's own is changed. Made-up
-- lines. Not tested in game.
-- Fails before: UI/Chat.lua is absent (addon.Chat is nil) and the fake
-- client has no chat controls (c.pushChat is nil).
local tests = {}

local PRAT, PRAT_URLS, PRAT_COPY = "Prat-3.0", "UrlCopy", "CopyChat"
local WINDOW = "ChatFrame1"
local SAY, GUILD = "CHAT_MSG_SAY", "CHAT_MSG_GUILD"
local URL = "https://example.com/guide"
local ITEM_LINK = "item:2589::::::::10:::::"
local ITEM = "|cff1eff00|H" .. ITEM_LINK .. "|h[Linen Cloth]|h|r"

-- opts: account / char (saved tables: a reload), window = false (no chat
-- window to put a button on), prat = { [module] = true / false } (Prat
-- loaded, each named module on or off; an empty table: Prat says nothing).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if opts.window ~= false then c.setWindow(WINDOW, { shown = true }) end
    if type(opts.prat) == "table" then
        c.setLoaded(PRAT, true)
        if type(c.setPratModule) == "function" then
            for name, on in pairs(opts.prat) do c.setPratModule(name, on) end
        end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function ready(t, c, addon)
    local ok = type(addon.Chat) == "table" and type(addon.chat) == "table" and type(c.pushChat) == "function"
        and type(c.clickLink) == "function" and type(c.chatFilterCount) == "function"
    t.ok(ok, "the chat module is loaded and the fake client has its chat controls")
    return ok
end

local function off(key) return { settings = { chat = { [key] = false } } } end

local function wrapped(addon, url)
    return addon.Chat.Link(url, addon.Chat.Prefix(ns.id))
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

-- How many lines since `from` name `word`.
local function naming(c, from, word)
    local n = 0
    for i = from, #c.printed do
        if string.find(c.printed[i], word, 1, true) then n = n + 1 end
    end
    return n
end

local function lastBox(c) return c.copyBoxes[#c.copyBoxes] end

-- This add-on's buttons on the chat window.
local function buttons(c)
    local out = {}
    for _, h in ipairs(c.windowButtons) do
        if h.frame == WINDOW then out[#out + 1] = h end
    end
    return out
end

local function linkIn(text)
    return string.match(text, "|H(.-)|h")
end

tests["chat 236: a line with an address reaches the window with the address wrapped once"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    t.eq(c.chatFilterCount(SAY), 1, "one filter on a say line")
    t.eq(c.chatFilterCount(GUILD), 1, "one filter on a guild line")
    local shown = c.pushChat(SAY, "look at " .. URL .. " please")
    t.eq(shown, "look at " .. wrapped(addon, URL) .. " please")
    t.eq(c.chatLines(1, 5), { shown }, "the window holds the wrapped line")
    local again, n = addon.Chat.Wrap(shown, addon.Chat.Prefix(ns.id))
    t.eq(again, shown, "a second pass does not wrap it again")
    t.eq(n, 0)
    t.eq(c.pushChat(SAY, "no address here"), "no address here")
    t.eq(addon.problems:count(), base, "no problem")
    t.eq(#c.copyBoxes, 0, "no box until the player asks")
end

tests["chat 236: a click on the address opens the copy box with it, unfocused; no browser"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local shown = c.pushChat(GUILD, "guide: " .. URL .. ".")
    t.eq(shown, "guide: " .. wrapped(addon, URL) .. ".")
    t.eq(c.clickLink(linkIn(shown)), 1, "the click is this add-on's")
    local box = lastBox(c)
    t.ok(box ~= nil, "a copy box")
    if not box then return end
    t.eq(box.text, URL)
    t.eq(box.shown, true)
    t.eq(box.focused, false, "it does not take the keyboard")
    c.pushChat(SAY, "and www.example.org")
    t.eq(c.clickLink(linkIn(c.chatLines(1, 1)[1])), 1)
    t.eq(#c.copyBoxes, 1, "the same box again")
    t.eq(lastBox(c).text, "www.example.org")
end

tests["chat 236: an item link is the same bytes and its click is not this add-on's"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    local line = "wts " .. ITEM .. " 5s each"
    t.eq(c.pushChat(SAY, line), line)
    t.eq(c.clickLink(ITEM_LINK), 0, "nothing of this add-on's hears an item click")
    t.eq(c.clickLink("player:Thrall-Realm:123:WHISPER"), 0)
    t.eq(c.linkClicks, { ITEM_LINK, "player:Thrall-Realm:123:WHISPER" }, "the game handled both itself")
    t.eq(#c.copyBoxes, 0, "no box")
    local mixed = c.pushChat(SAY, ITEM .. " see " .. URL .. " " .. ITEM)
    t.eq(mixed, ITEM .. " see " .. wrapped(addon, URL) .. " " .. ITEM)
    t.eq(addon.problems:count(), base)
end

tests["chat 236: chat copy opens the copy box with the window's lines as plain text"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local none = said(c, "chat copy")
    t.eq(#none, 1, "no lines yet: one line says so")
    t.eq(#c.copyBoxes, 0)
    c.pushChat(SAY, "|cff00ff00Thrall|r: hello")
    c.pushChat(SAY, "wts " .. ITEM)
    c.pushChat(GUILD, "see " .. URL .. " now")
    t.eq(said(c, "chat copy"), {}, "nothing said when the box opens")
    local box = lastBox(c)
    t.ok(box ~= nil, "a copy box")
    if not box then return end
    t.eq(box.text, "Thrall: hello\nwts [Linen Cloth]\nsee " .. URL .. " now")
    t.eq(box.shown, true)
    said(c, "chat copy 2")
    t.eq(lastBox(c).text, "wts [Linen Cloth]\nsee " .. URL .. " now", "the last two lines")
    t.eq(#c.copyBoxes, 1)
end

tests["chat 236: the button on the chat window opens the same box"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local mine = buttons(c)
    t.eq(#mine, 1, "one button on the chat window")
    if #mine ~= 1 then return end
    t.eq(mine[1].shown, true)
    c.pushChat(SAY, "one")
    c.pushChat(SAY, "two")
    mine[1].click()
    t.eq(lastBox(c) and lastBox(c).text, "one\ntwo")
    t.eq(lastBox(c) and lastBox(c).shown, true)
end

tests["chat 236: no chat window at login - the button is made when the window is there"] = function(t)
    local c, addon = boot({ window = false })
    if not ready(t, c, addon) then return end
    t.eq(#buttons(c), 0)
    c.setWindow(WINDOW, { shown = true })
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(#buttons(c), 1)
end

tests["chat 236: the links setting off - no filter, no wrapping; the copy button is its own switch"] = function(t)
    local c, addon = boot({ account = off("urls") })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:get(addon.Chat.URLS), false)
    t.eq(c.chatFilterCount(SAY), 0, "no filter registered")
    t.eq(c.pushChat(SAY, "look at " .. URL), "look at " .. URL)
    t.eq(c.clickLink(addon.Chat.Prefix(ns.id) .. ":" .. URL), 0, "and no link click is followed")
    t.eq(#buttons(c), 1, "the copy button is still there")
    t.eq(buttons(c)[1] and buttons(c)[1].shown, true)
    -- Turned on while playing, then off again: no reload needed.
    t.eq(addon.settings:set(addon.Chat.URLS, true), true)
    t.eq(c.chatFilterCount(SAY), 1)
    t.eq(c.pushChat(SAY, URL), wrapped(addon, URL))
    t.eq(addon.settings:set(addon.Chat.URLS, false), true)
    t.eq(c.chatFilterCount(SAY), 0)
    t.eq(c.pushChat(SAY, URL), URL)
end

tests["chat 236: the copy setting off - no button and the word says it is off; links still work"] = function(t)
    local c, addon = boot({ account = off("copy") })
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:get(addon.Chat.COPY), false)
    t.eq(#buttons(c), 0, "no button made")
    c.pushChat(SAY, "a line")
    local lines = said(c, "chat copy")
    t.eq(#lines, 1)
    t.ok(string.find(lines[1] or "", "off", 1, true) ~= nil, "says it is off: " .. tostring(lines[1]))
    t.eq(#c.copyBoxes, 0)
    t.eq(c.chatFilterCount(SAY), 1, "the links are their own switch")
    t.eq(addon.settings:set(addon.Chat.COPY, true), true)
    t.eq(#buttons(c), 1)
    t.eq(buttons(c)[1] and buttons(c)[1].shown, true)
    t.eq(addon.settings:set(addon.Chat.COPY, false), true)
    t.eq(buttons(c)[1] and buttons(c)[1].shown, false)
end

tests["chat 236: both settings are on at first, filed under chat and found by the owner's words"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local Topics = addon.Settings.Topics
    for _, key in ipairs({ addon.Chat.COPY, addon.Chat.URLS }) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        if row then
            t.eq({ row.scope, row.type, row.default, row.group }, { "account", "bool", true, "general.chat" }, key)
            local topic, section = Topics.Find(row.group)
            t.eq(topic and topic.id, "general")
            t.eq(section and section.id, "chat")
            for _, word in ipairs({ "chat", "copy", "url", "link", "text", "prat" }) do
                t.ok(Topics.Match(row, Topics.Words(word)) ~= nil, key .. " is found by " .. word)
            end
        end
    end
    t.eq({ addon.Chat.COPY, addon.Chat.URLS }, { "chat.copy", "chat.urls" })
end

tests["chat 236: Prat loaded with its two modules on - nothing is wrapped twice, no second button, said once"] = function(t)
    local c, addon = boot({ prat = { [PRAT_URLS] = true, [PRAT_COPY] = true } })
    if not ready(t, c, addon) then return end
    t.eq(c.chatFilterCount(SAY), 0, "no filter beside Prat's")
    local theirs = "see |Hurl:" .. URL .. "|h[" .. URL .. "]|h"
    t.eq(c.pushChat(SAY, theirs), theirs, "Prat's link is left as it is")
    t.eq(c.pushChat(SAY, "see " .. URL), "see " .. URL, "and a bare address is Prat's to wrap")
    t.eq(#buttons(c), 0, "no button beside Prat's")
    t.eq(naming(c, 1, PRAT_URLS), 1, "said once for the links")
    t.eq(naming(c, 1, PRAT_COPY), 1, "said once for the button")
    c.fire("PLAYER_ENTERING_WORLD"); c.fire("PLAYER_ENTERING_WORLD"); c.fire("ADDON_LOADED", PRAT)
    t.eq(naming(c, 1, PRAT_URLS), 1, "still once")
    t.eq(naming(c, 1, PRAT_COPY), 1)
    t.eq(c.chatFilterCount(SAY), 0)
    local status = table.concat(said(c, "chat"), " / ")
    t.ok(string.find(status, PRAT_URLS, 1, true) ~= nil and string.find(status, PRAT_COPY, 1, true) ~= nil,
        "the chat word says why: " .. status)
end

tests["chat 236: Prat loaded with those modules off - this add-on does both"] = function(t)
    local c, addon = boot({ prat = { [PRAT_URLS] = false, [PRAT_COPY] = false } })
    if not ready(t, c, addon) then return end
    t.eq(c.chatFilterCount(SAY), 1)
    t.eq(c.pushChat(SAY, URL), wrapped(addon, URL))
    t.eq(#buttons(c), 1)
    t.eq(naming(c, 1, "Prat"), 0, "nothing said")
end

tests["chat 236: Prat loaded with one module on - only that one stands down"] = function(t)
    local c, addon = boot({ prat = { [PRAT_URLS] = true, [PRAT_COPY] = false } })
    if not ready(t, c, addon) then return end
    t.eq(c.chatFilterCount(SAY), 0)
    t.eq(#buttons(c), 1)
    t.eq(buttons(c)[1] and buttons(c)[1].shown, true)
end

tests["chat 236: Prat loaded and saying nothing about a module - stands down, never wraps twice"] = function(t)
    local c, addon = boot({ prat = {} })
    if not ready(t, c, addon) then return end
    t.eq(c.chatFilterCount(SAY), 0)
    t.eq(c.pushChat(SAY, URL), URL)
    t.eq(#buttons(c), 0)
end

tests["chat 236: Prat loading later, or its module turned on later, is seen without a reload"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(c.chatFilterCount(SAY), 1)
    t.eq(buttons(c)[1] and buttons(c)[1].shown, true)
    c.setLoaded(PRAT, true)
    c.setPratModule(PRAT_URLS, true)
    c.setPratModule(PRAT_COPY, true)
    c.fire("ADDON_LOADED", PRAT)
    t.eq(c.chatFilterCount(SAY), 0, "the filter is taken away")
    t.eq(c.pushChat(SAY, URL), URL)
    t.eq(buttons(c)[1] and buttons(c)[1].shown, false, "and the button hidden")
    -- Prat's module turned off again: seen at the next zone change.
    c.setPratModule(PRAT_URLS, false)
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(c.chatFilterCount(SAY), 1)
end

tests["chat 236: the chat lines read raising, then recovering"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    c.pushChat(SAY, "a line")
    local base = addon.problems:count("chat")
    local real = c.chatLines
    c.chatLines = function() error("chat read failed") end
    local lines = said(c, "chat copy")
    t.eq(#lines, 1, "one line says it could not be read")
    t.eq(#c.copyBoxes, 0, "no box while the read raises")
    t.eq(addon.problems:count("chat"), base + 1, "one chat problem for that error")
    local mine = buttons(c)
    if mine[1] then mine[1].click() end
    t.eq(#c.copyBoxes, 0, "nor from the button")
    c.chatLines = real
    t.eq(said(c, "chat copy"), {})
    t.eq(lastBox(c) and lastBox(c).text, "a line", "the box once the read works")
    -- A client that does not give the lines at all: said, and no problem.
    local now = addon.problems:count("chat")
    c.chatLines = function() return nil end
    t.eq(#said(c, "chat copy"), 1)
    t.eq(addon.problems:count("chat"), now)
end

tests["chat 236: a client with no chat filter or no link hook - nothing wrapped, said by the chat word, no problem"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local c2 = ns.make.fakeClient()
    c2.setSaved(ns.id.accountDB, {})
    c2.setSaved(ns.id.charDB, {})
    c2.setLinkHook(false)
    local addon2 = ns.offline.addon(c2)
    c2.fire("ADDON_LOADED", ns.id.addon); c2.fire("PLAYER_LOGIN"); c2.fire("PLAYER_ENTERING_WORLD")
    c2.advance(5, 20)
    t.eq(c2.chatFilterCount(SAY), 0, "no link that could not be clicked")
    t.eq(c2.pushChat(SAY, URL), URL)
    t.eq(addon2.problems:count("chat"), 0)
    t.eq(addon2.chat.state("urls"), "unavailable")
    t.eq(addon.chat.state("urls"), "on")
end

tests["chat 236: reload keeps both settings"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(addon.settings:set(addon.Chat.URLS, false), true)
    t.eq(addon.settings:set(addon.Chat.COPY, false), true)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(addon2.Chat.URLS), false, "links still off after the reload")
    t.eq(addon2.settings:get(addon2.Chat.COPY), false, "copy still off after the reload")
    t.eq(c2.chatFilterCount(SAY), 0)
    t.eq(c2.pushChat(SAY, URL), URL)
    t.eq(#buttons(c2), 0)
end

tests["chat 236: the filter and the button are made once, whatever events repeat"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local base = addon.problems:count()
    for _ = 1, 3 do
        c.fire("PLAYER_ENTERING_WORLD")
        c.fire("ADDON_LOADED", "SomeOtherAddon")
        c.setCombat(true)
        c.setCombat(false)
        c.advance(2, 4)
    end
    t.eq(c.chatFilterCount(SAY), 1, "one filter on a say line")
    t.eq(c.chatFilterCount(GUILD), 1)
    t.eq(c.pushChat(SAY, "see " .. URL), "see " .. wrapped(addon, URL), "wrapped once")
    t.eq(c.clickLink(addon.Chat.Prefix(ns.id) .. ":" .. URL), 1, "one listener to the click")
    t.eq(#buttons(c), 1, "one button")
    t.eq(addon.problems:count(), base)
end

tests["chat 236: the chat word is in help and says how each part stands"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local head = ns.id.title .. ": " .. ns.id.slash .. " " .. addon.Chat.WORD .. " - "
    local help = said(c, "help " .. addon.Chat.WORD)
    t.eq(#help, 1, "one help line for the word")
    local line = help[1] or ""
    t.eq(line:sub(1, #head), head)
    t.ok(#line > #head and line ~= head .. addon.Diag.NO_HELP, "and it says what the word does: " .. line)
    local status = said(c, "chat")
    t.ok(#status >= 2, "a line for the links and one for the copy button: " .. #status)
    t.eq(addon.chat.state("urls"), "on")
    t.eq(addon.chat.state("copy"), "on")
end

return tests
