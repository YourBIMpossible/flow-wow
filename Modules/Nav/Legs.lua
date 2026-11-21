-------------------------------------------------------------------------------
-- Flow - Nav/Legs.lua
-- Trips you've made, and how long they took: the route is planned by them
-- (0.35.350).
--
-- "I'd like that system to start working now, where it's working locally and
-- recording that data and optimizing my paths and learning from me."
--
-- Flow's trails already remember how long each short stretch of ground took
-- you, and the arrow follows the quickest known trail. The planner didn't
-- learn anything: it ordered your steps by the straight line between them
-- (or a flight, a gate, a travel spell where it knows one). A cliff, a river
-- or a winding road between two steps was invisible to it.
--
-- A leg is one trip between two steps: from where you finished one to where
-- you arrived at the next. For each Flow keeps the quickest it has seen you
-- do it: the seconds you were actually travelling (not fighting, not standing
-- still), whether you rode, flew or ran, and the straight line between the
-- two ends. Legs are kept by place, not by quest: both ends are rounded to a
-- 40-yard square, so the trip "Crossroads inn -> the harpies" serves every
-- step that starts and ends there.
--
-- The planner then measures a leg three ways, best first:
--   1. you've made this very trip (same two squares, either direction):
--      what it took you;
--   2. you've crossed between these two neighbourhoods (250-yard squares):
--      the straight line, stretched by how much longer such trips took you
--      than the straight line would (the detour round a mountain);
--   3. nothing known: the straight line, as before.
--
-- Not a leg: a trip with a hearthstone or a teleport in it (a jump), one you
-- died on, one that crossed to another continent, one where you wandered
-- (more than L.WANDER times the straight line on the ground, without a
-- flight). Those would teach the planner nonsense.
--
-- This is the unit a shared route graph would be built from (docs/
-- FLOW-GRAPH.md): a leg carries no name, no quest and no clock time, only two
-- squares of the map, a number of seconds and how you travelled.
-------------------------------------------------------------------------------

local _, ns = ...
local L = {}
ns.legs = L

L.CELL = 40          -- yards: a leg's ends are rounded to this
L.COARSE = 250       -- yards: a "neighbourhood", for trips nobody made exactly
L.ARRIVE = 30        -- yards from the step's spot: you've arrived
L.MIN_YARDS = 60     -- shorter trips teach nothing
L.MIN_SPEED = 1.5    -- yards a second: slower than this you aren't travelling
L.JUMP = 70          -- yards in one look (a second): a hearthstone, a teleport, a loading screen
L.WANDER = 2.5       -- ground covered / straight line: more is wandering, not a trip
L.RUN = 7            -- yards a second on foot (as the trails count)
L.FASTEST = 0.12     -- a learned leg counts as at least this share of the straight line
L.SLOWEST = 5        -- and at most this many times it
L.COARSE_MIN = 150   -- only trips this long say something about a neighbourhood
L.MAX = 3000         -- legs kept a continent
L.AGE = 30 * 86400   -- seconds: a best older than this gives way to the next trip, and isn't planned by

function L.On() return not (ns.db and ns.db.nav and ns.db.nav.learnLegs == false) end

local floor = math.floor
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- A spot's square, as a key. size: L.CELL or L.COARSE.
function L.Cell(wx, wy, size)
    size = size or L.CELL
    return floor(wx / size) .. ":" .. floor(wy / size)
end

-- One look at you, a second after the last. Follows a trip from an anchor
-- (where the last one ended) to your arrival at the step you're heading for.
--   st: { anchor = { cont, wx, wy }, last = { wx, wy, cont }, sec, ground, taxi, ridden, looks }
--   s:  { cont, wx, wy, dt, combat, taxi, mounted, dead, target = { cont, wx, wy } or nil }
--   -> a finished leg { cont, ax, ay, bx, by, sec, d, mode } or nil
-- (st is changed in place.)
function L.Look(st, s)
    if not (s and s.wx and s.cont ~= nil) then return nil end
    local last = st.last
    st.last = { wx = s.wx, wy = s.wy, cont = s.cont }
    -- Dead, another continent, or a jump no legs or wings explain: no trip.
    if s.dead or (last and last.cont ~= s.cont) then st.anchor = nil return nil end
    local moved = last and dist(last.wx, last.wy, s.wx, s.wy) or 0
    if moved > L.JUMP * math.max(1, s.dt or 1) and not s.taxi then st.anchor = nil return nil end
    if st.anchor then
        -- Travelling: moving, and not in a fight (a flight always counts).
        if s.taxi or (not s.combat and moved >= L.MIN_SPEED * (s.dt or 1)) then
            st.sec = (st.sec or 0) + (s.dt or 1)
            st.looks = (st.looks or 0) + 1
            if s.mounted and not s.taxi then st.ridden = (st.ridden or 0) + 1 end
        end
        st.ground = (st.ground or 0) + moved
        if s.taxi then st.taxi = true end
    end
    local t = s.target
    if not (t and t.wx and t.cont == s.cont and dist(s.wx, s.wy, t.wx, t.wy) <= L.ARRIVE) then return nil end
    -- Arrived. The trip that ends here, if there was one worth keeping.
    local a, leg = st.anchor, nil
    if a and a.cont == s.cont then
        local d = dist(a.wx, a.wy, t.wx, t.wy)
        local sec = st.sec or 0
        if d >= L.MIN_YARDS and sec > 0 and (st.taxi or (st.ground or 0) <= d * L.WANDER) then
            local mode = st.taxi and "taxi" or (((st.ridden or 0) * 2 > (st.looks or 0)) and "mount" or "foot")
            leg = { cont = s.cont, ax = a.wx, ay = a.wy, bx = t.wx, by = t.wy, sec = sec, d = d, mode = mode }
        end
    end
    st.anchor = { cont = s.cont, wx = t.wx, wy = t.wy }
    st.sec, st.ground, st.taxi, st.ridden, st.looks = 0, 0, nil, 0, 0
    return leg
end

-- Keeps a leg in a continent's store: the quickest wins (until it's older
-- than L.AGE: then the next trip replaces it), the count goes up. The
-- quickest on foot is kept too (f, ft), for a character who can't ride: a
-- trip learned riding mustn't time it (the store is shared by your characters).
--   store: { [cellA] = { [cellB] = { s, d, n, m, at, bt, f, ft } } }
--   (at: last trip; bt: when the best was set)  -> the entry, and whether it's a new best
function L.Keep(store, leg, now)
    local ka, kb = L.Cell(leg.ax, leg.ay), L.Cell(leg.bx, leg.by)
    if ka == kb then return nil, false end
    store[ka] = store[ka] or {}
    local e = store[ka][kb]
    local sec = floor(leg.sec * 10 + 0.5) / 10
    local function stale(t) return now and t and now - t > L.AGE end
    if leg.mode == "foot" and e and (not e.f or sec < e.f or stale(e.ft)) then e.f, e.ft = sec, now end
    if not e then
        e = { s = sec, d = floor(leg.d + 0.5), n = 1, m = leg.mode, at = now, bt = now }
        if leg.mode == "foot" then e.f, e.ft = sec, now end
        store[ka][kb] = e
        return e, true
    end
    e.n, e.at = (e.n or 1) + 1, now
    if sec < e.s or stale(e.bt or e.at) then
        e.s, e.d, e.m, e.bt = sec, floor(leg.d + 0.5), leg.mode, now
        return e, true
    end
    return e, false
end

-- Pure: the seconds an entry gives the planner, or nil. how (optional):
-- { ride = false } for a character who can't ride (only a trip made on foot
-- or by flight times it), { now = time } to leave out a best past L.AGE.
function L.SecondsFor(e, how)
    if not e then return nil end
    local now = how and how.now
    local function stale(t) return now and t and now - t > L.AGE end
    local s, t = e.s, e.bt
    if how and how.ride == false and e.m == "mount" then s, t = e.f, e.ft end
    if not s or stale(t) then return nil end
    return s
end

-- Pure: what a leg counts as for the planner, in yards at running speed,
-- for a trip of `d` straight yards between the same two squares.
function L.YardsOf(e, d)
    if not (e and e.s and e.d and e.d > 0 and d and d > 0) then return nil end
    -- (The ends differ a little within their squares: by the length's share.)
    local scale = math.max(0.7, math.min(1.4, d / e.d))
    local yards = e.s * L.RUN * scale
    return math.max(d * L.FASTEST, math.min(d * L.SLOWEST, yards))
end

-- Pure: how much longer than the straight line trips between two
-- neighbourhoods take: the best ratio seen. coarse: { [KA] = { [KB] = ratio } }
function L.Ratio(coarse, e, ax, ay, bx, by)
    if not (e and e.d and e.d >= L.COARSE_MIN and e.m ~= "taxi") then return nil end
    local ratio = (e.s * L.RUN) / e.d
    local KA, KB = L.Cell(ax, ay, L.COARSE), L.Cell(bx, by, L.COARSE)
    if KA == KB then return nil end
    for _, pair in ipairs({ { KA, KB }, { KB, KA } }) do
        coarse[pair[1]] = coarse[pair[1]] or {}
        local old = coarse[pair[1]][pair[2]]
        if not old or ratio < old then coarse[pair[1]][pair[2]] = ratio end
    end
    return ratio
end

-- Pure: the planner's answer for a trip from a to b ({ wx, wy }) of d
-- straight yards. -> yards, and "exact" | "area"; nil when nothing is known.
--   store, coarse: one continent's; how: as L.SecondsFor
function L.Lookup(store, coarse, a, b, d, how)
    if not (store and a and b and d and d >= L.MIN_YARDS) then return nil end
    local ka, kb = L.Cell(a.wx, a.wy), L.Cell(b.wx, b.wy)
    local fw = store[ka] and store[ka][kb]
    local s = L.SecondsFor(fw, how)
    local e = s and { s = s, d = fw.d } or nil
    -- (The way back, when it wasn't a flight: a path is the same both ways.)
    local back = store[kb] and store[kb][ka]
    local sb = back and back.m ~= "taxi" and L.SecondsFor(back, how)
    if sb and (not e or sb < e.s) then e = { s = sb, d = back.d } end
    if e then return L.YardsOf(e, d), "exact" end
    if coarse and d >= L.COARSE_MIN then
        local KA, KB = L.Cell(a.wx, a.wy, L.COARSE), L.Cell(b.wx, b.wy, L.COARSE)
        local r = coarse[KA] and coarse[KA][KB]
        if r then return math.max(d * L.FASTEST, math.min(d * L.SLOWEST, d * r)), "area" end
    end
    return nil
end

-- Pure: how many legs a store holds, and the oldest's time.
function L.Count(store)
    local n = 0
    for _, row in pairs(store or {}) do for _ in pairs(row) do n = n + 1 end end
    return n
end
-- Pure: drops the legs used longest ago until `max` are left. -> how many went.
function L.Prune(store, max)
    local all = {}
    for ka, row in pairs(store or {}) do
        for kb, e in pairs(row) do all[#all + 1] = { ka, kb, e.at or 0 } end
    end
    if #all <= max then return 0 end
    table.sort(all, function(x, y) return x[3] < y[3] end)
    local gone = #all - max
    for i = 1, gone do
        local row = store[all[i][1]]
        row[all[i][2]] = nil
        if not next(row) then store[all[i][1]] = nil end
    end
    return gone
end

-------------------------------------------------------------------------------
-- Your own trips
-------------------------------------------------------------------------------
local coarse = {}     -- [cont] = { [KA] = { [KB] = ratio } }, built from the legs
local state = {}      -- the trip being made
L.used = { exact = 0, area = 0, none = 0 }   -- what the last plans were measured by
L.recent = {}         -- the last legs learned, newest first (for /flow legs)

local function storeOf(cont, make)
    local all = ns.db and ns.db.nav and ns.db.nav.legs
    if not all then return nil end
    if not all[cont] and make then all[cont] = {} end
    return all[cont]
end

-- A leg's two squares, back as spots (their middles), for the neighbourhoods.
local function middle(key, size)
    local cx, cy = key:match("^(-?%d+):(-?%d+)$")
    return (tonumber(cx) + 0.5) * size, (tonumber(cy) + 0.5) * size
end
local function rebuild()
    wipe(coarse)
    for cont, store in pairs((ns.db and ns.db.nav and ns.db.nav.legs) or {}) do
        coarse[cont] = {}
        for ka, row in pairs(store) do
            local ax, ay = middle(ka, L.CELL)
            for kb, e in pairs(row) do
                local bx, by = middle(kb, L.CELL)
                L.Ratio(coarse[cont], e, ax, ay, bx, by)
            end
        end
    end
end

-- The planner's option (Nav.lua: N:Options): a trip from spot a to spot b of
-- d straight yards -> yards as you travel it, and how it's known.
local planHow = {}   -- this plan's { ride, now } (L.PlanLegs: once a plan, not once a leg)
function L.Yards(a, b, d)
    if not (a and b and a.cont ~= nil and a.cont == b.cont and a.wx and b.wx) then return nil end
    local yards, how = L.Lookup(storeOf(a.cont), coarse[a.cont], a, b, d, planHow)
    L.used[how or "none"] = (L.used[how or "none"] or 0) + 1
    return yards, how
end
function L.PlanLegs()
    if not L.On() then return nil end
    -- Can this character ride? (Unknown: as before, any trip counts.)
    local MT, ride = ns.mounts, nil
    if MT and MT.HasRiding and MT.HasMount then
        local ok, yes = pcall(function() return MT:HasRiding() and MT:HasMount() end)
        if ok then ride = yes and true or false end
    end
    planHow.ride, planHow.now = ride, time and time() or nil
    return L.Yards
end

-- A second has passed: where you are, where you're headed.
function L.Tick()
    if not L.On() then return end
    if ns.Lite and ns.Lite() then state.anchor = nil return end   -- (a raid, a dungeon: no trips to time)
    local N = ns.nav
    local p = N and N.PlayerPos and N:PlayerPos()
    if not (p and p.wx) then return end
    local first = N.plan and N.plan[1]
    local pt = first and first.point
    local now = GetTime()
    local leg = L.Look(state, {
        cont = p.cont, wx = p.wx, wy = p.wy, dt = math.min(3, now - (state.at or now - 1)),
        combat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false,
        taxi = UnitOnTaxi and UnitOnTaxi("player") and true or false,
        mounted = IsMounted and IsMounted() and true or false,
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true or false,
        target = (pt and pt.wx) and { cont = pt.cont, wx = pt.wx, wy = pt.wy } or nil,
    })
    state.at = now
    if not leg then return end
    local store = storeOf(leg.cont, true)
    if not store then return end
    local e, best = L.Keep(store, leg, time())
    if not e then return end
    coarse[leg.cont] = coarse[leg.cont] or {}
    L.Ratio(coarse[leg.cont], e, leg.ax, leg.ay, leg.bx, leg.by)
    table.insert(L.recent, 1, { sec = leg.sec, d = leg.d, mode = leg.mode, best = best, n = e.n })
    L.recent[9] = nil
    ns:Log("nav", string.format("leg learned: %d yd straight in %.0f s %s (%.1fx the straight line at a run)%s", leg.d, leg.sec,
        leg.mode == "taxi" and "by flight" or (leg.mode == "mount" and "riding" or "on foot"), leg.sec * L.RUN / leg.d,
        best and (e.n > 1 and ", your quickest yet" or "") or ", not quicker than before"))
    if L.Count(store) > L.MAX then L.Prune(store, floor(L.MAX * 0.9)) end
end

ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.legs = saved.nav.legs or {}
    rebuild()
    if C_Timer and C_Timer.NewTicker then
        local tick = (ns.perf and ns.perf.Wrap and ns.perf.Wrap("legs", L.Tick)) or function() pcall(L.Tick) end
        C_Timer.NewTicker(1, tick)
    end
end)

-- /flow legs: what Flow has learned (also in the diagnostics).
function L.Lines()
    local out, total = {}, 0
    for cont, store in pairs((ns.db and ns.db.nav and ns.db.nav.legs) or {}) do
        local n, taxi, mount = 0, 0, 0
        for _, row in pairs(store) do
            for _, e in pairs(row) do
                n = n + 1
                if e.m == "taxi" then taxi = taxi + 1 elseif e.m == "mount" then mount = mount + 1 end
            end
        end
        total = total + n
        local hoods = 0
        for _, row in pairs(coarse[cont] or {}) do for _ in pairs(row) do hoods = hoods + 1 end end
        out[#out + 1] = string.format("  continent %s: %d trip(s) (%d by flight, %d riding), %d pair(s) of neighbourhoods", tostring(cont), n, taxi, mount, hoods / 2)
    end
    table.insert(out, 1, string.format("trips Flow has learned from you: %d%s", total, L.On() and "" or " (learning is off)"))
    out[#out + 1] = string.format("  the route's legs since login: %d by a trip you made, %d by its neighbourhood, %d by the straight line",
        L.used.exact or 0, L.used.area or 0, L.used.none or 0)
    for i, r in ipairs(L.recent) do
        out[#out + 1] = string.format("  %d. %d yd in %.0f s, %s%s", i, r.d, r.sec, r.mode, r.best and "" or " (not quicker than before)")
    end
    local a = state.anchor
    out[#out + 1] = a and string.format("  on a trip now: %.0f s travelling, %.0f yd on the ground", state.sec or 0, state.ground or 0) or "  no trip under way (it starts when you arrive at a step)"
    return out
end
ns.commands.legs = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.learnLegs = (arg == "on")
        ns:Print("learning how long your trips take: " .. arg)
        if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("legs " .. arg) end
        return
    end
    if arg == "forget" then
        wipe(ns.db.nav.legs)
        rebuild()
        ns:Print("forgot every trip Flow had learned")
        return
    end
    for i, l in ipairs(L.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow legs on|off|forget")
end
ns:Register("help", "legs", { order = 37, title = "Trips Flow learns", lines = {
    "Each trip from one step to the next is timed: the seconds you were travelling, and whether you ran, rode or flew. Flow keeps your quickest for each pair of places.",
    "The route is then ordered by those times where you've made the trip, by how much longer than the straight line trips between two neighbourhoods took you where you haven't, and by the straight line elsewhere.",
    "/flow legs: what it has learned. /flow legs on|off|forget.",
} })

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Learn how long my trips take, and plan by it",
        note = "(from step to step)",
        tip = "Flow times each trip between two steps (travelling only: not fights, not standing still) and keeps your quickest. "
            .. "The route is ordered by those times instead of the straight line, so a cliff or a river between two steps counts. "
            .. "Off: nothing is timed, and the route goes by the straight line, flights and gates as before.",
        get = function() return L.On() end,
        set = function(on)
            ns.db.nav.learnLegs = on and true or false
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("legs setting") end
        end,
    })
end
