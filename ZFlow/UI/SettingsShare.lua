local _, ns = ...

-- Settings export and import (row N70, research item 12): the player's
-- Z-Flow settings as a line of text to copy, and such a line pasted back,
-- on this character or another. DATA ONLY: the text is parsed here, piece
-- by piece, against a fixed format. Nothing in it is ever run: this file
-- has no code loader of any kind and calls none (a test reads its
-- functions and fails on any such name).
--
-- What an export holds: every settings row of the add-on that holds a
-- plain value (on/off, a number, one of the row's choices), with its key,
-- its scope and its value now; the row "Settings an export holds"
-- (share.exportScope) narrows it to the account's rows or this
-- character's. Window places ("place" rows) are not in it. Nor are the
-- saved plans (goals, gear sets, kept seal and blessing choices): they
-- have no checked set path yet, so they are not exported until they do.
-- No character, realm, guild or account name, no GUID and nothing else of
-- the saved data is read: every value comes from a settings row through
-- the kernel's settings (a choice is one the row itself lists).
--
-- THE FORMAT, version 1. One line; parts split by ";" (spaces and line
-- breaks between parts are allowed and ignored):
--   ZFLOW-EXPORT:1                     the first part, exactly
--   <scope>:<key>=<type>:<value>       one part a setting
--       scope   account | char
--       key     letters, digits, "." and "_", starting with a letter,
--               SettingsShare.MAX_KEY at most
--       type    bool   value 1 (on) or 0 (off)
--               num    a decimal number (digits, ".", "-", "+", e); not
--                      hex, not infinite
--               choice the choice's text, every character but letters,
--                      digits, ".", "_" and "-" written %XX (hex byte)
--   END:<n>                            the last part; n = how many
--                                      settings parts stand between
-- No "|" ever (the game reads it as a code). A text longer than MAX_BYTES,
-- or of more than MAX_ITEMS parts, is not read at all; a text whose first
-- part is not the header, or whose END count does not match, neither.
-- A setting part that is not well written, names no row, gives the wrong
-- type, a value outside the row's limits or choices, a key given twice, or
-- a row that does not apply now, is skipped and counted with its reason.
-- A row's scope in the text is informational: the value is kept at the
-- row's own scope.
--
-- Import: the text is read into a preview (what will change, from what to
-- what, and every skipped part with its reason: "N will change, M skipped,
-- U already the same"). Nothing is set until the player presses Apply;
-- then each change goes through SettingsPage.Set, the settings page's one
-- checked path (type, limits, choices, the row's requires, the settings
-- model's check). A change Set refuses is counted, not forced.
-- Combat: as the settings page, a combat lock that is on or that the
-- client will not tell refuses the import and the Apply; nothing changes
-- and the preview stays.
--
-- Entry points:
--   <slash> export settings   the text, in a copy box (select, then copy)
--   <slash> import settings   the share window and the box to paste into
--   the settings row "Settings an export holds" (Advanced; found by
--   export, import, backup, share, profile, copy), and its button, which
--   opens the share window (Export / Import / the preview / Apply).
-- The bare words keep their old work: <slash> export makes the
-- character's lines (UI/Export.lua), <slash> import reports on the
-- predecessor's data (Core/Diag.lua).
--
--   SettingsShare.Encode(items) -> text        pure
--     items { { scope, key, type = "bool"|"number"|"choice", value }, ... }
--   SettingsShare.Decode(text) -> got, or nil and why     pure
--     got = { items = { as above }, skipped = { { key, why }, ... } }
--   SettingsShare.Export(k, which) -> text, how many, left out, first error
--   SettingsShare.Plan(k, got) -> { changes = { { key, label, scope, from,
--     to } }, skipped = { { key, why } }, same = n }
local S = {}
ns.SettingsShare = S

S.NAME = "settingsShare"
S.WORD = "settings"
S.SETTING = "share.exportScope"
S.SCOPES = { "all", "account", "char" }
S.HEADER = ns.id.bindingHeader .. "-EXPORT:1"   -- the add-on's binding header, read from Core/Identity.lua
S.END = "END"
S.MAX_BYTES = 16384
S.MAX_ITEMS = 600
S.MAX_KEY = 80
S.MAX_CHOICE = 80
S.MAX_SHOWN = 25

-- Row type <-> the type word in the text.
S.TYPE_WORD = { bool = "bool", number = "num", choice = "choice" }
S.WORD_TYPE = { bool = "bool", num = "number", choice = "choice" }
S.TAKES = { bool = "on or off", number = "a number", choice = "one of its choices" }

S.NOT_EXPORT = "This is not a " .. ns.id.title .. " settings export (it starts with " .. S.HEADER .. "); nothing was read."
S.TOO_LONG = "The text is too long (more than " .. S.MAX_BYTES .. " characters); nothing was read."
S.TOO_MANY = "The text has more than " .. S.MAX_ITEMS .. " parts; nothing was read."
S.CUT_SHORT = "The text is cut short or changed (its END count does not match); nothing was read."
S.BAD_PART = "not written as scope:key=type:value"
S.BAD_SCOPE = "the scope is not account or char"
S.BAD_KEY = "not a setting's name"
S.TWICE = "given twice; the first is used"
S.BAD_BOOL = "not 1 or 0"
S.BAD_NUMBER = "not a number"
S.BAD_CHOICE = "the choice is badly written"
S.BAD_TYPE = "not bool, num or choice"
S.UNKNOWN = "no setting has this name"
S.WRONG_TYPE = "wrong type: it takes "
S.NOT_HERE = "not set from an import"
S.NOT_NOW = "this setting does not apply right now"
S.LOCKED = "Settings can't change in combat; nothing was imported."
S.LOCK_UNKNOWN = "The game won't say whether you are in combat, so nothing was imported."
S.NOT_READY = "settings share: not started yet."
S.NO_BOX = "The copy box could not be made; the text follows."
S.NO_ENTRY = "The box to paste into could not be made."
S.NO_WINDOW = "The share window could not be made."
S.NOTHING = "There is nothing to apply."
S.CANCELLED = "Nothing was imported."
S.ASK = "Paste a " .. ns.id.title .. " settings export (Ctrl+V), then press Enter."
S.INTRO = "Export: your settings as text to copy. Import: paste such text; you see every change before anything is set."
S.EXPORT_BUTTON = "Export my settings"
S.IMPORT_BUTTON = "Import settings"
S.CANCEL = "Cancel"
S.EXPORT_TITLE = ": settings export (select, then copy)"
S.ROW_OPEN = "Export or import"
S.WIDTH = 460
S.DEFAULT_POINT = { "CENTER", "CENTER", 0, 60 }

local function clip(text, n)
    text = tostring(text)
    if #text > n then return text:sub(1, n) .. "..." end
    return text
end

-- Pasted text as it may be shown: only safe characters, cut short.
function S.Shown(text)
    return clip((tostring(text):gsub("[^%w%._%-:=%%]", "?")), 40)
end

function S.Escape(text)
    return (tostring(text):gsub("[^%w%._%-]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

function S.Unescape(text)
    if text:find("%%[^%x]") or text:find("%%%x[^%x]") or text:find("%%%x?$") then return nil end
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function S.NumText(v)
    if not finite(v) then return nil end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.14g", v)
end

-- A row's value as the text's value, or nil when it cannot be written.
function S.ValueText(kind, v)
    if kind == "bool" then
        if type(v) ~= "boolean" then return nil end
        if v then return "1" end
        return "0"
    elseif kind == "number" then
        return S.NumText(v)
    elseif kind == "choice" then
        if type(v) ~= "string" or #v > S.MAX_CHOICE then return nil end
        return S.Escape(v)
    end
    return nil
end

-- The text's value as a row's value: value, or nil and why.
function S.Value(word, text)
    if word == "bool" then
        if text == "1" then return true end
        if text == "0" then return false end
        return nil, S.BAD_BOOL
    elseif word == "num" then
        if not text:find("^[%d%.eE%+%-]+$") then return nil, S.BAD_NUMBER end
        local v = tonumber(text)
        if not finite(v) then return nil, S.BAD_NUMBER end
        return v
    elseif word == "choice" then
        local v = S.Unescape(text)
        if v == nil or #v > S.MAX_CHOICE then return nil, S.BAD_CHOICE end
        return v
    end
    return nil, S.BAD_TYPE
end

function S.KeyOk(key)
    return type(key) == "string" and #key <= S.MAX_KEY and key:find("^%a[%w%._]*$") ~= nil
end

function S.Encode(items)
    local parts = { S.HEADER }
    for _, item in ipairs(items) do
        parts[#parts + 1] = item.scope .. ":" .. item.key .. "=" .. S.TYPE_WORD[item.type] .. ":"
            .. S.ValueText(item.type, item.value)
    end
    parts[#parts + 1] = S.END .. ":" .. (#parts - 1)
    return table.concat(parts, ";")
end

function S.Decode(text)
    if type(text) ~= "string" then return nil, S.NOT_EXPORT end
    if #text > S.MAX_BYTES then return nil, S.TOO_LONG end
    local parts = {}
    for part in text:gmatch("[^;%s]+") do
        parts[#parts + 1] = part
        if #parts > S.MAX_ITEMS + 2 then return nil, S.TOO_MANY end
    end
    if parts[1] ~= S.HEADER then return nil, S.NOT_EXPORT end
    if #parts - 2 > S.MAX_ITEMS then return nil, S.TOO_MANY end
    local count
    if #parts >= 2 then
        local n = parts[#parts]:match("^" .. S.END .. ":(%d+)$")
        if n then count = tonumber(n) end
    end
    if count == nil or count ~= #parts - 2 then return nil, S.CUT_SHORT end
    local items, skipped, seen = {}, {}, {}
    for i = 2, #parts - 1 do
        local part = parts[i]
        local scope, key, word, valueText = part:match("^(%a+):([^=]+)=(%a+):(.*)$")
        local why
        if not scope then
            why = S.BAD_PART
            key = part
        elseif scope ~= "account" and scope ~= "char" then
            why = S.BAD_SCOPE
        elseif not S.KeyOk(key) then
            why = S.BAD_KEY
        elseif seen[key] then
            why = S.TWICE
        end
        local value
        if not why then
            seen[key] = true
            value, why = S.Value(word, valueText)
        end
        if why then
            skipped[#skipped + 1] = { key = S.Shown(key), why = why }
        else
            items[#items + 1] = { scope = scope, key = key, type = S.WORD_TYPE[word], value = value }
        end
    end
    return { items = items, skipped = skipped }
end

-- Why the value does not fit the row, or nil when it does (the settings
-- page's own words; SettingsPage.Set checks again when it is applied).
function S.Misfit(row, value)
    if row.type == "bool" then
        if type(value) ~= "boolean" then return S.WRONG_TYPE .. S.TAKES.bool end
    elseif row.type == "number" then
        if not finite(value) then return S.WRONG_TYPE .. S.TAKES.number end
        if row.min ~= nil and value < row.min then return "below the lowest value allowed (" .. row.min .. ")" end
        if row.max ~= nil and value > row.max then return "above the highest value allowed (" .. row.max .. ")" end
    elseif row.type == "choice" then
        for i = 1, #row.choices do
            if row.choices[i] == value then return nil end
        end
        return "not one of its choices"
    else
        return S.NOT_HERE
    end
    return nil
end

-- The settings model's word on a key it also holds (as the settings page).
function S.ModelWhy(key, value)
    local Model = ns.Settings and ns.Settings.Model
    if type(Model) ~= "table" or type(Model.Default) ~= "function" then return nil end
    local ok, model = pcall(Model.Default)
    if not ok or type(model) ~= "table" or model:row(key) == nil then return nil end
    local fine, why = model:check(key, value)
    if fine then return nil end
    return tostring(why)
end

function S.Plan(k, got)
    local plan = { changes = {}, skipped = {}, same = 0 }
    for _, one in ipairs(got.skipped) do plan.skipped[#plan.skipped + 1] = one end
    for _, item in ipairs(got.items) do
        local row = k.settings:row(item.key)
        local why
        if type(row) ~= "table" then
            why = S.UNKNOWN
        elseif S.TYPE_WORD[row.type] == nil then
            why = S.NOT_HERE
        elseif row.type ~= item.type then
            why = S.WRONG_TYPE .. S.TAKES[row.type]
        else
            why = S.Misfit(row, item.value)
        end
        if not why and not k.settings:available(row.key) then why = S.NOT_NOW end
        if not why then why = S.ModelWhy(row.key, item.value) end
        if why then
            plan.skipped[#plan.skipped + 1] = { key = item.key, why = why }
        else
            local okGet, now = pcall(k.settings.get, k.settings, row.key)
            if okGet and now == item.value then
                plan.same = plan.same + 1
            else
                local from
                if okGet then from = now end
                plan.changes[#plan.changes + 1] = { key = row.key, label = tostring(row.label or row.key),
                    scope = row.scope, from = from, to = item.value }
            end
        end
    end
    return plan
end

-- Every plain row's value now, as the text. A read that raises leaves its
-- row out; the first error is handed back to be kept.
function S.Export(k, which)
    local items, left, firstErr = {}, 0, nil
    for row in k.settings:each() do
        if S.TYPE_WORD[row.type] and S.KeyOk(row.key) and (which == "all" or which == row.scope)
            and (row.scope == "account" or row.scope == "char") then
            local ok, v = pcall(k.settings.get, k.settings, row.key)
            local text
            if ok then text = S.ValueText(row.type, v) end
            if text then
                items[#items + 1] = { scope = row.scope, key = row.key, type = row.type, value = v }
            else
                left = left + 1
                if not ok and firstErr == nil then firstErr = v end
            end
        end
    end
    return S.Encode(items), #items, left, firstErr
end

-- The combat lock: true, false, or nil when the client will not tell.
function S.Lock(client)
    if type(client) ~= "table" or type(client.combatLockdown) ~= "function" then return nil end
    local ok, state = pcall(client.combatLockdown)
    if not ok or type(state) ~= "boolean" then return nil end
    return state
end

function S.LockText(lock)
    if lock == true then return S.LOCKED end
    return S.LOCK_UNKNOWN
end

local function shownValue(v)
    if type(v) == "boolean" then
        if v then return "on" end
        return "off"
    end
    if v == nil then return "?" end
    return clip(tostring(v), 30)
end

function S.Summary(plan)
    return #plan.changes .. " will change, " .. #plan.skipped .. " skipped, " .. plan.same .. " already the same."
end

function S.ChangeLine(change)
    return clip(change.label, 50) .. ": " .. shownValue(change.from) .. " -> " .. shownValue(change.to)
end

function S.ApplyLabel(n)
    return "Apply " .. n .. " change(s)"
end

function S.ResultLine(r)
    local line = r.applied .. " setting(s) imported."
    if #r.refused > 0 then line = line .. " " .. #r.refused .. " could not be set." end
    return line
end

function S.Declare(k, diag)
    local api = {}
    local ctx, panel, entry, box
    local plan, note
    local draw

    local function id() return k.id or ns.id end

    local function say(line)
        k.client.print(tostring(id().title) .. ": " .. line)
    end

    local function scopeChoice()
        local ok, v = pcall(k.settings.get, k.settings, S.SETTING)
        if ok and (v == "account" or v == "char") then return v end
        return "all"
    end

    -- -> text, how many, left out; or nil and why.
    function api.export(which)
        if not ctx then return nil, S.NOT_READY end
        local text, n, left, err = S.Export(k, which or scopeChoice())
        if err ~= nil then k.problems:add(S.NAME, "export", err) end
        return text, n, left
    end

    function api.showExport()
        local text, n, left = api.export()
        if not text then
            say(tostring(n))
            return false
        end
        local line = "settings export: " .. n .. " settings in the text."
        if left > 0 then line = line .. " " .. left .. " could not be read and are left out." end
        say(line)
        if box == nil and type(k.client.copyBox) == "function" then
            local CopyBox = ns.CopyBox or {}
            box = k.client.copyBox({ name = id().framePrefix .. "ShareExport", width = CopyBox.WIDTH or 520,
                height = CopyBox.HEIGHT or 320, title = id().title .. S.EXPORT_TITLE }) or false
        end
        if not box then
            say(S.NO_BOX)
            say(text)
            return false
        end
        box.setText(text)
        box.show(true)
        return true
    end

    -- The text read into a preview; nothing is set. -> plan, or nil and why.
    function api.importText(text)
        if not ctx then return nil, S.NOT_READY end
        local lock = S.Lock(k.client)
        if lock ~= false then
            plan = nil
            return nil, S.LockText(lock)
        end
        local got, why = S.Decode(text)
        if not got then
            plan = nil
            return nil, why
        end
        plan = S.Plan(k, got)
        return plan
    end

    function api.preview() return plan end

    -- Applies the preview through the settings page's Set. -> result, or
    -- nil and why (then nothing changed and the preview stays).
    function api.confirm()
        if not plan then return nil, S.NOTHING end
        local lock = S.Lock(k.client)
        if lock ~= false then return nil, S.LockText(lock) end
        local Page = ns.SettingsPage
        if type(Page) ~= "table" or type(Page.Set) ~= "function" then return nil, S.NOT_READY end
        local r = { applied = 0, refused = {} }
        for _, change in ipairs(plan.changes) do
            local ok, why = Page.Set(k, change.key, change.to)
            if ok then
                r.applied = r.applied + 1
            else
                r.refused[#r.refused + 1] = { key = change.key, why = tostring(why) }
            end
        end
        plan = nil
        return r
    end

    local function rows()
        local out = { { kind = "info", text = S.INTRO } }
        out[#out + 1] = { kind = "button", key = "export", label = S.EXPORT_BUTTON }
        out[#out + 1] = { kind = "button", key = "import", label = S.IMPORT_BUTTON }
        if note then out[#out + 1] = { kind = "info", text = note } end
        if plan then
            out[#out + 1] = { kind = "info", text = S.Summary(plan) }
            for i, change in ipairs(plan.changes) do
                if i <= S.MAX_SHOWN then out[#out + 1] = { kind = "info", text = S.ChangeLine(change) } end
            end
            if #plan.changes > S.MAX_SHOWN then
                out[#out + 1] = { kind = "info", text = "and " .. (#plan.changes - S.MAX_SHOWN) .. " more to change" }
            end
            for i, one in ipairs(plan.skipped) do
                if i <= S.MAX_SHOWN then
                    out[#out + 1] = { kind = "info", text = "skipped " .. S.Shown(one.key) .. ": " .. one.why }
                end
            end
            if #plan.skipped > S.MAX_SHOWN then
                out[#out + 1] = { kind = "info", text = "and " .. (#plan.skipped - S.MAX_SHOWN) .. " more skipped" }
            end
            out[#out + 1] = { kind = "button", key = "confirm", label = S.ApplyLabel(#plan.changes),
                enabled = #plan.changes > 0 }
            out[#out + 1] = { kind = "button", key = "cancel", label = S.CANCEL }
        end
        return out
    end

    local function act(key)
        if key == "export" then
            api.showExport()
            return
        elseif key == "import" then
            api.ask()
            return
        elseif key == "confirm" then
            local r, why = api.confirm()
            if r then note = S.ResultLine(r) else note = tostring(why) end
            say(note)
        elseif key == "cancel" then
            plan = nil
            note = S.CANCELLED
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
            say(S.NOT_READY)
            return false
        end
        if panel == nil and type(k.client.rowPanel) == "function" then
            panel = k.client.rowPanel({ name = id().framePrefix .. "Share", width = S.WIDTH, height = 80 }) or false
            if panel then panel.place(S.DEFAULT_POINT) end
        end
        if not panel then
            say(S.NO_WINDOW)
            return false
        end
        draw()
        panel.show(true)
        return true
    end

    -- The box to paste into. Refused while the combat lock is on or unread.
    function api.ask()
        if not ctx then
            say(S.NOT_READY)
            return false
        end
        local lock = S.Lock(k.client)
        if lock ~= false then
            note = S.LockText(lock)
            say(note)
            draw()
            return false
        end
        if entry == nil and type(k.client.textEntry) == "function" then
            entry = k.client.textEntry({ name = id().framePrefix .. "ShareEntry", width = 440 }) or false
        end
        if not entry then
            say(S.NO_ENTRY)
            return false
        end
        entry.ask(S.ASK, "", function(text)
            local got, why = api.importText(text)
            if got then
                note = nil
            else
                note = tostring(why)
                say(note)
            end
            api.open()
        end)
        return true
    end

    -- The slash words: "export settings" and "import settings" are this
    -- file's; any other rest goes to the word's old work, unchanged.
    if diag and type(diag.commands) == "table" then
        local function wrap(word, ours, help)
            local prior = diag.commands[word]
            diag.commands[word] = function(rest)
                local first
                if type(rest) == "string" then first = rest:match("^(%S+)") end
                if first == S.WORD then return ours() end
                if type(prior) == "function" then return prior(rest) end
            end
            if type(diag.help) == "table" then
                local was = diag.help[word]
                if type(was) == "string" and was ~= "" then
                    diag.help[word] = was .. "; " .. help
                else
                    diag.help[word] = help
                end
            end
        end
        wrap("export", function() api.showExport() end, "export settings: your settings as text to copy")
        wrap("import", function()
            api.open()
            api.ask()
        end, "import settings: paste such text, see every change, then apply")
    end

    k:Module({
        name = S.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = S.SETTING, scope = "account", type = "choice", choices = S.SCOPES, default = "all",
            label = "Settings an export holds",
            help = "all: every setting; account: the ones shared by your characters; char: this character's. "
                .. "An export is text you copy; an import shows every change before anything is set. "
                .. "Window places and saved plans are not in it. " .. tostring(id().slash)
                .. " export settings / import settings, or the button.",
            group = "advanced", synonyms = { "export", "import", "backup", "share", "profile", "copy" },
            open = { text = S.ROW_OPEN, run = function() return api.open() end },
        } },
        provides = { Open = api.open, Export = api.export, Import = api.importText, Confirm = api.confirm,
            Preview = api.preview },
        start = function(c) ctx = c end,
        stop = function()
            ctx = nil
            plan = nil
            if panel then panel.show(false) end
            if entry then entry.show(false) end
            if box then box.show(false) end
        end,
    })
    return api
end

-- The addon's own: declared when this file is read, started at login.
ns.settingsShare = S.Declare(ns, ns.diag)
