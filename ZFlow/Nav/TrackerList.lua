local _, ns = ...
-- The route's rows: the ONE builder of the stops list, for the tracker
-- window (UI/RouteTracker.lua), the list beside the quest log
-- (UI/RouteList.lua) and the numbers on the world map (UI/MapRoute.lua)
-- — slice 5 (DISPATCH section 893): there was one builder per window
-- and they could disagree (a held step read "Waiting: ..." in one and
-- "Held: ..." in the other). The windows draw these rows; the look is
-- theirs, the rows are these.
--
-- Facts are the route's and the log's own (owner section 611): the
-- steps are Nav/TripRoute.lua View()'s or the current trip's (the
-- tracker picks its source, RT.Rows), held steps with their reason;
-- the count is read from the log's own objective text ("Boars slain:
-- 2/8"), never made up; the distance is Nav/Trip.lua P.TrackRows',
-- from where you stand. Pure Lua 5.1: no client calls.
--
--   TL.Kind(stop) -> "objective" | "turnin" | "pickup" | "town" | "run" | nil
--   TL.Count(stop) -> "2/8" | nil
--   TL.Why(why) -> the reason in plain words, as a whole sentence
--   TL.MaxShown(v) -> the row cap nav.routeShown asks for (TL.ALL: all)
--   TL.Plan(mode, sort) -> "Today's route · Shortest first", or nil
--   TL.Rows(view, here[, max[, needOf]]) -> rows, more, nLeft, counts | nil
--     rows: one per stop to walk, numbered in route order (n), turn-ins
--     at one place as one row (merged, names, to); then the held ones
--     (held = the reason in plain words, why = as the route gave it);
--     then the steps that can't be placed (left = the plain why).
--     A row: { n, label, kind, count, detail, text, sub, icon, place,
--     dist, quest, current and now on the first walked row, merged,
--     names, to, held, why, left, blocked on held and left rows }.
--     At most max rows in all (TL.MAX when not given); more: how many
--     stops are left out by the cap; nLeft: how many steps can't be
--     placed, shown or not; counts: { stops, waiting } over all stops,
--     capped or not. needOf(quest) -> tags, note (Questie's fields,
--     through the caller) tags a row's text, as the list has always done.
--     nil: no route and nothing left.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local TL = {}
N.TrackerList = TL

TL.MAX = 8
TL.ALL = math.huge
TL.TOWN = { sell = true, repair = true, riding = true, hearth = true }
TL.RUN = { giver = true, entrance = true, ready = true, run = true }
TL.TURN_IN = "Turn in %s"
TL.TURN_IN_MANY = "Turn in %d quests"
TL.GIVE_TO = "Give it to %s"
TL.GIVE_THEM_TO = "Give them to %s"
TL.FOR_QUEST = "For the quest %s"
-- Tags from Questie's quest fields (Flow Q.ApplyNeed).
TL.ESCORT = "escort"
TL.GROUP = "group of %d"
TL.TAGS = "%s (%s)"
-- The held and left-off steps' part headings, the same in both windows.
TL.WAITING_HEAD = "Waiting"
TL.LEFT_HEAD = "Not on the route"
TL.LEFT_OFF = "Not on the route: %s"

-- The reasons the route gives in a few words, said as a whole sentence. A
-- reason not listed here is shown as the route gave it.
TL.PLAIN = {
    ["not complete any more"] = "this quest is not complete any more. Finish it again first.",
    ["objectives not read yet"] = "the game has not told its objectives yet. Open the quest once.",
    ["a quest before it is not done"] = "a quest that comes before it is not done.",
    ["not on this map"] = "it is in another zone. Plan a new route when you get there.",
    ["giver's place not known"] = "nobody you met has shown where its giver stands.",
    ["location unknown"] = "its place is not known yet.",
}

local function isText(v) return type(v) == "string" and v ~= "" end

function TL.Why(why)
    if not isText(why) then return "the route gave no reason." end
    return TL.PLAIN[why] or why
end

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

-- How many rows nav.routeShown asks for: its choices are "5", "10",
-- "15", "20" and "All"; no saved value (or anything else) is all.
function TL.MaxShown(v)
    local n = tonumber(v)
    if n ~= nil and n >= 1 then return math.floor(n) end
    return TL.ALL
end

-- The plan in one plain line, from TripRoute's own labels (section
-- 651): "Today's route · Shortest first".
function TL.Plan(mode, sort)
    local T = N.TripRoute
    if type(T) ~= "table" or type(T.ModeOf) ~= "function" or type(T.SortOf) ~= "function" then return nil end
    local ml = type(T.MODE_LABELS) == "table" and T.MODE_LABELS[T.ModeOf(mode)] or nil
    local sl = type(T.SORT_LABELS) == "table" and T.SORT_LABELS[T.SortOf(sort)] or nil
    if not isText(ml) or not isText(sl) then return nil end
    return ml .. " · " .. sl
end

-- "Turn in: <name>" (Nav/QuestSource.lua Q.TURN_IN_TO) -> the name, or nil.
local function receiver(detail)
    if not isText(detail) then return nil end
    local Q = N.QuestSource
    local form = type(Q) == "table" and Q.TURN_IN_TO or "Turn in: %s"
    local head = form:gsub("%%s", "")
    if detail:sub(1, #head) == head and #detail > #head then return detail:sub(#head + 1) end
    return nil
end

local function samePlace(a, b)
    return type(a) == "table" and type(b) == "table" and a.map == b.map and a.x == b.x and a.y == b.y
end

-- One stop's words: text, sub, icon (a Kit.look.icon key).
local function words(s)
    local label = isText(s.label) and s.label or "?"
    if s.kind == nil and s.turnIn == true then
        local to = receiver(s.detail)
        return TL.TURN_IN:format(label), to and TL.GIVE_TO:format(to) or nil, "questInLog"
    end
    if s.kind == nil and s.quest ~= nil then
        if isText(s.detail) then return s.detail, TL.FOR_QUEST:format(label), "questLater" end
        return label, nil, "questLater"
    end
    return label, isText(s.detail) and s.detail or nil, s.kind == "pickup" and "questAvailable" or nil
end

function TL.Needs(raw)
    if type(raw) ~= "table" then return nil end
    local tags = {}
    local te = raw.triggerEnd
    local text = type(te) == "table" and te[1]
    if type(text) == "string" and text:lower():find("escort", 1, true) then
        tags[#tags + 1] = TL.ESCORT
    end
    local g = raw.suggestedGroup
    if type(g) == "number" and g == g and g >= 2 and g < 100 then
        tags[#tags + 1] = TL.GROUP:format(math.floor(g))
    end
    if #tags == 0 then return nil end
    return tags, nil
end

local function withNeeds(row, quest, needOf)
    if type(needOf) ~= "function" or quest == nil then return row end
    local ok, tags, note = pcall(needOf, quest)
    if not ok or type(tags) ~= "table" or #tags == 0 then return row end
    row.text = TL.TAGS:format(row.text, table.concat(tags, ", "))
    if isText(note) then row.sub = row.sub and (note .. " " .. row.sub) or note end
    return row
end

function TL.Rows(view, here, max, needOf)
    if type(view) ~= "table" then return nil end
    local stops, left = view.stops, view.left
    if type(stops) ~= "table" then stops = {} end
    if type(left) ~= "table" then left = {} end
    if #stops == 0 and #left == 0 then return nil end
    max = tonumber(max) or TL.MAX
    -- Lead section 770: the walked steps first, then the held ones, as
    -- Flow's tracker lists its plan and then its blocked goals (a held
    -- step is not in Flow's plan).
    local walkedRaw, heldRaw = {}, {}
    for _, s in ipairs(stops) do
        if type(s) == "table" and s.held ~= nil then
            heldRaw[#heldRaw + 1] = s
        else
            walkedRaw[#walkedRaw + 1] = s
        end
    end
    -- Turn-ins at one place are one row (the list beside the quest log
    -- has always read them so; now the tracker reads the same rows).
    local walked = {}
    for _, s in ipairs(walkedRaw) do
        local last = walked[#walked]
        if last and last.turnIn and type(s) == "table" and s.kind == nil and s.turnIn == true
            and type(last.stop) == "table" and samePlace(last.stop.place, s.place) then
            last.merged = last.merged + 1
            last.names[#last.names + 1] = isText(s.label) and s.label or "?"
            if last.to ~= receiver(s.detail) then last.to = nil end
        else
            walked[#walked + 1] = { stop = s, merged = 1,
                names = { type(s) == "table" and isText(s.label) and s.label or "?" },
                to = type(s) == "table" and receiver(s.detail) or nil,
                turnIn = type(s) == "table" and s.kind == nil and s.turnIn == true }
        end
    end
    -- The legs are the walked rows' own (over the merged rows' first
    -- stops, as the list has always counted them).
    local dists = {}
    local T = N.Trip
    if #walked > 0 and type(T) == "table" and type(T.TrackRows) == "function" then
        local plain = {}
        for i, w in ipairs(walked) do plain[i] = w.stop end
        local ok, got = pcall(T.TrackRows, { stops = plain }, here)
        if ok and type(got) == "table" then
            for i, r in ipairs(got) do dists[i] = r.dist end
        end
    end
    local rows = {}
    local function baseRow(s)
        local label = "?"
        if type(s) == "table" and s.label ~= nil then label = s.label end
        local row = { label = tostring(label), kind = TL.Kind(s), count = TL.Count(s) }
        if type(s) == "table" then
            row.detail = s.detail
            row.place = s.place
            row.quest = s.quest
        end
        return row
    end
    for i, w in ipairs(walked) do
        if #rows >= max then break end
        local s = w.stop
        local row = baseRow(s)
        row.n = i
        row.dist = dists[i]
        row.merged, row.names, row.to = w.merged, w.names, w.to
        if i == 1 then row.current, row.now = true, true end
        if w.merged > 1 then
            row.text = TL.TURN_IN_MANY:format(w.merged)
            row.sub = table.concat(w.names, ", ")
            if w.to then row.sub = row.sub .. ". " .. TL.GIVE_THEM_TO:format(w.to) end
            row.icon = "questInLog"
        elseif type(s) == "table" then
            local text, sub, icon = words(s)
            row.text, row.sub, row.icon = text, sub, icon
            withNeeds(row, s.quest, needOf)
        else
            row.text = row.label
        end
        rows[#rows + 1] = row
    end
    for _, s in ipairs(heldRaw) do
        if #rows >= max then break end
        local row = baseRow(s)
        local text = words(s)
        row.text = text
        row.icon = "questNotForYou"
        row.blocked = true
        row.why = s.held
        row.held = TL.Why(s.held)
        row.sub = row.held
        withNeeds(row, s.quest, needOf)
        rows[#rows + 1] = row
    end
    for _, l in ipairs(left) do
        if #rows >= max then break end
        local row = { label = "?", kind = TL.Kind(l), blocked = true }
        if type(l) == "table" then
            if l.label ~= nil then row.label = tostring(l.label) end
            row.detail = l.detail
            row.quest = l.quest
            row.why = l.why
        end
        row.left = TL.Why(row.why)
        row.text = row.label
        row.sub = TL.LEFT_OFF:format(row.left)
        row.icon = "questNotForYou"
        rows[#rows + 1] = row
    end
    local counts = { stops = #walked, waiting = #heldRaw }
    return rows, math.max(0, #stops - max), #left, counts
end
