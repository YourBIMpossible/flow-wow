local _, ns = ...

-- Chat, part 1 (row N60a): copy chat text, and copy a web address someone
-- typed in chat. Look only: nothing is sent, no browser is opened, no chat
-- line is hidden and no link of the game's own is changed. All of it is
-- this add-on's own code; none of it is taken from another add-on.
--
-- Copy chat text. `<slash> chat copy [n]` and a small Copy button on the
-- main chat window put the window's last n lines (Chat.LINES when n is
-- left out, never more than Chat.LINES_MAX) into the client's copy box as
-- plain text: colour and picture codes taken out, a link shown as the text
-- it shows ("[Linen Cloth]"). The lines are read only when the player asks.
--
-- Links. A web address in a chat line (http:// or https://, www., a bare
-- name.tld of a well-known ending with or without a path, an ip:port) is
-- wrapped in this add-on's own hyperlink before the line is shown. A click
-- on it puts the address in the copy box; that is all a click does. What
-- is already inside a link (an item, a player, another add-on's link) is
-- never looked into, so those stay the same bytes and the game handles
-- their clicks as before. Chat text is data: it is never run and never
-- used as a pattern.
--
-- Two settings, each its own switch, both on at first (as the roll hint,
-- Gear/RollHint.lua: something shown, nothing done for the player):
--   chat.copy   "Copy chat text": the button and the copy word
--   chat.urls   "Clickable links in chat": the filter and the link click
-- Off means not there: no filter is registered, no button is made.
--
-- Beside Prat (ns.id.prat): when Prat is loaded and its matching module is
-- on (UrlCopy for the links, CopyChat for the button), or Prat does not
-- say, this add-on's matching part stands down, so no line is wrapped
-- twice and there is no second button. It says so once in chat and in
-- `<slash> chat`. The copy word still answers: the player asked for it.
-- Looked at again when an add-on loads, on entering the world and when a
-- fight ends.
--
--   Chat.Prefix(id)          -> the kind of this add-on's link
--   Chat.Link(url, prefix)   -> the link text for one address
--   Chat.IsUrl(word)         -> true when the word is an address
--   Chat.Wrap(text, prefix)  -> text with each address wrapped, how many
--   Chat.Plain(text[, prefix]) -> the line as a player wants to paste it
--   api = Chat.Declare(k[, diag])
--     api.state(part)   "urls" or "copy": "on", "off", "prat" (standing
--                       down), "unavailable" (the client gives no way) or
--                       "waiting" (the button is not made yet)
--     api.lines()       what `<slash> chat` says
--     api.errors()      how many things failed
--     api.run(rest)     the chat word
--   ns.use(Chat.NAME) -> { State = api.state, Lines = api.lines }
--
-- CLIENT (Core/Client.lua, all first guesses, not seen in game on 16001):
-- chatLines, chatFilter, onLinkClick, pratModule, and the existing
-- copyBox, windowButton and addonLoaded.
--
-- The link is "|Haddon:<this add-on>:url:<address>|h[<address>]|h". The
-- "addon" link type is the one the game's own link click leaves to add-ons
-- on current clients; that 16001 does so is a first guess (needs a game
-- look: a click must open the box and show no error).

local Chat = {}
ns.Chat = Chat

Chat.NAME = "chat"
Chat.WORD = "chat"
Chat.COPY = "chat.copy"
Chat.URLS = "chat.urls"
Chat.GROUP = "general.chat"
-- Prat's modules that do the same (module names as its files name them).
Chat.PRAT_URLS, Chat.PRAT_COPY = "UrlCopy", "CopyChat"
-- The main chat window: its number and its frame's name.
Chat.FRAME, Chat.WINDOW = 1, "ChatFrame1"
Chat.LINES, Chat.LINES_MAX = 100, 500
Chat.URL_MAX = 400
Chat.WIDTH, Chat.HEIGHT = 520, 320

-- The chat events whose lines are looked at. Event names as the game has
-- long listed them (warcraft.wiki.gg, Events); one this client does not
-- have never comes.
Chat.EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- The endings a bare name must have to count as an address ("wowhead.com").
-- Kept short to be careful: "notes.txt" and "ok.so" are not links.
Chat.TLDS = {
    com = true, net = true, org = true, gg = true, io = true, tv = true, edu = true, gov = true,
    info = true, de = true, fr = true, eu = true, ru = true, uk = true, ca = true, app = true,
    dev = true, xyz = true,
}

-- Part 2 (row N60b): readability. Each its own row, each off at first:
-- each changes how the game's own chat windows look or move, so the
-- player turns it on (timestamps too: the game has its own option).
--   chat.fontSize     text size of every chat window, 0 = the game's
--   chat.keepLines    lines stay instead of fading
--   chat.fadeTime     seconds before a line fades, 0 = the game's
--   chat.scrollLines  lines per wheel notch, Ctrl+wheel to the top,
--                     Shift+wheel to the bottom; 0 = the game's scrolling
--   chat.timestamps   "off", "HH:MM" or "HH:MM:SS" before each chat line
--   chat.tabsVisible  the chat tabs do not fade away
-- Turned off, or the module stopped: each window gets back what the game
-- had before this add-on changed it. Beside Prat: its Font, Fading and
-- Timestamps modules (module names as its files name them) stand the
-- matching part down, as for part 1; the game's own timestamps
-- (showTimestamps not "none") stand the timestamps down. No line is
-- stamped twice. A line the client hides is passed on unread.
Chat.FONT, Chat.KEEP, Chat.FADE = "chat.fontSize", "chat.keepLines", "chat.fadeTime"
Chat.SCROLL, Chat.STAMPS, Chat.TABS = "chat.scrollLines", "chat.timestamps", "chat.tabsVisible"
Chat.PRAT_FONT, Chat.PRAT_FADE, Chat.PRAT_STAMPS = "Font", "Fading", "Timestamps"
-- The chat windows looked at: ChatFrame1 to ChatFrame10, the game's
-- NUM_CHAT_WINDOWS on current clients (first guess for 16001). A window
-- that is not there is passed over.
Chat.WINDOWS = 10
Chat.FONT_MIN, Chat.FONT_MAX = 10, 20
Chat.FADE_MAX, Chat.SCROLL_MAX = 600, 10
Chat.TAB_ALPHA = 1
-- The game's own timestamp option (Interface options, Social); "none" is
-- off (warcraft.wiki.gg, CVar showTimestamps).
Chat.GAME_STAMPS, Chat.GAME_STAMPS_OFF = "showTimestamps", "none"
Chat.STAMP_OFF = "off"
Chat.STAMP_CHOICES = { "off", "HH:MM", "HH:MM:SS" }
Chat.STAMP_FORMAT = { ["HH:MM"] = "[%02d:%02d] ", ["HH:MM:SS"] = "[%02d:%02d:%02d] " }
Chat.READ_PARTS = { "font", "fade", "scroll", "stamps", "tabs" }

Chat.HELP = "how the chat links, the chat copy button and the chat readability settings stand; chat copy "
    .. "[n] puts the main chat window's last n lines in a box to copy"
Chat.LABEL = {
    urls = "chat links", copy = "chat copy button", font = "chat text size", fade = "chat fading",
    scroll = "chat wheel scrolling", stamps = "chat timestamps", tabs = "chat tabs kept visible",
}
Chat.STATE = {
    on = "on", off = "off (its setting is off)", prat = "standing down",
    unavailable = "not available", waiting = "not made yet",
    game = "standing down",
}
Chat.GAME_STAMPS_WHY = "the game's own chat timestamps are on"

-- The stamp put before a chat line, or nil when the format is not one of
-- Chat.STAMP_FORMAT or a part of the time is not a number.
function Chat.Stamp(format, h, m, s)
    local pattern = Chat.STAMP_FORMAT[format]
    if pattern == nil or type(h) ~= "number" or type(m) ~= "number" or type(s) ~= "number" then return nil end
    if format == "HH:MM" then return string.format(pattern, h, m) end
    return string.format(pattern, h, m, s)
end
Chat.COPY_OFF = "copying chat text is off: turn on \"Copy chat text\" in the settings."
Chat.NO_LINES = "this client does not give the chat window's lines."
Chat.READ_FAILED = "the chat lines could not be read; it is kept as a problem."
Chat.NOTHING = "no chat lines to copy yet."
Chat.NO_BOX = "this client cannot draw the copy box."
Chat.NOT_STARTED = "not started yet."

---------------------------------------------------------------------------
-- Pure: the codes in a chat line, addresses, plain text.
---------------------------------------------------------------------------

-- A code that runs to its own closing code.
local CLOSERS = { H = "|h", T = "|t", A = "|a", K = "|k" }

-- A chat line as its parts, in order: { text = } for what is shown as
-- typed, { code = letter, raw = } for a code of the game ("|cff00ff00",
-- "|r", "||", "|Hitem:1|h", "|h", "|Tpath:16|t"). A code that never closes
-- is { code = "open", raw = the rest of the line }.
local function tokens(text)
    local out, pos, n = {}, 1, #text
    while pos <= n do
        local bar = text:find("|", pos, true)
        if not bar then
            out[#out + 1] = { text = text:sub(pos) }
            break
        end
        if bar > pos then out[#out + 1] = { text = text:sub(pos, bar - 1) } end
        local letter = text:sub(bar + 1, bar + 1)
        local last = bar + 1
        if letter == "" then
            last = bar
        elseif letter == "c" then
            if text:find("^%x%x%x%x%x%x%x%x", bar + 2) then last = bar + 9 end
        elseif CLOSERS[letter] then
            local _, to = text:find(CLOSERS[letter], bar + 2, true)
            if to then
                last = to
            else
                letter, last = "open", n
            end
        end
        out[#out + 1] = { code = letter, raw = text:sub(bar, last) }
        pos = last + 1
    end
    return out
end

function Chat.Prefix(id)
    if type(id) ~= "table" or type(id.addon) ~= "string" then id = ns.id end
    return "addon:" .. id.addon .. ":url"
end

function Chat.Link(url, prefix)
    return "|H" .. prefix .. ":" .. url .. "|h[" .. url .. "]|h"
end

local function octet(s)
    local n = tonumber(s)
    return n ~= nil and #s <= 3 and n <= 255
end

-- What may follow the host of an address: nothing, a path, a query, a
-- fragment, or a port and then one of those.
local function tailOk(rest)
    if rest == "" then return true end
    local first = rest:sub(1, 1)
    if first == "/" or first == "?" or first == "#" then return true end
    if first == ":" then
        return rest:find("^:%d+$") ~= nil or rest:find("^:%d+[/%?#]") ~= nil
    end
    return false
end

-- True when the word, with nothing before or after it, is an address:
--   http:// or https:// and something after it
--   www.name.ending
--   name.ending where the ending is one of Chat.TLDS
--   four numbers of 0 to 255 and a port ("10.0.0.5:8080")
-- each with or without a port, a path, a query or a fragment. Anything
-- else is not: a version ("1.2.3"), a file name, a mail address, a bare
-- ip, two words with a full stop between them.
function Chat.IsUrl(word)
    if type(word) ~= "string" or #word < 4 or #word > Chat.URL_MAX then return false end
    if word:find("|", 1, true) or word:find("%s") then return false end
    local low = word:lower()
    if low:find("^https?://[%w%[]") then return true end
    local host, rest = low:match("^([%w][%w%-%.]*)(.*)$")
    if not host or not tailOk(rest) then return false end
    if host:find("..", 1, true) or host:sub(-1) == "." or host:sub(-1) == "-" then return false end
    local o1, o2, o3, o4 = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if o1 then
        local port = rest:match("^:(%d+)")
        if not port or #port > 5 then return false end
        local n = tonumber(port)
        return octet(o1) and octet(o2) and octet(o3) and octet(o4) and n >= 1 and n <= 65535
    end
    local ending = host:match("%.(%a+)$")
    if not ending or #ending < 2 then return false end
    if Chat.TLDS[ending] then return true end
    return host:find("^www%.[%w%-]+%.") ~= nil
end

-- A typed word as what stands before the address, the address, and what
-- stands after it: brackets and quotes in front, punctuation behind.
local SPLIT = "^([%(%[<\"']*)(.-)([%.,;:!%?%)%]>\"']*)$"

-- A closing bracket belongs to the address when the address opened it.
local function balance(core, trail)
    if trail:sub(1, 1) ~= ")" then return core, trail end
    local _, opens = core:gsub("%(", "")
    local _, closes = core:gsub("%)", "")
    if opens > closes then return core .. ")", trail:sub(2) end
    return core, trail
end

local function wrapPlain(chunk, prefix)
    local found = 0
    local out = chunk:gsub("%S+", function(word)
        local lead, core, trail = word:match(SPLIT)
        if not core or core == "" then return nil end
        core, trail = balance(core, trail)
        if not Chat.IsUrl(core) then return nil end
        found = found + 1
        return lead .. Chat.Link(core, prefix) .. trail
    end)
    return out, found
end

-- The line with each address wrapped in this add-on's link, and how many
-- were. Nothing inside a link that is already there, and no code of the
-- game, is looked into. With no address the very text given comes back.
function Chat.Wrap(text, prefix)
    if type(text) ~= "string" or text == "" then return text, 0 end
    if not text:find(".", 1, true) then return text, 0 end
    local parts, out, n, inLink = tokens(text), {}, 0, false
    for i = 1, #parts do
        local part = parts[i]
        if part.code ~= nil then
            if part.code == "H" then
                inLink = true
            elseif part.code == "h" then
                inLink = false
            end
            out[i] = part.raw
        elseif inLink then
            out[i] = part.text
        else
            local piece, found = wrapPlain(part.text, prefix)
            out[i] = piece
            n = n + found
        end
    end
    if n == 0 then return text, 0 end
    return table.concat(out), n
end

-- Codes that show nothing a player would paste.
local SILENT = { c = true, r = true, T = true, A = true, K = true }

-- The line as a player wants to paste it: colours and pictures out, a
-- link as the text it shows, a doubled bar as one bar. With `prefix`, a
-- link of this add-on reads as the address alone, without its brackets.
function Chat.Plain(text, prefix)
    if type(text) ~= "string" then return "" end
    if not text:find("|", 1, true) then return text end
    local parts, out, own = tokens(text), {}, false
    for i = 1, #parts do
        local part = parts[i]
        if part.code == "h" then
            own = false
        elseif own then
            -- inside this add-on's own link: the address is already out
            own = true
        elseif part.code == nil then
            out[#out + 1] = part.text
        elseif part.code == "|" then
            out[#out + 1] = "|"
        elseif part.code == "n" then
            out[#out + 1] = "\n"
        elseif part.code == "H" then
            local data = part.raw:sub(3, -3)
            if type(prefix) == "string" and data:sub(1, #prefix + 1) == prefix .. ":" then
                out[#out + 1] = data:sub(#prefix + 2)
                own = true
            end
        elseif not SILENT[part.code] then
            out[#out + 1] = part.raw
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- The module.
---------------------------------------------------------------------------

function Chat.Declare(k, diag)
    local api = {}
    local ctx = nil
    local cancels = {}
    local cancelFilter, cancelClick, button, box = nil, nil, nil, nil
    local state = { urls = "off", copy = "off", font = "off", fade = "off", scroll = "off", stamps = "off",
        tabs = "off" }
    local why, told, seen = {}, {}, {}
    local errors = 0
    function api.state(part) return state[part] end
    function api.errors() return errors end

    local function id()
        if type(k.id) == "table" then return k.id end
        return ns.id
    end

    local function client()
        if ctx then return ctx.client end
        return k.client
    end

    local function settingOn(key)
        local settings = k.settings
        if ctx then settings = ctx.settings end
        return type(settings) == "table" and settings:get(key) == true
    end

    local function problem(what, err)
        errors = errors + 1
        local text = tostring(err)
        local key = what .. "\0" .. text
        if not seen[key] then
            seen[key] = true
            if type(k.problems) == "table" then k.problems:add(Chat.NAME, what, text) end
        end
    end

    local function say(text)
        client().print(id().title .. ": " .. text)
    end

    -- The copy box with this text, shown. It never takes the keyboard.
    local function open(text)
        local c = client()
        if not box and type(c.copyBox) == "function" then
            box = c.copyBox({ name = id().framePrefix .. "ChatCopyBox", width = Chat.WIDTH,
                height = Chat.HEIGHT, title = id().title .. ": select, then copy" })
        end
        if not box then
            say(Chat.NO_BOX)
            return false
        end
        box.setText(text)
        box.show(true)
        return true
    end

    -- The main chat window's last n lines into the copy box.
    local function copy(n)
        if not settingOn(Chat.COPY) then
            say(Chat.COPY_OFF)
            return false
        end
        local c = client()
        if type(c.chatLines) ~= "function" then
            say(Chat.NO_LINES)
            return false
        end
        local ok, lines = pcall(c.chatLines, Chat.FRAME, n)
        if not ok then
            problem("chat lines", lines)
            say(Chat.READ_FAILED)
            return false
        end
        if type(lines) ~= "table" then
            say(Chat.NO_LINES)
            return false
        end
        if #lines == 0 then
            say(Chat.NOTHING)
            return false
        end
        local plain, own = {}, Chat.Prefix(id())
        for i = 1, #lines do plain[i] = Chat.Plain(lines[i], own) end
        return open(table.concat(plain, "\n"))
    end

    local function lineCount(arg)
        local n = tonumber(arg)
        if n == nil or n ~= n then return Chat.LINES end
        n = math.floor(n)
        if n < 1 then return 1 end
        if n > Chat.LINES_MAX then return Chat.LINES_MAX end
        return n
    end

    -- A click on one of this add-on's links: the address into the box.
    local function clicked(url)
        if type(url) ~= "string" or url == "" then return end
        local ok, err = pcall(open, url)
        if not ok then problem("chat link", err) end
    end

    local function filter(text)
        if state.urls ~= "on" then return nil end
        local new, n = Chat.Wrap(text, Chat.Prefix(id()))
        if n > 0 then return new end
        return nil
    end

    -- What Prat says of its module: nil when Prat is not loaded, else
    -- "on", "off" or "unknown".
    local function pratSays(module)
        local c = ctx.client
        if type(c.addonLoaded) ~= "function" or c.addonLoaded(id().prat or ns.id.prat) ~= true then
            return nil
        end
        local on = nil
        if type(c.pratModule) == "function" then
            local ok, answer = pcall(c.pratModule, module)
            if ok then on = answer end
        end
        if on == true then return "on" end
        if on == false then return "off" end
        return "unknown"
    end

    local function standDown(part, module, says)
        state[part] = "prat"
        if says == "on" then
            why[part] = "Prat's " .. module .. " is on"
        else
            why[part] = "Prat is loaded and does not say whether its " .. module .. " is on"
        end
        if not told[part] then
            told[part] = true
            say(Chat.LABEL[part] .. ": standing down, " .. why[part] .. ".")
        end
    end

    local function dropFilter()
        if cancelFilter then pcall(cancelFilter) end
        cancelFilter = nil
    end

    local function hideButton()
        if button then button.show(false) end
    end

    local function syncUrls()
        why.urls = nil
        if ctx.settings:get(Chat.URLS) ~= true then
            dropFilter()
            state.urls = "off"
            return
        end
        local says = pratSays(Chat.PRAT_URLS)
        if says == "on" or says == "unknown" then
            dropFilter()
            standDown("urls", Chat.PRAT_URLS, says)
            return
        end
        local c = ctx.client
        -- The click first: a link nobody listens to must not be written.
        if not cancelClick and type(c.onLinkClick) == "function" then
            local ok, got = pcall(c.onLinkClick, Chat.Prefix(id()), clicked)
            if not ok then
                problem("chat link click", got)
            elseif type(got) == "function" then
                cancelClick = got
            end
        end
        if cancelClick and not cancelFilter and type(c.chatFilter) == "function" then
            local ok, got = pcall(c.chatFilter, Chat.EVENTS, filter)
            if not ok then
                problem("chat filter", got)
            elseif type(got) == "function" then
                cancelFilter = got
            end
        end
        if cancelFilter then
            state.urls = "on"
        else
            state.urls = "unavailable"
            why.urls = "this client gives no chat filter or no link click to follow"
        end
    end

    local function syncCopy()
        why.copy = nil
        if ctx.settings:get(Chat.COPY) ~= true then
            hideButton()
            state.copy = "off"
            return
        end
        local says = pratSays(Chat.PRAT_COPY)
        if says == "on" or says == "unknown" then
            hideButton()
            standDown("copy", Chat.PRAT_COPY, says)
            return
        end
        if not button then
            local c = ctx.client
            local reason = "this client cannot put a button on a window"
            if type(c.windowButton) == "function" then
                local ok, h, whyNot = pcall(c.windowButton, Chat.WINDOW, {
                    name = id().framePrefix .. "ChatCopyButton",
                    text = "Copy", tip = id().title .. ": this window's chat text in a box to copy",
                    point = { "TOPRIGHT", "TOPRIGHT", -2, -2 },
                })
                if not ok then
                    problem("chat copy button", h)
                    reason = "it failed"
                elseif type(h) == "table" then
                    button = h
                elseif type(whyNot) == "string" then
                    reason = whyNot
                end
            end
            if not button then
                state.copy = "waiting"
                why.copy = reason
                return
            end
            button.onClick(function() copy(Chat.LINES) end, function(err) problem("chat copy button", err) end)
        end
        button.show(true)
        state.copy = "on"
    end

    -------------------------------------------------------------------
    -- Part 2: readability. What each window had before this add-on
    -- changed it is kept, and given back when the part is turned off.
    -------------------------------------------------------------------
    local fontSaved, fontSet = {}, {}
    local fadeSaved, fadeSet = {}, {}
    local wheelCancels, scrollLines = {}, 0
    local cancelStamps, stampFormat = nil, nil
    local tabsHeld = {}

    -- A client call that may raise: its answers, or nil and a problem.
    local function ask(what, fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, a, b, c3 = pcall(fn, ...)
        if not ok then
            problem(what, a)
            return nil
        end
        return a, b, c3
    end

    local function prattled(part, module)
        local says = pratSays(module)
        if says == "on" or says == "unknown" then
            standDown(part, module, says)
            return true
        end
        return false
    end

    local function restoreFonts()
        local c = client()
        for i, size in pairs(fontSaved) do
            if fontSet[i] ~= nil then ask("chat text size", c.setChatFont, i, size) end
        end
        fontSaved, fontSet = {}, {}
    end

    local function syncFont()
        why.font = nil
        local size = tonumber(ctx.settings:get(Chat.FONT)) or 0
        if size <= 0 then
            restoreFonts()
            state.font = "off"
            return
        end
        if prattled("font", Chat.PRAT_FONT) then
            restoreFonts()
            return
        end
        size = math.floor(size)
        if size < Chat.FONT_MIN then size = Chat.FONT_MIN end
        if size > Chat.FONT_MAX then size = Chat.FONT_MAX end
        local c, any = ctx.client, false
        for i = 1, Chat.WINDOWS do
            if fontSaved[i] == nil then
                local now = ask("chat text size", c.chatFont, i)
                if type(now) == "number" then fontSaved[i] = now end
            end
            if fontSaved[i] ~= nil and fontSet[i] ~= size then
                if ask("chat text size", c.setChatFont, i, size) == true then fontSet[i] = size end
            end
            if fontSet[i] ~= nil then any = true end
        end
        state.font = "unavailable"
        if any then state.font = "on" end
    end

    local function restoreFades()
        local c = client()
        for i, was in pairs(fadeSaved) do
            if fadeSet[i] ~= nil then ask("chat fading", c.setChatFading, i, was.fading, was.time) end
        end
        fadeSaved, fadeSet = {}, {}
    end

    local function syncFade()
        why.fade = nil
        local keep = ctx.settings:get(Chat.KEEP) == true
        local time = math.floor(tonumber(ctx.settings:get(Chat.FADE)) or 0)
        if keep == false and time <= 0 then
            restoreFades()
            state.fade = "off"
            return
        end
        if prattled("fade", Chat.PRAT_FADE) then
            restoreFades()
            return
        end
        local c, any = ctx.client, false
        for i = 1, Chat.WINDOWS do
            if fadeSaved[i] == nil then
                local now = ask("chat fading", c.chatFading, i)
                if type(now) == "table" and type(now.time) == "number" then
                    fadeSaved[i] = { fading = now.fading == true, time = now.time }
                end
            end
            local was = fadeSaved[i]
            if was ~= nil then
                local wantTime = was.time
                if time > 0 then wantTime = time end
                local want = tostring(not keep) .. ":" .. tostring(wantTime)
                if fadeSet[i] ~= want and ask("chat fading", c.setChatFading, i, not keep, wantTime) == true then
                    fadeSet[i] = want
                end
            end
            if fadeSet[i] ~= nil then any = true end
        end
        state.fade = "unavailable"
        if any then state.fade = "on" end
    end

    -- One wheel notch on a chat window, after the game's own line.
    local function wheel(_, ctrl, shift)
        if scrollLines <= 0 then return nil end
        if ctrl then return "top" end
        if shift then return "bottom" end
        return scrollLines - 1
    end

    local function dropWheels()
        for _, cancel in pairs(wheelCancels) do pcall(cancel) end
        wheelCancels = {}
    end

    local function syncScroll()
        why.scroll = nil
        local n = math.floor(tonumber(ctx.settings:get(Chat.SCROLL)) or 0)
        if n > Chat.SCROLL_MAX then n = Chat.SCROLL_MAX end
        scrollLines = n
        if n <= 0 then
            dropWheels()
            state.scroll = "off"
            return
        end
        local c = ctx.client
        for i = 1, Chat.WINDOWS do
            if wheelCancels[i] == nil then
                local cancel = ask("chat wheel", c.chatWheel, i, wheel)
                if type(cancel) == "function" then wheelCancels[i] = cancel end
            end
        end
        state.scroll = "unavailable"
        if next(wheelCancels) ~= nil then state.scroll = "on" end
    end

    -- The stamp before a chat line. A line that is no text, or a time not
    -- known, leaves the line as it came.
    local function stampFilter(text)
        if ctx == nil or state.stamps ~= "on" or type(text) ~= "string" then return nil end
        local h, m, s = ask("chat clock", ctx.client.localTime)
        local stamp = Chat.Stamp(stampFormat, h, m, s)
        if stamp == nil then return nil end
        return stamp .. text
    end

    local function dropStamps()
        if cancelStamps then pcall(cancelStamps) end
        cancelStamps = nil
    end

    -- Whether the game's own timestamps are on; false when not known.
    local function gameStamps()
        local v = ask("chat timestamps", ctx.client.gameSetting, Chat.GAME_STAMPS)
        return type(v) == "string" and v ~= "" and v ~= Chat.GAME_STAMPS_OFF
    end

    local function syncStamps()
        why.stamps = nil
        local format = ctx.settings:get(Chat.STAMPS)
        if Chat.STAMP_FORMAT[format] == nil then
            dropStamps()
            state.stamps = "off"
            return
        end
        if gameStamps() then
            dropStamps()
            state.stamps = "game"
            why.stamps = Chat.GAME_STAMPS_WHY
            if not told.game then
                told.game = true
                say(Chat.LABEL.stamps .. ": standing down, " .. why.stamps .. ".")
            end
            return
        end
        if prattled("stamps", Chat.PRAT_STAMPS) then
            dropStamps()
            return
        end
        stampFormat = format
        local c = ctx.client
        if cancelStamps == nil and type(c.chatFilter) == "function" then
            local got = ask("chat timestamps", c.chatFilter, Chat.EVENTS, stampFilter)
            if type(got) == "function" then cancelStamps = got end
        end
        if cancelStamps then
            state.stamps = "on"
        else
            state.stamps = "unavailable"
            why.stamps = "this client gives no chat filter"
        end
    end

    local function releaseTabs()
        local c = client()
        for i in pairs(tabsHeld) do ask("chat tabs", c.chatTabAlpha, i, nil) end
        tabsHeld = {}
    end

    local function syncTabs()
        why.tabs = nil
        if ctx.settings:get(Chat.TABS) ~= true then
            releaseTabs()
            state.tabs = "off"
            return
        end
        local c = ctx.client
        for i = 1, Chat.WINDOWS do
            if tabsHeld[i] == nil and ask("chat tabs", c.chatTabAlpha, i, Chat.TAB_ALPHA) == true then
                tabsHeld[i] = true
            end
        end
        state.tabs = "unavailable"
        if next(tabsHeld) ~= nil then state.tabs = "on" end
    end

    local PARTS = {
        { "chat links", syncUrls }, { "chat copy", syncCopy }, { "chat text size", syncFont },
        { "chat fading", syncFade }, { "chat wheel", syncScroll }, { "chat timestamps", syncStamps },
        { "chat tabs", syncTabs },
    }

    -- Each part made to stand as its setting, Prat and the client say.
    -- Safe to call again and again: nothing is made twice.
    local function sync()
        if ctx == nil then return end
        for _, part in ipairs(PARTS) do
            local ok, err = pcall(part[2])
            if not ok then problem(part[1], err) end
        end
    end

    function api.lines()
        if ctx == nil then return { Chat.NOT_STARTED } end
        local out = {}
        for _, part in ipairs({ "urls", "copy", "font", "fade", "scroll", "stamps", "tabs" }) do
            local line = Chat.LABEL[part] .. ": " .. tostring(Chat.STATE[state[part]])
            if why[part] then line = line .. " (" .. why[part] .. ")" end
            out[#out + 1] = line .. "."
        end
        out[#out + 1] = id().slash .. " " .. Chat.WORD .. " copy [n]: the main chat window's last n lines ("
            .. Chat.LINES .. " when left out, " .. Chat.LINES_MAX .. " at most) in a box to copy."
        return out
    end

    local function run(rest)
        local what, arg = tostring(rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
        if what == "copy" then
            copy(lineCount(arg))
            return false
        end
        sync()
        local lines = api.lines()
        for i = 1, #lines do say(lines[i]) end
        return false
    end
    api.run = run
    if diag and type(diag.commands) == "table" then
        diag.commands[Chat.WORD] = run
        if type(diag.help) == "table" then diag.help[Chat.WORD] = Chat.HELP end
    end

    k:Module({
        name = Chat.NAME,
        needs = { "client", "store", "settings", "bus" },
        settings = { {
            key = Chat.COPY, scope = "account", type = "bool", default = true,
            label = "Copy chat text",
            help = "A small Copy button on the main chat window, and the chat copy word: the window's recent "
                .. "lines in a box to select and copy, as plain text. With Prat's CopyChat on, the button "
                .. "stands down.",
            group = Chat.GROUP, synonyms = { "chat", "copy", "url", "link", "text", "prat" },
        }, {
            key = Chat.URLS, scope = "account", type = "bool", default = true,
            label = "Clickable links in chat",
            help = "A web address someone types in chat becomes a link: click it to get the address in a box "
                .. "to copy. It never opens a browser. Item and player links stay as they are. With Prat's "
                .. "UrlCopy on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "copy", "url", "link", "text", "prat" },
        }, {
            key = Chat.FONT, scope = "account", type = "number", default = 0, min = 0, max = Chat.FONT_MAX, step = 1,
            label = "Chat text size",
            help = "The size of the text in every chat window, from " .. Chat.FONT_MIN .. " to " .. Chat.FONT_MAX
                .. ". 0 keeps the game's own size, and gives it back. With Prat's Font on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "font", "size", "text", "prat" },
        }, {
            key = Chat.KEEP, scope = "account", type = "bool", default = false,
            label = "Keep chat lines from fading",
            help = "Chat lines stay in the chat windows instead of fading away. Off gives the game's fading back. "
                .. "With Prat's Fading on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "fade", "fading", "lines", "prat" },
        }, {
            key = Chat.FADE, scope = "account", type = "number", default = 0, min = 0, max = Chat.FADE_MAX, step = 10,
            label = "Chat fade time (seconds)",
            help = "How long a chat line stays before it fades. 0 keeps the game's own time, and gives it back.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "fade", "fading", "time", "seconds" },
        }, {
            key = Chat.SCROLL, scope = "account", type = "number", default = 0, min = 0, max = Chat.SCROLL_MAX,
            step = 1,
            label = "Chat lines per wheel notch",
            help = "How many lines one mouse-wheel notch scrolls a chat window. Then Ctrl+wheel goes to the top "
                .. "and Shift+wheel to the newest line. 0 keeps the game's own scrolling.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "scroll", "wheel", "mouse", "lines" },
        }, {
            key = Chat.STAMPS, scope = "account", type = "choice", default = Chat.STAMP_OFF,
            choices = Chat.STAMP_CHOICES,
            label = "Chat timestamps",
            help = "The time before each chat line: off, HH:MM or HH:MM:SS. Off at first: the game has its own "
                .. "timestamp option. With the game's timestamps or Prat's Timestamps on, this stands down, so "
                .. "no line has two.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "time", "timestamp", "clock", "prat" },
        }, {
            key = Chat.TABS, scope = "account", type = "bool", default = false,
            label = "Keep chat tabs visible",
            help = "The chat window tabs stay fully shown instead of fading when the mouse is away. Off gives the "
                .. "game's fading back.",
            group = Chat.GROUP, synonyms = { "chat", "readability", "tab", "tabs", "fade", "visible" },
        } },
        provides = { State = api.state, Lines = api.lines },
        start = function(c)
            ctx = c
            for _, key in ipairs({ Chat.COPY, Chat.URLS, Chat.FONT, Chat.KEEP, Chat.FADE, Chat.SCROLL, Chat.STAMPS,
                Chat.TABS }) do
                local row = c.settings:row(key)
                if type(row) == "table" then
                    local cancel = c.store:watch(row.scope, row.path or ("settings." .. key), sync)
                    if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
                end
            end
            -- Prat may load, or turn a module on, after this add-on starts;
            -- a button asked for in a fight is made when the fight ends.
            c.bus:on(Chat.NAME, "ADDON_LOADED", sync)
            c.bus:on(Chat.NAME, "PLAYER_ENTERING_WORLD", sync)
            c.bus:on(Chat.NAME, "PLAYER_REGEN_ENABLED", sync)
            sync()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            dropFilter()
            if cancelClick then pcall(cancelClick) end
            cancelClick = nil
            hideButton()
            if box then pcall(box.show, false) end
            restoreFonts()
            restoreFades()
            dropWheels()
            scrollLines = 0
            dropStamps()
            releaseTabs()
            for part in pairs(state) do state[part] = "off" end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.chat = Chat.Declare(ns, ns.diag)
