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

-- Part 3 (row N60c): mentions. A chat line from someone else holding the
-- player's own name (read from the client, without a realm) or a word of
-- the player's keyword list has that word shown in a chosen colour, and,
-- when the player picks it, the alert sound plays (client.playAlert, the
-- one sound this add-on has; at most once in Chat.SOUND_GAP seconds). A
-- word counts whole and in any case; it is found as plain text, never as a
-- pattern. Nothing inside a link or a colour code is looked into, so links
-- stay the very bytes. The player's own lines (the author is the player,
-- or a whisper the player sent) never count. Which chat kinds count is a
-- switch each; whispers count at first, public channels do not.
--   chat.mentions        the part, off at first
--   chat.keywords        words, comma-separated, at most Chat.KEYWORDS_MAX
--   chat.mentionColour   one of Chat.COLOUR_CHOICES
--   chat.mentionSound    "off" or "alert"
--   chat.mention<Kind>   the kinds, Chat.SCOPE
-- Beside Prat: its CustomFilters module (the colouring) and Sounds module
-- (module names inferred, first guess) stand down the matching half. A
-- line the client hides is passed on unread.
Chat.MENTIONS, Chat.KEYWORDS = "chat.mentions", "chat.keywords"
Chat.MENTION_COLOUR, Chat.MENTION_SOUND = "chat.mentionColour", "chat.mentionSound"
Chat.PRAT_MARK, Chat.PRAT_SOUND = "CustomFilters", "Sounds"
Chat.KEYWORDS_MAX, Chat.KEYWORD_LEN = 10, 32
Chat.SOUND_GAP = 10
Chat.SOUND_OFF, Chat.SOUND_ALERT = "off", "alert"
Chat.SOUND_CHOICES = { "off", "alert" }
Chat.COLOUR_CHOICES = { "gold", "orange", "green", "pink" }
Chat.COLOURS = { gold = "ffffd100", orange = "ffff8000", green = "ff1eff00", pink = "ffff66cc" }
Chat.SCOPE_ORDER = { "say", "party", "raid", "guild", "whisper", "channel" }
Chat.SCOPE = {
    say = "chat.mentionSay", party = "chat.mentionParty", raid = "chat.mentionRaid",
    guild = "chat.mentionGuild", whisper = "chat.mentionWhisper", channel = "chat.mentionChannel",
}
Chat.SCOPE_DEFAULT = { say = true, party = true, raid = true, guild = true, whisper = true, channel = false }
Chat.SCOPE_LABEL = {
    say = "say, yell and emote", party = "party and instance chat", raid = "raid chat and raid warnings",
    guild = "guild and officer chat", whisper = "whispers to you", channel = "chat channels (trade, general...)",
}
-- Each chat event that may hold a mention and its kind. A whisper the
-- player sent (the _INFORM events) is no event here.
Chat.SCOPE_EVENTS = {
    CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "say", CHAT_MSG_EMOTE = "say",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_INSTANCE_CHAT = "party",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "guild",
    CHAT_MSG_WHISPER = "whisper", CHAT_MSG_BN_WHISPER = "whisper",
    CHAT_MSG_CHANNEL = "channel",
}
Chat.MENTION_EVENTS = {}
for _, event in ipairs(Chat.EVENTS) do
    if Chat.SCOPE_EVENTS[event] then Chat.MENTION_EVENTS[#Chat.MENTION_EVENTS + 1] = event end
end

-- Part 4 (row N60d): names, channel labels, the edit box. Each its own
-- row, each off at first.
--   chat.classNames     the author's name in the class colour: the game's
--                       own "colour names by class" turned on for each chat
--                       kind (it colours inside its own player link), and
--                       a player link in a line's text whose class is known
--                       (learnt from the GUID of a line that player wrote,
--                       client.classOfGuid) gets the colour around its
--                       shown text only: "|Hplayer:X|h|cff..[X]|r|h". A
--                       class not known leaves the link as it was.
--   chat.shortChannels  "[1. General - Zone]" shown as "[1]" (through the
--                       chat filter's channel text), and the game's labels
--                       of Guild, Officer, Party, Raid, Instance as "[G]",
--                       "[O]", "[P]", "[R]", "[I]" (Chat.SHORT_LABELS). Say
--                       and yell untouched. The line's own text is never
--                       changed by this part, so links stay the very bytes.
--   chat.editArrows     the main chat edit box: arrow keys move the cursor
--                       without Alt, and up/down recall what was typed this
--                       session (the game's own history, Chat.HISTORY
--                       lines). Nothing is hooked, so nothing is tainted.
-- Off, or the module stopped: what the game had is given back. Beside
-- Prat: its PlayerNames, ChannelNames and EditBox modules (module names
-- inferred, first guess) stand the matching part down. A line the client
-- hides is passed on unread.
Chat.CLASS_NAMES, Chat.SHORT_CHANNELS, Chat.EDIT_ARROWS = "chat.classNames", "chat.shortChannels", "chat.editArrows"
Chat.PRAT_NAMES, Chat.PRAT_CHANNELS, Chat.PRAT_EDIT = "PlayerNames", "ChannelNames", "EditBox"
Chat.CLASS_CACHE = 200
Chat.HISTORY = 20
Chat.CHANNEL_EVENTS = { "CHAT_MSG_CHANNEL" }
-- The chat kinds whose author name the game colours by class.
Chat.CLASS_TYPES = {
    "SAY", "YELL", "EMOTE", "WHISPER", "WHISPER_INFORM", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "GUILD", "OFFICER", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
}
for i = 1, Chat.WINDOWS do Chat.CLASS_TYPES[#Chat.CLASS_TYPES + 1] = "CHANNEL" .. i end
-- The game's chat kind labels and their short forms.
Chat.SHORT_ORDER = {
    "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
    "INSTANCE_CHAT_LEADER",
}
Chat.SHORT_LABELS = {
    GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL",
    RAID_WARNING = "RW", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
}
-- Class colours as the game's RAID_CLASS_COLORS has them, "aarrggbb".
Chat.CLASS_COLOURS = {
    WARRIOR = "ffc79c6e", PALADIN = "fff58cba", HUNTER = "ffabd473", ROGUE = "fffff569", PRIEST = "ffffffff",
    SHAMAN = "ff0070de", MAGE = "ff3fc7eb", WARLOCK = "ff8788ee", DRUID = "ffff7d0a",
}

-- Part 5 (row N60e): filters, repeated lines, substitutions. Each its own
-- row, each off at first; for display only, nothing is sent.
--   chat.filters        hide a line holding a word of chat.filterWords
--                       (comma-separated, at most Chat.FILTER_WORDS_MAX;
--                       whole words, any case, found as plain text, never
--                       as a pattern; the shown text of a link counts) in
--                       the kinds chat.filterScope names. Whispers to or
--                       from the player only with chat.filterWhispers on.
--   chat.repeats        "off", or seconds: the same line from the same
--                       author again within that time is hidden. At most
--                       Chat.REPEAT_MAX lines kept in mind.
--   chat.subs           each "from=to" pair of chat.subPairs (at most
--                       Chat.SUB_PAIRS_MAX) replaces the whole word in
--                       other players' lines. Never inside a link or a
--                       coloured run; a bar in the new word is shown as a
--                       bar, never read as a code.
-- The player's own lines are never hidden or changed; while the player's
-- name is not known, nothing is. One line shown in two windows is judged
-- once (the game's line id). Beside Prat: its Filtering module stands
-- filters and repeats down, its Substitutions module the substitutions
-- (module names inferred, first guess). A line the client hides is passed
-- on unread.
Chat.FILTERS, Chat.FILTER_WORDS = "chat.filters", "chat.filterWords"
Chat.FILTER_SCOPE, Chat.FILTER_WHISPERS = "chat.filterScope", "chat.filterWhispers"
Chat.REPEATS, Chat.SUBS, Chat.SUB_PAIRS = "chat.repeats", "chat.subs", "chat.subPairs"
Chat.PRAT_FILTER, Chat.PRAT_SUBS = "Filtering", "Substitutions"
Chat.FILTER_WORDS_MAX, Chat.SUB_PAIRS_MAX, Chat.REPEAT_MAX = 20, 10, 200
Chat.FILTER_SCOPES = { "channels", "channels and say", "every kind" }
Chat.REPEAT_CHOICES = { "off", "10", "30", "60" }
-- The kinds each scope takes, by the event's kind (Chat.SCOPE_EVENTS).
Chat.FILTER_KINDS = {
    channels = { channel = true },
    ["channels and say"] = { channel = true, say = true },
    ["every kind"] = { channel = true, say = true, party = true, raid = true, guild = true },
}
-- Whispers to or from the player: only chat.filterWhispers lets a filter
-- or the repeats hide one, whatever the scope.
Chat.WHISPER_EVENTS = {
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
}

Chat.HELP = "how the chat links, the chat copy button, the chat readability settings, chat mentions, "
    .. "class names, short channel labels, the edit box, chat filters, repeated lines and substitutions "
    .. "stand, and how many lines were hidden; chat copy [n] puts the main chat "
    .. "window's last n lines in a box to copy"
Chat.LABEL = {
    urls = "chat links", copy = "chat copy button", font = "chat text size", fade = "chat fading",
    scroll = "chat wheel scrolling", stamps = "chat timestamps", tabs = "chat tabs kept visible",
    mentions = "chat mentions", sound = "chat mention sound",
    names = "chat class names", short = "short chat channel labels", edit = "chat edit box arrows",
    filters = "chat filters", repeats = "hiding repeated chat lines", subs = "chat substitutions",
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

-- Part 3, pure: the keyword list, names, and the colouring of words.

-- The player's keyword text as words, lower case: split at commas, spaces
-- at either end taken off, empty, too long and repeated words left out, at
-- most Chat.KEYWORDS_MAX.
function Chat.Keywords(text)
    local out, seenWord = {}, {}
    if type(text) ~= "string" then return out end
    for piece in (text .. ","):gmatch("([^,]*),") do
        local word = piece:match("^%s*(.-)%s*$"):lower()
        if word ~= "" and #word <= Chat.KEYWORD_LEN and not seenWord[word] and #out < Chat.KEYWORDS_MAX then
            seenWord[word] = true
            out[#out + 1] = word
        end
    end
    return out
end

-- True when the author is the player: the name before any "-realm", in
-- any case.
function Chat.SameName(author, name)
    if type(author) ~= "string" or type(name) ~= "string" or name == "" then return false end
    local bare = author:match("^([^%-]*)") or author
    return bare:lower() == name:lower()
end

-- A byte that belongs to a word: a letter or digit, or part of a letter
-- written in more than one byte.
local function wordByte(s, i)
    if i < 1 or i > #s then return false end
    if s:byte(i) >= 128 then return true end
    return s:sub(i, i):find("%w") ~= nil
end

-- The first whole-word match of any word at or after `from` in `low`
-- (both lower case), the longest when two start at one place.
local function nextWord(low, words, from)
    local bestA, bestB = nil, nil
    for i = 1, #words do
        local word, init = words[i], from
        while true do
            local a, b = low:find(word, init, true)
            if a == nil then break end
            if bestA ~= nil and a > bestA then break end
            if not wordByte(low, a - 1) and not wordByte(low, b + 1) then
                if bestA == nil or a < bestA or b > bestB then bestA, bestB = a, b end
                break
            end
            init = a + 1
        end
    end
    return bestA, bestB
end

local function markPlain(chunk, words, colour)
    local low, out, pos, n = chunk:lower(), {}, 1, 0
    while true do
        local a, b = nextWord(low, words, pos)
        if a == nil then break end
        out[#out + 1] = chunk:sub(pos, a - 1)
        out[#out + 1] = "|c" .. colour .. chunk:sub(a, b) .. "|r"
        n = n + 1
        pos = b + 1
    end
    if n == 0 then return chunk, 0 end
    out[#out + 1] = chunk:sub(pos)
    return table.concat(out), n
end

-- The line with each whole word of `words` (lower case) in `colour`
-- ("aarrggbb"), and how many were. Nothing inside a link and nothing
-- already coloured is looked into. With none, the very text given.
function Chat.Mark(text, words, colour)
    if type(text) ~= "string" or text == "" or type(words) ~= "table" or #words == 0 then return text, 0 end
    if type(colour) ~= "string" then return text, 0 end
    local parts, out, n, inLink, coloured = tokens(text), {}, 0, false, false
    for i = 1, #parts do
        local part = parts[i]
        if part.code ~= nil then
            if part.code == "H" then
                inLink = true
            elseif part.code == "h" then
                inLink = false
            elseif part.code == "c" and #part.raw == 10 then
                coloured = true
            elseif part.code == "r" then
                coloured = false
            end
            out[i] = part.raw
        elseif inLink or coloured then
            out[i] = part.text
        else
            local piece, found = markPlain(part.text, words, colour)
            out[i] = piece
            n = n + found
        end
    end
    if n == 0 then return text, 0 end
    return table.concat(out), n
end

-- Part 4, pure: names and labels.

-- A chat author or a player link's name as a cache key: lower case.
function Chat.NameKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

-- The line with each player link's shown text in its class colour,
-- "|Hplayer:X|h[X]|h" -> "|Hplayer:X|h|cffxxxxxx[X]|r|h", and how many
-- were. colourOf(name) gives "aarrggbb" or nil. The |H..|h opener and the
-- closing |h are kept as the very bytes; a link already coloured inside,
-- or with anything but plain text inside, is left as it is.
function Chat.ColourPlayers(text, colourOf)
    if type(text) ~= "string" or text == "" or type(colourOf) ~= "function" then return text, 0 end
    local parts, out, n = tokens(text), {}, 0
    local i = 1
    while i <= #parts do
        local part = parts[i]
        out[#out + 1] = part.raw or part.text
        if part.code == "H" then
            local name = part.raw:match("^|Hplayer:([^:|]+)")
            local inner, close = parts[i + 1], parts[i + 2]
            if name and inner and inner.text and close and close.code == "h" and close.raw == "|h" then
                local colour = colourOf(name)
                if type(colour) == "string" then
                    out[#out + 1] = "|c" .. colour .. inner.text .. "|r"
                    out[#out + 1] = close.raw
                    n = n + 1
                    i = i + 2
                end
            end
        end
        i = i + 1
    end
    if n == 0 then return text, 0 end
    return table.concat(out), n
end

-- The short form of a channel's text: "1. General - Zone" -> "1"; nil
-- when it does not start with a number and a dot.
function Chat.ShortChannel(channel)
    if type(channel) ~= "string" then return nil end
    return channel:match("^(%d+)%.")
end

-- A game label with the text between its link's "|h[" and "]|h" made
-- `short`: "|Hchannel:GUILD|h[Guild]|h %s: " -> "|Hchannel:GUILD|h[G]|h %s: ".
-- nil when the label has no such link.
function Chat.ShortLabel(label, short)
    if type(label) ~= "string" or type(short) ~= "string" then return nil end
    local a = label:find("|h[", 1, true)
    if a == nil then return nil end
    local b = label:find("]|h", a + 3, true)
    if b == nil then return nil end
    return label:sub(1, a + 2) .. short .. label:sub(b)
end

-- Part 5, pure: filter words, substitution pairs.

-- The player's filter text as words, lower case: as Chat.Keywords, at most
-- Chat.FILTER_WORDS_MAX.
function Chat.FilterWords(text)
    local out, seenWord = {}, {}
    if type(text) ~= "string" then return out end
    for piece in (text .. ","):gmatch("([^,]*),") do
        local word = piece:match("^%s*(.-)%s*$"):lower()
        if word ~= "" and #word <= Chat.KEYWORD_LEN and not seenWord[word] and #out < Chat.FILTER_WORDS_MAX then
            seenWord[word] = true
            out[#out + 1] = word
        end
    end
    return out
end

-- True when the line, as a player reads it (a link as its shown text),
-- holds a whole word of `words` (lower case).
function Chat.Holds(text, words)
    if type(text) ~= "string" or type(words) ~= "table" or #words == 0 then return false end
    return nextWord(Chat.Plain(text):lower(), words, 1) ~= nil
end

-- The player's substitution text as { from = (lower case), to = }, at most
-- Chat.SUB_PAIRS_MAX: split at commas, then at the first "="; spaces at
-- either end taken off. A pair with no "=", an empty or too long word, a
-- bar in the old word, or an old word already given is left out. A bar in
-- the new word is doubled, so it is shown and never read as a code.
function Chat.Pairs(text)
    local out, seenWord = {}, {}
    if type(text) ~= "string" then return out end
    for piece in (text .. ","):gmatch("([^,]*),") do
        local eq = piece:find("=", 1, true)
        if eq ~= nil and #out < Chat.SUB_PAIRS_MAX then
            local from = piece:sub(1, eq - 1):match("^%s*(.-)%s*$"):lower()
            local to = piece:sub(eq + 1):match("^%s*(.-)%s*$")
            local okFrom = from ~= "" and #from <= Chat.KEYWORD_LEN and not from:find("|", 1, true)
            if okFrom and #to <= Chat.KEYWORD_LEN and not seenWord[from] then
                seenWord[from] = true
                out[#out + 1] = { from = from, to = (to:gsub("|", "||")) }
            end
        end
    end
    return out
end

local function substitutePlain(chunk, words, swap)
    local low, out, pos, n = chunk:lower(), {}, 1, 0
    while true do
        local a, b = nextWord(low, words, pos)
        if a == nil then break end
        out[#out + 1] = chunk:sub(pos, a - 1)
        out[#out + 1] = swap[low:sub(a, b)]
        n = n + 1
        pos = b + 1
    end
    if n == 0 then return chunk, 0 end
    out[#out + 1] = chunk:sub(pos)
    return table.concat(out), n
end

-- The line with each whole old word of `list` (Chat.Pairs) replaced by its
-- new word, and how many were. Nothing inside a link and nothing coloured
-- is looked into. With none, the very text given.
function Chat.Substitute(text, list)
    if type(text) ~= "string" or text == "" or type(list) ~= "table" or #list == 0 then return text, 0 end
    local words, swap = {}, {}
    for i = 1, #list do
        words[i] = list[i].from
        swap[list[i].from] = list[i].to
    end
    local parts, out, n, inLink, coloured = tokens(text), {}, 0, false, false
    for i = 1, #parts do
        local part = parts[i]
        if part.code ~= nil then
            if part.code == "H" then
                inLink = true
            elseif part.code == "h" then
                inLink = false
            elseif part.code == "c" and #part.raw == 10 then
                coloured = true
            elseif part.code == "r" then
                coloured = false
            end
            out[i] = part.raw
        elseif inLink or coloured then
            out[i] = part.text
        else
            local piece, found = substitutePlain(part.text, words, swap)
            out[i] = piece
            n = n + found
        end
    end
    if n == 0 then return text, 0 end
    return table.concat(out), n
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
        tabs = "off", mentions = "off", sound = "off", names = "off", short = "off", edit = "off",
        filters = "off", repeats = "off", subs = "off" }
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

    -------------------------------------------------------------------
    -- Part 3: mentions.
    -------------------------------------------------------------------
    local cancelMentions, mentionWords, mentionColour = nil, {}, nil
    local marking, ringing, myName, lastSound = false, false, nil, nil

    -- The player's name, read once it is known; nil while not known.
    local function me()
        if myName ~= nil then return myName end
        local c = ctx.client
        if type(c.playerName) ~= "function" then return nil end
        local ok, name = pcall(c.playerName)
        if not ok then
            problem("chat player name", name)
            return nil
        end
        if type(name) == "string" and name ~= "" then myName = name end
        return myName
    end

    local function ring()
        local c = ctx.client
        if type(c.now) ~= "function" or type(c.playAlert) ~= "function" then return end
        local okNow, now = pcall(c.now)
        if not okNow or type(now) ~= "number" then return end
        if lastSound ~= nil and now - lastSound < Chat.SOUND_GAP then return end
        lastSound = now
        local ok, err = pcall(c.playAlert)
        if not ok then problem("chat mention sound", err) end
    end

    local function mentionFilter(text, event, author)
        if ctx == nil or type(text) ~= "string" then return nil end
        if marking == false and ringing == false then return nil end
        local kind = Chat.SCOPE_EVENTS[event]
        if kind == nil or ctx.settings:get(Chat.SCOPE[kind]) ~= true then return nil end
        local name = me()
        if name == nil or Chat.SameName(author, name) then return nil end
        local words = { name:lower() }
        for i = 1, #mentionWords do words[#words + 1] = mentionWords[i] end
        local new, n = Chat.Mark(text, words, mentionColour)
        if n == 0 then return nil end
        if ringing then ring() end
        if marking then return new end
        return nil
    end

    local function dropMentions()
        if cancelMentions then pcall(cancelMentions) end
        cancelMentions = nil
        marking, ringing = false, false
    end

    local function syncMentions()
        why.mentions, why.sound = nil, nil
        if ctx.settings:get(Chat.MENTIONS) ~= true then
            dropMentions()
            state.mentions, state.sound = "off", "off"
            return
        end
        mentionWords = Chat.Keywords(ctx.settings:get(Chat.KEYWORDS))
        mentionColour = Chat.COLOURS[ctx.settings:get(Chat.MENTION_COLOUR)] or Chat.COLOURS.gold
        marking = prattled("mentions", Chat.PRAT_MARK) == false
        ringing = false
        if ctx.settings:get(Chat.MENTION_SOUND) ~= Chat.SOUND_ALERT then
            state.sound = "off"
        elseif prattled("sound", Chat.PRAT_SOUND) == false then
            ringing = true
        end
        if marking == false and ringing == false then
            dropMentions()
            return
        end
        local c = ctx.client
        if cancelMentions == nil and type(c.chatFilter) == "function" then
            local got = ask("chat mentions", c.chatFilter, Chat.MENTION_EVENTS, mentionFilter)
            if type(got) == "function" then cancelMentions = got end
        end
        if cancelMentions == nil then
            marking, ringing = false, false
            state.mentions, state.sound = "unavailable", "unavailable"
            why.mentions = "this client gives no chat filter"
            return
        end
        if marking then state.mentions = "on" end
        if ringing then state.sound = "on" end
    end

    -------------------------------------------------------------------
    -- Part 4: class names, short channel labels, the edit box.
    -------------------------------------------------------------------
    local cancelNames, nameSaved = nil, {}
    local guidClass, guidCount, nameClass, nameCount = {}, 0, {}, 0
    local cancelShort, labelSaved = nil, {}
    local editSaved = nil

    -- The class of a GUID, read once and kept (at most Chat.CLASS_CACHE;
    -- when full the cache starts again). A read that raises is a problem
    -- and is asked again next time.
    local function classOf(guid)
        if type(guid) ~= "string" or guid == "" then return nil end
        local known = guidClass[guid]
        if known ~= nil then return known end
        local c = ctx.client
        if type(c.classOfGuid) ~= "function" then return nil end
        local ok, class = pcall(c.classOfGuid, guid)
        if not ok then
            problem("chat class read", class)
            return nil
        end
        if type(class) ~= "string" or Chat.CLASS_COLOURS[class] == nil then return nil end
        if guidCount >= Chat.CLASS_CACHE then guidClass, guidCount = {}, 0 end
        guidClass[guid], guidCount = class, guidCount + 1
        return class
    end

    local function learnName(author, class)
        local key = Chat.NameKey(author)
        if key == nil or nameClass[key] == class then return end
        if nameClass[key] == nil then
            if nameCount >= Chat.CLASS_CACHE then nameClass, nameCount = {}, 0 end
            nameCount = nameCount + 1
        end
        nameClass[key] = class
    end

    local function colourOf(name)
        local key = Chat.NameKey(name)
        if key == nil then return nil end
        local class = nameClass[key]
        if class == nil then return nil end
        return Chat.CLASS_COLOURS[class]
    end

    local function namesFilter(text, _, author, info)
        if ctx == nil or state.names ~= "on" or type(text) ~= "string" then return nil end
        if type(info) == "table" then
            local class = classOf(info.guid)
            if class ~= nil then learnName(author, class) end
        end
        local new, n = Chat.ColourPlayers(text, colourOf)
        if n > 0 then return new end
        return nil
    end

    local function restoreNameColours()
        local c = client()
        for chatType, was in pairs(nameSaved) do ask("chat class names", c.setChatNameByClass, chatType, was) end
        nameSaved = {}
    end

    local function dropNames()
        if cancelNames then pcall(cancelNames) end
        cancelNames = nil
        restoreNameColours()
    end

    local function syncNames()
        why.names = nil
        if ctx.settings:get(Chat.CLASS_NAMES) ~= true then
            dropNames()
            state.names = "off"
            return
        end
        if prattled("names", Chat.PRAT_NAMES) then
            dropNames()
            return
        end
        local c = ctx.client
        for _, chatType in ipairs(Chat.CLASS_TYPES) do
            if nameSaved[chatType] == nil then
                local was = ask("chat class names", c.chatNameByClass, chatType)
                if type(was) == "boolean" and ask("chat class names", c.setChatNameByClass, chatType, true) == true then
                    nameSaved[chatType] = was
                end
            end
        end
        if cancelNames == nil and type(c.chatFilter) == "function" then
            local got = ask("chat class names", c.chatFilter, Chat.EVENTS, namesFilter)
            if type(got) == "function" then cancelNames = got end
        end
        if cancelNames ~= nil or next(nameSaved) ~= nil then
            state.names = "on"
        else
            state.names = "unavailable"
            why.names = "this client gives no chat filter and no class colour option"
        end
    end

    local function shortFilter(text, _, _, info)
        if ctx == nil or state.short ~= "on" or type(text) ~= "string" or type(info) ~= "table" then return nil end
        local short = Chat.ShortChannel(info.channel)
        if short == nil then return nil end
        return nil, { channel = short }
    end

    local function restoreLabels()
        local c = client()
        for name, was in pairs(labelSaved) do ask("chat channel labels", c.setChatTypeHeader, name, was) end
        labelSaved = {}
    end

    local function dropShort()
        if cancelShort then pcall(cancelShort) end
        cancelShort = nil
        restoreLabels()
    end

    local function syncShort()
        why.short = nil
        if ctx.settings:get(Chat.SHORT_CHANNELS) ~= true then
            dropShort()
            state.short = "off"
            return
        end
        if prattled("short", Chat.PRAT_CHANNELS) then
            dropShort()
            return
        end
        local c = ctx.client
        for _, name in ipairs(Chat.SHORT_ORDER) do
            if labelSaved[name] == nil then
                local was = ask("chat channel labels", c.chatTypeHeader, name)
                local short = Chat.ShortLabel(was, Chat.SHORT_LABELS[name])
                if short ~= nil and ask("chat channel labels", c.setChatTypeHeader, name, short) == true then
                    labelSaved[name] = was
                end
            end
        end
        if cancelShort == nil and type(c.chatFilter) == "function" then
            local got = ask("chat channel labels", c.chatFilter, Chat.CHANNEL_EVENTS, shortFilter)
            if type(got) == "function" then cancelShort = got end
        end
        if cancelShort ~= nil or next(labelSaved) ~= nil then
            state.short = "on"
        else
            state.short = "unavailable"
            why.short = "this client gives no chat filter and no chat labels"
        end
    end

    local function restoreEdit()
        if editSaved == nil then return end
        ask("chat edit box", client().setEditBox, editSaved.alt, editSaved.history)
        editSaved = nil
    end

    local function syncEdit()
        why.edit = nil
        if ctx.settings:get(Chat.EDIT_ARROWS) ~= true then
            restoreEdit()
            state.edit = "off"
            return
        end
        if prattled("edit", Chat.PRAT_EDIT) then
            restoreEdit()
            return
        end
        if editSaved == nil then
            local c = ctx.client
            local was = ask("chat edit box", c.editBox)
            if type(was) == "table" and type(was.alt) == "boolean"
                and ask("chat edit box", c.setEditBox, false, Chat.HISTORY) == true then
                editSaved = { alt = was.alt, history = was.history }
            end
        end
        if editSaved ~= nil then
            state.edit = "on"
        else
            state.edit = "unavailable"
            why.edit = "this client gives no way to the chat edit box"
        end
    end

    -------------------------------------------------------------------
    -- Part 5: filters, repeated lines, substitutions. One chat filter
    -- for the three.
    -------------------------------------------------------------------
    local cancelSift = nil
    local siftWords, siftKinds, siftWhispers, subList = {}, {}, false, {}
    local repeatGap, repeatSeen, repeatCount = 0, {}, 0
    local hiddenCount, lastLine, lastHide = 0, nil, false

    function api.remembered() return repeatCount end
    function api.hidden() return hiddenCount end

    -- Whether the same line from the same author was seen less than
    -- repeatGap seconds ago; the time is kept either way. When
    -- Chat.REPEAT_MAX lines are kept, the old ones go, then all of them.
    local function repeated(author, text)
        local now = ask("chat clock", ctx.client.now)
        if type(now) ~= "number" then return false end
        -- As read, and without this add-on's own timestamp: another part's
        -- filter may have run first, and a stamp would make every line new.
        local plain = Chat.Plain(text):gsub("^%[%d+:%d+:?%d*%] ", "")
        local key = author .. "\0" .. plain
        local last = repeatSeen[key]
        if last == nil then
            if repeatCount >= Chat.REPEAT_MAX then
                for seenKey, seenAt in pairs(repeatSeen) do
                    if now - seenAt >= repeatGap then
                        repeatSeen[seenKey] = nil
                        repeatCount = repeatCount - 1
                    end
                end
                if repeatCount >= Chat.REPEAT_MAX then repeatSeen, repeatCount = {}, 0 end
            end
            repeatCount = repeatCount + 1
        end
        repeatSeen[key] = now
        return last ~= nil and now - last < repeatGap
    end

    local function siftFilter(text, event, author, info)
        if ctx == nil or type(text) ~= "string" or type(author) ~= "string" then return nil end
        local sifting, repeating = state.filters == "on", state.repeats == "on"
        local swapping = state.subs == "on"
        if sifting == false and repeating == false and swapping == false then return nil end
        local name = me()
        if name == nil or Chat.SameName(author, name) then return nil end
        local line = nil
        if type(info) == "table" and type(info.line) == "number" then line = info.line end
        local hide = false
        if line ~= nil and line == lastLine then
            hide = lastHide
        else
            local open = siftWhispers
            if Chat.WHISPER_EVENTS[event] == nil then
                local kind = Chat.SCOPE_EVENTS[event]
                open = kind ~= nil and siftKinds[kind] == true
            end
            if sifting and open and Chat.Holds(text, siftWords) then hide = true end
            local whisper = Chat.WHISPER_EVENTS[event] ~= nil
            if repeating and hide == false and (whisper == false or siftWhispers) and repeated(author, text) then
                hide = true
            end
            if line ~= nil then lastLine, lastHide = line, hide end
            if hide then hiddenCount = hiddenCount + 1 end
        end
        if hide then return nil, { hide = true } end
        if swapping then
            local new, n = Chat.Substitute(text, subList)
            if n > 0 then return new end
        end
        return nil
    end

    local function dropSift()
        if cancelSift then pcall(cancelSift) end
        cancelSift = nil
    end

    local function syncSift()
        why.filters, why.repeats, why.subs = nil, nil, nil
        local set = ctx.settings
        local gap = tonumber(set:get(Chat.REPEATS)) or 0
        siftWords = Chat.FilterWords(set:get(Chat.FILTER_WORDS))
        siftKinds = Chat.FILTER_KINDS[set:get(Chat.FILTER_SCOPE)] or Chat.FILTER_KINDS.channels
        siftWhispers = set:get(Chat.FILTER_WHISPERS) == true
        subList = Chat.Pairs(set:get(Chat.SUB_PAIRS))
        if gap ~= repeatGap then repeatSeen, repeatCount = {}, 0 end
        repeatGap = gap
        local want = { filters = set:get(Chat.FILTERS) == true, repeats = gap > 0, subs = set:get(Chat.SUBS) == true }
        local live = {}
        for _, part in ipairs({ "filters", "repeats", "subs" }) do
            local module = Chat.PRAT_FILTER
            if part == "subs" then module = Chat.PRAT_SUBS end
            if want[part] == false then
                state[part] = "off"
            elseif prattled(part, module) == false then
                live[part] = true
            end
        end
        if next(live) == nil then
            dropSift()
            return
        end
        local c = ctx.client
        if cancelSift == nil and type(c.chatFilter) == "function" then
            local got = ask("chat filters", c.chatFilter, Chat.EVENTS, siftFilter)
            if type(got) == "function" then cancelSift = got end
        end
        for part in pairs(live) do
            if cancelSift ~= nil then
                state[part] = "on"
            else
                state[part] = "unavailable"
                why[part] = "this client gives no chat filter"
            end
        end
    end

    local PARTS = {
        { "chat links", syncUrls }, { "chat copy", syncCopy }, { "chat text size", syncFont },
        { "chat fading", syncFade }, { "chat wheel", syncScroll }, { "chat timestamps", syncStamps },
        { "chat tabs", syncTabs }, { "chat mentions", syncMentions },
        { "chat class names", syncNames }, { "chat channel labels", syncShort }, { "chat edit box", syncEdit },
        { "chat filters", syncSift },
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
        for _, part in ipairs({ "urls", "copy", "font", "fade", "scroll", "stamps", "tabs", "mentions", "sound", "names", "short",
            "edit", "filters", "repeats", "subs" }) do
            local line = Chat.LABEL[part] .. ": " .. tostring(Chat.STATE[state[part]])
            if why[part] then line = line .. " (" .. why[part] .. ")" end
            out[#out + 1] = line .. "."
        end
        out[#out + 1] = hiddenCount .. " chat lines hidden this session (filters and repeated lines)."
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
        }, {
            key = Chat.MENTIONS, scope = "account", type = "bool", default = false,
            label = "Highlight mentions in chat",
            help = "When someone else's chat line holds your name, or one of your mention keywords, that word is "
                .. "shown in your mention colour. Item and player links are never changed. With Prat's "
                .. "CustomFilters on, the colouring stands down.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "mentions", "highlight", "name", "prat" },
        }, {
            key = Chat.KEYWORDS, scope = "account", type = "string", default = "",
            label = "Mention keywords",
            help = "More words that count as a mention, separated by commas (\"onyxia, tank\"). At most "
                .. Chat.KEYWORDS_MAX .. " words of up to " .. Chat.KEYWORD_LEN .. " letters; whole words, any case.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "keyword", "keywords", "highlight", "words" },
        }, {
            key = Chat.MENTION_COLOUR, scope = "account", type = "choice", default = "gold",
            choices = Chat.COLOUR_CHOICES,
            label = "Mention colour",
            help = "The colour a mentioned word is shown in: gold, orange, green or pink.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "colour", "color", "highlight" },
        }, {
            key = Chat.MENTION_SOUND, scope = "account", type = "choice", default = Chat.SOUND_OFF,
            choices = Chat.SOUND_CHOICES,
            label = "Mention sound",
            help = "Off, or the alert sound when you are mentioned, at most once every " .. Chat.SOUND_GAP
                .. " seconds. With Prat's Sounds on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "sound", "alert", "ping", "prat" },
        }, {
            key = Chat.SCOPE.say, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.say,
            label = "Mentions in say, yell and emote",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.say .. ".",
            group = Chat.GROUP, synonyms = { "chat", "mention", "say", "yell", "emote" },
        }, {
            key = Chat.SCOPE.party, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.party,
            label = "Mentions in party chat",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.party .. ".",
            group = Chat.GROUP, synonyms = { "chat", "mention", "party", "group", "instance" },
        }, {
            key = Chat.SCOPE.raid, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.raid,
            label = "Mentions in raid chat",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.raid .. ".",
            group = Chat.GROUP, synonyms = { "chat", "mention", "raid", "warning" },
        }, {
            key = Chat.SCOPE.guild, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.guild,
            label = "Mentions in guild chat",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.guild .. ".",
            group = Chat.GROUP, synonyms = { "chat", "mention", "guild", "officer" },
        }, {
            key = Chat.SCOPE.whisper, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.whisper,
            label = "Mentions in whispers",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.whisper .. ". Whispers you send never count.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "whisper", "tell" },
        }, {
            key = Chat.SCOPE.channel, scope = "account", type = "bool", default = Chat.SCOPE_DEFAULT.channel,
            label = "Mentions in chat channels",
            help = "Mentions count in " .. Chat.SCOPE_LABEL.channel .. ". Off at first: busy channels say a lot.",
            group = Chat.GROUP, synonyms = { "chat", "mention", "channel", "trade", "general" },
        }, {
            key = Chat.CLASS_NAMES, scope = "account", type = "bool", default = false,
            label = "Class-coloured names in chat",
            help = "Who wrote a chat line is shown in their class colour, and so is a player's name linked in "
                .. "a line once their class is known. The links still work as before. With Prat's PlayerNames "
                .. "on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "class", "colour", "color", "name", "names", "player", "prat" },
        }, {
            key = Chat.SHORT_CHANNELS, scope = "account", type = "bool", default = false,
            label = "Short chat channel labels",
            help = "\"[1. General - Zone]\" is shown as \"[1]\", and Guild, Officer, Party, Raid and Instance as "
                .. "[G], [O], [P], [R] and [I]. Say and yell are as they were. Off gives the game's labels back. "
                .. "With Prat's ChannelNames on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "channel", "channels", "label", "short", "guild", "prat" },
        }, {
            key = Chat.EDIT_ARROWS, scope = "account", type = "bool", default = false,
            label = "Chat box arrow keys without Alt",
            help = "In the chat box, the left and right arrows move the cursor without holding Alt, and up and "
                .. "down bring back what you typed this session (the last " .. Chat.HISTORY .. " lines). Off "
                .. "gives the game's keys back. With Prat's EditBox on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "edit", "box", "arrow", "arrows", "keys", "history", "prat" },
        }, {
            key = Chat.FILTERS, scope = "account", type = "bool", default = false,
            label = "Hide chat lines with filter words",
            help = "A chat line holding one of your filter words is not shown. Your own lines are never hidden, "
                .. "and whispers only when \"Filters also hide whispers\" is on. With Prat's Filtering on, this "
                .. "stands down.",
            group = Chat.GROUP, synonyms = { "chat", "filter", "filters", "hide", "block", "spam", "words", "prat" },
        }, {
            key = Chat.FILTER_WORDS, scope = "account", type = "string", default = "",
            label = "Chat filter words",
            help = "The words that hide a chat line, separated by commas (\"wts, boost\"). At most "
                .. Chat.FILTER_WORDS_MAX .. " words of up to " .. Chat.KEYWORD_LEN .. " letters; whole words, any "
                .. "case. A word in an item's name counts too.",
            group = Chat.GROUP, synonyms = { "chat", "filter", "filters", "hide", "words", "block" },
        }, {
            key = Chat.FILTER_SCOPE, scope = "account", type = "choice", default = "channels",
            choices = Chat.FILTER_SCOPES,
            label = "Where chat filters hide lines",
            help = "channels: chat channels (trade, general...) only. channels and say: say, yell and emote too. "
                .. "every kind: party, raid and guild chat too. Whispers have their own setting.",
            group = Chat.GROUP, synonyms = { "chat", "filter", "filters", "scope", "channel", "kind" },
        }, {
            key = Chat.FILTER_WHISPERS, scope = "account", type = "bool", default = false,
            label = "Filters also hide whispers",
            help = "Chat filters and repeated-line hiding also hide whispers to and from you. Off at first: a "
                .. "whisper is never hidden.",
            group = Chat.GROUP, synonyms = { "chat", "filter", "filters", "whisper", "tell", "hide" },
        }, {
            key = Chat.REPEATS, scope = "account", type = "choice", default = "off",
            choices = Chat.REPEAT_CHOICES,
            label = "Hide repeated chat lines (seconds)",
            help = "off, or 10, 30 or 60: the same line from the same player again within that many seconds is "
                .. "not shown. Your own lines and whispers are never hidden. With Prat's Filtering on, this "
                .. "stands down.",
            group = Chat.GROUP, synonyms = { "chat", "repeat", "repeats", "duplicate", "spam", "hide", "prat" },
        }, {
            key = Chat.SUBS, scope = "account", type = "bool", default = false,
            label = "Chat word substitutions",
            help = "Words in other players' chat lines are shown as you set in \"Chat substitution pairs\". Only "
                .. "how it looks to you; links are never changed. With Prat's Substitutions on, this stands down.",
            group = Chat.GROUP, synonyms = { "chat", "substitute", "substitution", "replace", "swap", "words", "prat" },
        }, {
            key = Chat.SUB_PAIRS, scope = "account", type = "string", default = "",
            label = "Chat substitution pairs",
            help = "Pairs of old=new separated by commas (\"lol=haha, brb=back soon\"). At most "
                .. Chat.SUB_PAIRS_MAX .. " pairs; whole words, any case.",
            group = Chat.GROUP, synonyms = { "chat", "substitute", "substitution", "replace", "pairs", "words" },
        } },
        provides = { State = api.state, Lines = api.lines },
        start = function(c)
            ctx = c
            local keys = { Chat.COPY, Chat.URLS, Chat.FONT, Chat.KEEP, Chat.FADE, Chat.SCROLL, Chat.STAMPS,
                Chat.TABS, Chat.MENTIONS, Chat.KEYWORDS, Chat.MENTION_COLOUR, Chat.MENTION_SOUND, Chat.CLASS_NAMES,
                Chat.SHORT_CHANNELS, Chat.EDIT_ARROWS, Chat.FILTERS, Chat.FILTER_WORDS, Chat.FILTER_SCOPE,
                Chat.FILTER_WHISPERS, Chat.REPEATS, Chat.SUBS, Chat.SUB_PAIRS }
            for _, kind in ipairs(Chat.SCOPE_ORDER) do keys[#keys + 1] = Chat.SCOPE[kind] end
            for _, key in ipairs(keys) do
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
            dropMentions()
            dropNames()
            dropShort()
            restoreEdit()
            dropSift()
            repeatSeen, repeatCount, repeatGap, lastLine, lastHide = {}, 0, 0, nil, false
            guidClass, guidCount, nameClass, nameCount = {}, 0, {}, 0
            myName, lastSound = nil, nil
            for part in pairs(state) do state[part] = "off" end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.chat = Chat.Declare(ns, ns.diag)
