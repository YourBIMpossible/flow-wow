local _, ns = ...
-- Z-Flow activities and route lanes (S38, lead section 395 item 6): the
-- trip's stops (Nav/Trip.lua) grouped by what the player does there:
-- questing, gathering, profession trainer, repair and vendor, dungeon. One
-- summary line ("Questing: 3 stops · Gathering: 4 Herbalism nodes on the
-- way") and each stop tagged with its lane. LOOK ONLY: nothing moves,
-- targets, casts or sends. A stop whose lane is not known gets no tag, and
-- a lane with nothing in it is not said.
--
-- Gathering is the nodes the player gathered themselves (Nav/Nodes.lua,
-- account N.Nodes.PATH) on the maps of the trip's stops, of the player's
-- own gathering professions (client.professions). Nothing else is guessed.
--
-- Pure:
--   A.LaneOf(stop) -> lane key or nil
--   A.Group(stops) -> { { lane, label, stops = { n, ... } }, ... } in A.ORDER
--   A.Gather(nodes, maps, profs) -> { { prof, n }, ... } sorted by prof
--   A.Summary(groups, gather) -> line or nil
--   A.Lines(stops, gather) -> lines
-- Word "lanes" says them. Module "activities" provides Lines. Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local A = {}
N.Activities = A

A.NAME = "activities"
A.WORD = "lanes"
A.HELP = "the trip's stops grouped by what you do there: questing, gathering, trainer, repair and vendor, dungeon"
A.SEP = " \194\183 "
A.EMPTY = "No stops on the trip; trip add ... puts one on."
A.ORDER = { "quest", "gather", "trainer", "service", "dungeon" }
A.LABELS = {
    quest = "Questing", gather = "Gathering", trainer = "Profession trainer",
    service = "Repair and vendor", dungeon = "Dungeon",
}
-- Trip stop kind -> lane. "here" and "flight" are places, not activities.
A.KIND_LANE = {
    giver = "quest", trainer = "trainer", dungeon = "dungeon",
    vendor = "service", repair = "service", bank = "service", inn = "service", mail = "service",
}

function A.LaneOf(stop)
    if type(stop) ~= "table" or type(stop.kind) ~= "string" then return nil end
    return A.KIND_LANE[stop.kind]
end

function A.Group(stops)
    local by = {}
    for i, s in ipairs(type(stops) == "table" and stops or {}) do
        local lane = A.LaneOf(s)
        if lane then
            by[lane] = by[lane] or {}
            by[lane][#by[lane] + 1] = i
        end
    end
    local groups = {}
    for _, lane in ipairs(A.ORDER) do
        if by[lane] then groups[#groups + 1] = { lane = lane, label = A.LABELS[lane], stops = by[lane] } end
    end
    return groups
end

function A.Gather(nodes, maps, profs)
    local out = {}
    if type(nodes) ~= "table" or type(maps) ~= "table" or type(profs) ~= "table" then return out end
    local count = {}
    for map in pairs(maps) do
        local list = nodes[map]
        if type(list) == "table" then
            for _, e in ipairs(list) do
                if type(e) == "table" and type(e.prof) == "string" and profs[e.prof] then
                    count[e.prof] = (count[e.prof] or 0) + 1
                end
            end
        end
    end
    for prof, n in pairs(count) do out[#out + 1] = { prof = prof, n = n } end
    table.sort(out, function(a, b) return a.prof < b.prof end)
    return out
end

local function stopsWord(n)
    if n == 1 then return "1 stop" end
    return n .. " stops"
end

local function gatherWords(gather)
    local parts = {}
    for _, g in ipairs(type(gather) == "table" and gather or {}) do
        if type(g) == "table" and type(g.n) == "number" and g.n > 0 then
            parts[#parts + 1] = g.n .. " " .. tostring(g.prof) .. (g.n == 1 and " node" or " nodes")
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ") .. " on the way"
end

function A.Summary(groups, gather)
    local by = {}
    for _, g in ipairs(type(groups) == "table" and groups or {}) do by[g.lane] = g end
    local parts = {}
    for _, lane in ipairs(A.ORDER) do
        if lane == "gather" then
            local words = gatherWords(gather)
            if words then parts[#parts + 1] = A.LABELS.gather .. ": " .. words end
        elseif by[lane] then
            parts[#parts + 1] = A.LABELS[lane] .. ": " .. stopsWord(#by[lane].stops)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, A.SEP)
end

function A.Lines(stops, gather)
    local list = type(stops) == "table" and stops or {}
    if #list == 0 then return { A.EMPTY } end
    local lines = {}
    local summary = A.Summary(A.Group(list), gather)
    if summary then lines[#lines + 1] = summary end
    for i, s in ipairs(list) do
        local line = i .. ". " .. tostring(type(s) == "table" and s.label or "?")
        local lane = A.LaneOf(s)
        if lane then line = line .. " - " .. A.LABELS[lane] end
        lines[#lines + 1] = line
    end
    return lines
end

function A.Declare(k, diag)
    local api = {}
    local ctx

    local function ask(name, ...)
        local c = ctx and ctx.client or k.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function tripStops()
        local trip = k.use and k.use("trip")
        if not (trip and type(trip.List) == "function") then return {} end
        local ok, list = pcall(trip.List)
        if ok and type(list) == "table" then return list end
        return {}
    end

    local function gatherOn(list)
        if not ctx then return {} end
        local maps = {}
        for _, s in ipairs(list) do
            if type(s) == "table" and type(s.place) == "table" and s.place.map ~= nil then maps[s.place.map] = true end
        end
        local path = type(N.Nodes) == "table" and N.Nodes.PATH or nil
        if not path then return {} end
        local ok, nodes = pcall(ctx.store.get, ctx.store, "account", path)
        if not ok then return {} end
        return A.Gather(nodes, maps, ask("professions"))
    end

    function api.Lines()
        local list = tripStops()
        return A.Lines(list, gatherOn(list))
    end

    local function say(lines)
        local c = ctx and ctx.client or k.client
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        for _, line in ipairs(lines) do c.print(id.title .. ": " .. tostring(line)) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[A.WORD] = function() say(api.Lines()) end
        if type(diag.help) == "table" then diag.help[A.WORD] = A.HELP end
    end

    k:Module({
        name = A.NAME,
        needs = { "client", "store" },
        provides = { Lines = api.Lines },
        start = function(c) ctx = c end,
    })
    return api
end

ns.activities = A.Declare(ns, ns.diag)
