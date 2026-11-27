-- Advisor panel (U-A, G32): a small panel listing short prompts that other
-- modules register. Hidden while it has no prompts. The setting row
-- "advisor.panel" turns it off.
--
-- Drawn by the shared kit (UI/Kit.lua, lead sections 297 item 5 and 322
-- line 4): one window, a line for each prompt. When the kit or the client
-- refuses the window, the plain text panel shows the same lines
-- (UI/KitHost.lua). The player can close the kit window; it stays closed
-- for the prompts already there and opens again for a new one.
--
-- LOOK ONLY. The panel draws text and has no buttons of its own; nothing
-- here acts in the game. A prompt is advice for the player to read,
-- nothing more.
--
-- The API (fixed; other modules code against it):
--   Advisor.Add(id, text, priority[, urgency]) -> true | false, reason
--     id        non-empty string, the caller's own name for the prompt
--               ("l6c.repair"). Adding an id that is there replaces its
--               text and priority; it never makes a second line.
--     text      non-empty string, one line as the player reads it
--     priority  number, higher shows first; nil is 0. Equal priorities
--               keep the order they were first added in.
--     urgency   how pressing it is (parity row C-44), one of
--               Advisor.LEVELS: "info" (worth doing, nothing is lost by
--               waiting), "soon" (close to a limit) or "now" (the player
--               is losing something until it is done). nil is "info". As
--               Flow's Modules/Advisor/Advisor.lua (Adv.URGENCY: later,
--               soon, now): whoever adds the prompt says it. Flow also
--               made a prompt "soon" from its importance alone; priorities
--               here are an order, not an importance, so nothing is
--               guessed from them. It never changes the order. Data only:
--               the colour is the drawing lane's.
--     Bad arguments are refused with a reason and change nothing.
--   Advisor.Remove(id) -> true when the prompt was there, else false
--   Advisor.List()     -> copies, in shown order: { { id, text, priority }, ... }
--               A row said to be "soon" or "now" also has urgency; an
--               "info" row has no such field.
--   Advisor.Urgency(row) -> "info" | "soon" | "now"   pure: a row's level
--
-- Hiding a row (parity row C-46, the data half; the buttons are the
-- drawing lane's). As Flow's Modules/Advisor/Advisor.lua:83-112: a row the
-- player hid is not shown, the hidden ones can be listed, and one can be
-- brought back; kept for the character.
--   Advisor.KeyOf(id) -> key or nil   pure: the id with each dot-part
--               that is all digits as "#", so "train.2" stays hidden as
--               "train.3"; digits inside a word stay ("l6c.repair"). Lead
--               section 671. Flow made its key from the text, with every
--               digit run out; an id's digits inside a word are its name.
--   Advisor.Hide(id)    -> true | false, reason   the prompt of that id,
--               which must be there and not hidden. Nothing is hidden
--               before the module starts, past Advisor.MAX_HIDDEN keys, or
--               when the saved data cannot be read or written.
--   Advisor.Unhide(key) -> true when something was hidden under that key
--   Advisor.Hidden()    -> { { key, text, at, applies, id }, ... } by key:
--               every hidden key. applies: a prompt of that key is there
--               now (then id is its id and text its words now); else text
--               is what it said when it was hidden. at: client.clock()
--               when hidden, absent when the client gave no time.
--   A hidden prompt is left out of List() and the panel, tells no Watch
--   and opens no closed window. Remove and Add work on it as before.
--   Saved: char Advisor.HIDDEN = { [key] = { text, at } }.
--   Advisor.Watch(fn)  -> cancel | nil (N68). fn(id, text) is told when a
--               prompt id that was not there is added: a rule that turned
--               true. A replaced text is not new; a prompt removed and added
--               again is. A watcher that raises breaks nothing. nil for a
--               non-function.
-- These three are the addon's own advisor. A module reaches the same API
-- through its needs, which also orders its start after the advisor's:
--   ns:Module{ name = "...", needs = { "advisor" },
--              start = function(ctx) ctx.use("advisor").Add(...) end }
-- Prompts may be added before the advisor starts (while files load); they
-- show when it starts.
--
--   Advisor.Open() -> true | false, reason (G32)
--               the player asked to see the panel (the minimap menu's
--               advice row, "<slash> advice"). Shown even with no prompt,
--               as Advisor.NONE, and even while a new player's reveal holds
--               it back. Refused with Advisor.OFF while the setting is off.
--               Closing the window ends the ask. On the plain panel
--               (no close button) a second Open while it shows hides it.
--
--   Advisor.Declare(k, diag) -> api  declares the module on kernel k; with
--               diag (Core/Diag.lua's Start result) it adds the slash word
--               Advisor.WORD
--     api.Add, api.Remove, api.List, api.Open  as above, for that kernel
--   ns.use("advisor") -> { Add, Remove, List, Watch, Open }
--
-- The panel shows at most Advisor.MAX_SHOWN prompts, then "and N more".
--
-- Setting: "advisor.panel" (bool, char, on by default). The row is the
-- lead's to add to the settings model; until it is there, the panel is on.
-- Off hides the panel at once; prompts are still taken and kept, and show
-- again when it is turned back on.
--
-- Reads: none from the game (client.clock() for when a row was hidden).
-- Writes: none to the game; the hidden keys to the character's saved data.
local _, ns = ...

local Advisor = ns.Advisor or {}
ns.Advisor = Advisor

Advisor.NAME = "advisor"
Advisor.SETTING = "advisor.panel"
-- When the panel appears, in one line, for its settings row (lead section 294).
Advisor.APPEARS = "The panel appears only while there is a prompt for you, such as gear to repair."
Advisor.MAX_SHOWN = 5
Advisor.WIDTH, Advisor.HEIGHT = 300, 120
Advisor.DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -220, -200 }
-- The kit window. Its size is a first guess: not seen in game.
-- Its title is the add-on's own (lead sections 340/341): Advisor.Title(id),
-- also the plain panel's first line. Advisor.TITLE is the words after it.
Advisor.TITLE = "Advice"
-- Owner's report (lead sections 561 item 6 and 564 R8): the panel says what
-- it is in one short row under its title every time it shows (lead
-- section 578 point A). A section row, so it is never read as one of the
-- prompts; the plain panel the window falls back to does not carry it.
Advisor.ABOUT = "Things worth doing now, such as a repair."
-- Parity row C-46: the rows the player hid, for the character.
Advisor.HIDDEN = "state.advisor.hidden"
Advisor.MAX_HIDDEN = 200
Advisor.NO_PROMPT = "there is no such advice now."
Advisor.HID = "that advice is hidden already."
Advisor.FULL = "too many rows are hidden: bring one back first."
Advisor.UNREAD = "what is hidden could not be read, so nothing was changed."
Advisor.UNSAVED = "what is hidden could not be saved, so nothing was changed."

function Advisor.KeyOf(id)
    if type(id) ~= "string" or id == "" then return nil end
    -- Split on dots, keeping empty parts, and put back with dots.
    local parts = {}
    for part in (id .. "."):gmatch("([^.]*)%.") do
        if part:find("^%d+$") then part = "#" end
        parts[#parts + 1] = part
    end
    return table.concat(parts, ".")
end

-- Parity row C-44: how pressing a prompt is, least pressing first.
Advisor.LEVELS = { "info", "soon", "now" }
local LEVEL = {}
for _, level in ipairs(Advisor.LEVELS) do LEVEL[level] = true end

function Advisor.Urgency(row)
    local u = type(row) == "table" and row.urgency or nil
    if u ~= nil and LEVEL[u] then return u end
    return Advisor.LEVELS[1]
end
Advisor.KIT_ID = "Advisor"
Advisor.KIT_WIDTH = 320
-- G32: the panel opened on purpose.
Advisor.NONE = "No advice right now."
-- The Advice row (all-windows; the modernization assessment's
-- section 1): a prompt is drawn as a card with the icon of its
-- kind — the last part of its id ("l6c.repair" is a repair
-- prompt). A small table here, not a game read; a kind with no
-- entry gets a card with no picture. The pictures are first
-- guesses, not seen in game.
Advisor.KIND_ICONS = {
    repair = "Interface\\Icons\\Trade_BlackSmithing",
    trainer = "Interface\\Icons\\INV_Misc_Book_09",
    bank = "Interface\\Icons\\INV_Misc_Bag_10",
    vendor = "Interface\\Icons\\INV_Misc_Coin_01",
    setup = "Interface\\Icons\\INV_Misc_Gear_01",
    attune = "Interface\\Icons\\INV_Misc_Key_14",
    learn = "Interface\\Icons\\INV_Scroll_02",
}

-- Advisor.KindOf(id) -> the prompt's kind: its id's last part.
function Advisor.KindOf(id)
    if type(id) ~= "string" then return nil end
    local kind = string.match(id, "([^.]+)$")
    return kind
end

-- How many prompts are not shown, in plain words.
function Advisor.MoreText(n)
    return tostring(n) .. " more prompts"
end

-- A pressing level as a card's tone: "now" is bad, "soon" warns,
-- "info" is untinted.
local TONE = { now = "bad", soon = "warn" }
Advisor.OFF = "the advice panel is turned off in the settings (Advisor panel)."
Advisor.NOT_READY = "the advice panel is not ready yet."
Advisor.WORD = "advice"
Advisor.HELP = "show the advice panel, even when it has nothing to say"

-- Advisor.KitHeight(lines) -> the height of a kit window of that many
-- one-row lines: the title bar, the padding above and below, the lines.
-- Lead section 408: the window is as tall as its lines. The client fits it
-- at every draw (a wrapped line is taller); this is where it starts.
function Advisor.KitHeight(lines)
    local size = ns.Kit.look.size
    if type(lines) ~= "number" or lines < 1 then lines = 1 end
    return size.title + 2 * size.pad + lines * size.lineHeight
end

local function isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function checkId(id)
    if type(id) ~= "string" or id == "" then return "the id must be a non-empty string" end
    return nil
end

-- Advisor.Title(id) -> "<add-on title>: Advice". id: the identity (default ns.id).
function Advisor.Title(id)
    id = type(id) == "table" and id or ns.id
    return tostring(id.title) .. ": " .. Advisor.TITLE
end

-- Advisor.View(lines, title, about, levels, kinds) -> a kit window spec:
-- a header, then one row for each text, top to bottom. A line that is
-- no text is left out, so it cannot cost the window. Nothing in it can
-- be pressed. Escape does not close it: advice should not go with
-- every Escape.
-- about: the one line that says what the panel is, first, or nil.
-- levels: { [i] = "soon" | "now" } for lines[i], or nil (C-44): put on
-- the row as urgency, for whoever draws its colour. An "info" row
-- has none.
-- kinds: { [i] = kind } for lines[i], or nil (the Advice row): a
-- prompt with a kind stands as a card with that kind's icon and its
-- urgency as the card's tone; the kind "more" is the count of the
-- rest, drawn faded; a line with no kind stays a line, as before.
function Advisor.View(lines, title, about, levels, kinds)
    if type(title) ~= "string" or title == "" then title = Advisor.Title() end
    -- Lead section 408: the title stands in the title bar only (no header
    -- part repeats it), a long line wraps and is never cut, and the window
    -- is as tall as its lines.
    local view = { id = Advisor.KIT_ID, title = title, children = {},
        width = Advisor.KIT_WIDTH, point = Advisor.DEFAULT_POINT,
        escape = false, fit = true }
    local kids = view.children
    if type(about) == "string" and about:find("%S") then
        kids[#kids + 1] = { kind = "section", key = "about", text = about }
    end
    local cards = 0
    if type(lines) == "table" then
        for i = 1, #lines do
            local text = lines[i]
            if type(text) == "string" and text:find("%S") then
                local level = type(levels) == "table" and levels[i] or nil
                local pressing = nil
                if level ~= nil and level ~= Advisor.LEVELS[1] and LEVEL[level] then pressing = level end
                local kind = type(kinds) == "table" and kinds[i] or nil
                if kind == "more" then
                    kids[#kids + 1] = { kind = "fadedLine", key = "more", text = text }
                elseif type(kind) == "string" then
                    local card = { kind = "card", key = "prompt" .. i, text = text, icon = Advisor.KIND_ICONS[kind], wrap = true }
                    if pressing ~= nil then
                        card.urgency = pressing
                        card.tone = TONE[pressing]
                    end
                    kids[#kids + 1] = card
                    cards = cards + 1
                else
                    local line = { kind = "line", key = "prompt" .. i, text = text, wrap = true }
                    if pressing ~= nil then line.urgency = pressing end
                    kids[#kids + 1] = line
                end
            end
        end
    end
    view.height = Advisor.KitHeight(#kids)
    if cards > 0 then
        -- A card stands taller than a line: grow the window by the
        -- difference, once per card (a first guess; the window fits).
        local size = ns.Kit.look.size
        local cardMin = size.cardMin
        if type(cardMin) ~= "number" then cardMin = size.lineHeight end
        view.height = view.height + cards * (cardMin - size.lineHeight)
    end
    return view
end

-- Declares the module on kernel k. Usable at once: prompts added before the
-- module starts are kept and shown when it starts.
function Advisor.Declare(k, diag)
    local api = {}
    local entries = {}         -- { id, text, priority, seq }
    local seq = 0
    -- host: the kit window with the plain panel behind it (UI/KitHost.lua).
    -- closed: the player closed the window; a new prompt opens it again.
    local host, ctx, cancelWatch
    local closed = false
    -- asked: the player opened the panel on purpose (G32); the window then
    -- shows with no prompt and is not held back. Closing it ends the ask.
    local asked = false
    local watchers = {}        -- by token: fn(id, text)
    local watchSeq = 0
    -- C-46: the hidden keys as saved, { [key] = { text, at } }. nil before
    -- the module starts; false when what is saved there is not a table
    -- (then nothing is hidden and nothing is written over).
    local hid

    local function isHidden(id)
        return type(hid) == "table" and hid[Advisor.KeyOf(id)] ~= nil
    end

    -- The prompts the player has not hidden, in shown order.
    local function sorted()
        local list = {}
        for i = 1, #entries do
            if not isHidden(entries[i].id) then list[#list + 1] = entries[i] end
        end
        table.sort(list, function(a, b)
            if a.priority ~= b.priority then return a.priority > b.priority end
            return a.seq < b.seq
        end)
        return list
    end

    local function enabled()
        -- Off only when the player turned it off; a missing row is on.
        return ctx ~= nil and ctx.settings:get(Advisor.SETTING) ~= false
    end

    -- G55 (UI/Reveal.lua): a new player's panel waits for its stage. No
    -- reveal module, or any doubt: shown.
    local function held()
        local R = ns.Reveal
        return type(R) == "table" and type(R.Open) == "function" and R.Open(k, "advice") == false
    end

    local function render()
        if not host then return end
        if #entries == 0 and not asked then closed = false end
        -- C-46 (lead section 671): with every prompt hidden there is
        -- nothing to show, the same as with none.
        local list = sorted()
        if not enabled() or (not asked and (#list == 0 or held())) then
            host.show(false)
            return
        end
        local lines = {}
        local levels = {}
        local kinds = {}
        for i = 1, math.min(#list, Advisor.MAX_SHOWN) do
            lines[i] = list[i].text
            levels[i] = list[i].urgency
            kinds[i] = Advisor.KindOf(list[i].id)
        end
        if #list == 0 then lines[1] = Advisor.NONE end
        if #list > Advisor.MAX_SHOWN then
            lines[#lines + 1] = Advisor.MoreText(#list - Advisor.MAX_SHOWN)
            kinds[#kinds + 1] = "more"
        end
        -- The plain panel has no title of its own: the title is its first line.
        local title = Advisor.Title(k.id or ns.id)
        local rows = { title }
        for i = 1, #lines do rows[#rows + 1] = lines[i] end
        -- Every time it shows it says what it is (section 578 point A).
        host.draw(Advisor.View(lines, title, Advisor.ABOUT, levels, kinds), rows)
        if not closed then host.show(true) end
    end

    local function find(id)
        for i = 1, #entries do
            if entries[i].id == id then return i end
        end
        return nil
    end

    function api.Add(id, text, priority, urgency)
        local problem = checkId(id)
        if problem then return false, problem end
        if type(text) ~= "string" or not text:find("%S") then
            return false, "the text must be a non-empty string"
        end
        if priority == nil then priority = 0 end
        if not isFinite(priority) then return false, "the priority must be a number" end
        if urgency ~= nil and not (type(urgency) == "string" and LEVEL[urgency]) then
            return false, "the urgency must be info, soon or now"
        end
        -- "info" is the level of a prompt that says none: not kept.
        if urgency == Advisor.LEVELS[1] then urgency = nil end
        local at = find(id)
        if at then
            entries[at].text = text
            entries[at].priority = priority
            entries[at].urgency = urgency
        else
            seq = seq + 1
            entries[#entries + 1] = { id = id, text = text, priority = priority, urgency = urgency, seq = seq }
            -- A new prompt opens a window the player closed; a replaced
            -- text does not, and neither does one the player hid.
            if not isHidden(id) then closed = false end
        end
        render()
        if not at and not isHidden(id) then
            local tokens = {}
            for token in pairs(watchers) do tokens[#tokens + 1] = token end
            table.sort(tokens)
            for _, token in ipairs(tokens) do
                local fn = watchers[token]
                if fn then pcall(fn, id, text) end
            end
        end
        return true
    end

    function api.Watch(fn)
        if type(fn) ~= "function" then return nil end
        watchSeq = watchSeq + 1
        local token = watchSeq
        watchers[token] = fn
        return function() watchers[token] = nil end
    end

    function api.Remove(id)
        if checkId(id) then return false end
        local at = find(id)
        if not at then return false end
        table.remove(entries, at)
        render()
        return true
    end

    function api.List()
        local out = {}
        for i, e in ipairs(sorted()) do
            out[i] = { id = e.id, text = e.text, priority = e.priority, urgency = e.urgency }
        end
        return out
    end

    -- C-46: writes the hidden keys, a new table, never the stored one.
    local function keep(now)
        if not ctx then return false end
        local ok, done = pcall(ctx.store.set, ctx.store, "char", Advisor.HIDDEN, now)
        if not ok or done ~= true then return false end
        hid = now
        return true
    end

    local function copyHid()
        local now, n = {}, 0
        for key, v in pairs(hid) do now[key], n = v, n + 1 end
        return now, n
    end

    function api.Hide(id)
        local problem = checkId(id)
        if problem then return false, problem end
        local at = find(id)
        if not at then return false, Advisor.NO_PROMPT end
        if hid == nil then return false, Advisor.NOT_READY end
        if hid == false then return false, Advisor.UNREAD end
        local key = Advisor.KeyOf(id)
        if hid[key] ~= nil then return false, Advisor.HID end
        local now, n = copyHid()
        if n >= Advisor.MAX_HIDDEN then return false, Advisor.FULL end
        local when
        if type(ctx.client) == "table" and type(ctx.client.clock) == "function" then
            local ok, t = pcall(ctx.client.clock)
            if ok and isFinite(t) then when = t end
        end
        now[key] = { text = entries[at].text, at = when }
        if not keep(now) then return false, Advisor.UNSAVED end
        render()
        return true
    end

    function api.Unhide(key)
        if type(key) ~= "string" or type(hid) ~= "table" or hid[key] == nil then return false end
        local now = copyHid()
        now[key] = nil
        if not keep(now) then return false end
        render()
        return true
    end

    function api.Hidden()
        local out = {}
        if type(hid) ~= "table" then return out end
        local keys = {}
        for key in pairs(hid) do
            if type(key) == "string" then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local v = type(hid[key]) == "table" and hid[key] or {}
            local row = { key = key, text = v.text, at = v.at, applies = false }
            for i = 1, #entries do
                if Advisor.KeyOf(entries[i].id) == key then
                    row.applies, row.id, row.text = true, entries[i].id, entries[i].text
                    break
                end
            end
            out[#out + 1] = row
        end
        return out
    end

    function api.Open()
        if not host or not ctx then return false, Advisor.NOT_READY end
        if not enabled() then return false, Advisor.OFF end
        -- The plain panel has no close button: asked again while it shows
        -- on purpose, it hides, as a closed kit window does.
        if asked and host.plain() and host.shown() then
            asked = false
            closed = true
            host.show(false)
            return true
        end
        asked = true
        closed = false
        render()
        return true
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Advisor.WORD] = function()
            local ok, why = api.Open()
            if not ok and type(k.client) == "table" and type(k.client.print) == "function" then
                k.client.print((k.id or ns.id).title .. ": " .. tostring(why))
            end
            return ok
        end
        if type(diag.help) == "table" then diag.help[Advisor.WORD] = Advisor.HELP end
    end

    local function stop()
        if cancelWatch then
            cancelWatch()
            cancelWatch = nil
        end
        if host then host.show(false) end
    end

    k:Module({
        name = Advisor.NAME,
        needs = { "client", "store", "settings" },
        provides = { Add = api.Add, Remove = api.Remove, List = api.List, Watch = api.Watch,
            Open = api.Open, Hide = api.Hide, Unhide = api.Unhide, Hidden = api.Hidden },
        start = function(c)
            ctx = c
            -- C-46: what the character hid. Not a table: nothing is hidden,
            -- and it is not written over.
            local okHid, saved = pcall(c.store.get, c.store, "char", Advisor.HIDDEN)
            if okHid and saved == nil then
                hid = {}
            elseif okHid and type(saved) == "table" then
                hid = saved
            else
                hid = false
            end
            -- Follow the setting while running: turning it off hides the
            -- panel at once, turning it on shows the kept prompts.
            local row = c.settings:row(Advisor.SETTING)
            local scope = row and row.scope or "char"
            local path = row and row.path or ("settings." .. Advisor.SETTING)
            cancelWatch = c.store:watch(scope, path, function() render() end)
            -- G55: a stage shown or reset draws the panel again.
            local R = ns.Reveal
            if type(R) == "table" and type(R.EVENT) == "string" and type(c.bus) == "table" then
                c.bus:on(Advisor.NAME, R.EVENT, function() render() end)
            end
            -- The frame last, after everything that can switch the module off.
            local id = k.id or ns.id
            local panel = c.client.panel({ name = id.framePrefix .. "Advisor",
                width = Advisor.WIDTH, height = Advisor.HEIGHT })
            -- The plain panel as the host draws it: its lines, and whether
            -- it is shown (the client's panel does not say).
            local plain
            if panel then
                panel.show(false)
                panel.place(Advisor.DEFAULT_POINT)
                local open = false
                plain = {
                    draw = function(lines) panel.setLines(lines) end,
                    show = function(on)
                        open = on == true
                        panel.show(open)
                    end,
                    shown = function() return open end,
                }
            end
            host = ns.KitHost.New(k, c.client, { name = id.framePrefix .. "AdvisorKit", panel = plain,
                onClose = function()
                    closed = true
                    asked = false
                end })
            render()
        end,
        stop = stop,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.advisor = Advisor.Declare(ns, ns.diag)
Advisor.Add = ns.advisor.Add
Advisor.Remove = ns.advisor.Remove
Advisor.List = ns.advisor.List
Advisor.Watch = ns.advisor.Watch
Advisor.Open = ns.advisor.Open
Advisor.Hide = ns.advisor.Hide
Advisor.Unhide = ns.advisor.Unhide
Advisor.Hidden = ns.advisor.Hidden
