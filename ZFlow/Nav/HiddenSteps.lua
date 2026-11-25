local _, ns = ...

-- Parity row A1-28, the data half (lead section 794): hide a quest step,
-- list the hidden ones and unhide them, as Flow's Modules/Nav/Nav.lua
-- (at origin/craft-repeat: N:Hide and N:Unhide :1228-1237; the route leaving hidden steps out :609;
-- "Unhide all steps (N)" in its menu). Saved per character at PATH as
-- { [step key] = label }: Z-Flow's own data; nothing in the game changes.
--   key  = HS.KeyOf(step)            "q:<quest>:<objective>" or
--                                    "q:<quest>:in"; nil when not a quest step
--   ok   = HS.Hide(store, key, label) / HS.Unhide(store, key)
--   n    = HS.UnhideAll(store)        how many came back
--   list = HS.List(store)             { { key, label } } by label
--   HS.IsHidden(store, key) -> bool   HS.Filter(steps, store) -> the rest
--   <slash> hidden                   the list, numbered
--   <slash> hidden show <n>|all      bring one, or all, back
-- The arrow's "Hide this step" click (UI/Arrow.lua) and the route's filter
-- (Nav/TripRoute.lua) are in held files: a LEAD NEED (call HS.Hide with
-- HS.KeyOf(step); pass the route's steps through HS.Filter). Not tested in
-- game.
ns.Nav = ns.Nav or {}
local HS = {}
ns.Nav.HiddenSteps = HS

HS.NAME = "hiddenSteps"
HS.PATH = "state.nav.hidden"
HS.WORD = "hidden"
HS.HELP = "the quest steps you hid: hidden show <n> or hidden show all brings them back"
HS.NONE = "No step is hidden."
HS.HEAD = "Hidden steps (%d):"
HS.BACK = "Back on your route: %s."
HS.ALL_BACK = "%d step(s) back on your route."
HS.NO_SUCH = "There is no hidden step %s."
HS.NOT_BACK = "Could not save the change: %s is still hidden."

function HS.KeyOf(step)
    if type(step) ~= "table" or step.quest == nil then return nil end
    if step.objective ~= nil and step.turnIn ~= true then
        return "q:" .. tostring(step.quest) .. ":" .. tostring(step.objective)
    end
    return "q:" .. tostring(step.quest) .. ":in"
end

local function read(store)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, "char", HS.PATH)
    if ok and type(v) == "table" then return v end
    return nil
end

local function copy(store)
    local out = {}
    for k, v in pairs(read(store) or {}) do out[k] = v end
    return out
end

local function write(store, t)
    local ok, done = pcall(store.set, store, "char", HS.PATH, t)
    return ok and done == true
end

function HS.Hide(store, key, label)
    if type(key) ~= "string" or key == "" or type(store) ~= "table" or type(store.set) ~= "function" then return false end
    local t = copy(store)
    local words = key
    if type(label) == "string" and label ~= "" then words = label end
    t[key] = words
    return write(store, t)
end

function HS.Unhide(store, key)
    local t = copy(store)
    if key == nil or t[key] == nil then return false end
    t[key] = nil
    return write(store, t)
end

function HS.UnhideAll(store)
    local n = 0
    for _ in pairs(read(store) or {}) do n = n + 1 end
    if n == 0 then return 0 end
    if not write(store, {}) then return 0 end
    return n
end

function HS.List(store)
    local out = {}
    for key, label in pairs(read(store) or {}) do
        if type(key) == "string" then out[#out + 1] = { key = key, label = tostring(label) } end
    end
    table.sort(out, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.key < b.key
    end)
    return out
end

function HS.IsHidden(store, key)
    local t = read(store)
    return t ~= nil and key ~= nil and t[key] ~= nil
end

function HS.Filter(steps, store)
    if type(steps) ~= "table" then return {} end
    local t = read(store)
    if not t then return steps end
    local out = {}
    for _, s in ipairs(steps) do
        local key = HS.KeyOf(s)
        if key == nil or t[key] == nil then out[#out + 1] = s end
    end
    return out
end

function HS.Declare(k, diag)
    local ctx
    k:Module({
        name = HS.NAME,
        needs = { "client", "store" },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    if diag and type(diag.commands) == "table" then
        diag.commands[HS.WORD] = function(rest)
            if not ctx then return end
            local function say(line) ctx.client.print(ns.id.title .. ": " .. line) end
            local arg = tostring(rest or ""):lower():match("^%s*show%s+(%S+)")
            local list = HS.List(ctx.store)
            if arg == "all" then
                say(HS.ALL_BACK:format(HS.UnhideAll(ctx.store)))
                return
            elseif arg then
                local n = tonumber(arg)
                local e = nil
                if n then e = list[n] end
                if not e then say(HS.NO_SUCH:format(arg)) return end
                -- A refused save brings nothing back, and says so.
                if HS.Unhide(ctx.store, e.key) then
                    say(HS.BACK:format(e.label))
                else
                    say(HS.NOT_BACK:format(e.label))
                end
                return
            end
            if #list == 0 then say(HS.NONE) return end
            say(HS.HEAD:format(#list))
            for i, e in ipairs(list) do ctx.client.print("  " .. i .. ". " .. e.label) end
        end
        if type(diag.help) == "table" then diag.help[HS.WORD] = HS.HELP end
    end
end

-- The addon's own: declared when this file loads.
HS.Declare(ns, ns.diag)
