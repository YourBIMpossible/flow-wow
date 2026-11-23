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
--                  each a text or a list of texts: names to take out.
--     opts.madeUp  true: the state is made up and holds no character. With
--                  no character name known and this not said, the snapshot
--                  is refused.
--     opts.diag    nil: the diag word is asked (see DIAG). false: not asked.
--                  A list of texts: those lines are used as they are.
--     opts.chat    false: the chat lines are left out ("not asked").
--     text      the lines joined by "\n", no line break at the end.
--     problems  { "section: error" }: a section whose making raised says
--               "failed" in the block; the error text is only here, never
--               in the block (an error names a file path).
--   ns.offline.seenDiff(a, b) -> { { section, line, was, now, text } ... }
--     Two snapshot texts, compared line by line inside each section: line
--     is the number of the line under its section's header, was / now the
--     two lines (nil: that side has no such line), text the one line to
--     post: arrows, line 2: was "..."; now "...". Lines are matched by
--     their place: a line put in or taken out moves every line of that
--     section after it, and each is reported.
--   ns.offline.seenParts: this file's table (HEAD, SECTIONS, UNKNOWN, PLACE,
--     sections(text) -> { [section] = lines }, order; names; redact).
--
-- THE BLOCK. The first line is HEAD. Then every section of SECTIONS, in
-- that order, always: a header "== name ==" and its lines. A section with
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
-- NAMES. Every line under a header is searched, upper and lower case
-- alike, for each known name, the longest first, and the name is replaced
-- by PLACE[kind]: <character>, <realm>, <guild>, <account>, <guid>. Known
-- names: opts.names, and what the fake client answers for the game's own
-- reads (UnitName, UnitFullName, GetRealmName, GetNormalizedRealmName,
-- GetGuildInfo through c.raw; c.realm(); c.guid("player")), and the
-- character and realm the diag snapshots in the account's saved table
-- hold. A name with spaces, hyphens or apostrophes is also searched for
-- without them. Fails closed twice: with no character name from either
-- source and opts.madeUp not true, nothing is returned; and a line that
-- still holds a name after the replacing returns nothing. The limits: a
-- name this file was not told and cannot read is not found (another
-- player's name in a chat line, an alt, an account name the client never
-- says: hand them in); a name that is also a common word is replaced
-- wherever the word is. This is not the capture sanitizer and does not
-- use it.
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
local function addName(names, kind, v)
    if type(v) == "table" then
        for i = 1, #v do addName(names, kind, v[i]) end
        return
    end
    if type(v) ~= "string" or v == "" then return end
    names[#names + 1] = { kind = kind, lower = v:lower() }
    names[kind] = true
    local tight = v:gsub("[%s%-']", "")
    if tight ~= v and tight ~= "" then names[#names + 1] = { kind = kind, lower = tight:lower() } end
end

-- One of the game's own reads, through the fake client's c.raw: the
-- answers, or nothing when the client has no such read or it raised.
local function read(c, fn, ...)
    if type(c.raw) ~= "function" then return nil end
    local got = { pcall(c.raw, fn, ...) }
    if got[1] and got[2] == true then return got[3], got[4] end
    return nil
end

-- M.names(c, addon, given) -> the names to take out, longest first; the
-- list also has [kind] = true for each kind that has a name.
function M.names(c, addon, given)
    local names = {}
    given = list(given)
    for _, kind in ipairs(M.KINDS) do addName(names, kind, given[kind]) end
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
            if ok then addName(names, "guid", guid) end
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
    local rank = {}
    for i, kind in ipairs(M.KINDS) do rank[kind] = i end
    table.sort(names, function(a, b)
        if #a.lower ~= #b.lower then return #a.lower > #b.lower end
        if a.lower ~= b.lower then return a.lower < b.lower end
        return rank[a.kind] < rank[b.kind]
    end)
    return names
end

-- The name that starts at place i of the lowered line, or nil.
local function nameAt(low, i, names)
    for k = 1, #names do
        local name = names[k].lower
        if low:sub(i, i + #name - 1) == name then return names[k] end
    end
    return nil
end

-- M.redact(line, names) -> the line with every name replaced. One pass
-- over the line as it was: a replacement is never searched again.
function M.redact(line, names)
    if #names == 0 then return line end
    local low, out, i = line:lower(), {}, 1
    while i <= #line do
        local hit = nameAt(low, i, names)
        if hit then
            out[#out + 1] = M.PLACE[hit.kind]
            i = i + #hit.lower
        else
            out[#out + 1] = line:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(out)
end

-- True when the line, its placeholders set aside, still holds a name.
local function leaks(line, names)
    local low = line:lower()
    for _, kind in ipairs(M.KINDS) do
        local parts, from = {}, 1
        local place = M.PLACE[kind]
        while true do
            local a, b = low:find(place, from, true)
            if not a then break end
            parts[#parts + 1] = low:sub(from, a - 1)
            from = b + 1
        end
        parts[#parts + 1] = low:sub(from)
        low = table.concat(parts, "\0")
    end
    for i = 1, #low do
        if nameAt(low, i, names) then return true end
    end
    return false
end

-- --------------------------------------------------------------- snapshot
function M.seen(c, addon, opts)
    opts = list(opts)
    if type(c) ~= "table" then return nil, "no fake client was given" end
    local names = M.names(c, addon, opts.names)
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

    local lines, problems = { M.HEAD }, {}
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
            if leaks(line, names) then
                return nil, "a name was still in a line of " .. name .. " after the replacing: refused"
            end
            lines[#lines + 1] = line
        end
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
