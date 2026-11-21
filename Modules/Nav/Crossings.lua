-------------------------------------------------------------------------------
-- Flow - Nav/Crossings.lua
-- Crossing to another continent: zeppelins and boats as a step (0.35.369).
--
-- "All these current quest items are just telling me I need to go across a
-- continent ... I'd like an arrow to show me the fastest way to get across.
-- There's this concept already in the code base [gates] to pinpoint the
-- locations between zones ... and now we need intercontinental travel
-- gateways."
--
-- Gates.lua knows the ways between zones you walk through, and Flow knows
-- flights. A step across the sea was only ever a locked row with a sentence
-- ("Zeppelin from the tower outside Orgrimmar ..."). A crossing is the third
-- kind of way: a place you board on this continent and a place you land on
-- the other.
--
--   ns:Register("crossing", key, {
--       how = "zeppelin" | "boat", faction = "Horde" | "Alliance" | nil (anyone),
--       a = { name = "Orgrimmar", map = uiMapID, x = 50.8, y = 13.6 },
--       b = { name = "Undercity", map = uiMapID, x = 60.7, y = 58.8 } })
--
-- While steps of yours wait on another continent, the route gets one step a
-- continent: "Zeppelin to Undercity (3 steps wait in the Eastern Kingdoms)",
-- at the boarding place. Which crossing: the one that makes the trip
-- shortest, from where you stand to the boarding place plus from the landing
-- to the nearest of those steps. It's weighted to come after what's left to
-- do here; on a custom route whose line continues across the sea it's the
-- step the arrow leads to. Route includes has a tick for it.
--
-- Where the platforms are: the spots below are Classic's, good to within a
-- few dozen yards, and WoW: Forever may have moved some. So Flow corrects
-- them from you: when the continent changes under you close to a boarding
-- place Flow knows, where you stood becomes that boarding place and where
-- you appear becomes the landing (kept for all your characters).
-------------------------------------------------------------------------------

local _, ns = ...
local C = {}
ns.crossings = C

C.WEIGHT = 2.5       -- after the steps here (the planner: distance x weight)
C.NEAR = 250         -- yards from a boarding place: a continent change here corrects it
C.NAMES = { [0] = "the Eastern Kingdoms", [1] = "Kalimdor" }

-- (The classic map numbers: Durotar 1411, Tirisfal Glades 1420, Stranglethorn
-- Vale 1434, The Barrens 1413, Wetlands 1437, Dustwallow Marsh 1445, Darkshore 1439.)
ns:Register("crossing", "org-uc", { how = "zeppelin", faction = "Horde",
    a = { name = "Orgrimmar", place = "the zeppelin tower outside Orgrimmar", map = 1411, x = 50.8, y = 13.6 },
    b = { name = "Undercity", place = "the zeppelin tower outside Undercity", map = 1420, x = 60.7, y = 58.8 } })
ns:Register("crossing", "org-gromgol", { how = "zeppelin", faction = "Horde",
    a = { name = "Orgrimmar", place = "the zeppelin tower outside Orgrimmar", map = 1411, x = 50.6, y = 12.6 },
    b = { name = "Grom'gol", place = "the zeppelin tower at Grom'gol Base Camp", map = 1434, x = 31.5, y = 29.8 } })
ns:Register("crossing", "ratchet-bootybay", { how = "boat",
    a = { name = "Ratchet", place = "the dock at Ratchet", map = 1413, x = 63.7, y = 38.6 },
    b = { name = "Booty Bay", place = "the dock at Booty Bay", map = 1434, x = 25.9, y = 73.1 } })
ns:Register("crossing", "theramore-menethil", { how = "boat", faction = "Alliance",
    a = { name = "Theramore", place = "the dock at Theramore", map = 1445, x = 71.6, y = 56.4 },
    b = { name = "Menethil Harbor", place = "the dock at Menethil Harbor", map = 1437, x = 5.0, y = 63.5 } })
ns:Register("crossing", "auberdine-menethil", { how = "boat", faction = "Alliance",
    a = { name = "Auberdine", place = "the dock at Auberdine", map = 1439, x = 32.4, y = 43.8 },
    b = { name = "Menethil Harbor", place = "the dock at Menethil Harbor", map = 1437, x = 4.6, y = 57.1 } })

function C.On() return not (ns.db and ns.db.nav and ns.db.nav.crossings == false) end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- May you use it? (A faction's own, or anyone's.)
function C.Usable(cr, faction)
    return type(cr) == "table" and (cr.faction == nil or cr.faction == faction)
end

-- The best crossing from where you stand to steps on another continent.
--   list: { { key, cr, a = { cont, wx, wy }, b = { cont, wx, wy } } } (both
--         ends in world yards; a crossing works both ways)
--   me: { cont, wx, wy }; targets: { { cont, wx, wy } } on the other continent
--   -> { key, cr, from (the end you board at), to (where you land), board,
--        land (their world spots), yards } or nil when none joins the two
function C.Best(list, me, targets)
    local best
    for _, e in ipairs(list or {}) do
        for _, way in ipairs({ { "a", "b" }, { "b", "a" } }) do
            local board, land = e[way[1]], e[way[2]]
            if board and land and board.cont == me.cont and land.cont ~= me.cont then
                local near
                for _, t in ipairs(targets or {}) do
                    if t.cont == land.cont then
                        local d = dist(land.wx, land.wy, t.wx, t.wy)
                        if not near or d < near then near = d end
                    end
                end
                if near then
                    local yards = dist(me.wx, me.wy, board.wx, board.wy) + near
                    if not best or yards < best.yards then
                        best = { key = e.key, cr = e.cr, from = e.cr[way[1]], to = e.cr[way[2]], board = board, land = land, yards = yards }
                    end
                end
            end
        end
    end
    return best
end

-- How early the crossing comes (the planner: distance x weight; under 1 is
-- "worth going out of your way for", over 1 "leave it for later").
-- 0.35.372: "I'm already in Orgrimmar ... once I get over there and turn
-- those in, I can just hearth back to the Crossroads. Why did the router not
-- optimize like that?" Because the crossing was always weighted to come
-- last (2.5), wherever you stood: the planner counted the walk to the tower
-- and nothing of the way back. Now:
--   you're near the boarding place and your hearthstone is ready: first
--   (the way back costs a cast);
--   near it without a hearthstone: with the rest, by its distance;
--   far from it: after what's left here, as before.
C.CLOSE = 800       -- yards to the boarding place that count as "you're there anyway"
C.W_NOW, C.W_NEAR = 0.5, 1.1
function C.Weight(yardsToBoard, hearthReady)
    if not yardsToBoard or yardsToBoard > C.CLOSE then return C.WEIGHT end
    return hearthReady and C.W_NOW or C.W_NEAR
end
-- Pure: a line for the step's details about when it comes.
function C.WhenText(weight)
    if weight == C.W_NOW then return "You're close to it and your hearthstone is ready for the way back, so it comes first." end
    if weight == C.W_NEAR then return "You're close to it, so it's planned with the rest by its distance (no hearthstone ready for the way back)." end
    return "Planned after what's left to do here: you're far from it."
end

-- The step's words: "Zeppelin to Undercity (3 steps wait in the Eastern Kingdoms)".
function C.Text(how, toName, n, continent)
    local ride = how == "boat" and "Boat" or "Zeppelin"
    return string.format("%s to %s (%d step%s wait%s in %s)", ride, tostring(toName), n, n == 1 and "" or "s", n == 1 and "s" or "", tostring(continent or "another continent"))
end

-- The quests whose steps wait over there: { [questID] = true } (a custom
-- route keeps the crossing when one of its lines needs it: Focus.lua).
function C.QuestsOf(goals)
    local out = {}
    for _, g in ipairs(goals or {}) do
        local id = type(g.key) == "string" and tonumber(g.key:match("^pickup:(%d+)$") or g.key:match("^(%d+):"))
        if id then out[id] = true end
    end
    return out
end

-- A continent change close to a boarding place: that end and the landing,
-- corrected. ends: { [key] = { a = { cont, wx, wy }, b = ... } } (changed in
-- place); list: as C.Best; before, after: { cont, wx, wy }. -> the key, or nil
function C.Learn(ends, list, before, after, near)
    if not (before and after and before.cont ~= nil and after.cont ~= nil and before.cont ~= after.cont) then return nil end
    local bestKey, bestSide, bestD
    for _, e in ipairs(list or {}) do
        for _, side in ipairs({ "a", "b" }) do
            local p = e[side]
            local other = e[side == "a" and "b" or "a"]
            if p and other and p.cont == before.cont and other.cont == after.cont then
                local d = dist(p.wx, p.wy, before.wx, before.wy)
                -- (Two crossings can share a tower, Orgrimmar's: the one whose
                -- landing is nearest to where you appeared is the one you took.)
                local score = d + dist(other.wx, other.wy, after.wx, after.wy)
                if d <= (near or C.NEAR) and (not bestD or score < bestD) then bestKey, bestSide, bestD = e.key, side, score end
            end
        end
    end
    if not bestKey then return nil end
    ends[bestKey] = ends[bestKey] or {}
    ends[bestKey][bestSide] = { cont = before.cont, wx = before.wx, wy = before.wy }
    ends[bestKey][bestSide == "a" and "b" or "a"] = { cont = after.cont, wx = after.wx, wy = after.wy }
    return bestKey
end

-------------------------------------------------------------------------------
-- The crossings you can use, in world yards
-------------------------------------------------------------------------------
local function world(spot)
    local N = ns.nav
    if not (N and N.ToWorld and spot and spot.map) then return nil end
    local ok, cont, wx, wy = pcall(N.ToWorld, N, spot.map, spot.x, spot.y)
    if ok and cont ~= nil and wx then return { cont = cont, wx = wx, wy = wy } end
    return nil
end

function C.List()
    local out = {}
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local learned = (ns.db and ns.db.nav and ns.db.nav.crossingEnds) or {}
    for key, cr in ns:Each("crossing") do
        if C.Usable(cr, faction) then
            local l = learned[key] or {}
            local a, b = l.a or world(cr.a), l.b or world(cr.b)
            if a and b then out[#out + 1] = { key = key, cr = cr, a = a, b = b, learned = (l.a or l.b) and true or false } end
        end
    end
    table.sort(out, function(x, y) return x.key < y.key end)
    return out
end

-- Your steps that wait on another continent, by continent:
-- { [cont] = { goals = { goal }, targets = { { cont, wx, wy } } } }
function C.Waiting(me)
    local N = ns.nav
    local by, seen = {}, {}
    for _, list in ipairs({ N:Goals() or {}, N.blockedGoals or {}, ns.focus and ns.focus.all or {} }) do
        for _, g in ipairs(list) do
            if type(g.key) == "string" and not seen[g.key] and g.provider ~= "crossing" and not g.optional then
                seen[g.key] = true
                local ok, cont = pcall(N.AwayCont, g, me.cont)
                if ok and cont ~= nil then
                    local e = by[cont] or { goals = {}, targets = {} }
                    by[cont] = e
                    e.goals[#e.goals + 1] = g
                    for _, pt in ipairs(g.points or {}) do
                        if pt.wx and pt.cont == cont and #e.targets < 60 then e.targets[#e.targets + 1] = { cont = cont, wx = pt.wx, wy = pt.wy } end
                    end
                end
            end
        end
    end
    return by
end

-- Steps that wait on a continent no crossing you can use joins (F-053): one
-- line each, naming what's missing, for /flow crossings. Pure.
--   waiting: C.Waiting's shape; list: C.List's; me: { cont, wx, wy }
function C.Unjoined(waiting, list, me)
    local out = {}
    for cont, e in pairs(waiting or {}) do
        if not C.Best(list, me, e.targets) then
            local n = #(e.goals or {})
            local why = #(list or {}) == 0
                and "no crossing your faction can use is known, or none of their map spots could be read"
                or (#(e.targets or {}) == 0 and "those steps have no place on the map to aim for"
                    or "no known crossing joins your continent to that one")
            out[#out + 1] = string.format("%d step%s in %s can't be routed: %s", n, n == 1 and "" or "s",
                C.NAMES[cont] or "another continent", why)
        end
    end
    table.sort(out)
    return out
end

ns:Register("navGoal", "crossing", {
    collect = function()
        C.unjoined = nil
        if not C.On() then return nil end
        local N = ns.nav
        local me = N and N.PlayerPos and N:PlayerPos()
        if not (me and me.cont ~= nil and me.wx) then return nil end
        local list = C.List()
        local waiting = C.Waiting(me)
        C.unjoined = C.Unjoined(waiting, list, me)
        if #list == 0 then C.last = {} return nil end
        local goals = {}
        for cont, e in pairs(waiting) do
            local best = C.Best(list, me, e.targets)
            if best then
                local n = #e.goals
                local details = {
                    string.format("%d step%s of yours %s in %s, where the route can't take you on foot:", n, n == 1 and "" or "s", n == 1 and "is" or "are", C.NAMES[cont] or "another continent"),
                }
                for i = 1, math.min(5, n) do details[#details + 1] = "- " .. tostring(e.goals[i].text or e.goals[i].title or e.goals[i].key) end
                if n > 5 then details[#details + 1] = string.format("- and %d more", n - 5) end
                details[#details + 1] = string.format("Board at %s; it lands at %s. It comes by every few minutes.", tostring(best.from.place or best.from.name), tostring(best.to.place or best.to.name))
                local toBoard = dist(me.wx, me.wy, best.board.wx, best.board.wy)
                local weight = C.Weight(toBoard, C.HearthReady())
                details[#details + 1] = C.WhenText(weight)
                details[#details + 1] = "The boarding place is corrected from where you actually board."
                goals[#goals + 1] = {
                    key = "cross:" .. tostring(cont), kind = "merchant", crossing = best.key, weight = weight, toCont = cont,
                    points = { { cont = best.board.cont, wx = best.board.wx, wy = best.board.wy, map = best.from.map, x = best.from.x, y = best.from.y } },
                    title = "Crossing", text = C.Text(best.cr.how, best.to.name, n, C.NAMES[cont]),
                    details = details, forQuests = C.QuestsOf(e.goals),
                }
            end
        end
        C.last = goals
        return goals
    end,
})
-- Is your hearthstone ready (and set somewhere)? The way back from across the sea.
function C.HearthReady()
    local H = ns.hearth
    if not (H and H.CooldownLeft) then return false end
    local ok, left = pcall(H.CooldownLeft, H)
    return ok and left ~= nil and left <= 60
end

-- "Go here next" on a step across the sea (0.35.372: "they just don't even
-- have points ... if we can make it so that those do, then I can hit go here
-- next on them, and you can use the gateways to get me there"). The step
-- itself can't be walked to, but its crossing can: its quest line joins your
-- custom route and the crossing becomes the next step.
-- The continent a step waits on, when that isn't yours (nil: it's here).
function C.AwayOf(goal)
    local N = ns.nav
    local me = N and N.PlayerPos and N:PlayerPos()
    if not (goal and me and me.cont ~= nil) then return nil end
    local ok, cont = pcall(N.AwayCont, goal.awayRoot or goal, me.cont)
    return ok and cont or nil
end
-- Pure: the crossing step for a continent among the route's, or nil.
function C.StepFor(cont, steps)
    for _, g in ipairs(steps or {}) do
        if g.toCont == cont then return g end
    end
end
function C.CanLead(goal)
    local cont = C.AwayOf(goal)
    return cont ~= nil and C.StepFor(cont, C.last) ~= nil
end
function C.Lead(goal)
    local cont = C.AwayOf(goal)
    local step = cont ~= nil and C.StepFor(cont, C.last) or nil
    if not step then return false end
    if ns.focus and ns.focus.AddKey then ns.focus.AddKey(goal.key, goal.text or goal.title) end
    ns.nav:Select(step.key)
    ns:Print(string.format("%s is across the sea: %s is your next step.", tostring(goal.text or goal.title or "That step"), tostring(step.text)))
    return true
end

ns:Register("routeKind", "crossings", { order = 66, default = true,
    label = "Crossing to another continent (zeppelins, boats)", short = "crossings",
    tip = "While steps of yours wait on another continent, a step at the zeppelin tower or the dock that gets you there, planned after what's left to do here. "
        .. "Off: those steps are only listed as locked, with how to cross.",
    match = function(g) return g.provider == "crossing" end })

-------------------------------------------------------------------------------
-- Correcting the boarding places from where you board
-------------------------------------------------------------------------------
local lastPos
function C.Tick()
    local N = ns.nav
    local p = N and N.PlayerPos and N:PlayerPos()
    if not (p and p.cont ~= nil and p.wx) then return end
    local before = lastPos
    lastPos = { cont = p.cont, wx = p.wx, wy = p.wy }
    if not before or before.cont == p.cont then return end
    ns.db.nav.crossingEnds = ns.db.nav.crossingEnds or {}
    local key = C.Learn(ns.db.nav.crossingEnds, C.List(), before, lastPos)
    if key then
        ns:Log("nav", string.format("crossing %s: boarding place and landing corrected from this trip", key))
        if N.RequestCollect then N.RequestCollect("crossed to another continent") end
    end
end
ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.crossingEnds = saved.nav.crossingEnds or {}
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(C.Tick) end) end
end)

function C.Lines()
    local list = C.List()
    local out = { string.format("crossings you can use: %d%s", #list, C.On() and "" or " (off)") }
    for _, e in ipairs(list) do
        out[#out + 1] = string.format("  %s: %s %s <-> %s%s", e.key, tostring(e.cr.how), tostring(e.cr.a.name), tostring(e.cr.b.name), e.learned and " (corrected from a trip of yours)" or "")
    end
    for _, g in ipairs(C.last or {}) do out[#out + 1] = "  on your route: " .. tostring(g.text) end
    for _, l in ipairs(C.unjoined or {}) do out[#out + 1] = "  " .. l end
    if #(C.last or {}) == 0 and #(C.unjoined or {}) == 0 then out[#out + 1] = "  nothing of yours waits on another continent" end
    return out
end
ns.commands.crossings = function(arg)
    arg = (arg or ""):lower()
    if arg == "forget" then
        wipe(ns.db.nav.crossingEnds)
        ns:Print("forgot the corrected boarding places")
        return
    end
    for i, l in ipairs(C.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow crossings forget (the corrected boarding places)")
end
ns:Register("help", "crossings", { order = 38, title = "Crossing to another continent", lines = {
    "While steps of yours wait on another continent, your route gets a step at the zeppelin tower or dock that gets you there, by the crossing that makes the whole trip shortest. It comes after what's left to do here.",
    "The boarding places are Classic's and may be a little off: Flow corrects each from where you actually board. /flow crossings lists them. Route includes has a tick for the step.",
} })
