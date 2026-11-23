-- Z-Flow offline: the seen-result snapshot (lead DISPATCH section 188, Zen).
-- Lua 5.1. Test tooling: loaded by tools/offline/zflow-run.lua, never by
-- the game; not in ZFlow/manifest.lua and not in the TOC.
--
-- For an add-on loaded on a fake client (ns.offline.addon(c)): ONE text
-- block of what the player sees, the same text for the same state, with no
-- character, realm, guild or account name in it. It is what is posted and
-- compared after a run on a real capture.
--
--   ns.offline.seen(c, addon, opts) -> text, lines, problems
--                                   -> nil, why          (refused, see NAMES)
--     c       the fake client (ZFlow/Core/ClientFake.lua) the add-on is on.
--     addon   what ns.offline.addon(c) returned. nil: only what the client
--             recorded is said; the rotation's reason and the diag lines
--             are "not known".
--     opts.names   { character =, realm =, guild =, account =, guid = },
--                  each a text or a list of texts: names to take out. Any
--                  other key, a list entry (names = { "X" }) or a value
--                  that is not a text or a list of texts: refused.
--     opts.shortNames  true: a name under 3 characters is replaced where
--                  it stands as a whole word. Not said: such a name is
--                  refused (see NAMES).
--     opts.madeUp  true: the state is made up and holds no character. With
--                  no character name known and this not said, the snapshot
--                  is refused.
--     opts.diag    nil: the diag word is asked (see DIAG). false: not asked.
--                  A list of texts: those lines are used as they are.
--     opts.chat    false: the chat lines are left out ("not asked").
--     text      the lines joined by "\n", no line break at the end.
--     problems  { "section: error" }: a section whose making raised says
--               "failed" in the block; the error text is only here, never
--               in the block. Each text has had its absolute paths cut to
--               "<path>/" and the file's name (see PATHS) and its names
--               replaced, and is checked, as a line of the block is.
--   ns.offline.seenDiff(a, b) -> { { section, line, was, now, text } ... }
--     Two snapshot texts, compared line by line inside each section: line
--     is the number of the line under its section's header, was / now the
--     two lines (nil: that side has no such line), text the one line to
--     post: arrows, line 2: was "..."; now "...". Lines are matched by
--     their place: a line put in or taken out moves every line of that
--     section after it, and each is reported.
--   ns.offline.seenParts: this file's table (HEAD, SECTIONS, UNKNOWN, PLACE,
--     sections(text) -> { [section] = lines }, order; names; normal;
--     redact; held; paths).
--
-- THE BLOCK. The first line is HEAD. The second says which kinds of name
-- were known, and so replaced, and which were not, the kinds in the order
-- of KINDS, "none" for an empty side:
--   names: character, realm known; guild, account, guid not known
-- A kind that is not known was not searched for: a reader sees it here.
-- The compare has both lines as the section "head". Then every section of
-- SECTIONS, in that order, always: a header "== name ==" and its lines. A
-- section with
-- nothing in it says "none". Things are numbered in the order the client
-- made them (the add-on makes them in file order). A thing that is hidden
-- says "hidden" and nothing else: a hidden arrow keeps the lines it last
-- drew, and those are not what the player sees.
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
--                           pins sorted as text, then lines sorted as text.
--   == minimap pins ==      pin <i> (<frame name>): shown at <x>, <y>, edge | inside   or hidden
--   == nameplate labels ==  label <i> (<unit>): shown | hidden
--                             text: <text> | hidden by the game
--   == combo bars ==        bar <i>: shown on <unit>, <filled> of <sections>   or hidden
--   == slot icons ==        icon <i> (<frame name>): shown | hidden
--                             texture: <texture>
--   == panels ==            panel <i> (<frame name>): shown | hidden
--                             line <n>: <text>
--   == chat ==                <every line the add-on printed, in order>
--   == diag ==                <every line the diag word prints, in order>
--
-- A share of a map is said to 3 decimals, a minimap offset to 1, a whole
-- number as it is. What is nil, empty or not a text or number is said as
-- "not known", never left out. Nothing is read with pairs() into the
-- block. Not in the block: where an arrow points (its drawing changes
-- with every frame), tooltips and menus, the copy box, window buttons.
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
-- NAMES. Known names: opts.names, and what the fake client answers for
-- the game's own reads (UnitName, UnitFullName, GetRealmName,
-- GetNormalizedRealmName, GetGuildInfo through c.raw; c.realm();
-- c.guid("player")), and the character and realm the diag snapshots in the
-- account's saved table hold. Of a GUID ("Player-1234-ABCDEF") the parts
-- after the first are names too, each alone and joined to the end
-- ("1234-ABCDEF", "1234", "ABCDEF"), when they have 4 letters or digits or
-- more; the first part says what kind of thing it is, not who.
--
-- A line and a name are compared in their normal form: lower case, every
-- character that is not a letter or a digit taken out, a byte of 128 or
-- more kept as it is. So a name is found in upper or lower case and with
-- anything or nothing between its letters that is not a letter or digit:
-- "Quell Made" is found in "Quell-Made", "Quell_Made", "quell.made" and
-- "QuellMade". From the first to the last character of what was found, the
-- line is replaced by PLACE[kind]: <character>, <realm>, <guild>,
-- <account>, <guid>. Names that overlap in a line are replaced as one,
-- with the kind of the one that starts first (the longest of those).
--
-- A name of under 3 letters or digits cannot be told from ordinary text:
-- it is refused, unless opts.shortNames is true; then it is replaced only
-- as it was written (upper and lower case alike) where no letter, digit or
-- byte of 128 or more is next to it. A name with no letter or digit at all
-- is always refused.
--
-- Fails closed, each time with nothing returned but nil and the reason:
--   * opts.names is not as said above;
--   * a name is too short (above);
--   * no character name is known from either source and opts.madeUp is
--     not true. Realm, guild, account and GUID may be not known (a
--     character with no guild is usual): the second line says so;
--   * after the replacing, a line or a problem still holds a name. This
--     second check (held) does not use the replacing's search: it takes
--     the placeholders and "<path>/" out, makes the normal form of each
--     piece between them and of each name its own way, and looks for the
--     name (3 or more) in the piece.
--
-- The limits. string.lower knows only A to Z in Lua 5.1: a non-ASCII
-- letter is compared byte for byte. A name with such a letter is found
-- when those bytes are the same and its ASCII letters are in any case;
-- it is NOT found, by the replacing or by the second check, when the
-- non-ASCII letter itself is in the other case (bytes 195 137 for bytes
-- 195 169), is written another way (a letter and a combining accent, or
-- the plain ASCII letter), or is a look-alike. Not found either: a name
-- this file was not told and cannot read (another player's name in a chat
-- line, an alt, an account name the client never says: hand them in); a
-- name cut short, misspelt, or with a letter or digit put between its
-- letters; a short name with a letter or digit next to it (shortNames),
-- which the second check does not look for either. Replaced too much: a
-- name that is also a word, or whose letters come up across two words
-- ("Tom" in "to Moonglade"), is replaced wherever that is. This is not the
-- capture sanitizer and does not use it.
--
-- PATHS. In a problem's text a path is cut to "<path>/" and what follows
-- its last slash or backslash: it starts at a drive letter and a colon, at
-- a slash that begins a word, or at the "..." Lua puts where it cut a long
-- file name short, and runs to the next of : " ' < > | * ? or the line's
-- end. A path with no folder in front (ZFlow/Core/Diag.lua) is left as it
-- is.
local M = {}

M.HEAD = "zflow seen 1"
M.UNKNOWN = "not known"
M.NONE = "none"
M.NOT_ASKED = "not asked"
M.FAILED = "failed"
M.SECTIONS = { "arrows", "rotation icon", "flight marks", "map pins", "minimap pins",
    "nameplate labels", "combo bars", "slot icons", "panels", "chat", "diag" }
M.KINDS = { "character", "realm", "guild", "account", "guid" }
M.PLACE = { character = "<character>", realm = "<realm>", guild = "<guild>",
    account = "<account>", guid = "<guid>" }
M.PATH = "<path>/"
M.SHORT = 3
M.GUID_PART = 4

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

local function frameName(h)
    return word(type(h.spec) == "table" and h.spec.name or nil)
end

-- ------------------------------------------------------------- the sections
local function arrows(c)
    local out = {}
    for i, h in ipairs(list(c.arrows)) do
        local head = "arrow " .. i .. " (" .. frameName(h) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            local lines = list(h.lines)
            if #lines == 0 then out[#out + 1] = "  no lines" end
            for n = 1, #lines do out[#out + 1] = "  line " .. n .. ": " .. word(lines[n]) end
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

local function rotationIcon(c, addon)
    local out, made = {}, false
    for _, h in ipairs(list(c.icons)) do
        local name = type(h.spec) == "table" and h.spec.name or nil
        if type(name) == "string" and name:find("RotationIcon", 1, true) then
            made = true
            if h.shown == true then
                out[#out + 1] = "icon (" .. word(name) .. "): shown"
                out[#out + 1] = "  texture: " .. word(h.texture)
                out[#out + 1] = "  mark: " .. (h.marked == nil and M.NONE or word(h.marked))
            else
                out[#out + 1] = "icon (" .. word(name) .. "): hidden"
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
        for i = 1, #why do out[#out + 1] = "  reason: " .. word(why[i]) end
    end
    return out
end

local function flightMarks(c)
    local out = {}
    for i, h in ipairs(list(c.taxiMarks)) do
        if h.shown == true then
            local node = list(h.node)
            out[#out + 1] = "mark " .. i .. ": shown"
            out[#out + 1] = "  node: " .. word(node.name) .. " at " .. share(node.x) .. ", " .. share(node.y)
            out[#out + 1] = "  label: " .. word(h.label)
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

local function mapPins(c)
    local out = {}
    for i, h in ipairs(list(c.mapPinSets)) do
        if h.shown == true then
            out[#out + 1] = "pins " .. i .. ": shown"
            sortedInto(out, h.pins, function(p)
                return "  pin: " .. word(p.name) .. ", " .. word(p.kind) .. ", " .. word(p.role)
                    .. ", at " .. share(p.x) .. ", " .. share(p.y)
            end)
            sortedInto(out, h.lines, function(l)
                return "  line: " .. word(l.from) .. " to " .. word(l.to) .. ", " .. share(l.ax) .. ", "
                    .. share(l.ay) .. " to " .. share(l.bx) .. ", " .. share(l.by)
            end)
        else
            out[#out + 1] = "pins " .. i .. ": hidden"
        end
    end
    return out
end

local function minimapPins(c)
    local out = {}
    for i, h in ipairs(list(c.minimapPins)) do
        local head = "pin " .. i .. " (" .. frameName(h) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown at " .. offset(h.x) .. ", " .. offset(h.y) .. ", "
                .. (h.edge == true and "edge" or "inside")
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function plateLabels(c)
    local out = {}
    for i, h in ipairs(list(c.plateLabels)) do
        local head = "label " .. i .. " (" .. word(h.unit) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            -- A value the game hides is kept as it came: it has no text.
            local says = h.says
            if says ~= nil and type(says) ~= "string" and type(says) ~= "number" then
                out[#out + 1] = "  text: hidden by the game"
            else
                out[#out + 1] = "  text: " .. word(says)
            end
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function comboBars(c)
    local out = {}
    for i, h in ipairs(list(c.comboBars)) do
        if h.shown == true then
            out[#out + 1] = "bar " .. i .. ": shown on " .. word(h.hung) .. ", " .. word(h.value)
                .. " of " .. word(h.max)
        else
            out[#out + 1] = "bar " .. i .. ": hidden"
        end
    end
    return out
end

local function slotIcons(c)
    local out = {}
    for i, h in ipairs(list(c.slotIcons)) do
        local head = "icon " .. i .. " (" .. frameName(h) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            out[#out + 1] = "  texture: " .. word(h.texture)
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function panels(c)
    local out = {}
    for i, h in ipairs(list(c.panels)) do
        local head = "panel " .. i .. " (" .. frameName(h) .. "): "
        if h.shown == true then
            out[#out + 1] = head .. "shown"
            local lines = list(h.lines)
            if #lines == 0 then out[#out + 1] = "  no lines" end
            for n = 1, #lines do out[#out + 1] = "  line " .. n .. ": " .. word(lines[n]) end
        else
            out[#out + 1] = head .. "hidden"
        end
    end
    return out
end

local function indented(lines)
    local out = {}
    for i = 1, #lines do out[i] = "  " .. word(lines[i]) end
    return out
end

-- ------------------------------------------------------------------- diag
-- What the diag word's snapshot will change in the account's saved table,
-- as it is now.
local function keepDiag(c, id)
    if type(c.savedExists) ~= "function" or type(c.saved) ~= "function" then return nil end
    if not c.savedExists(id.accountDB) then return { absent = true } end
    local db = c.saved(id.accountDB)
    local kept = { db = db, diag = db.diag }
    local d = db.diag
    if type(d) == "table" then
        kept.count, kept.names, kept.snaps = d.count, d.names, d.snaps
        if type(d.snaps) == "table" then
            kept.rows = {}
            for i = 1, #d.snaps do kept.rows[i] = d.snaps[i] end
        end
    end
    return kept
end

local function putBackDiag(c, id, kept)
    if kept == nil then return end
    if kept.absent then
        if type(c.setSaved) == "function" then c.setSaved(id.accountDB, nil) end
        return
    end
    kept.db.diag = kept.diag
    local d = kept.diag
    if type(d) ~= "table" then return end
    d.count, d.names, d.snaps = kept.count, kept.names, kept.snaps
    if kept.rows then
        local snaps = kept.snaps
        for i = #snaps, 1, -1 do snaps[i] = nil end
        for i = 1, #kept.rows do snaps[i] = kept.rows[i] end
    end
end

-- Types the diag word and gives its lines; nil when it cannot be asked.
-- See DIAG in the header for what is put back.
local function askDiag(c, addon)
    local id = type(addon) == "table" and addon.id or nil
    if type(id) ~= "table" or type(c.slashes) ~= "table" then return nil end
    local slash = c.slashes[id.slash]
    if type(slash) ~= "function" then return nil end
    local printed = type(c.printed) == "table" and c.printed or nil
    local before = printed and #printed or 0
    local kept = keepDiag(c, id)
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
    putBackDiag(c, id, kept)
    if not ok then error(err, 0) end
    for i = 1, #said do
        said[i] = said[i]:gsub("snapshot %d+ kept", "snapshot <n> kept")
    end
    return said
end

-- ------------------------------------------------------------------ names
-- M.normal(text) -> the text in lower case with every character that is
-- not a letter or a digit taken out (a byte of 128 or more is kept as it
-- is), and for each place of it the place in the text it came from.
function M.normal(text)
    local out, map = {}, {}
    for i = 1, #text do
        local b = text:byte(i)
        if b >= 65 and b <= 90 then b = b + 32 end
        if (b >= 48 and b <= 57) or (b >= 97 and b <= 122) or b >= 128 then
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

local function addName(names, kind, v)
    if type(v) ~= "string" or v == "" then return end
    local norm = M.normal(v)
    names[#names + 1] = { kind = kind, text = v, lower = v:lower(), norm = norm, short = #norm < M.SHORT }
    names[kind] = true
end

-- A GUID, and its parts after the first (see NAMES).
local function addGuid(names, kind, v)
    if type(v) ~= "string" or v == "" then return end
    addName(names, kind, v)
    local parts = {}
    for part in v:gmatch("[^%-]+") do parts[#parts + 1] = part end
    for i = 2, #parts do
        local alone, tail = parts[i], table.concat(parts, "-", i)
        if #(M.normal(alone)) >= M.GUID_PART then addName(names, kind, alone) end
        if tail ~= alone and #(M.normal(tail)) >= M.GUID_PART then addName(names, kind, tail) end
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

-- One of the game's own reads, through the fake client's c.raw: the
-- answers, or nothing when the client has no such read or it raised.
local function read(c, fn, ...)
    if type(c.raw) ~= "function" then return nil end
    local got = { pcall(c.raw, fn, ...) }
    if got[1] and got[2] == true then return got[3], got[4] end
    return nil
end

-- M.names(c, addon, given, shortNames) -> the names to take out, longest
-- first; the list also has [kind] = true for each kind that has a name.
-- Or nil and the reason: given is not as the header says, or a name is
-- too short (shortNames true lets a name of 1 or 2 through).
function M.names(c, addon, given, shortNames)
    local names = {}
    local bad = addGiven(names, given)
    if bad then return nil, bad end
    if type(c) == "table" then
        local name, realm = read(c, "UnitName", "player")
        addName(names, "character", name); addName(names, "realm", realm)
        name, realm = read(c, "UnitFullName", "player")
        addName(names, "character", name); addName(names, "realm", realm)
        addName(names, "realm", (read(c, "GetRealmName")))
        addName(names, "realm", (read(c, "GetNormalizedRealmName")))
        addName(names, "guild", (read(c, "GetGuildInfo", "player")))
        if type(c.realm) == "function" then
            local ok, own = pcall(c.realm)
            if ok then addName(names, "realm", own) end
        end
        if type(c.guid) == "function" then
            local ok, guid = pcall(c.guid, "player")
            if ok then addGuid(names, "guid", guid) end
        end
        -- What the diag snapshots kept of the session (Core/Diag.lua).
        local id = type(addon) == "table" and addon.id or nil
        if type(id) == "table" and type(c.savedExists) == "function" and c.savedExists(id.accountDB) then
            local diag = c.saved(id.accountDB).diag
            local snaps = type(diag) == "table" and list(diag.snaps) or {}
            for i = 1, #snaps do
                local timing = type(snaps[i]) == "table" and snaps[i].timing or nil
                if type(timing) == "table" then
                    addName(names, "character", timing.character)
                    addName(names, "realm", timing.realm)
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

-- The second line of the block: the kinds known and not known.
local function namesLine(names)
    local known, missing = {}, {}
    for _, kind in ipairs(M.KINDS) do
        local into = names[kind] and known or missing
        into[#into + 1] = kind
    end
    return "names: " .. (#known > 0 and table.concat(known, ", ") or M.NONE) .. " known; "
        .. (#missing > 0 and table.concat(missing, ", ") or M.NONE) .. " not known"
end

-- Where the names are in the line: { s, e, kind } by place in the line as
-- it is, in order, no two overlapping (those that did are one).
local function spans(line, names)
    local norm, map = M.normal(line)
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
            else
                a, b = norm:find(name.norm, from, true)
                if not a then break end
                found[#found + 1] = { s = map[a], e = map[b], kind = name.kind, at = #found + 1 }
            end
            from = a + 1
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

-- M.redact(line, names) -> the line with every name replaced. Every place
-- of every name is found in the line as it was, the places that overlap
-- are made one, and each is replaced once: a replacement is never searched.
function M.redact(line, names)
    if #names == 0 then return line end
    local out, from = {}, 1
    for _, span in ipairs(spans(line, names)) do
        out[#out + 1] = line:sub(from, span.s - 1)
        out[#out + 1] = M.PLACE[span.kind]
        from = span.e + 1
    end
    out[#out + 1] = line:sub(from)
    return table.concat(out)
end

-- The line cut at every placeholder: the pieces between them.
local function pieces(line)
    local rest = { line }
    local places = { M.PATH }
    for _, kind in ipairs(M.KINDS) do places[#places + 1] = M.PLACE[kind] end
    for _, place in ipairs(places) do
        local cut = {}
        for _, piece in ipairs(rest) do
            local from = 1
            while true do
                local a, b = piece:find(place, from, true)
                if not a then break end
                cut[#cut + 1] = piece:sub(from, a - 1)
                from = b + 1
            end
            cut[#cut + 1] = piece:sub(from)
        end
        rest = cut
    end
    return rest
end

-- The second check's own normal form (not M.normal: see NAMES).
local function flat(text)
    local s = text:lower():gsub("[^%w\128-\255]", "")
    return s
end

-- M.held(line, names) -> true when the line, its placeholders set aside,
-- still holds a name of 3 or more. Does not use redact's search.
function M.held(line, names)
    local wanted = {}
    for k = 1, #names do
        local name = flat(names[k].text)
        if #name >= M.SHORT then wanted[#wanted + 1] = name end
    end
    for _, piece in ipairs(pieces(line)) do
        local text = flat(piece)
        for k = 1, #wanted do
            if text:find(wanted[k], 1, true) then return true end
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

-- M.paths(text) -> the text with every absolute path cut to "<path>/" and
-- what follows its last separator.
function M.paths(text)
    local out, from, i, n = {}, 1, 1, #text
    while i <= n do
        local body, cut = pathBody(text, i), nil
        if body then
            local stop = text:find("[:\"'<>|%*%?\r\n\t]", body) or (n + 1)
            local last = text:sub(body, stop - 1):match(".*()[\\/]")
            if last then cut = body + last - 1 end
        end
        if cut then
            out[#out + 1] = text:sub(from, i - 1)
            out[#out + 1] = M.PATH
            from, i = cut + 1, cut + 1
        else
            i = i + 1
        end
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
end

-- --------------------------------------------------------------- snapshot
function M.seen(c, addon, opts)
    opts = list(opts)
    if type(c) ~= "table" then return nil, "no fake client was given" end
    local names, bad = M.names(c, addon, opts.names, opts.shortNames == true)
    if not names then return nil, bad end
    if not names.character and opts.madeUp ~= true then
        return nil, "no character name is known (none in opts.names, none from the client's reads): "
            .. "refused, because the names cannot be taken out. For made-up state say opts.madeUp = true."
    end

    local makers = {
        ["arrows"] = function() return arrows(c) end,
        ["rotation icon"] = function() return rotationIcon(c, addon) end,
        ["flight marks"] = function() return flightMarks(c) end,
        ["map pins"] = function() return mapPins(c) end,
        ["minimap pins"] = function() return minimapPins(c) end,
        ["nameplate labels"] = function() return plateLabels(c) end,
        ["combo bars"] = function() return comboBars(c) end,
        ["slot icons"] = function() return slotIcons(c) end,
        ["panels"] = function() return panels(c) end,
        ["chat"] = function()
            if opts.chat == false then return { M.NOT_ASKED } end
            return indented(list(c.printed))
        end,
        ["diag"] = function()
            if opts.diag == false then return { M.NOT_ASKED } end
            if type(opts.diag) == "table" then return indented(opts.diag) end
            local said = askDiag(c, addon)
            if said == nil then return { M.UNKNOWN } end
            return indented(said)
        end,
    }

    local lines, problems = { M.HEAD, namesLine(names) }, {}
    for _, name in ipairs(M.SECTIONS) do
        lines[#lines + 1] = "== " .. name .. " =="
        local ok, got = pcall(makers[name])
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
            if M.held(line, names) then
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
