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
--   Advisor.Add(id, text, priority) -> true | false, reason
--     id        non-empty string, the caller's own name for the prompt
--               ("l6c.repair"). Adding an id that is there replaces its
--               text and priority; it never makes a second line.
--     text      non-empty string, one line as the player reads it
--     priority  number, higher shows first; nil is 0. Equal priorities
--               keep the order they were first added in.
--     Bad arguments are refused with a reason and change nothing.
--   Advisor.Remove(id) -> true when the prompt was there, else false
--   Advisor.List()     -> copies, in shown order: { { id, text, priority }, ... }
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
-- Reads: none from the game. Writes: none.
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
Advisor.KIT_ID = "Advisor"
Advisor.KIT_WIDTH, Advisor.KIT_HEIGHT = 320, 220
-- G32: the panel opened on purpose.
Advisor.NONE = "No advice right now."
Advisor.OFF = "the advice panel is turned off in the settings (Advisor panel)."
Advisor.NOT_READY = "the advice panel is not ready yet."
Advisor.WORD = "advice"
Advisor.HELP = "show the advice panel, even when it has nothing to say"

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

-- Advisor.View(lines, title) -> a kit window spec: a header, then one line for
-- each text, top to bottom. A line that is no text is left out, so it
-- cannot cost the window. Nothing in it can be pressed. Escape does not
-- close it: advice should not go with every Escape.
function Advisor.View(lines, title)
    if type(title) ~= "string" or title == "" then title = Advisor.Title() end
    local view = { id = Advisor.KIT_ID, title = title, children = {},
        width = Advisor.KIT_WIDTH, height = Advisor.KIT_HEIGHT, point = Advisor.DEFAULT_POINT,
        escape = false }
    local kids = view.children
    kids[1] = { kind = "header", title = title }
    if type(lines) ~= "table" then return view end
    for i = 1, #lines do
        local text = lines[i]
        if type(text) == "string" and text:find("%S") then
            kids[#kids + 1] = { kind = "line", key = "prompt" .. i, text = text }
        end
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

    local function sorted()
        local list = {}
        for i = 1, #entries do list[i] = entries[i] end
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
        if not enabled() or (not asked and (#entries == 0 or held())) then
            host.show(false)
            return
        end
        local list = sorted()
        local lines = {}
        for i = 1, math.min(#list, Advisor.MAX_SHOWN) do lines[i] = list[i].text end
        if #list == 0 then lines[1] = Advisor.NONE end
        if #list > Advisor.MAX_SHOWN then
            lines[#lines + 1] = "and " .. (#list - Advisor.MAX_SHOWN) .. " more"
        end
        -- The plain panel has no title of its own: the title is its first line.
        local title = Advisor.Title(k.id or ns.id)
        local rows = { title }
        for i = 1, #lines do rows[i + 1] = lines[i] end
        host.draw(Advisor.View(lines, title), rows)
        if not closed then host.show(true) end
    end

    local function find(id)
        for i = 1, #entries do
            if entries[i].id == id then return i end
        end
        return nil
    end

    function api.Add(id, text, priority)
        local problem = checkId(id)
        if problem then return false, problem end
        if type(text) ~= "string" or not text:find("%S") then
            return false, "the text must be a non-empty string"
        end
        if priority == nil then priority = 0 end
        if not isFinite(priority) then return false, "the priority must be a number" end
        local at = find(id)
        if at then
            entries[at].text = text
            entries[at].priority = priority
        else
            seq = seq + 1
            entries[#entries + 1] = { id = id, text = text, priority = priority, seq = seq }
            -- A new prompt opens a window the player closed; a replaced
            -- text does not.
            closed = false
        end
        render()
        if not at then
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
            out[i] = { id = e.id, text = e.text, priority = e.priority }
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
            Open = api.Open },
        start = function(c)
            ctx = c
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
