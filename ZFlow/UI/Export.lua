local _, ns = ...

-- S25 export: your character as lines a script can read. Ported from legacy
-- Flow's Modules/Export.lua (0.35.196), which ran on this client; research:
-- WoW/from-plexy/RESEARCH-export.md.
--
-- One line a record, the same format legacy Flow wrote and
-- tools/route-check.ps1 reads: E^<kind>^key=value^key=value ... (text last).
-- Fields are split by "^" because the game reads "|" in a chat line as the
-- start of a colour or link code; no "^" inside a value. Kinds written here:
--   export  the version of this format, the game time, the addon
--   you     class, faction, level, money, bag room, where you are
--   quest   a quest in your log;   obj  one of its objectives
--   skill   a profession and its rank, as last seen in its window
--   end     how many lines there are
-- Legacy Flow's goal, plan, opt, flight, fm, gate, ride and improve records
-- need Z-Flow's route in a settled shape; they are not written yet (see the
-- note). Nothing personal is in it but your class: no name, no realm.
--
--   <slash> export        keep the lines in this character's saved file
--                         (written at the next /reload) and say how many
--   <slash> export dump   also print them (copy with <slash> copy)
--
-- Read only: it reads the game and writes its own saved lines, nothing else.
--
--   Export.Clean(v) -> text with nothing that breaks a line or a field
--   Export.Line(kind, fields) -> one record; fields { { key, value }, ... },
--     nil values left out
--   Export.Parse(line) -> { kind =, key = value, ... } or nil
--   Export.Lines(r) -> every record, from the reads r (Export.Read's shape)
--   Export.Read(client, store) -> the reads, each nil when not read
--   Export.Declare(k, diag) -> api   (api.lines() -> the last lines made)
local X = {}
ns.Export = X

X.VERSION = 1
X.NAME = "export"
X.WORD = "export"
X.PATH = "export"
X.HELP = "your class, quests and professions as lines a script reads (export dump prints them)"

-- A value as text with nothing that breaks a line or a field.
function X.Clean(v)
    if v == nil then return "" end
    if type(v) == "boolean" then return v and "1" or "0" end
    if type(v) == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "" end
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.1f", v)
    end
    local s = tostring(v)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("[|%^\r\n]", " "):gsub("%s+", " ")
    return s
end

function X.Line(kind, fields)
    local parts = { "E", kind }
    for _, f in ipairs(fields) do
        if f[2] ~= nil then parts[#parts + 1] = f[1] .. "=" .. X.Clean(f[2]) end
    end
    return table.concat(parts, "^")
end

function X.Parse(line)
    if type(line) ~= "string" or line:sub(1, 2) ~= "E^" then return nil end
    local out, first = {}, true
    for part in line:sub(3):gmatch("[^%^]+") do
        if first then
            out.kind, first = part, false
        else
            local key, v = part:match("^([%w_]+)=(.*)$")
            if key then out[key] = v end
        end
    end
    return out
end

local function num(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
    return nil
end

function X.Lines(r)
    r = type(r) == "table" and r or {}
    local out = {}
    local function add(kind, fields) out[#out + 1] = X.Line(kind, fields) end
    add("export", { { "v", X.VERSION }, { "at", num(r.at) }, { "addon", r.addon } })

    local pos = type(r.position) == "table" and r.position or {}
    local zone = type(r.zone) == "table" and r.zone or {}
    add("you", {
        { "class", r.class }, { "faction", r.faction }, { "level", num(r.level) }, { "money", num(r.money) },
        { "bagsfree", num(r.bagsFree) }, { "cont", num(zone.cont) }, { "zone", num(zone.zone) },
        { "map", num(pos.map) }, { "x", num(pos.x) and pos.x * 100 or nil }, { "y", num(pos.y) and pos.y * 100 or nil },
    })

    for _, q in ipairs(type(r.quests) == "table" and r.quests or {}) do
        if type(q) == "table" then
            local objs = type(q.objectives) == "table" and q.objectives or {}
            add("quest", { { "id", num(q.id) }, { "complete", q.complete == true }, { "failed", q.failed == true or nil },
                { "n", #objs }, { "title", q.title } })
            for i, o in ipairs(objs) do
                if type(o) == "table" then
                    add("obj", { { "quest", num(q.id) }, { "i", i }, { "done", o.done == true }, { "text", o.text } })
                end
            end
        end
    end

    local skills = type(r.skills) == "table" and r.skills or {}
    local names = {}
    for name, s in pairs(skills) do
        if type(name) == "string" and type(s) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local s = skills[name]
        add("skill", { { "rank", num(s.skill) }, { "max", num(s.max) }, { "name", name } })
    end

    add("end", { { "lines", #out + 1 } })
    return out
end

local function read(client, name)
    local f = client[name]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f)
    if ok then return v end
    return nil
end

function X.Read(client, store)
    local free
    local bags = read(client, "bags")
    if type(bags) == "table" then
        free = 0
        for _, b in ipairs(bags) do
            if type(b) == "table" and num(b.free) then free = free + b.free end
        end
    end
    local skills = store and store:get("char", "learned.facts.profSkill")
    return {
        at = read(client, "clock"), class = read(client, "class"), faction = read(client, "faction"),
        level = read(client, "level"), money = read(client, "money"), bagsFree = free,
        zone = read(client, "zone"), position = read(client, "position"), quests = read(client, "questLog"),
        skills = type(skills) == "table" and skills or nil,
    }
end

function X.Declare(k, diag)
    local api = {}
    local ctx, made = nil, nil
    function api.lines() return made end

    if diag and type(diag.commands) == "table" then
        diag.commands[X.WORD] = function(arg)
            local function say(s) k.client.print(k.id.title .. ": " .. s) end
            if not ctx then say("export: not started yet") return end
            local r = X.Read(ctx.client, ctx.store)
            r.addon = k.id.addon
            local lines = X.Lines(r)
            made = lines
            local copy = {}
            for i, l in ipairs(lines) do copy[i] = l end
            if ctx.store:set("char", X.PATH, { at = num(r.at), lines = copy }) then
                say(string.format("export: %d lines (your class, quests and professions), saved for this character at the next /reload.", #lines))
            else
                say(string.format("export: %d lines; they could not be saved (export dump prints them).", #lines))
            end
            if type(arg) == "string" and arg:lower():find("dump", 1, true) then
                for _, l in ipairs(lines) do k.client.print(l) end
            end
        end
        if type(diag.help) == "table" then diag.help[X.WORD] = X.HELP end
    end

    k:Module({
        name = X.NAME,
        needs = { "client", "store" },
        provides = { Lines = api.lines },
        start = function(c) ctx = c end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.export = X.Declare(ns, ns.diag)
