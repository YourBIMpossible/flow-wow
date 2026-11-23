local _, ns = ...
-- Z-Flow trails (G38, lead dispatch P-NAV): the path the player walked
-- into a cave or other indoor place, learned from the player's own
-- movement only, and the arrow following that path to a target reached
-- through it, one trail point at a time, instead of the straight line
-- through the rock. No route data from anywhere else.
--
-- LOOK ONLY. It reads where the player is and remembers it. Nothing moves,
-- targets or acts for the player; the arrow only points.
--
-- Learning (a look every T.EVERY seconds while the setting is on): the
-- player's spot in yards on the map (client.position() times
-- client.mapSize()) is kept as a short line of crumbs, one every T.STEP
-- yards (thinning), the last T.LEAD of them. When client.indoors() turns
-- true a trail starts from those crumbs and grows while indoors; walking
-- back over it cuts it back to the spot (no loops), and the longest form
-- seen is the one kept. It ends when the player is outdoors again, leaves
-- the map, dies, flies, jumps more than T.JUMP yards between two looks, or
-- reaches T.POINTS points. A trail of T.MIN_POINTS points or more is kept.
-- An indoors read that is not known learns nothing.
--
-- Saved, account T.PATH: { [map] = { { pts = { { x, y } }, at = clock } } }
--   x, y are shares 0..1 of the map (4 decimals). At most T.PER_MAP trails
--   a map (the oldest go) and T.MAPS maps (the map used longest ago goes).
--
-- Following: T.Refine(step) (provided as Refine; UI/Arrow.lua asks it for
-- the quest step). A step on the player's own map whose target is within
-- T.NEAR yards of a trail point, with the player within T.JOIN yards of the
-- same trail and more than T.NEAR yards from the target, is pointed at the
-- next trail point toward the target (T.Next). Otherwise the step is as
-- it was.
--
--   T.Next(pts, here, there) -> index or nil     pure, yards
--   T.Declare(k, diag) -> api
-- Not tested in game: client.indoors() is a first guess.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local T = {}
N.Trails = T

T.NAME = "trails"
T.SETTING = "nav.learnTrails"
T.PATH = "learned.trails"
T.WORD = "trails"
T.HELP = "the trails you walked into caves, that the arrow follows; trails forget clears them"
T.EVERY = 1          -- seconds between looks
T.STEP = 10          -- yards between two kept points
T.LEAD = 6           -- crumbs kept from before the way in
T.POINTS = 80        -- points a trail holds at most
T.MIN_POINTS = 4     -- shorter trails are not kept
T.JUMP = 100         -- yards between two looks no walk explains
T.NEAR = 25          -- yards: a target this close to a trail point is on it
T.JOIN = 60          -- yards: the player this close to a trail may take it
T.PER_MAP = 20
T.MAPS = 60

local sqrt = math.sqrt

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

local function nearest(pts, p)
    local best, bestD
    for i = 1, #pts do
        local d = dist(pts[i], p)
        if bestD == nil or d < bestD then best, bestD = i, d end
    end
    return best, bestD
end

-- The index of the trail point to head for, walking from the player's end
-- of the trail toward the target's; nil when the player is not near the
-- trail, the target is not on it, or the player is already at the target.
function T.Next(pts, here, there)
    if type(pts) ~= "table" or #pts < 2 or type(here) ~= "table" or type(there) ~= "table" then return nil end
    if dist(here, there) <= T.NEAR then return nil end
    local j, dj = nearest(pts, there)
    if not j or dj > T.NEAR then return nil end
    local i, di = nearest(pts, here)
    if not i or di > T.JOIN or i == j then return nil end
    if di > T.STEP then return i end
    if i < j then return i + 1 end
    return i - 1
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

function T.Declare(k, diag)
    local api = {}
    local ctx
    local crumbs, rec, best, lastMap = {}, nil, nil, nil

    local function ask(name, ...)
        local client = ctx and ctx.client
        if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
        local ok, v = pcall(client[name], ...)
        if ok then return v end
        return nil
    end

    local function on()
        if not ctx then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, T.SETTING)
        return not (ok and v == false)
    end

    local function saved()
        if not ctx then return nil end
        local ok, v = pcall(ctx.store.get, ctx.store, "account", T.PATH)
        if ok and type(v) == "table" then return v end
        return nil
    end

    -- Where the player is, in yards on their map, with the map's size.
    local function here()
        local p = ask("position")
        if type(p) ~= "table" or p.map == nil or not finite(p.x) or not finite(p.y) then return nil end
        local size = ask("mapSize", p.map)
        if type(size) ~= "table" or not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then
            return nil
        end
        return { map = p.map, x = p.x * size.w, y = p.y * size.h }, size
    end

    local function keep()
        local trail = best
        rec, best = nil, nil
        if type(trail) ~= "table" or #trail.pts < T.MIN_POINTS then return end
        local all = saved()
        if not all then
            ctx.store:set("account", T.PATH, {})
            all = saved()
        end
        if not all then return end
        local list = type(all[trail.map]) == "table" and all[trail.map] or {}
        all[trail.map] = list
        local pts = {}
        for i, p in ipairs(trail.pts) do
            pts[i] = { x = round4(p.x / trail.size.w), y = round4(p.y / trail.size.h) }
        end
        list[#list + 1] = { pts = pts, at = ask("clock") }
        while #list > T.PER_MAP do table.remove(list, 1) end
        -- Too many maps: the one whose newest trail is oldest goes.
        local maps, oldest, oldestAt = 0, nil, nil
        for map, l in pairs(all) do
            maps = maps + 1
            local newest = type(l) == "table" and l[#l] and tonumber(l[#l].at) or 0
            if oldestAt == nil or newest < oldestAt then oldest, oldestAt = map, newest end
        end
        if maps > T.MAPS and oldest ~= nil then all[oldest] = nil end
    end

    local function reset()
        crumbs, rec, best = {}, nil, nil
    end

    function api.look()
        if not ctx then return end
        if not on() then
            reset()
            return
        end
        local p, size = here()
        if not p or ask("onTaxi") == true or ask("dead") == true or ask("ghost") == true then
            if rec then keep() end
            reset()
            return
        end
        if p.map ~= lastMap then
            if rec then keep() end
            reset()
            lastMap = p.map
        end
        local last = crumbs[#crumbs]
        if last and dist(last, p) > T.JUMP then
            if rec then keep() end
            reset()
            last = nil
        end
        local added = false
        if not last or dist(last, p) >= T.STEP then
            crumbs[#crumbs + 1] = { x = p.x, y = p.y }
            while #crumbs > T.LEAD do table.remove(crumbs, 1) end
            added = true
        end
        local inside = ask("indoors")
        if inside == true and not rec then
            local pts = {}
            for i, c in ipairs(crumbs) do pts[i] = { x = c.x, y = c.y } end
            rec = { map = p.map, size = { w = size.w, h = size.h }, pts = pts }
        elseif inside == true and rec and added then
            -- Walking back over the trail cuts it back to that spot.
            local cut
            for i = 1, #rec.pts - 1 do
                if dist(rec.pts[i], p) < T.STEP then
                    cut = i
                    break
                end
            end
            if cut then
                for i = #rec.pts, cut + 1, -1 do rec.pts[i] = nil end
            else
                rec.pts[#rec.pts + 1] = { x = p.x, y = p.y }
            end
        elseif inside ~= true and rec then
            if inside == false then keep() else rec, best = nil, nil end
            return
        end
        if rec then
            if not best or #rec.pts > #best.pts then
                local pts = {}
                for i, c in ipairs(rec.pts) do pts[i] = { x = c.x, y = c.y } end
                best = { map = rec.map, size = rec.size, pts = pts }
            end
            if #rec.pts >= T.POINTS then keep() end
        end
    end

    -- The step pointed at the next trail point, or the step as it was.
    function api.refine(step)
        if not ctx or not on() or type(step) ~= "table" or type(step.place) ~= "table" then return step end
        local place = step.place
        if place.map == nil or not finite(place.x) or not finite(place.y) then return step end
        local p, size = here()
        if not p or p.map ~= place.map then return step end
        local all = saved()
        local list = all and all[p.map]
        if type(list) ~= "table" then return step end
        local there = { x = place.x * size.w, y = place.y * size.h }
        local pick, pickD
        for _, trail in ipairs(list) do
            if type(trail) == "table" and type(trail.pts) == "table" then
                local pts = {}
                for i, q in ipairs(trail.pts) do
                    if type(q) == "table" and finite(q.x) and finite(q.y) then
                        pts[#pts + 1] = { x = q.x * size.w, y = q.y * size.h }
                    end
                    if #pts ~= i then break end
                end
                local n = T.Next(pts, p, there)
                if n then
                    local d = dist(pts[n], p)
                    if pickD == nil or d < pickD then pick, pickD = pts[n], d end
                end
            end
        end
        if not pick then return step end
        local out = {}
        for key, v in pairs(step) do out[key] = v end
        out.place = { cont = place.cont, map = place.map, x = pick.x / size.w, y = pick.y / size.h }
        out.trail = true
        return out
    end

    function api.count(map)
        local all = saved()
        if not all then return 0 end
        if map ~= nil then return type(all[map]) == "table" and #all[map] or 0 end
        local n = 0
        for _, l in pairs(all) do
            if type(l) == "table" then n = n + #l end
        end
        return n
    end

    local function say(line)
        if ctx then ctx.client.print((k.id or ns.id).title .. ": " .. line) end
    end

    k:Setting({ key = T.SETTING, scope = "account", type = "bool", default = true,
        label = "Learn the paths I walk into caves", group = "travel.route",
        help = "Remembers the way you walked into caves and indoor places; the arrow then follows it there. Shows when the arrow's target is past a path you walked.",
        synonyms = { "cave", "trail", "path", "indoors", "learn" } })

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "settings" },
        provides = {
            Refine = function(step) return api.refine(step) end,
            Count = function(map) return api.count(map) end,
        },
        ticks = { { every = T.EVERY, when = "always", run = function() api.look() end } },
        start = function(c) ctx = c end,
        stop = function()
            reset()
            lastMap = nil
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[T.WORD] = function(rest)
            if not ctx then return end
            if rest == "forget" then
                local ok = ctx.store:set("account", T.PATH, nil)
                reset()
                say(ok and "forgot every trail it had learned." or "could not forget the trails.")
                return
            end
            local n = api.count()
            local p = ask("position")
            local mapN = type(p) == "table" and p.map ~= nil and api.count(p.map) or 0
            say(("%d trail%s learned, %d on this map%s."):format(n, n == 1 and "" or "s", mapN,
                on() and "" or " (learning is off)"))
            if rec then say(("  walking one now: %d points."):format(#rec.pts)) end
        end
        if type(diag.help) == "table" then diag.help[T.WORD] = T.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.trails = T.Declare(ns, ns.diag)
