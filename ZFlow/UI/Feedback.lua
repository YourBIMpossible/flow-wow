local _, ns = ...

-- Feedback (row N73, lead section 247): the player writes a problem, a
-- suggestion or an idea in the game, and the add-on prepares one piece of
-- text for the player to copy. Preparation and export only: nothing here
-- uploads, calls a network or starts another program, and no report is
-- kept. What becomes of the text is the player's to do.
--
-- It opens from the arrow menu's Feedback row, from the settings (the row
-- below is found by feedback, bug, report, problem, idea or suggest, and
-- has a button that opens the window) and from <slash> feedback.
--
-- The window is the client's row panel (plain buttons), the typing is the
-- client's text entry, and the text to copy stands in the client's copy
-- box, as <slash> copy's does. Nothing is made and nothing is read until
-- the window is opened; nothing polls. What the player wrote is kept in
-- memory only while the game runs: a reload keeps the one setting.
--
-- The report (Feedback.Build) is the description, for a problem what
-- happened and what was expected, and, only when "Attach relevant
-- diagnostics" is on (off by default), a short block the add-on puts
-- together itself. With the setting off the report has no diagnostics line
-- at all.
--
-- PRIVACY (lead section 251, from Plexy's walk of Core/Diag.lua): nothing
-- in Diag is masked in the game, so the block is an ALLOWLIST. It is put
-- together field by field from these and nothing else:
--   the add-on's version and the game build
--   of a Diag snapshot taken now and not saved: at, whether there is a
--     clock; the names table as two counts (types only); `known`, for the
--     reads named in Feedback.KNOWN; of `reads`, the counts and yes/no
--     answers named in Feedback.READS; of the kernel, phase (one of
--     Feedback.PHASES), paused, storeOpened, how many events were not
--     registered or expected absent, and the two frame flags
--   of the saved diag: starts, count and how many read records are kept
--   the add-on's own problems (the kernel's list in that snapshot), newest
--     first, MAX_ERRORS at most, each one line through Feedback.Clean
-- Every value above is printed as a number, as yes or no, or as one of a
-- fixed set of words; a field that is not named here is never read, so a
-- field added to the snapshot later cannot reach a report.
-- NEVER read: the snapshot's shapes (realm, realmNormalized, fullName, item
-- and merchant links among them), timing.character and timing.realm,
-- timing.errors (any add-on's Lua errors: not the add-on's own to share),
-- the kernel's pauseText and blocked reasons, reads.money, position, zone,
-- bags and recipes, the saved diag.api, chat, and saved data.
--
-- Feedback.Clean is the in-game cleaner every problem line goes through:
--   colour codes and textures are taken off; a link, and a bare item,
--     spell, enchant or quest string, becomes Feedback.LINK
--   paths: from the first to the last word holding a slash is one path;
--     of it only the part from "<add-on folder>/" on is kept (the file and
--     line in the add-on), and any other path becomes Feedback.PATH whole
--   text in double or single quotes becomes Feedback.QUOTED
--   the player's own character, realm and guild names, read at that
--     moment through the client's guarded call, become Feedback.HIDDEN
--   the line is cut at MAX_ERROR_CHARS
-- A line the cleaner raises on is left out, and one line says an error
-- could not be included. While the character's name cannot be read, the
-- problems are only counted.
-- What the player typed is theirs: only their own names are replaced, and
-- a file path (a word with a backslash or a drive letter) is cut the same
-- way; no other word is altered.
--
-- A diagnostics read that raises, or a snapshot that comes back empty,
-- leaves the written feedback whole with one line saying so.
--
-- Combat: the window is the add-on's own plain frame, so it opens in a
-- fight too. A combat lock that is on, or that the client will not tell
-- (which counts as on, as for the settings page), only adds one line
-- saying so; nothing of the game's is opened or changed either way.
--
--   Feedback.Build(form, diag, names, title, addon) -> text   pure
--     form   { kind, description, happened, expected }
--     diag   nil (not attached), false (could not be collected), or what
--            Feedback.Collect answers
--   Feedback.Clean(text, names, addon) -> one cleaned line
--   Feedback.CleanTyped(text, names, addon) -> the player's words, names
--                                              and file paths taken out
--   Feedback.Mask(text, names) -> text, how many names were replaced
--   Feedback.Collect(k, names, known) -> the allowlisted values, or false
--   Feedback.Names(k) -> names, known (true when the character's is)
--   Feedback.Declare(k, diag) -> api
--     api.open() -> true when the window is on the screen
--     api.report() -> the text as it would be copied now, or nil and why
--     api.form() -> a copy of what was written
-- Fake client only; not tested in game.
local F = {}
ns.Feedback = F

F.NAME = "feedback"
F.WORD = "feedback"
F.SETTING = "feedback.diagnostics"
F.HELP = "write a problem, a suggestion or an idea, and get a report to copy"

-- Where a report goes. Not decided yet: while this is empty the window says
-- so and shows no address. The one place it is written.
F.DESTINATION = ""

-- The caps. Bytes of one typed field; bytes of one diagnostics line; how
-- many of the add-on's own problems are listed and the bytes of each after
-- cleaning; lines of the diagnostics block; bytes of the whole report.
F.MAX_FIELD = 600
F.MAX_LINE = 240
F.MAX_ERRORS = 5
F.MAX_ERROR_CHARS = 160
F.MAX_DIAG_LINES = 18
F.MAX_BYTES = 3000

-- The allowlist's fixed names (see PRIVACY above). KNOWN: the reads whose
-- known flag is printed. READS: the counts and yes/no answers of the
-- snapshot's reads, each with the words it is printed under. PHASES: the
-- kernel's phases; any other is printed as "other".
F.KNOWN = { "money", "combatLockdown", "bags", "bagStacks", "bankOpen", "bankStacks", "position", "zone" }
F.READS = {
    { "inCombat", "in combat" }, { "combatLockdown", "combat lock" }, { "bagStacks", "bag stacks" },
    { "bankOpen", "bank open" }, { "bankStacks", "bank stacks" }, { "predecessorLoaded", "old add-on loaded" },
    { "predecessorData", "old add-on data" }, { "selfLoaded", "add-on loaded" },
}
F.PHASES = { "declare", "wire", "running", "paused" }

F.KINDS = {
    { key = "problem", pick = "Report a problem", head = "Problem report" },
    { key = "suggest", pick = "Suggest an improvement", head = "Suggested improvement" },
    { key = "idea", pick = "Share an idea", head = "Idea" },
}
F.FIELDS = {
    { key = "description", label = "Description", write = "Write the description",
      ask = "Describe it in a sentence or two, then press Enter." },
    { key = "happened", label = "What happened", write = "Write what happened (optional)",
      ask = "What happened? Press Enter when done.", problem = true },
    { key = "expected", label = "What was expected", write = "Write what you expected (optional)",
      ask = "What did you expect instead? Press Enter when done.", problem = true },
}

F.INTRO = "Write here; you get a report to copy. Nothing leaves the game by itself."
F.LOCK_NOTE = "You may be in combat: this window is the add-on's own and changes nothing in the game."
F.NOT_WRITTEN = "(not written yet)"
F.ATTACH = "Attach relevant diagnostics: "
F.PREVIEW = "Preview report"
F.COPY = "Copy report"
F.AGAIN = "Start again"
F.NO_DESTINATION = "Where to share a report is not set up yet. Keep the copied text until it is."
F.SHARE_AT = "Where to share it: use the button below, then copy the address."
F.COPY_DESTINATION = "Copy the address"
F.NEED_KIND = "choose what kind of feedback it is first"
F.NEED_TEXT = "write the description first"
F.NO_WINDOW = "this client cannot draw the feedback window."
F.NO_ENTRY = "this client cannot draw a box to type in."
F.NO_BOX = "this client cannot draw the copy box, so the report is printed here instead."
F.NOT_READY = "feedback is not ready until login."
F.PREVIEW_TITLE = ": preview - exactly the text you would share"
F.COPY_TITLE = ": select, then copy"
F.DIAG_HEAD = "Diagnostics"
F.NO_DIAG = "Diagnostics could not be collected."
F.CUT = "(cut short at the size limit)"
F.HIDDEN = "(name)"
F.LINK = "(link)"
F.PATH = "(path)"
F.QUOTED = "(text)"
F.ERROR_DROPPED = "An error could not be included."
F.TEXTS_OUT = "Their texts are left out: your character's name could not be read to take it out."
F.ROW_LABEL = "Attach relevant diagnostics to feedback"
F.ROW_OPEN = "Write feedback"
F.WIDTH = 380
F.DEFAULT_POINT = { "CENTER", "CENTER", 0, 60 }

local function trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- At most n bytes of text, never ending inside a letter of several bytes.
local function clip(text, n)
    if #text <= n then return text end
    local cut = n
    while cut > 0 do
        local b = text:byte(cut + 1)
        if b == nil or b < 128 or b > 191 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end
F.Clip = clip

-- What the player typed, as one plain line of at most MAX_FIELD bytes.
function F.Field(text)
    if type(text) ~= "string" then return "" end
    local plain = text
    if ns.CopyBox and type(ns.CopyBox.Plain) == "function" then plain = ns.CopyBox.Plain(text) end
    plain = plain:gsub("%c", " ")
    return clip(trim(plain), F.MAX_FIELD)
end

-- Every place one of the names stands, whatever its capitals, becomes
-- F.HIDDEN. Answers the text and how many were replaced. (The name rule of
-- the capture mask, Core/Capture.lua maskNames, which does not ship.)
function F.Mask(text, names)
    text = tostring(text)
    local n = 0
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if type(name) == "string" and #name >= 2 then
            local low, from, out = name:lower(), 1, {}
            local lower = text:lower()
            while true do
                local a, b = lower:find(low, from, true)
                if not a then break end
                out[#out + 1] = text:sub(from, a - 1)
                out[#out + 1] = F.HIDDEN
                n = n + 1
                from = b + 1
            end
            out[#out + 1] = text:sub(from)
            text = table.concat(out)
        end
    end
    return text, n
end

-- Whether a word is (part of) a file path. In a line the add-on wrote, any
-- word with a slash is; in the player's own words only one with a
-- backslash, or one that starts with a drive letter.
local function pathWord(word, typed)
    if typed then
        if word:find("\\", 1, true) then return true end
        return word:find("^%a:[\\/]") ~= nil
    end
    return word:find("[\\/]") ~= nil
end

-- From the first to the last path word is one path (a folder name may hold
-- blanks). Of it only the part from "<addon>/" on is kept, when the last
-- word has one; any other path becomes F.PATH whole.
function F.CutPaths(text, addon, typed)
    text = tostring(text)
    local words, first, last = {}, nil, nil
    for gap, word in text:gmatch("(%s*)(%S+)") do
        words[#words + 1] = { gap = gap, word = word }
        if pathWord(word, typed) then
            if not first then first = #words end
            last = #words
        end
    end
    if not first then return text end
    local keep = F.PATH
    local tail, lead = words[last].word, tostring(addon or "")
    if lead ~= "" then
        local at, from = nil, 1
        while true do
            local a = tail:find(lead, from, true)
            if not a then break end
            local after = tail:sub(a + #lead, a + #lead)
            if after == "/" or after == "\\" then at = a end
            from = a + 1
        end
        if at then keep = tail:sub(at) end
    end
    local out = {}
    for i = 1, first - 1 do out[#out + 1] = words[i].gap .. words[i].word end
    out[#out + 1] = words[first].gap .. keep
    for i = last + 1, #words do out[#out + 1] = words[i].gap .. words[i].word end
    return table.concat(out)
end

local LINK_KINDS = { "item", "spell", "enchant", "quest", "talent", "achievement", "trade", "player" }

-- One line of the add-on's own, cleaned for sharing (see the header).
function F.Clean(text, names, addon)
    local s = tostring(text):gsub("%c", " ")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h.-|h", F.LINK)
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    for i = 1, #LINK_KINDS do
        s = s:gsub(LINK_KINDS[i] .. ":[%-%w:]+", F.LINK)
    end
    s = F.CutPaths(s, addon, false)
    s = s:gsub('"[^"]*"', F.QUOTED):gsub("'[^']*'", F.QUOTED)
    s = F.Mask(s, names)
    return clip(trim(s), F.MAX_ERROR_CHARS)
end

-- What the player typed: their own names and a file path taken out, no
-- other word altered.
function F.CleanTyped(text, names, addon)
    local s = F.CutPaths(tostring(text), addon, true)
    s = F.Mask(s, names)
    return s
end

local function kindOf(key)
    for _, kind in ipairs(F.KINDS) do
        if kind.key == key then return kind end
    end
    return nil
end

local function yes(v)
    if v == true then return "yes" end
    return "no"
end

-- A whole number as text; anything that is not a number is "unknown".
local function numText(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return "unknown" end
    return tostring(math.floor(v))
end

local function inList(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- The lines of the diagnostics block, MAX_DIAG_LINES at most. Only numbers,
-- yes or no, the fixed words and the cleaned problem lines are printed.
local function diagLines(diag)
    if diag == false then return { F.NO_DIAG } end
    local lines = { F.DIAG_HEAD }
    local version, build = "unknown", "unknown"
    if type(diag.version) == "string" and diag.version ~= "" then version = diag.version end
    if type(diag.build) == "string" and diag.build ~= "" then build = diag.build end
    lines[#lines + 1] = "Version: " .. version .. "; game build: " .. build
    lines[#lines + 1] = "Snapshot: seconds since start " .. numText(diag.at) .. "; wall clock: " .. yes(diag.clock)
    lines[#lines + 1] = "Client names asked: " .. numText(diag.namesAsked) .. "; missing: " .. numText(diag.namesMissing)
    local known = {}
    for _, row in ipairs(type(diag.known) == "table" and diag.known or {}) do
        if type(row) == "table" and inList(F.KNOWN, row[1]) then known[#known + 1] = row[1] .. " " .. yes(row[2]) end
    end
    if #known > 0 then lines[#lines + 1] = "Reads known: " .. table.concat(known, ", ") end
    local labels, reads = {}, {}
    for i = 1, #F.READS do labels[i] = F.READS[i][2] end
    for _, row in ipairs(type(diag.reads) == "table" and diag.reads or {}) do
        if type(row) == "table" and inList(labels, row[1]) then
            if type(row[2]) == "boolean" then
                reads[#reads + 1] = row[1] .. " " .. yes(row[2])
            elseif type(row[2]) == "number" then
                reads[#reads + 1] = row[1] .. " " .. numText(row[2])
            end
        end
    end
    if #reads > 0 then lines[#lines + 1] = "Reads: " .. table.concat(reads, "; ") end
    local phase = "other"
    if inList(F.PHASES, diag.phase) then phase = diag.phase end
    lines[#lines + 1] = "State: " .. phase .. "; paused: " .. yes(diag.paused)
        .. "; saved data loaded: " .. yes(diag.loaded)
    lines[#lines + 1] = "Events not registered: " .. numText(diag.eventsNot) .. "; expected absent: "
        .. numText(diag.eventsAbsent) .. "; event frame missing: " .. yes(diag.noEventFrame)
        .. "; tick frame missing: " .. yes(diag.noTickFrame)
    lines[#lines + 1] = "Snapshots: starts " .. numText(diag.starts) .. "; kept " .. numText(diag.count)
        .. "; read records " .. numText(diag.readRecords)
    lines[#lines + 1] = "The add-on's own problems, newest first: " .. numText(diag.problemCount)
    local problems = {}
    if type(diag.problems) == "table" then problems = diag.problems end
    for i = 1, math.min(#problems, F.MAX_ERRORS) do
        if type(problems[i]) == "string" then lines[#lines + 1] = "  " .. problems[i] end
    end
    if diag.dropped == true then lines[#lines + 1] = F.ERROR_DROPPED end
    if diag.texts == false then lines[#lines + 1] = F.TEXTS_OUT end
    while #lines > F.MAX_DIAG_LINES do lines[#lines] = nil end
    for i = 1, #lines do
        lines[i] = clip((lines[i]:gsub("%c", " ")), F.MAX_LINE)
    end
    return lines
end

function F.Build(form, diag, names, title, addon)
    form = type(form) == "table" and form or {}
    local kind = kindOf(form.kind)
    local head = "?"
    if kind then head = kind.head end
    local lines = { tostring(title or "") .. " feedback: " .. head }
    for _, field in ipairs(F.FIELDS) do
        local text = F.CleanTyped(F.Field(form[field.key]), names, addon)
        local wanted = not field.problem
        if kind and kind.key == "problem" then wanted = true end
        if text ~= "" and wanted then lines[#lines + 1] = field.label .. ": " .. text end
    end
    if diag ~= nil then
        for _, line in ipairs(diagLines(diag)) do lines[#lines + 1] = line end
    end
    local text = table.concat(lines, "\n")
    if #text > F.MAX_BYTES then
        text = clip(text, F.MAX_BYTES - #F.CUT - 1) .. "\n" .. F.CUT
    end
    return text
end

-- A name the client gave: text of two letters or more that it does not hide.
local function nameOf(client, v)
    if type(v) ~= "string" or #v < 2 then return nil end
    if ns.Diag and ns.Diag.IsSecret(client, v) then return nil end
    return v
end

-- The player's own names: the character's, the realm's (both spellings)
-- and the guild's, read at this moment through the client's guarded call
-- and from nowhere else. known is true when the character's own was read.
function F.Names(k)
    local client = k.client
    local out, seen, known = {}, {}, false
    local function add(v)
        local name = nameOf(client, v)
        if name and not seen[name:lower()] then
            seen[name:lower()] = true
            out[#out + 1] = name
        end
        return name ~= nil
    end
    -- The first two answers of a client name, or nothing when it is not
    -- there or raised.
    local function ask(name, arg)
        local ok, good, first, second = pcall(client.raw, name, arg)
        if not ok or good ~= true then return nil, nil end
        return first, second
    end
    local who = ask("UnitName", "player")
    if add(who) then known = true end
    add((ask("GetRealmName")))
    add((ask("GetNormalizedRealmName")))
    local full, realm = ask("UnitFullName", "player")
    if add(full) then known = true end
    add(realm)
    add((ask("GetGuildInfo", "player")))
    table.sort(out, function(a, b)
        if #a ~= #b then return #a > #b end
        return a < b
    end)
    return out, known
end

local function count(v)
    if type(v) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return n
end

-- A version or build text as the client gave it: letters, digits, dots,
-- dashes, blanks and brackets only, 40 at most. nil for anything else.
local function plainWord(v)
    if type(v) ~= "string" and type(v) ~= "number" then return nil end
    local s = tostring(v):gsub("[^%w%.%-%s%(%)]", "")
    return clip(trim(s), 40)
end

-- The diagnostics for a report, read now, field by field from the
-- allowlist in the header; false when a read raised or the snapshot came
-- back empty. Nothing is saved, and no field that is not named here is read.
--   names, known   as F.Names answers: the names to take out of the
--                  problem lines; with known not true they are only counted
function F.Collect(k, names, known)
    local ok, out = pcall(function()
        local client, id = k.client, k.id
        local got = { texts = known == true }
        got.version = plainWord(client.version(id.addon))
        got.build = plainWord(ns.Diag.BuildKey(client))
        local snap = ns.Diag.Collect(k, F.NAME)
        if type(snap) ~= "table" or type(snap.kernel) ~= "table" then return false end
        if type(snap.at) == "number" then got.at = snap.at end
        got.clock = type(snap.clock) == "number"
        got.namesAsked, got.namesMissing = 0, 0
        if type(snap.names) == "table" then
            for _, kind in pairs(snap.names) do
                got.namesAsked = got.namesAsked + 1
                if kind == "nil" then got.namesMissing = got.namesMissing + 1 end
            end
        end
        got.known = {}
        if type(snap.known) == "table" then
            for _, name in ipairs(F.KNOWN) do
                local v = snap.known[name]
                if type(v) == "boolean" then got.known[#got.known + 1] = { name, v } end
            end
        end
        got.reads = {}
        if type(snap.reads) == "table" then
            for _, row in ipairs(F.READS) do
                local v = snap.reads[row[1]]
                if type(v) == "boolean" or type(v) == "number" then got.reads[#got.reads + 1] = { row[2], v } end
            end
        end
        local kernel = snap.kernel
        if type(kernel.phase) == "string" then got.phase = kernel.phase end
        got.paused, got.loaded = kernel.paused == true, kernel.storeOpened == true
        got.eventsNot, got.eventsAbsent = count(kernel.eventsNotRegistered), count(kernel.eventsExpectedAbsent)
        got.noEventFrame, got.noTickFrame = kernel.eventFrameNotMade == true, kernel.tickFrameNotMade == true
        local saved = client.saved(id.accountDB)
        local kept
        if type(saved) == "table" then kept = saved.diag end
        if type(kept) == "table" then
            if type(kept.starts) == "number" then got.starts = kept.starts end
            if type(kept.count) == "number" then got.count = kept.count end
            got.readRecords = count(kept.reads)
        end
        -- The add-on's own problems, newest first, each through the cleaner.
        local listed = {}
        if type(kernel.problems) == "table" then listed = kernel.problems end
        got.problems, got.problemCount, got.dropped = {}, #listed, false
        if got.texts then
            for i = #listed, 1, -1 do
                if #got.problems >= F.MAX_ERRORS then break end
                local p = listed[i]
                if type(p) == "table" then
                    local times = 1
                    if type(p.count) == "number" then times = p.count end
                    local okClean, line = pcall(F.Clean,
                        tostring(p.kind) .. ", " .. tostring(p.owner) .. ": " .. tostring(p.text), names, id.addon)
                    if okClean and type(line) == "string" then
                        got.problems[#got.problems + 1] = line .. " (x" .. numText(times) .. ")"
                    else
                        got.dropped = true
                    end
                end
            end
        end
        return got
    end)
    if not ok or type(out) ~= "table" then return false end
    return out
end

function F.Declare(k, diag)
    local api = {}
    local ctx, panel, entry
    local boxes = {}
    local form = {}
    local draw

    local function say(line)
        local id = k.id or ns.id
        k.client.print(tostring(id.title) .. ": " .. line)
    end

    local function attach()
        return k.settings:get(F.SETTING) == true
    end

    function api.form()
        local out = {}
        for key, value in pairs(form) do out[key] = value end
        return out
    end

    -- The text as it would be copied now. Built afresh each time: nothing
    -- of it is kept.
    function api.report()
        if not kindOf(form.kind) then return nil, F.NEED_KIND end
        if F.Field(form.description) == "" then return nil, F.NEED_TEXT end
        local id = k.id or ns.id
        local okNames, names, known = pcall(F.Names, k)
        if not okNames or type(names) ~= "table" then names, known = {}, false end
        local got
        if attach() then got = F.Collect(k, names, known) end
        return F.Build(form, got, names, id.title, id.addon)
    end

    local function lock()
        local state
        if type(k.client.combatLockdown) == "function" then state = k.client.combatLockdown() end
        return state
    end

    local function rows()
        local out = { { kind = "info", text = F.INTRO } }
        -- A lock that is on, or not known, is said; nothing else changes.
        if lock() ~= false then out[#out + 1] = { kind = "info", text = F.LOCK_NOTE } end
        for _, kind in ipairs(F.KINDS) do
            out[#out + 1] = { kind = "button", key = "kind." .. kind.key,
                label = (form.kind == kind.key and "> " or "") .. kind.pick }
        end
        for _, field in ipairs(F.FIELDS) do
            if not field.problem or form.kind == "problem" then
                local text = F.Field(form[field.key])
                if text == "" then text = F.NOT_WRITTEN end
                out[#out + 1] = { kind = "info", text = field.label .. ": " .. clip(text, 60) }
                out[#out + 1] = { kind = "button", key = "write." .. field.key, label = field.write }
            end
        end
        out[#out + 1] = { kind = "button", key = "diag", label = F.ATTACH .. (attach() and "on" or "off") }
        local ready = kindOf(form.kind) ~= nil and F.Field(form.description) ~= ""
        out[#out + 1] = { kind = "button", key = "preview", label = F.PREVIEW, enabled = ready }
        out[#out + 1] = { kind = "button", key = "copy", label = F.COPY, enabled = ready }
        if F.DESTINATION == "" then
            out[#out + 1] = { kind = "info", text = F.NO_DESTINATION }
        else
            out[#out + 1] = { kind = "info", text = F.SHARE_AT }
            out[#out + 1] = { kind = "button", key = "destination", label = F.COPY_DESTINATION }
        end
        out[#out + 1] = { kind = "button", key = "clear", label = F.AGAIN }
        return out
    end

    -- The text in a copy box of its own (one for the preview, one to copy
    -- from, one for the address), made the first time it is asked for.
    local function box(which, title, text)
        local id = k.id or ns.id
        if boxes[which] == nil and type(k.client.copyBox) == "function" then
            local CopyBox = ns.CopyBox or {}
            boxes[which] = k.client.copyBox({ name = id.framePrefix .. "Feedback" .. which,
                width = CopyBox.WIDTH or 520, height = CopyBox.HEIGHT or 320, title = id.title .. title }) or false
        end
        if not boxes[which] then
            say(F.NO_BOX)
            for line in text:gmatch("[^\n]+") do say(line) end
            return false
        end
        boxes[which].setText(text)
        boxes[which].show(true)
        return true
    end

    local function act(key)
        local what, which = tostring(key):match("^(%a+)%.?(.*)$")
        if what == "kind" and kindOf(which) then
            form.kind = which
        elseif what == "write" then
            local field
            for _, one in ipairs(F.FIELDS) do
                if one.key == which then field = one end
            end
            if not field then return end
            if entry == nil and type(k.client.textEntry) == "function" then
                local id = k.id or ns.id
                entry = k.client.textEntry({ name = id.framePrefix .. "FeedbackEntry", width = 440 }) or false
            end
            if not entry then
                say(F.NO_ENTRY)
                return
            end
            entry.ask(field.ask, F.Field(form[field.key]), function(text)
                form[field.key] = F.Field(text)
                draw()
            end)
            return
        elseif what == "diag" then
            local ok, why = k.settings:set(F.SETTING, not attach())
            if not ok then k.problems:add(F.NAME, "setting", why) end
        elseif what == "preview" or what == "copy" then
            local text, why = api.report()
            if not text then
                say(tostring(why) .. ".")
                return
            end
            if what == "preview" then box("Preview", F.PREVIEW_TITLE, text) else box("Copy", F.COPY_TITLE, text) end
            return
        elseif what == "destination" then
            if F.DESTINATION ~= "" then box("Address", F.COPY_TITLE, F.DESTINATION) end
            return
        elseif what == "clear" then
            form = {}
        else
            return
        end
        draw()
    end

    draw = function()
        if panel then panel.draw(rows(), act) end
    end

    function api.open()
        if not ctx then
            say(F.NOT_READY)
            return false
        end
        if panel == nil and type(k.client.rowPanel) == "function" then
            local id = k.id or ns.id
            panel = k.client.rowPanel({ name = id.framePrefix .. "Feedback", width = F.WIDTH, height = 80 }) or false
            if panel then panel.place(F.DEFAULT_POINT) end
        end
        if not panel then
            say(F.NO_WINDOW)
            return false
        end
        draw()
        panel.show(true)
        return true
    end

    function api.shown()
        return panel ~= nil and panel ~= false and panel.shown() == true
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[F.WORD] = function() api.open() end
        if type(diag.help) == "table" then diag.help[F.WORD] = F.HELP end
    end

    k:Module({
        name = F.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = F.SETTING, scope = "account", type = "bool", default = false,
            label = F.ROW_LABEL,
            help = "Off: a feedback report holds only what you write. On: the add-on's version, the game build, "
                .. "its own listed problems and a short state summary are added, with names and paths taken out. "
                .. "You see all of it before you copy it. " .. k.id.slash .. " " .. F.WORD .. " opens the window.",
            group = "general", synonyms = { "feedback", "bug", "report", "problem", "idea", "suggest" },
            open = { text = F.ROW_OPEN, run = function() return api.open() end },
        } },
        provides = { Open = api.open, Report = api.report, Shown = api.shown },
        start = function(c) ctx = c end,
        stop = function()
            ctx = nil
            if panel then panel.show(false) end
            if entry then entry.show(false) end
            for _, one in pairs(boxes) do
                if one then one.show(false) end
            end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.feedback = F.Declare(ns, ns.diag)
