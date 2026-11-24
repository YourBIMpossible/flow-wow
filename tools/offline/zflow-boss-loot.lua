-- Build-time generator of ZFlow/Nav/BossLootData.lua (lead DISPATCH 426).
-- Reads the instance files of a local AllTheThings checkout (MIT; the
-- checkout is never committed) and writes ids only: instance -> boss
-- (encounter id, creature ids) -> item ids. No name, comment, text or code
-- of AllTheThings is written.
--
--   lua zflow-boss-loot.lua <out file> <commit> <build> <list file>
--
-- <list file> names one AllTheThings instance file per line; <build> is the
-- game version the items must exist in ("1.60.1").
--
-- Each file is run in a closed environment: every global it names is a
-- symbol that can be called (giving a node: its name and arguments),
-- indexed, joined or counted with. Nothing of the real Lua library but the
-- plain table, string and math helpers is reachable from the file.
--
-- A boss is an e(<encounter id>, {...}) node, an n(<creature id>, {...})
-- node holding at least one item, or an n(<symbol>, {...}) node that names
-- its creatures (crs / creatureID) and holds items. Quest, zone-drop,
-- vendor, faction, treasure, profession, reward and shared-drop groups are
-- left out. An item with a timeline is kept when the timeline says it
-- exists in <build>; when the timeline cannot be read it is kept and
-- counted.
local OUT, COMMIT, BUILD, LIST = arg[1], arg[2], arg[3], arg[4]
if not (OUT and COMMIT and BUILD and LIST) then
    io.stderr:write("usage: zflow-boss-loot.lua <out file> <commit> <build> <list file>\n")
    os.exit(2)
end

local SKIP = { QUESTS = true, ZONE_DROPS = true, VENDORS = true, FACTIONS = true, ACHIEVEMENTS = true,
    REWARDS = true, PROFESSIONS = true, TREASURES = true, COMMON_BOSS_DROPS = true,
    SILITHID_ROYALTY_SHARED_DROPS = true }

-- Symbols ---------------------------------------------------------------
local symMeta = {}
local function symbol(name) return setmetatable({ __sym = name }, symMeta) end
local function isSym(v) return type(v) == "table" and rawget(v, "__sym") ~= nil end
local function isNode(v) return type(v) == "table" and rawget(v, "__tag") ~= nil end
symMeta.__index = function(t, k) return symbol(rawget(t, "__sym") .. "." .. tostring(k)) end
symMeta.__call = function(t, ...)
    return { __tag = rawget(t, "__sym"), n = select("#", ...), ... }
end
local function same(a) return isSym(a) and a or symbol("?") end
symMeta.__concat = function(a, b) return isSym(a) and a or same(b) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
    symMeta[op] = function(a, b) return isSym(a) and a or same(b) end
end
symMeta.__lt = function() return false end
symMeta.__le = function() return false end
symMeta.__tostring = function(t) return rawget(t, "__sym") end

local function environment()
    local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
        select = select, unpack = unpack, next = next, table = table, string = string, math = math }
    return setmetatable(env, { __index = function(_, k) return symbol(tostring(k)) end })
end

-- Versions --------------------------------------------------------------
local function version(text)
    local a, b, c = tostring(text):match("(%d+)[._](%d+)[._](%d+)")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end
local build = version(BUILD)
if not build then
    io.stderr:write("zflow-boss-loot: build '" .. BUILD .. "' is not a version\n")
    os.exit(2)
end

-- true / false (exists in the build or not), or nil when it cannot be read.
local function exists(timeline)
    if timeline == nil then return true end
    if type(timeline) ~= "table" then return nil end
    local state = true
    local first = true
    for _, entry in ipairs(timeline) do
        local text = isSym(entry) and rawget(entry, "__sym") or (type(entry) == "string" and entry or nil)
        if not text then return nil end
        local word = text:upper():match("(ADDED)") or text:upper():match("(CREATED)")
            or text:upper():match("(REMOVED)") or text:upper():match("(DELETED)")
        local v = version(text)
        if not word or not v then return nil end
        local adds = word == "ADDED" or word == "CREATED"
        if first and adds then state = false end
        first = false
        if v <= build then state = adds end
    end
    return state
end

-- Walk ------------------------------------------------------------------
local counts = { instances = 0, withEncounter = 0, byNpc = 0, noItems = 0, items = 0, timelineKept = 0,
    timelineDropped = 0, timelineUnread = 0, noArea = 0, npcNoItems = 0 }

local function children(body, fn)
    if type(body) ~= "table" then return end
    for _, v in ipairs(body) do fn(v) end
    for _, key in ipairs({ "groups", "g" }) do
        local list = rawget(body, key)
        if type(list) == "table" and not isNode(list) and not isSym(list) then
            for _, v in ipairs(list) do fn(v) end
        end
    end
end

local function head(node) return node[1] end
local function bodyOf(node)
    for i = 2, node.n or #node do
        if type(node[i]) == "table" and not isNode(node[i]) and not isSym(node[i]) then return node[i] end
    end
    return nil
end

local function skipped(node)
    if node.__tag == "q" then return true end
    if node.__tag == "n" and isSym(head(node)) and SKIP[rawget(head(node), "__sym")] then return true end
    return false
end

local function items(node, out, seen)
    local function visit(v)
        if not isNode(v) then return end
        if v.__tag == "i" then
            local id = head(v)
            if type(id) == "number" and not seen[id] then
                local body = bodyOf(v)
                local timeline = body and rawget(body, "timeline") or nil
                local ok = exists(timeline)
                if timeline ~= nil then
                    if ok == nil then counts.timelineUnread = counts.timelineUnread + 1
                    elseif ok then counts.timelineKept = counts.timelineKept + 1
                    else counts.timelineDropped = counts.timelineDropped + 1 end
                end
                if ok ~= false then
                    seen[id] = true
                    out[#out + 1] = id
                end
            end
            return
        end
        if skipped(v) then return end
        for i = 1, v.n or #v do
            if isNode(v[i]) then visit(v[i]) end
        end
        children(bodyOf(v), visit)
    end
    children(bodyOf(node), visit)
    return out
end

local function creatures(node, first)
    local out, seen = {}, {}
    local function add(v)
        if type(v) == "number" and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    add(first)
    local body = bodyOf(node)
    if body then
        add(rawget(body, "creatureID"))
        add(rawget(body, "cr"))
        local crs = rawget(body, "crs")
        if type(crs) == "table" and not isSym(crs) then
            for _, v in ipairs(crs) do add(v) end
        end
    end
    return out
end

local function bossOf(node)
    local h = head(node)
    if node.__tag == "e" and type(h) == "number" then
        return { e = h, npcs = creatures(node, nil), items = items(node, {}, {}) }
    end
    if node.__tag == "n" and type(h) == "number" then
        local list = items(node, {}, {})
        if #list == 0 then
            counts.npcNoItems = counts.npcNoItems + 1
            return false
        end
        return { npcs = creatures(node, h), items = list }
    end
    if node.__tag == "n" and isSym(h) then
        local npcs = creatures(node, nil)
        if #npcs > 0 then
            local direct, body = false, bodyOf(node)
            children(body, function(v) if isNode(v) and v.__tag == "i" then direct = true end end)
            if direct then return { npcs = npcs, items = items(node, {}, {}) } end
        end
    end
    return nil
end

local instances = {}

local function bosses(node, into)
    local function visit(v)
        if not isNode(v) or skipped(v) or v.__tag == "i" then return end
        local boss = bossOf(v)
        if boss then
            into[#into + 1] = boss
            return
        end
        if boss == false then return end
        for i = 1, v.n or #v do
            if isNode(v[i]) then visit(v[i]) end
        end
        children(bodyOf(v), visit)
    end
    children(bodyOf(node), visit)
end

local function find(v)
    if not isNode(v) then return end
    if (v.__tag == "instanceroot" or v.__tag == "inst") and type(head(v)) == "number" then
        local body = bodyOf(v)
        local area = body and rawget(body, "zoneTextAreaID") or nil
        local one = { id = head(v), area = type(area) == "number" and area or nil, bosses = {} }
        bosses(v, one.bosses)
        instances[#instances + 1] = one
        return
    end
    for i = 1, v.n or #v do
        if isNode(v[i]) then find(v[i]) end
    end
    children(bodyOf(v), find)
end

-- Run the files ---------------------------------------------------------
local failed = {}
for path in io.lines(LIST) do
    if path ~= "" then
        local chunk, err = loadfile(path)
        if not chunk then
            failed[#failed + 1] = path .. ": " .. tostring(err)
        else
            local env = environment()
            local roots = {}
            -- A file's top-level calls are its roots: kept as they are made.
            getmetatable(env).__index = function(_, k)
                local s = symbol(tostring(k))
                if k == "root" or k == "instanceroot" then
                    return function(...)
                        local node = { __tag = tostring(k), n = select("#", ...), ... }
                        roots[#roots + 1] = node
                        return node
                    end
                end
                return s
            end
            setfenv(chunk, env)
            local ok, why = pcall(chunk)
            if not ok then failed[#failed + 1] = path .. ": " .. tostring(why) end
            for _, r in ipairs(roots) do find(r) end
        end
    end
end

table.sort(instances, function(a, b) return a.id < b.id end)
for _, one in ipairs(instances) do
    counts.instances = counts.instances + 1
    if not one.area then counts.noArea = counts.noArea + 1 end
    for _, b in ipairs(one.bosses) do
        if b.e then counts.withEncounter = counts.withEncounter + 1 else counts.byNpc = counts.byNpc + 1 end
        if #b.items == 0 then counts.noItems = counts.noItems + 1 end
        counts.items = counts.items + #b.items
    end
end

-- Write -----------------------------------------------------------------
local function list(t)
    local parts = {}
    for i, v in ipairs(t) do parts[i] = tostring(v) end
    return table.concat(parts, ",")
end

local function wrapped(prefix, t, indent)
    local lines, line = {}, prefix
    for i, v in ipairs(t) do
        local piece = tostring(v) .. (i < #t and "," or "")
        if #line + #piece > 110 then
            lines[#lines + 1] = line
            line = indent
        end
        line = line .. piece
    end
    lines[#lines + 1] = line
    return table.concat(lines, "\r\n")
end

local o = {}
local function w(s) o[#o + 1] = s end
w("-- GENERATED by tools/zflow-boss-loot.ps1. Do not edit by hand: run the tool again.")
w("-- Which items each dungeon and raid boss can drop, as ids only (lead")
w("-- DISPATCH 426). Made from the instance files of AllTheThings")
w("-- (github.com/ATTWoWAddon/AllTheThings, MIT licence; notice in")
w("-- THIRD_PARTY.md), commit " .. COMMIT .. ", for game version " .. BUILD .. ".")
w("-- Holds numbers only: no name, text or code of AllTheThings.")
w("--")
w("-- Counts: " .. counts.instances .. " instances (" .. counts.noArea .. " without an area id); "
    .. counts.withEncounter .. " bosses with an encounter id;")
w("-- " .. counts.byNpc .. " bosses by creature only; " .. counts.noItems .. " bosses with no items; "
    .. counts.items .. " boss item entries.")
w("-- Items with a timeline: " .. counts.timelineKept .. " kept, " .. counts.timelineDropped
    .. " left out (not in this version), " .. counts.timelineUnread .. " kept unread.")
w("--")
w("--   ns.BossLootData.instances = { { id = <instance id>, area = <area id or nil>,")
w("--       bosses = { { e = <encounter id or nil>, npcs = { <creature id> }, items = { <item id> } } } } }")
w("local _, ns = ...")
w("")
w("ns.BossLootData = {")
w("    commit = \"" .. COMMIT .. "\",")
w("    build = \"" .. BUILD .. "\",")
w("    instances = {")
for _, one in ipairs(instances) do
    w("        { id = " .. one.id .. (one.area and (", area = " .. one.area) or "") .. ", bosses = {")
    for _, b in ipairs(one.bosses) do
        w("            { " .. (b.e and ("e = " .. b.e .. ", ") or "") .. "npcs = { " .. list(b.npcs) .. " },")
        w(wrapped("              items = { ", b.items, "                ") .. " } },")
    end
    w("        } },")
end
w("    },")
w("}")
w("")

local f = assert(io.open(OUT, "wb"))
f:write(table.concat(o, "\r\n"))
f:close()

for _, why in ipairs(failed) do io.stderr:write("zflow-boss-loot: could not run " .. why .. "\n") end
print(string.format(
    "zflow-boss-loot: %d instances (%d without an area id), %d bosses with an encounter id, %d by creature only, "
    .. "%d with no items, %d item entries; timeline: %d kept, %d left out, %d kept unread; "
    .. "%d creature groups without items left out; %d files failed",
    counts.instances, counts.noArea, counts.withEncounter, counts.byNpc, counts.noItems, counts.items,
    counts.timelineKept, counts.timelineDropped, counts.timelineUnread, counts.npcNoItems, #failed))
os.exit(#failed > 0 and 1 or 0)
