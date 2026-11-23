local _, ns = ...
-- Z-Flow gathered nodes (G22, lead dispatch P-NAV): the herb, ore and other
-- nodes the player gathered themselves are remembered where the player
-- stood, per map, for the account, and the nearest of the player's own
-- gathering professions are said, with a way to point the arrow at the
-- nearest (a waypoint, Nav/Waypoint.lua). No node data from anywhere else.
--
-- LOOK ONLY. It reads the loot window the player opened and where the
-- player stands. Nothing is looted, cast, targeted or moved.
--
-- A node is a loot window (client.lootWindow at LOOT_OPENED) whose source
-- is a game object (its GUID begins "GameObject-"), opened by a player who
-- has one of the gathering professions of Rotation/Gather.lua's G.LIST.
-- P-GATHER (zflow-gather-5): its profession is what the client said at that
-- moment, in this order: the player's own gathering cast within
-- X.CAST_WINDOW seconds before the window (UNIT_SPELLCAST_SUCCEEDED, the
-- spell named by client.spellName, X.CAST), else the looted items' class
-- (client.itemInfo: trade goods, herb or metal and stone, X.MATERIAL). A
-- profession the player does not have counts as none. With neither, the
-- window is a chest (or a box, or a quest object) and nothing is kept.
-- Minimap tracking is not used: a gatherer opens chests with it on.
-- Its name is the first gathering material's name (the link, else
-- client.itemInfo), else the first item's name. A node within X.SAME yards
-- of one kept with the same object id or name is that one again.
--
-- Saved, account X.PATH: { [map] = { { x, y, id, name, prof, n, at } } }
--   prof the profession (old nodes saved before zflow-gather-5 may have
--   none: those are shown to every gatherer, as before),
--   x, y shares 0..1 of the map (4 decimals), id the object id or nil, n
--   how many times it was gathered, at the clock of the last time. At most
--   X.PER_MAP a map (the least recently gathered go, X.Cap) and X.MAPS maps.
--
--   X.Cap(list)             keeps the X.PER_MAP most recent, oldest first out
--   X.Declare(k, diag) -> api
-- Not tested in game: LOOT_OPENED, the loot read, the professions read, the
-- cast names and the item class numbers are first guesses.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local X = {}
N.Nodes = X

X.NAME = "nodes"
X.SETTING = "nav.nodes"
X.PATH = "learned.nodes"
X.WORD = "nodes"
X.HELP = "nodes: the nearest nodes you gathered; nodes go points the arrow at the nearest; nodes forget clears them"
X.EVENT = "LOOT_OPENED"
X.SAME = 8          -- yards: a node this close with the same id or name is that node
X.PER_MAP = 200
X.MAPS = 80
X.SHOW = 5          -- nodes said by the word
X.CAST_EVENT = "UNIT_SPELLCAST_SUCCEEDED"   -- unit, castGUID, spellID
X.CAST_WINDOW = 5   -- seconds from a gathering cast to its loot window
-- The gathering spell the client casts on a node, by profession. First
-- guess at the names (the cast bar's words); not seen in game.
X.CAST = { ["Herb Gathering"] = "Herbalism", ["Mining"] = "Mining" }
-- Trade goods (classID 7): subclass 9 herb, 7 metal and stone. The
-- client's own numbers; first guess, not seen in game.
X.MATERIAL = { [7] = { [9] = "Herbalism", [7] = "Mining" } }

local sqrt = math.sqrt

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function byAt(a, b) return (tonumber(a.at) or 0) < (tonumber(b.at) or 0) end

function X.Cap(list)
    if type(list) ~= "table" or #list <= X.PER_MAP then return 0 end
    table.sort(list, byAt)
    local gone = 0
    while #list > X.PER_MAP do
        table.remove(list, 1)
        gone = gone + 1
    end
    return gone
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- The item's name in a link ("|h[Name]|h"), or nil.
local function itemName(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
    if not name or name == "" or name:find("[%c|]") then return nil end
    return name
end

-- The gathering profession an item's facts say it is from, or nil.
local function materialOf(info)
    if type(info) ~= "table" then return nil end
    local sub = X.MATERIAL[info.classID]
    return type(sub) == "table" and sub[info.subclassID] or nil
end

-- The gathering professions of Rotation/Gather.lua the player has.
local function gathering(profs)
    local out = {}
    local list = type(ns.Gather) == "table" and type(ns.Gather.LIST) == "table" and ns.Gather.LIST or {}
    if type(profs) ~= "table" then return out end
    for _, g in ipairs(list) do
        if type(g) == "table" and profs[g.profession] then out[#out + 1] = g.profession end
    end
    return out
end

function X.Declare(k, diag)
    local api = {}
    local ctx
    local lastCast   -- { prof, at }: the player's last gathering cast

    local function ask(name, ...)
        local client = ctx and ctx.client
        if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
        local ok, v = pcall(client[name], ...)
        if ok then return v end
        return nil
    end

    local function on()
        if not ctx then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, X.SETTING)
        return not (ok and v == false)
    end

    local function saved()
        if not ctx then return nil end
        local ok, v = pcall(ctx.store.get, ctx.store, "account", X.PATH)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function say(line)
        if ctx then ctx.client.print((k.id or ns.id).title .. ": " .. line) end
    end

    -- Yards between two shares on a map of that size; without a size, the
    -- shares times 1000 (only for ordering and the same-node test).
    local function yards(a, b, size)
        local w = size and size.w or 1000
        local h = size and size.h or 1000
        local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
        return sqrt(dx * dx + dy * dy)
    end

    local function sizeOf(map)
        local size = ask("mapSize", map)
        if type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0 then return size end
        return nil
    end

    function api.loot()
        if not ctx or not on() then return nil end
        local win = ask("lootWindow")
        local src = type(win) == "table" and win.source or nil
        local guid = type(src) == "table" and src.guid or nil
        if type(guid) ~= "string" or not guid:find("^GameObject%-") then return nil end
        local mine = gathering(ask("professions"))
        if #mine == 0 then return nil end
        local have = {}
        for _, prof in ipairs(mine) do have[prof] = true end
        local p = ask("position")
        if type(p) ~= "table" or p.map == nil or not finite(p.x) or not finite(p.y) then return nil end
        local now = ask("clock")
        local prof
        if lastCast and finite(now) and finite(lastCast.at) and now - lastCast.at <= X.CAST_WINDOW
            and have[lastCast.prof] then
            prof = lastCast.prof
        end
        lastCast = nil
        local name, first
        for _, row in ipairs(type(win.items) == "table" and win.items or {}) do
            local item = type(row) == "table" and row.item or nil
            local info = item ~= nil and ask("itemInfo", item) or nil
            local own = itemName(item) or (type(info) == "table" and type(info.name) == "string" and info.name ~= "" and info.name) or nil
            first = first or own
            local from = materialOf(info)
            if from and have[from] and (prof == nil or prof == from) and name == nil then
                prof = prof or from
                name = own
            end
        end
        if prof == nil then return nil end
        name = name or first or (type(src.name) == "string" and src.name ~= "" and src.name) or nil
        local id = tonumber(guid:match("^GameObject%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)"))
        local all = saved()
        if not all then
            ctx.store:set("account", X.PATH, {})
            all = saved()
        end
        if not all then return nil end
        local list = type(all[p.map]) == "table" and all[p.map] or {}
        all[p.map] = list
        local size = sizeOf(p.map)
        local spot = { x = p.x, y = p.y }
        for _, e in ipairs(list) do
            if type(e) == "table" and finite(e.x) and finite(e.y) and yards(e, spot, size) <= X.SAME
                and ((id ~= nil and e.id == id) or (id == nil and e.name == name)) then
                e.n = (tonumber(e.n) or 1) + 1
                e.at = now
                return e
            end
        end
        local e = { x = round4(p.x), y = round4(p.y), id = id, name = name,
                    prof = prof, n = 1, at = now }
        list[#list + 1] = e
        X.Cap(list)
        local maps, oldest, oldestAt = 0, nil, nil
        for map, l in pairs(all) do
            maps = maps + 1
            local newest = 0
            for _, n in ipairs(type(l) == "table" and l or {}) do
                if type(n) == "table" and (tonumber(n.at) or 0) > newest then newest = tonumber(n.at) end
            end
            if oldestAt == nil or newest < oldestAt then oldest, oldestAt = map, newest end
        end
        if maps > X.MAPS and oldest ~= nil and oldest ~= p.map then all[oldest] = nil end
        return e
    end

    -- The nearest kept nodes of the player's own gathering professions on
    -- the player's map: { { node, d } }, nearest first; nil when where the
    -- player is is not known.
    function api.nearest(max)
        local p = ask("position")
        if type(p) ~= "table" or p.map == nil or not finite(p.x) or not finite(p.y) then return nil end
        local mine = gathering(ask("professions"))
        local have = {}
        for _, prof in ipairs(mine) do have[prof] = true end
        local all = saved()
        local list = all and all[p.map]
        local size = sizeOf(p.map)
        local out = {}
        for _, e in ipairs(type(list) == "table" and list or {}) do
            if type(e) == "table" and finite(e.x) and finite(e.y)
                and ((e.prof == nil and #mine > 0) or (e.prof ~= nil and have[e.prof])) then
                out[#out + 1] = { node = e, d = yards(e, p, size) }
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        for i = #out, (max or X.SHOW) + 1, -1 do out[i] = nil end
        return out, size ~= nil, p
    end

    local function lineOf(i, r, known)
        local e = r.node
        local where = ("%.1f, %.1f"):format(e.x * 100, e.y * 100)
        local d = known and (math.floor(r.d + 0.5) .. " yd") or "distance not known"
        local what = e.name or "a node"
        if type(e.prof) == "string" then what = what .. " (" .. e.prof .. ")" end
        return ("  %d. %s, %s at %s%s"):format(i, what, d, where,
            (tonumber(e.n) or 1) > 1 and (", gathered " .. e.n .. " times") or "")
    end

    function api.go()
        local list, _, p = api.nearest(1)
        if not list then return nil, "where you are is not known." end
        local e = list[1] and list[1].node
        if not e then return nil, "no node you gathered is known on this map." end
        local W = N.Waypoint
        if type(W) ~= "table" or type(W.Set) ~= "function" then return nil, "waypoints are not loaded." end
        local label = e.name or "Node"
        if #label > W.LABEL_MAX then label = label:sub(1, W.LABEL_MAX) end
        local text = ("%.2f %.2f %s"):format(e.x * 100, e.y * 100, label)
        local wp, why = W.Set(W.Slot(ctx.store), p, text)
        if not wp then return nil, why end
        return wp
    end

    k:Setting({ key = X.SETTING, scope = "account", type = "bool", default = true,
        label = "Remember the nodes I gather", group = "professions",
        help = "Remembers where you gathered herbs, ore and other nodes, for the nodes word and its arrow. Shows when you have a gathering profession.",
        synonyms = { "nodes", "herbs", "ore", "mining", "herbalism", "gather" } })

    k:Module({
        name = X.NAME,
        needs = { "client", "store", "settings", "bus" },
        provides = {
            Nearest = function(max) return api.nearest(max) end,
            Go = function() return api.go() end,
        },
        start = function(c)
            ctx = c
            c.bus:on(X.NAME, X.CAST_EVENT, function(unit, _, id)
                if unit ~= "player" then return end
                local spell = ask("spellName", id)
                local prof = type(spell) == "string" and X.CAST[spell] or nil
                if prof then lastCast = { prof = prof, at = ask("clock") } end
            end)
            c.bus:on(X.NAME, X.EVENT, function()
                local ok, err = pcall(api.loot)
                if not ok then k.problems:add(X.NAME, X.EVENT, tostring(err)) end
            end)
        end,
        stop = function() end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[X.WORD] = function(rest)
            if not ctx then return end
            rest = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
            if rest == "forget" then
                local ok = ctx.store:set("account", X.PATH, nil)
                say(ok and "forgot every node it had kept." or "could not forget the nodes.")
                return
            end
            if rest == "go" then
                local wp, why = api.go()
                if wp then
                    say("waypoint set at the nearest node: " .. tostring(N.Waypoint.Text(wp)) .. ".")
                else
                    say(tostring(why))
                end
                return
            end
            local list, known = api.nearest()
            if not list then
                say("where you are is not known.")
                return
            end
            if #list == 0 then
                say("no node you gathered is known on this map" .. (on() and "." or " (remembering is off)."))
                return
            end
            say("the nearest nodes you gathered (" .. X.WORD .. " go points the arrow at the first):")
            for i, r in ipairs(list) do ctx.client.print(lineOf(i, r, known)) end
        end
        if type(diag.help) == "table" then diag.help[X.WORD] = X.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.nodes = X.Declare(ns, ns.diag)
