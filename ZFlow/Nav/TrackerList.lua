local _, ns = ...
-- What the tracker window lists for each step (FLOW-PARITY A2-18), the
-- logic half, after legacy Flow's tracker (Modules/Nav/RouteTracker.lua,
-- the next steps: every step with what it is, objectives with their counts,
-- turn-ins, quests to accept). The window is UI/RouteTracker.lua's and the
-- look is the drawing lane's (a MUSE NEED: a mark by kind, the count by
-- the label). Pure Lua 5.1: no client calls.
--
-- Facts are the route's and the log's own (owner section 611): the steps
-- are Nav/TripRoute.lua View()'s (the route planned by itself too, and
-- held steps with their reason); the count is read from the log's own
-- objective text ("Boars slain: 2/8"), never made up; the distance is
-- Nav/Trip.lua P.TrackRows', from where you stand.
--
--   TL.Kind(stop) -> "objective" | "turnin" | "pickup" | "town" | "run" | nil
--   TL.Count(stop) -> "2/8" | nil
--   TL.Rows(view, here[, max]) -> rows, more, nLeft | nil
--     rows: { label, kind, count, detail, dist, held (why) | nil,
--             current = true on the first step not held }: the steps not
--     held in route order, then the held ones (no distance: not walked),
--     at most max (TL.MAX); more: how many route steps are left out.
--     Then, in the rows left over, the steps that can't be placed
--     (View().left): { label, kind, detail, left = why }, no distance, never
--     current; nLeft counts them all, shown or not. As Flow's tracker: its
--     blocked goals after the plan (Modules/Nav/RouteTracker.lua:504-519),
--     all of them counted for the lock (:476, RT.Title :458-460).
--     nil: no route and nothing left.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local TL = {}
N.TrackerList = TL

TL.MAX = 8
TL.TOWN = { sell = true, repair = true, riding = true, hearth = true }
TL.RUN = { giver = true, entrance = true, ready = true, run = true }

function TL.Kind(stop)
    if type(stop) ~= "table" then return nil end
    if stop.turnIn == true then return "turnin" end
    if stop.kind == "pickup" then return "pickup" end
    if TL.TOWN[stop.kind] then return "town" end
    if TL.RUN[stop.kind] then return "run" end
    if stop.quest ~= nil then return "objective" end
    return nil
end

function TL.Count(stop)
    if type(stop) ~= "table" or type(stop.detail) ~= "string" then return nil end
    return stop.detail:match("(%d+/%d+)")
end

function TL.Rows(view, here, max)
    if type(view) ~= "table" then return nil end
    local stops, left = view.stops, view.left
    if type(stops) ~= "table" then stops = {} end
    if type(left) ~= "table" then left = {} end
    if #stops == 0 and #left == 0 then return nil end
    max = tonumber(max) or TL.MAX
    -- Lead section 770: the walked steps first, then the held ones, as
    -- Flow's tracker lists its plan and then its blocked goals (a held step
    -- is not in Flow's plan). The legs are the walked steps' own.
    local walked, held = {}, {}
    for _, s in ipairs(stops) do
        if type(s) == "table" and s.held ~= nil then
            held[#held + 1] = s
        else
            walked[#walked + 1] = s
        end
    end
    local dists = {}
    local T = N.Trip
    if #walked > 0 and type(T) == "table" and type(T.TrackRows) == "function" then
        local ok, got = pcall(T.TrackRows, { stops = walked }, here)
        if ok and type(got) == "table" then
            for i, r in ipairs(got) do dists[i] = r.dist end
        end
    end
    local rows = {}
    local function add(s, dist)
        local label = "?"
        if type(s) == "table" and s.label ~= nil then label = s.label end
        local row = { label = tostring(label), kind = TL.Kind(s), count = TL.Count(s), dist = dist }
        if type(s) == "table" then
            row.detail = s.detail
            if s.held ~= nil then row.held = tostring(s.held) end
        end
        rows[#rows + 1] = row
        return row
    end
    for i, s in ipairs(walked) do
        if #rows >= max then break end
        local row = add(s, dists[i])
        if i == 1 then row.current = true end
    end
    for _, s in ipairs(held) do
        if #rows >= max then break end
        add(s, nil)
    end
    for _, l in ipairs(left) do
        if #rows >= max then break end
        local label, why = "?", "?"
        if type(l) == "table" then
            if l.label ~= nil then label = l.label end
            if l.why ~= nil then why = l.why end
        end
        local row = { label = tostring(label), kind = TL.Kind(l), left = tostring(why) }
        if type(l) == "table" and l.detail ~= nil then row.detail = l.detail end
        rows[#rows + 1] = row
    end
    return rows, math.max(0, #stops - max), #left
end
