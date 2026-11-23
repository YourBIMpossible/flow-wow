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
-- together itself: its version and the game build, its own recent Lua
-- errors (Core/Diag.lua's bounded list, the add-on's lines only) and a
-- short summary of a Diag snapshot taken now and not saved. Every part has
-- a fixed cap (the MAX_ constants). With the setting off the report has no
-- diagnostics line at all.
--
-- Names: the character's, the realm's and the guild's names are read when
-- the report is built and taken out of the whole text, the player's own
-- words included (Feedback.Mask: the capture mask's name rule,
-- Core/Capture.lua maskNames, which is an offline file and does not ship).
-- When the character's name cannot be read, error and problem texts are
-- left out and only counted, so no name can ride in on one. No chat, no
-- saved-data dump and nothing of another add-on is ever read for it.
--
-- A diagnostics read that raises, or a snapshot that comes back empty,
-- leaves the written feedback whole with one line saying so.
--
-- Combat: the window is the add-on's own plain frame, so it opens in a
-- fight too. A combat lock that is on, or that the client will not tell
-- (which counts as on, as for the settings page), only adds one line
-- saying so; nothing of the game's is opened or changed either way.
--
--   Feedback.Build(form, diag, names, title) -> text   pure
--     form   { kind, description, happened, expected }
--     diag   nil (not attached), false (could not be collected), or
--            { version, build, errors = { { text, count } }, errorCount,
--              phase, paused, loaded, problems = { { kind, owner, text,
--              count } }, problemCount, texts = true | false }
--   Feedback.Mask(text, names) -> text, how many were taken out
--   Feedback.Collect(k, diag) -> the diag table above, or false
--   Feedback.Names(k, diag) -> names, known (true when the character's is)
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

-- The caps. Bytes of one typed field; bytes of one diagnostics line;
-- how many of the add-on's errors and of its problems are listed; lines of
-- the diagnostics block; bytes of the whole report.
F.MAX_FIELD = 600
F.MAX_LINE = 240
F.MAX_ERRORS = 5
F.MAX_PROBLEMS = 5
F.MAX_DIAG_LINES = 16
F.MAX_BYTES = 3000

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

-- Every place a name stands, whatever its capitals, is taken out. Also the
-- folder after "Account" in a path, which is the account's name. Answers
-- the text and how many were taken out.
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
    local paths
    text, paths = text:gsub("([Aa]ccount[\\/])[^\\/%s]+", "%1" .. F.HIDDEN)
    return text, n + paths
end

local function kindOf(key)
    for _, kind in ipairs(F.KINDS) do
        if kind.key == key then return kind end
    end
    return nil
end

local function yes(v) return v and "yes" or "no" end

-- The lines of the diagnostics block, MAX_DIAG_LINES at most.
local function diagLines(diag)
    if diag == false then return { F.NO_DIAG } end
    local lines = { F.DIAG_HEAD }
    lines[#lines + 1] = "Version: " .. tostring(diag.version or "unknown") .. "; game build: "
        .. tostring(diag.build or "unknown")
    local errors = type(diag.errors) == "table" and diag.errors or {}
    lines[#lines + 1] = "The add-on's own recent errors: " .. tostring(diag.errorCount or #errors)
    for i = 1, math.min(#errors, F.MAX_ERRORS) do
        lines[#lines + 1] = "  " .. tostring(errors[i].text) .. " (x" .. tostring(errors[i].count or 1) .. ")"
    end
    lines[#lines + 1] = "State: " .. tostring(diag.phase or "unknown") .. "; paused: " .. yes(diag.paused)
        .. "; saved data loaded: " .. yes(diag.loaded)
    local problems = type(diag.problems) == "table" and diag.problems or {}
    lines[#lines + 1] = "Problems the add-on listed: " .. tostring(diag.problemCount or #problems)
    for i = 1, math.min(#problems, F.MAX_PROBLEMS) do
        local p = problems[i]
        lines[#lines + 1] = "  " .. tostring(p.kind) .. " / " .. tostring(p.owner) .. ": " .. tostring(p.text)
            .. " (x" .. tostring(p.count or 1) .. ")"
    end
    if diag.texts == false then
        lines[#lines + 1] = "Their texts are left out: your character's name could not be read to take it out."
    end
    while #lines > F.MAX_DIAG_LINES do lines[#lines] = nil end
    for i = 1, #lines do
        lines[i] = clip((lines[i]:gsub("%c", " ")), F.MAX_LINE)
    end
    return lines
end

function F.Build(form, diag, names, title)
    form = type(form) == "table" and form or {}
    local kind = kindOf(form.kind)
    local lines = { tostring(title or "") .. " feedback: " .. (kind and kind.head or "?") }
    for _, field in ipairs(F.FIELDS) do
        local text = F.Field(form[field.key])
        if text ~= "" and (not field.problem or (kind and kind.key == "problem")) then
            lines[#lines + 1] = field.label .. ": " .. text
        end
    end
    if diag ~= nil then
        for _, line in ipairs(diagLines(diag)) do lines[#lines + 1] = line end
    end
    local text = F.Mask(table.concat(lines, "\n"), names)
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

-- The names to take out: the character's, the realm's (both spellings) and
-- the guild's, read now through the client's guarded call. known is true
-- when the character's own name was read.
function F.Names(k, diag)
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
    local timing
    if type(diag) == "table" and type(diag.timing) == "table" then timing = diag.timing end
    if timing then
        if add(timing.character) then known = true end
        add(timing.realm)
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

-- The diagnostics for a report, read now; false when a read raised or the
-- snapshot came back empty. Nothing is saved.
function F.Collect(k, diag, known)
    local ok, out = pcall(function()
        local client = k.client
        local got = { texts = known == true }
        got.version = client.version(k.id.addon)
        got.build = ns.Diag.BuildKey(client)
        got.errors, got.errorCount = {}, 0
        local timing
        if type(diag) == "table" and type(diag.timing) == "table" then timing = diag.timing end
        local kept = {}
        if timing and type(timing.errors) == "table" then kept = timing.errors end
        for i = 1, #kept do
            local row = kept[i]
            if type(row) == "table" and row.ours == true and type(row.text) == "string" then
                got.errorCount = got.errorCount + 1
                if got.texts then
                    got.errors[#got.errors + 1] = { text = (row.text:match("^[^\r\n]*")), count = row.count }
                end
            end
        end
        -- The newest are the ones worth reading.
        while #got.errors > F.MAX_ERRORS do table.remove(got.errors, 1) end
        local snap = ns.Diag.Collect(k, F.NAME)
        if type(snap) ~= "table" or type(snap.kernel) ~= "table" then return false end
        local kernel = snap.kernel
        got.phase, got.paused, got.loaded = kernel.phase, kernel.paused == true, kernel.storeOpened == true
        got.problems, got.problemCount = {}, 0
        local listed = {}
        if type(kernel.problems) == "table" then listed = kernel.problems end
        for i = 1, #listed do
            got.problemCount = got.problemCount + 1
            if got.texts then got.problems[#got.problems + 1] = listed[i] end
        end
        while #got.problems > F.MAX_PROBLEMS do table.remove(got.problems, 1) end
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
        local okNames, names, known = pcall(F.Names, k, diag)
        if not okNames or type(names) ~= "table" then names, known = {}, false end
        local got
        if attach() then got = F.Collect(k, diag, known) end
        return F.Build(form, got, names, id.title)
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
                .. "its own recent errors and a short state summary are added, with names taken out. "
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
