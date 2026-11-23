-- Z-Flow offline: the seen-result snapshot (lead DISPATCH sections 188 and
-- 199, Zen). Lua 5.1. Test tooling: loaded by tools/offline/zflow-run.lua,
-- never by the game; not in ZFlow/manifest.lua and not in the TOC.
--
-- For an add-on loaded on a fake client (ns.offline.addon(c)): ONE text
-- block of what the player sees, the same text for the same state. Every
-- line keeps only the add-on's own words, numbers and compass words; every
-- run of other text is a slot "<text:n>" (see TEMPLATE), and the names this
-- file knows are replaced on top of that (see NAMES). What it removes and
-- what it cannot is said under THE LIMITS: the block is not proof that no
-- name is in it. A block made from a real session stays on the machine
-- that made it (lead section 199, N8); this file does not post anything.
--
--   ns.offline.seen(c, addon, opts) -> text, lines, problems
--                                   -> nil, why          (refused, see REFUSED)
--     c       the fake client (ZFlow/Core/ClientFake.lua) the add-on is on.
--     addon   what ns.offline.addon(c) returned. nil: only what the client
--             recorded is said; the rotation's reason and the diag lines
--             are "not known".
--     opts.names   { character =, realm =, guild =, account =, guid = },
--                  each a text or a list of texts: names to take out. Any
--                  other key, a list entry (names = { "X" }) or a value
--                  that is not a text or a list of texts: refused.
--     opts.absent  a list of kinds ("realm", "guild", "account", "guid"):
--                  this state has no name of that kind (a character with no
--                  guild). For real state every kind of M.MUST (character,
--                  realm, guild, account, guid) is known or marked absent,
--                  or the snapshot is refused. character cannot be marked
--                  absent: a real state has one. A kind marked absent that has a
--                  known name: refused.
--     opts.shortNames  true: a name under 3 characters is replaced where
--                  it stands as a whole word. Not said: such a name is
--                  refused (see NAMES).
--     opts.madeUp  true: the state is made up and holds no character; line
--                  2 says "names: made up". Refused when the client itself
--                  answers a character name (UnitName, UnitFullName, or a
--                  diag snapshot kept in the account's saved table): that is
--                  real state. M.MUST is not asked of made-up state. Made up
--                  can only be shown when the client answered a name read
--                  (with no name) or an add-on was given whose kept diag
--                  snapshots were read; with neither, line 2 says "names:
--                  not known" in place of "made up" (lead section 217, N2).
--     opts.words   a list of texts: the words a line may keep, in place of
--                  the add-on's own (a test's list; a real run leaves it
--                  out). Line 3 says "words: given".
--     opts.diag    nil: the diag word is asked (see DIAG). false: not asked.
--                  A list of texts: those lines are used (as templates).
--     opts.chat    false: the chat lines are left out ("not asked").
--     text      the lines joined by "\n", no line break at the end.
--     problems  { "section: error" }: a section whose making raised says
--               "failed" in the block; the error text is only here, never
--               in the block. Each text has had its paths cut to "<path>/"
--               and the file's name, or to "<path>" (see PATHS), and its
--               names replaced, and is checked, as a line of the block is.
--               A problem is NOT a template: it is a diagnostic for the
--               machine it was made on.
--   ns.offline.seenDiff(a, b) -> { { section, line, was, now, text } ... }
--     Two snapshot texts, compared line by line inside each section: line
--     is the number of the line under its section's header, was / now the
--     two lines (nil: that side has no such line), text the one line to
--     say: arrows, line 2: was "..."; now "...". Lines are matched by
--     their place: a line put in or taken out moves every line of that
--     section after it, and each is reported.
--   ns.offline.seenParts: this file's table (HEAD, SECTIONS, UNKNOWN, PLACE,
--     MUST, sections(text) -> { [section] = lines }, order; names; normal;
--     redact; held; paths; template; wordSet; literals; words). HEAD is
--     "zflow seen 3": 2 was the block with the names line, 3 adds the
--     words line and the templates; a text of format 1 has neither line.
--
-- THE BLOCK. Line 1 is HEAD. Line 2 says which kinds of name were known,
-- and so replaced, which were marked absent, and which were neither, the
-- kinds in the order of KINDS, "none" for an empty part, after "made up;"
-- for made-up state ("not known;" when made up could not be shown):
--   names: character, realm known; guild, account absent; guid not known
--   names: made up; none known; none absent; character, realm, guild, account, guid not known
--   names: not known; none known; none absent; character, realm, guild, account, guid not known
-- A kind that is not known was not searched for: a reader sees it here.
-- Line 3 says whose words the templates kept: "words: the add-on's" or
-- "words: given". The compare has lines 1 to 3 as the section "head". Then
-- every section of SECTIONS, in that order, always: a header "== name =="
-- and its lines. A section with nothing in it says "none". Things are
-- numbered in the order the client made them (the add-on makes them in
-- file order). A thing that is hidden says "hidden" and nothing else: a
-- hidden arrow keeps the lines it last drew, and those are not what the
-- player sees. Every <...> below that is not a number is a template.
--
--   == arrows ==            arrow <i> (<frame name>): shown | hidden
--                             line <n>: <text>      (shown, no lines: "no lines")
--   == rotation icon ==     icon (<frame name>): shown | hidden,  or "icon: not made"
--                             texture: <texture>    (shown only)
--                             mark: far | none      (shown only)
--                             reason: <line>        always: the rotation
--                           lines of the diag word, from the same pure
--                           functions (Core/Diag.lua RotationLine, ...
--                           CooldownLine, ...StealthLine, ...ReadsLine)
--                           and the driver's view. Nothing is printed.
--   == flight marks ==      mark <i>: shown | hidden
--                             node: <name> at <x>, <y>
--                             label: <text>
--   == map pins ==          pins <i>: shown | hidden
--                             pin: <name>, <kind>, <role>, at <x>, <y>
--                             line: <from> to <to>, <ax>, <ay> to <bx>, <by>
--                           pins sorted as the lines they make (templates),
--                           then lines the same way.
--   == minimap pins ==      pin <i> (<frame name>): shown at <x>, <y>, edge | inside   or hidden
--   == nameplate labels ==  label <i> (<unit>): shown | hidden
--                             text: <text> | hidden by the game
--   == combo bars ==        bar <i>: shown on <unit>, <filled> of <sections>   or hidden
--   == slot icons ==        icon <i> (<frame name>): shown | hidden
--                             texture: <texture>
--   == panels ==            panel <i> (<frame name>): shown | hidden
--                             line <n>: <text>
--   == chat ==              lines: <count>
--                             <every line the add-on printed, in order, as its template>
--   == diag ==                <every line the diag word prints, in order, as its template>
--
-- A share of a map is said to 3 decimals, a minimap offset to 1, a whole
-- number as it is. What is nil, empty or not a text or number is said as
-- "not known", never left out. Nothing is read with pairs() into the
-- block. Not in the block: where an arrow points (its drawing changes
-- with every frame), tooltips and menus, the copy box, window buttons.
--
-- TEMPLATE (lead section 199, MyBuddy's root-cause repair). A value the
-- block says (every <...> above, a chat line, a diag line) is cut into
-- words, a word being a run of ASCII letters, digits and bytes of 128 or
-- more; the rest (blanks and signs) are not words. A word stays when it is
--   * all digits (a number: "0.349" is the numbers 0 and 349 and a dot),
--   * a compass word (COMPASS: N, NE, E, SE, S, SW, W, NW, north, south,
--     east, west), or
--   * one of the add-on's own words (WORDS), compared as written: "Fly"
--     stays, "fly" does not unless the add-on writes it too.
-- Every other word is free text. A run of free words, with whatever signs
-- stand between them, is ONE slot "<text:n>", n its length in bytes. The
-- signs around a kept word stay. So "Fly to Qorvfar Zank" is "Fly to
-- <text:12>", "Then: Qorvwolves" is "Then: <text:10>", "200 yd NE" stays,
-- and "|cff00ff00Al|r is here" is "|<text:13> is here" (a colour code is a
-- word the add-on does not write). The same text always gives the same
-- template, so seenDiff compares them. A "<text:" already in the value is
-- written "(text:" first, and a typed placeholder ("<realm>", "<path>")
-- "(realm>", so no value can look like a slot or a placeholder. The known
-- names are replaced BEFORE the template, on the value as it is (see
-- NAMES); the template keeps those placeholders as they are, never
-- slotted or rewritten.
--
-- WORDS. The add-on's own words are the words of every string literal
-- ("...", '...', [[...]], [=[...]=]) in every file ZFlow/manifest.lua
-- lists, dev files left out (the fake client's test data is not the
-- add-on's), read when the first snapshot asks for them and kept for the
-- run. Comments are not literals; a backslash before a line break (LF, or
-- CR LF as one) continues a quoted literal, as Lua reads it. A literal
-- percent "%%" is taken out first, then a format's specifiers ("%s",
-- "%d", "%-5.1f": a "%", flags - + # 0, a width, a precision, and one
-- conversion letter of c d i o u x X e E f g G q s), then a string's
-- escapes ("\n", "\"", "\123"), before the words are cut: "%d yd %s"
-- gives "yd", "%d%% what" gives "what". A blank is not read as a flag, so
-- "% of" gives "of" (a "% d" keeps the "d"). The folder is the one the
-- runner was given (tools/offline/zflow-run.lua sets M.RUN_ROOT to its
-- repo root, the -Root of tools/zflow-tests.ps1), else the one found from
-- where this file was loaded (tools/offline/ under the repo). It stays current by itself:
-- a word a shipped file adds is kept from the next run on; a word no
-- shipped literal has any more is slotted. When the manifest or a file it
-- lists cannot be read, the snapshot is refused (opts.words aside).
--
-- DIAG. By default the snapshot types the diag word itself and puts back
-- what the word changes: while it runs the client's print is swapped for a
-- collector, so c.printed and the copy box's log get nothing; the snapshot
-- the word keeps in the account's saved table (diag.snaps, diag.count,
-- diag.names) is taken out again. The count in "snapshot <n> kept" is said
-- as <n>: it counts logins and asks, not what the player sees. Left
-- changed: whatever Diag.Collect itself counts (the kernel's meter), and a
-- problem kept when a diag line raises.
--
-- NAMES. Known names are replaced in a value as it is, before the
-- template: a name made of the add-on's words, or a number, would pass the
-- template, and one with a free word in it ("Quell Made", "Made" the
-- add-on's) would be cut at a slot's edge and never be seen whole. Then the
-- line of the block is replaced and checked once more, slots and
-- placeholders left out (see REFUSED). Known names:
-- opts.names, and what the fake client answers for the game's own reads
-- (UnitName, UnitFullName, GetRealmName, GetNormalizedRealmName,
-- GetGuildInfo through c.raw; c.realm(); c.guid("player")), and the
-- character and realm the diag snapshots in the account's saved table
-- hold. Of a GUID ("Player-1234-ABCDEF") the parts after the first are
-- names too, each alone and joined to the end ("1234-ABCDEF", "1234",
-- "ABCDEF"), when they have 3 letters or digits or more (a realm id of 3
-- digits too); the first part says what kind of thing it is, not who.
--
-- A line and a name are compared in their normal form: lower case, every
-- character that is not a letter or a digit taken out, a byte of 128 or
-- more kept as it is. So a name is found in upper or lower case and with
-- anything or nothing between its letters that is not a letter or digit:
-- "Quell Made" is found in "Quell-Made", "Quell_Made", "quell.made" and
-- "QuellMade". A name whose own bytes are all ASCII is looked for a second
-- time in the line with every byte of 128 or more taken out too: "Quell
-- Made" is found with a no-break space between its words, "Q'Zorvex" with a
-- curly apostrophe. From the first to the last character of what was found, the
-- line is replaced by PLACE[kind]: <character>, <realm>, <guild>,
-- <account>, <guid>. Names that overlap in a line are replaced as one,
-- with the kind of the one that starts first (the longest of those). A slot
-- "<text:n>" is never searched, nor a placeholder: a name that is in the
-- word "text" ("Tex") leaves it alone.
--
-- A name of digits only (of any kind: the "1234" of a GUID) is a number,
-- and is found only as a whole one, in the line as it is: the digits as
-- they stand, with no digit before or after, nor a dot with a digit past
-- it. So "4904" is not found in "0.349, 0.412", in "49040" or in "49-04",
-- and "349" not in "0.349" or "349.5"; it is in "id 349." and "(349)".
--
-- A name of under 3 letters or digits cannot be told from ordinary text:
-- it is refused, unless opts.shortNames is true; then it is replaced only
-- as it was written (upper and lower case alike) where no letter, digit or
-- byte of 128 or more is next to it. A name with no letter or digit at all
-- is always refused.
--
-- REFUSED. Each time with nothing returned but nil and the reason, which
-- never repeats a name:
--   * opts.names or opts.absent is not as said above, or opts.words is not
--     a list of texts;
--   * a name is too short (above);
--   * opts.madeUp is true and the client answers a character name;
--   * not made up, and a kind of M.MUST is neither known nor marked absent
--     (no character name known is refused this way too);
--   * the add-on's words cannot be read (WORDS) and opts.words is not given;
--   * after the replacing, a value (before its template), a line of the
--     block (after it) or a problem still holds a name. This check (held)
--     does not use the replacing's search:
--     it takes the placeholders (and, in a line of the block, the slots)
--     out, makes the normal form of each piece between them and of each
--     name its own way, and looks for the name (3 or more) in the piece;
--     for an all-ASCII name also in the piece with its bytes of 128 or more
--     taken out; a name of digits only as a whole number (as above) in the
--     piece as it is.
--
-- THE LIMITS. What the block can still hold:
--   * the add-on's own words and numbers, from whatever text they stood in:
--     a quest title, an NPC's or a flight master's name, a chat line or a
--     typed label made of words a shipped literal also has ("The", "of",
--     "Camp" if the add-on says it) keeps those words, and every number
--     (a typed "Camp 3" keeps the 3); the signs between words stay, and a
--     slot says the length of what it hides. A name made only of such
--     words or numbers, that this file was not told and cannot read
--     (another player in a chat line, an alt, an account name the client
--     never says: hand them in), is printed. The add-on's words include
--     spell names, and several realm names are spell names: another
--     player's realm or guild built from them prints in full.
--   * numbers that say who: only the player's own GUID is known, so the
--     GUID digits of other players and of pets print, and so does a realm
--     id of under 3 digits (a part under 3 is not a name). A realm id that
--     prints identifies the realm even where the realm's name is replaced.
--     A known number joined to another by a dot and a digit ("1.349") is
--     read as part of that number and not found.
--   * a known name in the shapes the replacing does not find: string.lower
--     knows only A to Z in Lua 5.1, so a non-ASCII letter is compared byte
--     for byte; a name is NOT found when its non-ASCII letter is in the
--     other case (bytes 195 137 for 195 169), written another way (a
--     letter and a combining accent, or the plain ASCII letter), or a
--     look-alike; nor when a sign that is not ASCII stands between its
--     letters (only an all-ASCII name is looked for with those bytes taken
--     out); nor a name of digits only written with anything between its
--     digits; nor a name cut short, misspelt, or with a letter or digit put
--     between its letters; nor a short name with a letter or digit next to
--     it (shortNames), which the second check does not look for either.
--     The template slots most of these anyway, unless they are made of the
--     add-on's words.
-- Replaced too much: a name that is also a word, or whose letters come up
-- across two words ("Tom" in "to Moonglade"), is replaced wherever that is;
-- an all-ASCII name also across a non-ASCII letter ("Tom" in "t\195\169om").
-- A name that is one of the block's own words ("pin", "line", "shown",
-- "none", "hidden") replaces those words too: sections() and seenDiff still
-- read the block (lines 1 to 3 and the "== name ==" headers are not
-- searched), but those lines no longer say what was seen. This is not the
-- capture sanitizer and does not use it.
--
-- PATHS. Only a problem's text is cut; the lines of the block are
-- templates and need no cut. Two steps, each failing closed.
--
-- First, a path is cut to "<path>/" and what follows its last slash or
-- backslash: it starts at a drive letter and a colon, at a slash that
-- begins a word, or at the "..." Lua puts where it cut a long file name
-- short, and runs to the next of : " ' < > | * ? or the line's end. What
-- follows the last slash stays only when it starts as a file's name with
-- an extension does (letters, digits, _ - . then a dot and letters, as in
-- "x.lua" or "x.lua:12", no letter, digit, _ or - right after). Anything
-- else may be a folder (the user's) and is dropped to where the path
-- ended, "<path>/" alone; and when a slash still follows on that line (the
-- path went on past a quote in a folder's name), to the end of the last
-- word there that has one.
--
-- Then every word (what stands between blanks) that still has a slash or
-- backslash outside a "<path>/" is a relative path (..\Users\x.lua,
-- ZFlow/Core/Diag.lua:12:) or a path after a sign the first step does not
-- start at (lead section 199, N4): the word is replaced whole by "<path>/"
-- and what follows its last separator when that is a file's name with an
-- extension and at most ":<line>:" after it ("<path>/Diag.lua:12:"), else
-- by "<path>". Prose with a slash ("either/or") goes too, on purpose: a
-- problem is a diagnostic, and a lost word costs less than a folder's name.
--
-- Before both steps (lead section 217, N4 rest 1 and 2): the part of a path
-- after "Users" or "home" (any case, after a separator or at the start) is
-- the user's name, whatever it holds (an apostrophe, a dot, blanks): it is
-- taken out whole, up to the next separator, ": " or the line's end, and
-- "_" stands in its place for the two steps to cut.
--
-- Still let through: a last part that is a folder with a dot in its name
-- under any folder but Users or home ("/srv/zzyx.qorv" looks like a
-- file's); the words before the one with the first separator of a
-- relative path whose folder's name has blanks ("Zzyx Middle Owner\x.lua"
-- keeps "Zzyx" and "Middle").
local M = {}

M.HEAD = "zflow seen 3"
M.UNKNOWN = "not known"
M.NONE = "none"
M.NOT_ASKED = "not asked"
M.FAILED = "failed"
M.SECTIONS = { "arrows", "rotation icon", "flight marks", "map pins", "minimap pins",
    "nameplate labels", "combo bars", "slot icons", "panels", "chat", "diag" }
M.KINDS = { "character", "realm", "guild", "account", "guid" }
M.MUST = { "character", "realm", "guild", "account", "guid" }
-- Set by tools/offline/zflow-run.lua to the repo folder it was given (the
-- runner's -Root); nil: M.ROOT. See WORDS.
M.RUN_ROOT = nil
M.PLACE = { character = "<character>", realm = "<realm>", guild = "<guild>",
    account = "<account>", guid = "<guid>" }
M.PATH = "<path>/"
M.PATH_WHOLE = "<path>"
M.SHORT = 3
M.GUID_PART = 3
M.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW", "north", "south", "east", "west" }
-- A slot as a pattern, and a word as a pattern (see TEMPLATE).
local SLOT = "<text:%d+>"
local WORD = "[%w\128-\255]+"

local COMPASS = {}
for _, w in ipairs(M.COMPASS) do COMPASS[w] = true end

-- The repo's folder: two up from this file's (tools/offline/). nil when
-- this file was not loaded from a file.
do
    local source = debug.getinfo(1, "S").source
    if type(source) == "string" and source:sub(1, 1) == "@" then
        local dir = source:match("^@(.*)[/\\][^/\\]*$") or "."
        M.ROOT = dir .. "/../.."
    end
end

-- ------------------------------------------------------------------ words
local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function fixed(v, format)
    if not finite(v) then return M.UNKNOWN end
    local s = string.format(format, v)
    -- "-0.000" and "0.000" are the same place.
    if not s:find("[1-9]") then s = s:gsub("^%-", "") end
    return s
end

-- A share of a map (0..1), and an offset in screen units.
local function share(v) return fixed(v, "%.3f") end
local function offset(v) return fixed(v, "%.1f") end

-- A text or a number as one line; anything else is not known.
local function word(v)
    if type(v) == "number" then
        if not finite(v) then return M.UNKNOWN end
        if v == math.floor(v) and v > -1e15 and v < 1e15 then return string.format("%d", v) end
        return share(v)
    end
    if type(v) ~= "string" or v == "" then return M.UNKNOWN end
    local s = v:gsub("[\r\n]+", " ")
    return s
end

local function list(v) return type(v) == "table" and v or {} end

-- ---------------------------------------------------------------- template
-- M.template(text, words) -> the text with every run of free words as one
-- slot "<text:n>". words: a set { [word] = true } (nil: none). A
-- placeholder of a kind of name ("<character>" ...) stays. See TEMPLATE.
function M.template(text, words)
    words = type(words) == "table" and words or {}
    text = text:gsub("<text:", "(text:")
    local out, pos, runFrom, runTo = {}, 1, nil, nil
    local function close()
        if runFrom then
            out[#out + 1] = "<text:" .. (runTo - runFrom + 1) .. ">"
            runFrom = nil
        end
    end
    while true do
        local a, b = text:find(WORD, pos)
        if not a then
            close()
            out[#out + 1] = text:sub(pos)
            break
        end
        local token = text:sub(a, b)
        -- A placeholder the replacing put in ("<character>" ...) stays as it is.
        local placed = M.PLACE[token] ~= nil and text:sub(a - 1, a - 1) == "<" and text:sub(b + 1, b + 1) == ">"
        if placed or token:find("^%d+$") or words[token] or COMPASS[token] then
            close()
            out[#out + 1] = text:sub(pos, a - 1)
            out[#out + 1] = token
        elseif runFrom then
            -- The signs since the last free word go into the slot.
            runTo = b
        else
            out[#out + 1] = text:sub(pos, a - 1)
            runFrom, runTo = a, b
        end
        pos = b + 1
    end
    return table.concat(out)
end

-- M.wordSet(texts) -> { [word] = true }: the words of each text, with a
-- format's specifiers and a string's escapes taken out first (see WORDS).
function M.wordSet(texts)
    local set = {}
    for _, text in ipairs(list(texts)) do
        if type(text) == "string" then
            -- "%%" first: its second "%" would start a specifier that eats
            -- the next word's first letter ("%d%% what" gave "hat").
            local bare = text:gsub("%%%%", " "):gsub("%%[%-%+#0]*%d*%.?%d*[cdiouxXeEfgGqs]", " ")
                :gsub("\\%d%d?%d?", " "):gsub("\\.", " ")
            for token in bare:gmatch(WORD) do set[token] = true end
        end
    end
    return set
end

-- M.literals(source) -> the contents of every string literal of a Lua
-- source, as written (escapes not decoded); comments are skipped.
function M.literals(src)
    local out, i, n = {}, 1, #src
    while true do
        local a = src:find("[%-\"'%[]", i)
        if not a then break end
        local ch = src:sub(a, a)
        if ch == "-" then
            if src:sub(a + 1, a + 1) == "-" then
                -- A comment: long to its closing bracket, else to the line's end.
                local eq = src:match("^%[(=*)%[", a + 2)
                local e
                if eq then
                    e = select(2, src:find("]" .. eq .. "]", a + 4 + #eq, true))
                else
                    e = src:find("\n", a + 2, true)
                end
                i = (e or n) + 1
            else
                i = a + 1
            end
        elseif ch == "[" then
            local eq = src:match("^%[(=*)%[", a)
            if eq then
                local from = a + 2 + #eq
                local close, e = src:find("]" .. eq .. "]", from, true)
                out[#out + 1] = src:sub(from, (close or n + 1) - 1)
                i = (e or n) + 1
            else
                i = a + 1
            end
        else
            -- A quoted string: to the same quote not escaped, or the line's end.
            local stop = ch == '"' and '[\\\n"]' or "[\\\n']"
            local k = a + 1
            while true do
                local j = src:find(stop, k)
                if not j then
                    k = n + 1
                    break
                end
                if src:sub(j, j) == "\\" then
                    -- A backslash before CR LF continues the string over
                    -- both bytes, as Lua reads it.
                    k = src:sub(j + 1, j + 2) == "\r\n" and j + 3 or j + 2
                else
                    k = j
                    break
                end
            end
            out[#out + 1] = src:sub(a + 1, k - 1)
            i = k + 1
        end
    end
    return out
end

-- M.words(root) -> the add-on's own words { [word] = true }, or nil and
-- why. root: the repo's folder (nil: M.RUN_ROOT, the runner's, else
-- M.ROOT, this file's; that answer is kept for the run, for that folder).
-- See WORDS. The reason names no path.
local kept, keptAt
function M.words(root)
    local at = root or M.RUN_ROOT or M.ROOT
    if root == nil and kept and keptAt == at then return kept end
    if type(at) ~= "string" then return nil, "the repo's folder is not known (this file was not loaded from a file)" end
    local chunk = loadfile(at .. "/ZFlow/manifest.lua")
    if not chunk then return nil, "ZFlow/manifest.lua did not load" end
    local ok, manifest = pcall(chunk)
    if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
        return nil, "ZFlow/manifest.lua is not a list of files"
    end
    local texts, files = {}, 0
    for _, entry in ipairs(manifest.files) do
        local path, dev = entry, false
        if type(entry) == "table" then path, dev = entry[1], entry.dev == true end
        if type(path) ~= "string" then return nil, "ZFlow/manifest.lua has an entry that is not a path" end
        if not dev then
            local fh = io.open(at .. "/ZFlow/" .. path, "rb")
            if not fh then return nil, "a file ZFlow/manifest.lua lists did not open" end
            local src = fh:read("*a")
            fh:close()
            for _, literal in ipairs(M.literals(src or "")) do texts[#texts + 1] = literal end
            files = files + 1
        end
    end
    if files == 0 then return nil, "ZFlow/manifest.lua lists no shipped file" end
    local set = M.wordSet(texts)
    if root == nil then kept, keptAt = set, at end
    return set
end

local function frameName(h, say)
    return say(type(h.spec) == "table" and h.spec.name or nil)
end

-- ------------------------------------------------------------- the sections
-- Each takes say(v): what the block says of a free value (its template).
local function arrows(c, say)
    local out = {}
    for i, h in ipairs(list(c.arrows)) do
        local head = "arrow " .. i .. " (" .. frameName(h, say) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            local lines = list(h.lines)
            if #lines == 0 then out[#out + 1] = "  no lines" end
            for n = 1, #lines do out[#out + 1] = "  line " .. n .. ": " .. say(lines[n]) end
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

-- The rotation's reason: the lines the diag word says of it, made by the
-- same functions from the driver's view. nil: not known (no add-on, or it
-- has no diag or no driver). Nothing is printed and nothing is kept.
local function reasons(addon)
    if type(addon) ~= "table" then return nil end
    local Diag, driver = addon.Diag, addon.RotationDriver
    if type(Diag) ~= "table" or type(driver) ~= "table" or type(addon.ModuleState) ~= "function" then
        return nil
    end
    local state = addon:ModuleState(driver.NAME)
    if state == nil then return {} end
    local view, enabled
    if state == "started" then
        local got = type(addon.use) == "function" and addon.use(driver.NAME) or nil
        if type(got) ~= "table" or type(got.View) ~= "function" then
            return { "rotation: not running (" .. tostring(state) .. ")." }
        end
        view = got.View()
        enabled = type(addon.settings) == "table" and addon.settings:get(driver.SETTING) == true
    end
    local lines = {}
    lines[#lines + 1] = Diag.RotationLine(state, view, enabled)
    lines[#lines + 1] = Diag.RotationCooldownLine(view)
    lines[#lines + 1] = Diag.RotationStealthLine(view)
    lines[#lines + 1] = Diag.RotationReadsLine(view)
    return lines
end

local function rotationIcon(c, addon, say)
    local out, made = {}, false
    for _, h in ipairs(list(c.icons)) do
        local name = type(h.spec) == "table" and h.spec.name or nil
        if type(name) == "string" and name:find("RotationIcon", 1, true) then
            made = true
            if h.shown == true then
                out[#out + 1] = "icon (" .. say(name) .. "): shown"
                out[#out + 1] = "  texture: " .. say(h.texture)
                out[#out + 1] = "  mark: " .. (h.marked == nil and M.NONE or say(h.marked))
            else
                out[#out + 1] = "icon (" .. say(name) .. "): hidden"
            end
        end
    end
    if not made then out[#out + 1] = "icon: not made" end
    local why = reasons(addon)
    if why == nil then
        out[#out + 1] = "  reason: " .. M.UNKNOWN
    elseif #why == 0 then
        out[#out + 1] = "  reason: " .. M.NONE
    else
        for i = 1, #why do out[#out + 1] = "  reason: " .. say(why[i]) end
    end
    return out
end

local function flightMarks(c, say)
    local out = {}
    for i, h in ipairs(list(c.taxiMarks)) do
        if h.shown == true then
            local node = list(h.node)
            out[#out + 1] = "mark " .. i .. ": shown"
            out[#out + 1] = "  node: " .. say(node.name) .. " at " .. share(node.x) .. ", " .. share(node.y)
            out[#out + 1] = "  label: " .. say(h.label)
        else
            out[#out + 1] = "mark " .. i .. ": hidden"
        end
    end
    return out
end

-- Rows as lines, sorted as text, added to out.
local function sortedInto(out, rows, make)
    local lines = {}
    for _, row in ipairs(list(rows)) do
        if type(row) == "table" then lines[#lines + 1] = make(row) end
    end
    table.sort(lines)
    for i = 1, #lines do out[#out + 1] = lines[i] end
end

local function mapPins(c, say)
    local out = {}
    for i, h in ipairs(list(c.mapPinSets)) do
        if h.shown == true then
            out[#out + 1] = "pins " .. i .. ": shown"
            sortedInto(out, h.pins, function(p)
                return "  pin: " .. say(p.name) .. ", " .. say(p.kind) .. ", " .. say(p.role)
                    .. ", at " .. share(p.x) .. ", " .. share(p.y)
            end)
            sortedInto(out, h.lines, function(l)
                return "  line: " .. say(l.from) .. " to " .. say(l.to) .. ", " .. share(l.ax) .. ", "
                    .. share(l.ay) .. " to " .. share(l.bx) .. ", " .. share(l.by)
            end)
        else
            out[#out + 1] = "pins " .. i .. ": hidden"
        end
    end
    return out
end

local function minimapPins(c, say)
    local out = {}
    for i, h in ipairs(list(c.minimapPins)) do
        local head = "pin " .. i .. " (" .. frameName(h, say) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown at " .. offset(h.x) .. ", " .. offset(h.y) .. ", "
                .. (h.edge == true and "edge" or "inside")
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function plateLabels(c, say)
    local out = {}
    for i, h in ipairs(list(c.plateLabels)) do
        local head = "label " .. i .. " (" .. say(h.unit) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            -- A value the game hides is kept as it came: it has no text.
            local says = h.says
            if says ~= nil and type(says) ~= "string" and type(says) ~= "number" then
                out[#out + 1] = "  text: hidden by the game"
            else
                out[#out + 1] = "  text: " .. say(says)
            end
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function comboBars(c, say)
    local out = {}
    for i, h in ipairs(list(c.comboBars)) do
        if h.shown == true then
            out[#out + 1] = "bar " .. i .. ": shown on " .. say(h.hung) .. ", " .. say(h.value)
                .. " of " .. say(h.max)
        else
            out[#out + 1] = "bar " .. i .. ": hidden"
        end
    end
    return out
end

local function slotIcons(c, say)
    local out = {}
    for i, h in ipairs(list(c.slotIcons)) do
        local head = "icon " .. i .. " (" .. frameName(h, say) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            out[#out + 1] = "  texture: " .. say(h.texture)
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function panels(c, say)
    local out = {}
    for i, h in ipairs(list(c.panels)) do
        local head = "panel " .. i .. " (" .. frameName(h, say) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            local lines = list(h.lines)
            if #lines == 0 then out[#out + 1] = "  no lines" end
            for n = 1, #lines do out[#out + 1] = "  line " .. n .. ": " .. say(lines[n]) end
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

-- ------------------------------------------------------------------- diag
-- What the diag word's snapshot will change in the account's saved table,
-- as it is now.
local function keepDiag(c, id)
    if type(c.savedExists) ~= "function" or type(c.saved) ~= "function" then return nil end
    if not c.savedExists(id.accountDB) then return { absent = true } end
    local db = c.saved(id.accountDB)
    local saved = { db = db, diag = db.diag }
    local d = db.diag
    if type(d) == "table" then
        saved.count, saved.names, saved.snaps = d.count, d.names, d.snaps
        if type(d.snaps) == "table" then
            saved.rows = {}
            for i = 1, #d.snaps do saved.rows[i] = d.snaps[i] end
        end
    end
    return saved
end

local function putBackDiag(c, id, saved)
    if saved == nil then return end
    if saved.absent then
        if type(c.setSaved) == "function" then c.setSaved(id.accountDB, nil) end
        return
    end
    saved.db.diag = saved.diag
    local d = saved.diag
    if type(d) ~= "table" then return end
    d.count, d.names, d.snaps = saved.count, saved.names, saved.snaps
    if saved.rows then
        local snaps = saved.snaps
        for i = #snaps, 1, -1 do snaps[i] = nil end
        for i = 1, #saved.rows do snaps[i] = saved.rows[i] end
    end
end

-- Types the diag word and gives its lines as printed; nil when it cannot
-- be asked. See DIAG in the header for what is put back.
local function askDiag(c, addon)
    local id = type(addon) == "table" and addon.id or nil
    if type(id) ~= "table" or type(c.slashes) ~= "table" then return nil end
    local slash = c.slashes[id.slash]
    if type(slash) ~= "function" then return nil end
    local printed = type(c.printed) == "table" and c.printed or nil
    local before = printed and #printed or 0
    local saved = keepDiag(c, id)
    local said, own = {}, c.print
    c.print = function(line) said[#said + 1] = tostring(line) end
    local ok, err = pcall(slash, "diag")
    c.print = own
    -- A line that went round the swap: it is the word's too, and is taken
    -- out of the chat again.
    if printed then
        for i = before + 1, #printed do said[#said + 1] = tostring(printed[i]) end
        for i = #printed, before + 1, -1 do printed[i] = nil end
    end
    putBackDiag(c, id, saved)
    if not ok then error(err, 0) end
    return said
end

-- ------------------------------------------------------------------ names
-- M.normal(text, ascii) -> the text in lower case with every character
-- that is not a letter or a digit taken out (a byte of 128 or more is kept
-- as it is; with ascii true it is taken out too), and for each place of it
-- the place in the text it came from.
function M.normal(text, ascii)
    local out, map = {}, {}
    for i = 1, #text do
        local b = text:byte(i)
        if b >= 65 and b <= 90 then b = b + 32 end
        if (b >= 48 and b <= 57) or (b >= 97 and b <= 122) or (b >= 128 and not ascii) then
            out[#out + 1] = string.char(b)
            map[#map + 1] = i
        end
    end
    return table.concat(out), map
end

-- A digit, an ASCII letter, or a byte of a non-ASCII character.
local function wordByte(b)
    return b ~= nil and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 128)
end

local function digitByte(b)
    return b ~= nil and b >= 48 and b <= 57
end

-- True when text:sub(a, b) (digits) is a whole number: no digit next to
-- it, and no dot with a digit past it ("0.349", "349.5" are one number).
local function wholeAt(text, a, b)
    local before = a > 1 and text:byte(a - 1) or nil
    local after = text:byte(b + 1)
    if digitByte(before) or digitByte(after) then return false end
    if before == 46 and a > 2 and digitByte(text:byte(a - 2)) then return false end
    if after == 46 and digitByte(text:byte(b + 2)) then return false end
    return true
end

-- ascii: no byte of 128 or more in the name. digits: nothing but digits.
-- client: the client answered it (not handed in): names.fromClient[kind].
local function addName(names, kind, v, client)
    if type(v) ~= "string" or v == "" then return end
    local norm = M.normal(v)
    names[#names + 1] = { kind = kind, text = v, lower = v:lower(), norm = norm, short = #norm < M.SHORT,
        ascii = not v:find("[\128-\255]"), digits = v:find("^%d+$") ~= nil }
    names[kind] = true
    if client then names.fromClient[kind] = true end
end

-- A GUID, and its parts after the first (see NAMES).
local function addGuid(names, kind, v, client)
    if type(v) ~= "string" or v == "" then return end
    addName(names, kind, v, client)
    local parts = {}
    for part in v:gmatch("[^%-]+") do parts[#parts + 1] = part end
    for i = 2, #parts do
        local alone, tail = parts[i], table.concat(parts, "-", i)
        if #(M.normal(alone)) >= M.GUID_PART then addName(names, kind, alone, client) end
        if tail ~= alone and #(M.normal(tail)) >= M.GUID_PART then addName(names, kind, tail, client) end
    end
end

-- The names handed in (opts.names) into names; a text when they are not
-- as the header says. The text never repeats a key or a value: either may
-- be a name.
local function addGiven(names, given)
    if given == nil then return nil end
    local want = "refused, because names would be passed over. It is { character =, realm =, guild =, "
        .. "account =, guid = }, each a text or a list of texts."
    if type(given) ~= "table" then return "opts.names is not a table: " .. want end
    for key in pairs(given) do
        if type(key) ~= "string" or not M.PLACE[key] then
            return "opts.names has a key that is no kind of name (a list goes under its kind): " .. want
        end
    end
    for _, kind in ipairs(M.KINDS) do
        local v = given[kind]
        local add = kind == "guid" and addGuid or addName
        if type(v) == "table" then
            for key, item in pairs(v) do
                if type(key) ~= "number" or type(item) ~= "string" or item == "" then
                    return "opts.names." .. kind .. " is not a list of texts: " .. want
                end
                add(names, kind, item)
            end
        elseif type(v) == "string" and v ~= "" then
            add(names, kind, v)
        elseif v ~= nil then
            return "opts.names." .. kind .. " is not a text or a list of texts: " .. want
        end
    end
    return nil
end

-- True when the client has the read and it answered (with a name or none).
local function asked(c, fn, ...)
    if type(c.raw) ~= "function" then return false end
    local ok, done = pcall(c.raw, fn, ...)
    return ok and done == true
end

-- One of the game's own reads, through the fake client's c.raw: the
-- answers, or nothing when the client has no such read or it raised.
local function read(c, fn, ...)
    if type(c.raw) ~= "function" then return nil end
    local got = { pcall(c.raw, fn, ...) }
    if got[1] and got[2] == true then return got[3], got[4] end
    return nil
end

-- M.names(c, addon, given, shortNames) -> the names to take out, longest
-- first; the list also has [kind] = true for each kind that has a name,
-- and fromClient[kind] = true for each kind the client itself answered.
-- Or nil and the reason: given is not as the header says, or a name is
-- too short (shortNames true lets a name of 1 or 2 through).
function M.names(c, addon, given, shortNames)
    local names = { fromClient = {}, asked = false }
    local bad = addGiven(names, given)
    if bad then return nil, bad end
    if type(c) == "table" then
        -- Whether a name read answered at all (N2: made up can be shown).
        names.asked = asked(c, "UnitName", "player") or asked(c, "UnitFullName", "player")
        local name, realm = read(c, "UnitName", "player")
        addName(names, "character", name, true); addName(names, "realm", realm, true)
        name, realm = read(c, "UnitFullName", "player")
        addName(names, "character", name, true); addName(names, "realm", realm, true)
        addName(names, "realm", (read(c, "GetRealmName")), true)
        addName(names, "realm", (read(c, "GetNormalizedRealmName")), true)
        addName(names, "guild", (read(c, "GetGuildInfo", "player")), true)
        if type(c.realm) == "function" then
            local ok, own = pcall(c.realm)
            if ok then addName(names, "realm", own, true) end
        end
        if type(c.guid) == "function" then
            local ok, guid = pcall(c.guid, "player")
            if ok then addGuid(names, "guid", guid, true) end
        end
        -- What the diag snapshots kept of the session (Core/Diag.lua).
        local id = type(addon) == "table" and addon.id or nil
        if type(id) == "table" and type(c.savedExists) == "function" and c.savedExists(id.accountDB) then
            local diag = c.saved(id.accountDB).diag
            local snaps = type(diag) == "table" and list(diag.snaps) or {}
            -- SP-5: made up can be shown from kept snapshots only when there are some.
            if #snaps > 0 then names.snapsRead = true end
            for i = 1, #snaps do
                local timing = type(snaps[i]) == "table" and snaps[i].timing or nil
                if type(timing) == "table" then
                    addName(names, "character", timing.character, true)
                    addName(names, "realm", timing.realm, true)
                end
            end
        end
    end
    for i = 1, #names do
        local name = names[i]
        if name.norm == "" then
            return nil, "a " .. name.kind .. " name has no letter or digit in it and cannot be searched for: refused"
        end
        if name.short and shortNames ~= true then
            return nil, "a " .. name.kind .. " name is too short: a name under " .. M.SHORT
                .. " characters cannot be told from ordinary text. Refused; with opts.shortNames = true "
                .. "it is replaced where it stands as a whole word."
        end
    end
    local rank = {}
    for i, kind in ipairs(M.KINDS) do rank[kind] = i end
    table.sort(names, function(a, b)
        if #a.norm ~= #b.norm then return #a.norm > #b.norm end
        if a.norm ~= b.norm then return a.norm < b.norm end
        if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
        return a.lower < b.lower
    end)
    return names
end

-- opts.absent as { [kind] = true }, or nil and why (the why names kinds
-- only, never a value).
local function absentKinds(v)
    if v == nil then return {} end
    local want = "opts.absent is not a list of kinds of name (" .. table.concat(M.KINDS, ", ") .. "): refused"
    if type(v) ~= "table" then return nil, want end
    local out = {}
    for key, kind in pairs(v) do
        if type(key) ~= "number" or type(kind) ~= "string" or not M.PLACE[kind] then return nil, want end
        out[kind] = true
    end
    return out
end

-- Line 2 of the block: made up or not, and the kinds known, absent and
-- neither.
local function namesLine(names, absent, madeUp, shown)
    local known, gone, missing = {}, {}, {}
    for _, kind in ipairs(M.KINDS) do
        local into = names[kind] and known or (absent[kind] and gone or missing)
        into[#into + 1] = kind
    end
    local function said(kinds) return #kinds > 0 and table.concat(kinds, ", ") or M.NONE end
    local head = madeUp and (shown and "made up; " or (M.UNKNOWN .. "; ")) or ""
    return "names: " .. head .. said(known) .. " known; " .. said(gone) .. " absent; "
        .. said(missing) .. " not known"
end

-- Where the names are in the text: { s, e, kind } by place in the text as
-- it is, in order, no two overlapping (those that did are one).
local function spans(line, names)
    local norm, map = M.normal(line)
    -- The line with its non-ASCII bytes taken out: only when it has any.
    local plain, plainMap = M.normal(line, true)
    if #plain == #norm then plain = nil end
    local low, found = line:lower(), {}
    for k = 1, #names do
        local name = names[k]
        local from = 1
        while true do
            local a, b
            if name.short then
                -- As it was written, a whole word.
                a, b = low:find(name.lower, from, true)
                if not a then break end
                if not wordByte(low:byte(a - 1)) and not wordByte(low:byte(b + 1)) then
                    found[#found + 1] = { s = a, e = b, kind = name.kind, at = #found + 1 }
                end
            elseif name.digits then
                -- A whole number, in the line as it is.
                a, b = line:find(name.text, from, true)
                if not a then break end
                if wholeAt(line, a, b) then
                    found[#found + 1] = { s = a, e = b, kind = name.kind, at = #found + 1 }
                end
            else
                a, b = norm:find(name.norm, from, true)
                if not a then break end
                found[#found + 1] = { s = map[a], e = map[b], kind = name.kind, at = #found + 1 }
            end
            from = a + 1
        end
        if plain and name.ascii and not name.short and not name.digits then
            from = 1
            while true do
                local a, b = plain:find(name.norm, from, true)
                if not a then break end
                found[#found + 1] = { s = plainMap[a], e = plainMap[b], kind = name.kind, at = #found + 1 }
                from = a + 1
            end
        end
    end
    table.sort(found, function(x, y)
        if x.s ~= y.s then return x.s < y.s end
        if x.e ~= y.e then return x.e > y.e end
        return x.at < y.at
    end)
    local merged = {}
    for i = 1, #found do
        local last = merged[#merged]
        if last and found[i].s <= last.e then
            if found[i].e > last.e then last.e = found[i].e end
        else
            merged[#merged + 1] = found[i]
        end
    end
    return merged
end

-- One piece of a line (no slot in it) with every name replaced.
local function redactPiece(piece, names)
    local out, from = {}, 1
    for _, span in ipairs(spans(piece, names)) do
        out[#out + 1] = piece:sub(from, span.s - 1)
        out[#out + 1] = M.PLACE[span.kind]
        from = span.e + 1
    end
    out[#out + 1] = piece:sub(from)
    return table.concat(out)
end

-- The next slot or placeholder ("<character>" ..., "<path>") in the line
-- from place from: where it starts and ends, or nil.
local function nextKept(line, from)
    local a, b = line:find(SLOT, from)
    for i = 0, #M.KINDS do
        local place = i == 0 and M.PATH_WHOLE or M.PLACE[M.KINDS[i]]
        local pa, pb = line:find(place, from, true)
        if pa and (not a or pa < a) then a, b = pa, pb end
    end
    return a, b
end

-- M.redact(line, names) -> the line with every name replaced. Every place
-- of every name is found in the line as it was, the places that overlap
-- are made one, and each is replaced once: a replacement is never searched.
-- A slot "<text:n>" or a placeholder is never searched either: the pieces
-- between them are searched each on its own, so a line can be redacted
-- twice (the raw value, then the line of the block).
function M.redact(line, names)
    if #names == 0 then return line end
    local out, from = {}, 1
    while true do
        local a, b = nextKept(line, from)
        out[#out + 1] = redactPiece(line:sub(from, (a or #line + 1) - 1), names)
        if not a then break end
        out[#out + 1] = line:sub(a, b)
        from = b + 1
    end
    return table.concat(out)
end

-- The line cut at every placeholder (and, with slots true, every slot):
-- the pieces between them.
local function pieces(line, slots)
    local rest = { line }
    -- "<path>" is in "<path>/" too: the slash left over is no letter.
    local places = { M.PATH_WHOLE }
    for _, kind in ipairs(M.KINDS) do places[#places + 1] = M.PLACE[kind] end
    local function cut(at, plain)
        local into = {}
        for _, piece in ipairs(rest) do
            local from = 1
            while true do
                local a, b = piece:find(at, from, plain)
                if not a then break end
                into[#into + 1] = piece:sub(from, a - 1)
                from = b + 1
            end
            into[#into + 1] = piece:sub(from)
        end
        rest = into
    end
    for _, place in ipairs(places) do cut(place, true) end
    if slots then cut(SLOT, false) end
    return rest
end

-- The second check's own normal form (not M.normal: see NAMES). ascii
-- true: the bytes of 128 or more are taken out too.
local function flat(text, ascii)
    local s = text:lower():gsub(ascii and "[^0-9a-z]" or "[^%w\128-\255]", "")
    return s
end

-- The second check's own search for a name of digits only: true when the
-- number stands in the text with no digit before or after it, nor a dot
-- with a digit past it.
local function wholeNumber(text, number)
    local from = 1
    while true do
        local a, b = text:find(number, from, true)
        if not a then return false end
        local head = a > 2 and text:sub(a - 2, a - 1) or (a > 1 and text:sub(a - 1, a - 1) or "")
        local tail = text:sub(b + 1, b + 2)
        if not head:find("%d%.?$") and not tail:find("^%.?%d") then return true end
        from = a + 1
    end
end

-- M.held(line, names, slots) -> true when the line, its placeholders (and,
-- with slots true, its slots: a line of the block, which the template
-- made) set aside, still holds a name of 3 or more. Does not use redact's
-- search.
function M.held(line, names, slots)
    local wanted, plain, numbers = {}, {}, {}
    for k = 1, #names do
        local given = names[k].text
        local name = flat(given)
        if #name < M.SHORT then
            -- Not looked for (see the limits).
        elseif given:find("^%d+$") then
            numbers[#numbers + 1] = given
        else
            wanted[#wanted + 1] = name
            if not given:find("[\128-\255]") then plain[#plain + 1] = name end
        end
    end
    for _, piece in ipairs(pieces(line, slots == true)) do
        local text, bare = flat(piece), flat(piece, true)
        for k = 1, #wanted do
            if text:find(wanted[k], 1, true) then return true end
        end
        if bare ~= text then
            for k = 1, #plain do
                if bare:find(plain[k], 1, true) then return true end
            end
        end
        for k = 1, #numbers do
            if wholeNumber(piece, numbers[k]) then return true end
        end
    end
    return false
end

-- ------------------------------------------------------------------ paths
-- Where the folders of a path that starts at place i begin, or nil: no
-- path starts there. See PATHS in the header.
local function pathBody(text, i)
    local before = i > 1 and text:sub(i - 1, i - 1) or ""
    if text:find("^%a:[\\/]", i) and not before:find("^[%w\128-\255]") then return i + 2 end
    if text:find("^[\\/]%S", i) and (before == "" or before:find("^[%s\"'%(%[=,:]")) then return i end
    if text:find("^%.%.%.[^%s%.]", i) and before ~= "." then return i + 3 end
    return nil
end

-- True when the text at place i starts as a file's name with an extension
-- does: "x.lua", "x.lua:12", "d.txt" and a blank. Not "zzyxowner (...".
local function fileName(text, i)
    local e = text:match("^[%w_%-%.]+%.%a+()", i)
    return e ~= nil and not text:find("^[%w_%-\128-\255]", e)
end

-- A word with a separator the first step did not cut (lead section 199,
-- N4): "<path>/" and its file's name with at most ":<line>:" after it, or
-- "<path>".
local function relative(token)
    local tail = token:match("[\\/]([^\\/]*)$") or ""
    local file = tail:match("^[%w_%-%.]*%.%a+")
    if not file or file:sub(1, 1) == "." then return M.PATH_WHOLE end
    if not tail:sub(#file + 1):find("^:?%d*:?$") then return M.PATH_WHOLE end
    return M.PATH .. tail
end

-- Every word that still has a slash or backslash outside a "<path>/" is
-- replaced whole (see relative). (No character of M.PATH is a pattern's.)
local function wordsCut(text)
    local s = text:gsub("%S+", function(token)
        local rest = token:gsub(M.PATH, "")
        if rest:find("[\\/]") then return relative(token) end
        return nil
    end)
    return s
end

-- The folders whose next part is a user's name (N4 rest 1 and 2).
M.HOMES = { "users", "home", "documents and settings" }

-- Where the next home folder at or after i is: the start of its word and
-- the place of the separator after it, or nil. Only one that stands at the
-- start of the text, or right after a separator, a blank, a tab or a line
-- break (lead section 223, SP-1) counts.
local function nextHome(low, i)
    local s, e
    for _, word in ipairs(M.HOMES) do
        local a, b = low:find(word .. "[\\/]", i)
        while a and a > 1 and not low:sub(a - 1, a - 1):find("[\\/%s]") do
            a, b = low:find(word .. "[\\/]", a + 1)
        end
        if a and (not s or a < s) then s, e = a, b end
    end
    return s, e
end

-- The text with the part after each home folder taken out whole: up to the
-- next separator, ": ", a tab, a double quote, the line's end or the end,
-- "_" in its place (SP-3: what follows a tab or a closing quote stays). A
-- blank or an apostrophe does not end it: a user's folder can hold either.
local function userParts(text)
    local low, out, from = text:lower(), {}, 1
    local _, e = nextHome(low, 1)
    while e do
        local stop = #text + 1
        local sep = text:find("[\\/\r\n\t\"]", e + 1)
        if sep and sep < stop then stop = sep end
        local colon = text:find(": ", e + 1, true)
        if colon and colon < stop then stop = colon end
        out[#out + 1] = text:sub(from, e)
        out[#out + 1] = "_"
        from = stop
        _, e = nextHome(low, stop)
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
end

-- M.paths(text) -> the text with every path cut to "<path>/" and the
-- file's name that follows its last separator, or to "<path>". See PATHS.
function M.paths(text)
    text = userParts(text)
    local out, from, i, n = {}, 1, 1, #text
    while i <= n do
        local body, cut, stop = pathBody(text, i), nil, nil
        if body then
            stop = text:find("[:\"'<>|%*%?\r\n\t]", body) or (n + 1)
            local last = text:sub(body, stop - 1):match(".*()[\\/]")
            if last then cut = body + last - 1 end
        end
        if cut then
            out[#out + 1] = text:sub(from, i - 1)
            out[#out + 1] = M.PATH
            local keep = cut + 1
            if not fileName(text, keep) then
                -- A folder, maybe: dropped to the path's end, and past it
                -- to the last word of this line that has a slash.
                keep = text:match("^[^\r\n]*[\\/]%S*()", stop) or stop
            end
            from, i = keep, keep
        else
            i = i + 1
        end
    end
    out[#out + 1] = text:sub(from)
    return wordsCut(table.concat(out))
end

-- --------------------------------------------------------------- snapshot
-- The kinds that refuse, or nil: see REFUSED in the header.
local function refusedKinds(names, absent, madeUp)
    if absent.character then
        return "opts.absent cannot mark character absent: a real state has one. Refused"
    end
    for _, kind in ipairs(M.KINDS) do
        if absent[kind] and names[kind] then
            return "opts.absent marks " .. kind .. " absent, but a " .. kind .. " name is known: refused"
        end
    end
    if madeUp then
        if names.fromClient.character then
            return "the state was said to be made up, but the client answers a character name: refused, "
                .. "because it is real state. Hand in its names and say opts.absent instead."
        end
        return nil
    end
    for _, kind in ipairs(M.MUST) do
        if not names[kind] and not absent[kind] then
            return "no " .. kind .. " name is known (none in opts.names, none from the client's reads) and "
                .. "opts.absent does not mark it absent: refused, because it cannot be taken out. "
                .. "Hand it in, or mark it absent (not character)."
        end
    end
    return nil
end

function M.seen(c, addon, opts)
    opts = list(opts)
    if type(c) ~= "table" then return nil, "no fake client was given" end
    local names, bad = M.names(c, addon, opts.names, opts.shortNames == true)
    if not names then return nil, bad end
    local absent, badAbsent = absentKinds(opts.absent)
    if not absent then return nil, badAbsent end
    local madeUp = opts.madeUp == true
    local why = refusedKinds(names, absent, madeUp)
    if why then return nil, why end

    local words, whose
    if opts.words ~= nil then
        if type(opts.words) ~= "table" then return nil, "opts.words is not a list of texts: refused" end
        for key, item in pairs(opts.words) do
            if type(key) ~= "number" or type(item) ~= "string" then
                return nil, "opts.words is not a list of texts: refused"
            end
        end
        words, whose = M.wordSet(opts.words), "given"
    else
        local wordsWhy
        words, wordsWhy = M.words()
        if not words then
            return nil, "the add-on's own words could not be read (" .. tostring(wordsWhy) .. "): refused, "
                .. "because free text cannot be told from them"
        end
        whose = "the add-on's"
    end
    -- What the block says of a free value: its known names replaced on the
    -- raw text, then its template (see TEMPLATE and NAMES). A slot or a
    -- placeholder typed into the value is made plain text first, so only
    -- the replacing's own placeholders pass the template. heldRaw: a value
    -- still held a name after the replacing (the section is refused).
    local heldRaw = false
    local function neutral(kind)
        if M.PLACE[kind] or "<" .. kind .. ">" == M.PATH_WHOLE then return "(" .. kind .. ">" end
        return nil
    end
    local function say(v)
        local s = word(v)
        if s == M.UNKNOWN or type(v) == "number" then return s end
        s = s:gsub("<text:", "(text:"):gsub("<(%a+)>", neutral)
        s = M.redact(s, names)
        if M.held(s, names) then heldRaw = true end
        return M.template(s, words)
    end
    local function indented(said)
        local out = {}
        for i = 1, #said do
            local line = say(said[i])
            out[i] = "  " .. (line:gsub("snapshot %d+ kept", "snapshot <n> kept"))
        end
        return out
    end

    local makers = {
        ["arrows"] = function() return arrows(c, say) end,
        ["rotation icon"] = function() return rotationIcon(c, addon, say) end,
        ["flight marks"] = function() return flightMarks(c, say) end,
        ["map pins"] = function() return mapPins(c, say) end,
        ["minimap pins"] = function() return minimapPins(c, say) end,
        ["nameplate labels"] = function() return plateLabels(c, say) end,
        ["combo bars"] = function() return comboBars(c, say) end,
        ["slot icons"] = function() return slotIcons(c, say) end,
        ["panels"] = function() return panels(c, say) end,
        ["chat"] = function()
            if opts.chat == false then return { M.NOT_ASKED } end
            local printed = list(c.printed)
            local out = { "lines: " .. #printed }
            for i = 1, #printed do out[#out + 1] = "  " .. say(printed[i]) end
            return out
        end,
        ["diag"] = function()
            if opts.diag == false then return { M.NOT_ASKED } end
            if type(opts.diag) == "table" then return indented(opts.diag) end
            local said = askDiag(c, addon)
            if said == nil then return { M.UNKNOWN } end
            return indented(said)
        end,
    }

    -- N2: made up is shown only when a name read answered or an add-on's
    -- kept snapshots were read (SP-5: an add-on table alone is not enough).
    local shown = names.asked == true or names.snapsRead == true
    local lines, problems = { M.HEAD, namesLine(names, absent, madeUp, shown), "words: " .. whose }, {}
    for _, name in ipairs(M.SECTIONS) do
        lines[#lines + 1] = "== " .. name .. " =="
        local ok, got = pcall(makers[name])
        if heldRaw then
            return nil, "a name was still in a line of " .. name .. " after the replacing: refused"
        end
        if not ok then
            problems[#problems + 1] = name .. ": " .. tostring(got)
            got = { M.FAILED }
        elseif type(got) ~= "table" then
            got = { M.UNKNOWN }
        elseif #got == 0 then
            got = { M.NONE }
        end
        for i = 1, #got do
            local line = M.redact(got[i], names)
            if M.held(line, names, true) then
                return nil, "a name was still in a line of " .. name .. " after the replacing: refused"
            end
            lines[#lines + 1] = line
        end
    end
    -- An error's text names a file, and may name anything else.
    for i = 1, #problems do
        local text = M.redact(M.paths(problems[i]), names)
        if M.held(text, names) then
            return nil, "a name was still in the text of a problem after the replacing: refused"
        end
        problems[i] = text
    end
    return table.concat(lines, "\n"), lines, problems
end

-- ---------------------------------------------------------------- compare
-- M.sections(text) -> { [section] = lines }, order. Lines before the first
-- header are the section "head".
function M.sections(text)
    local by, order, at = {}, {}, "head"
    for line in ((type(text) == "string" and text or "") .. "\n"):gmatch("(.-)\r?\n") do
        local name = line:match("^== (.+) ==$")
        if name then at = name end
        if not by[at] then
            by[at] = {}
            order[#order + 1] = at
        end
        if not name then by[at][#by[at] + 1] = line end
    end
    return by, order
end

local function quoted(line)
    if line == nil then return "(no line)" end
    return '"' .. line .. '"'
end

function M.compare(a, b)
    local byA, orderA = M.sections(a)
    local byB, orderB = M.sections(b)
    local order, listed = {}, {}
    for _, from in ipairs({ orderA, orderB }) do
        for _, name in ipairs(from) do
            if not listed[name] then
                listed[name] = true
                order[#order + 1] = name
            end
        end
    end
    local diffs = {}
    for _, name in ipairs(order) do
        local was, now = byA[name] or {}, byB[name] or {}
        for i = 1, math.max(#was, #now) do
            if was[i] ~= now[i] then
                diffs[#diffs + 1] = { section = name, line = i, was = was[i], now = now[i],
                    text = name .. ", line " .. i .. ": was " .. quoted(was[i]) .. "; now " .. quoted(now[i]) }
            end
        end
    end
    return diffs
end

return M
