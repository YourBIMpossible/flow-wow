-- Advisor panel (U-A, G32): a small panel listing short prompts that other
-- modules register. Hidden while it has no prompts. The setting row
-- "advisor.panel" turns it off.
--
-- LOOK ONLY. The panel draws text and has no buttons; nothing here acts in
-- the game. A prompt is advice for the player to read, nothing more.
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
--   Advisor.Declare(k) -> api        declares the module on kernel k
--     api.Add, api.Remove, api.List  as above, for that kernel
--   ns.use("advisor") -> { Add, Remove, List, Watch }
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
Advisor.MAX_SHOWN = 5
Advisor.WIDTH, Advisor.HEIGHT = 300, 120
Advisor.DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -220, -200 }

local function isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function checkId(id)
    if type(id) ~= "string" or id == "" then return "the id must be a non-empty string" end
    return nil
end

-- Declares the module on kernel k. Usable at once: prompts added before the
-- module starts are kept and shown when it starts.
function Advisor.Declare(k)
    local api = {}
    local entries = {}         -- { id, text, priority, seq }
    local seq = 0
    local panel, ctx, cancelWatch
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

    local function render()
        if not panel then return end
        if not enabled() or #entries == 0 then
            panel.show(false)
            return
        end
        local list = sorted()
        local lines = {}
        for i = 1, math.min(#list, Advisor.MAX_SHOWN) do lines[i] = list[i].text end
        if #list > Advisor.MAX_SHOWN then
            lines[#lines + 1] = "and " .. (#list - Advisor.MAX_SHOWN) .. " more"
        end
        panel.setLines(lines)
        panel.show(true)
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

    local function stop()
        if cancelWatch then
            cancelWatch()
            cancelWatch = nil
        end
        if panel then panel.show(false) end
    end

    k:Module({
        name = Advisor.NAME,
        needs = { "client", "store", "settings" },
        provides = { Add = api.Add, Remove = api.Remove, List = api.List, Watch = api.Watch },
        start = function(c)
            ctx = c
            -- Follow the setting while running: turning it off hides the
            -- panel at once, turning it on shows the kept prompts.
            local row = c.settings:row(Advisor.SETTING)
            local scope = row and row.scope or "char"
            local path = row and row.path or ("settings." .. Advisor.SETTING)
            cancelWatch = c.store:watch(scope, path, function() render() end)
            -- The frame last, after everything that can switch the module off.
            local id = k.id or ns.id
            panel = c.client.panel({ name = id.framePrefix .. "Advisor",
                width = Advisor.WIDTH, height = Advisor.HEIGHT })
            if panel then
                panel.show(false)
                panel.place(Advisor.DEFAULT_POINT)
            end
            render()
        end,
        stop = stop,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.advisor = Advisor.Declare(ns)
Advisor.Add = ns.advisor.Add
Advisor.Remove = ns.advisor.Remove
Advisor.List = ns.advisor.List
Advisor.Watch = ns.advisor.Watch
