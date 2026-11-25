local _, ns = ...
-- Z-Flow learned quest spots (S43, lead dispatch P-TRIP): where the player
-- stood when one of their quest objectives moved on (its text in the quest
-- log changed, "Boars slain: 0/4" to "1/4") or when a complete quest left
-- the log (handed in). Learned from the player's own play only: no quest,
-- place or route data of any other add-on is copied here. The quest route
-- (Nav/TripRoute.lua) and the quest arrow (Nav/QuestRead.lua QuestWatch)
-- use these spots where Questie gives no place.
--
-- Saved, account wide, at QS.PATH (the path the Flow import already fills,
-- Import/FromFlow.lua KIND.questSpots):
--   [quest id][objective index] = { { map, x, y, n, at }, ... }
--   objective index QS.TURN_IN (0) is where the quest was handed in.
--   x, y shares 0..1 of map; n how often the player was there; at the
--   client's clock when last seen (absent when the clock is not known).
--   No more than QS.POINTS_MAX spots per objective, QS.QUESTS_MAX quests.
--
-- Pure:
--   QS.Changes(before, after, doneFn) -> { { quest, objective } }
--   QS.Record(book, change, at, now) -> true when kept
--   QS.Places(book, rows, map) -> places as N.QuestSource Q.Pick takes them
--   QS.Merge(primary, learned) -> places: primary's spots, learned where
--     primary has none on this map
--   QS.Lines(book, titles, mapName) -> chat lines for /zflow spots (parity
--     row C-08, lead section 603): one line per quest, by quest id, its
--     objectives then the hand-in, each spot "<map> x, y" in percent;
--     at most QS.LINES_MAX quests. Text only; a window would be Muse's.
-- Module "questSpots": looks at the quest log every QS.EVERY seconds while
-- the setting QS.SETTING is on. LOOK ONLY: it reads the log and the
-- player's position; it accepts, hands in, targets and clicks nothing.
-- Not tested in game: whether the log text changes on the same look as
-- the kill, and whether client.questDone already says true right after a
-- hand-in, are not seen on 16001.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local QS = {}
N.QuestSpots = QS

QS.NAME = "questSpots"
QS.PATH = "learned.places.questSpots"
QS.SETTING = "quest.learnSpots"
QS.TURN_IN = 0
QS.POINTS_MAX = 8
QS.QUESTS_MAX = 300
QS.NEAR = 0.02     -- shares of the map: closer than this is the same spot
QS.EVERY = 1       -- seconds between looks at the quest log
QS.WORD = "spots"
QS.HELP = "quest spots learned from your own play: where each objective moved on and where quests were handed in"
QS.NONE = "No quest spots learned yet. They are learned as your quest objectives move on and quests are handed in."
QS.LINES_MAX = 20

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

function QS.Changes(before, after, doneFn)
    local out = {}
    if type(before) ~= "table" or type(after) ~= "table" then return out end
    local now = {}
    for _, r in ipairs(after) do
        if type(r) == "table" and r.id ~= nil then now[r.id] = r end
    end
    for _, r in ipairs(before) do
        if type(r) == "table" and r.id ~= nil then
            local a = now[r.id]
            if a then
                local olds, news = r.objectives or {}, a.objectives or {}
                for i, o in ipairs(olds) do
                    local n = news[i]
                    if type(o) == "table" and type(n) == "table" then
                        local moved = type(o.text) == "string" and type(n.text) == "string" and o.text ~= n.text
                        if moved or (o.done ~= true and n.done == true) then
                            out[#out + 1] = { quest = r.id, objective = i }
                        end
                    end
                end
            elseif r.complete == true then
                local done = nil
                if type(doneFn) == "function" then
                    local ok, v = pcall(doneFn, r.id)
                    if ok then done = v end
                end
                if done ~= false then out[#out + 1] = { quest = r.id, objective = QS.TURN_IN } end
            end
        end
    end
    return out
end

-- When the quest of an entry was last seen: its newest spot's clock.
local function lastSeen(entry)
    local best = 0
    for _, list in pairs(type(entry) == "table" and entry or {}) do
        for _, p in ipairs(type(list) == "table" and list or {}) do
            if type(p) == "table" and finite(p.at) and p.at > best then best = p.at end
        end
    end
    return best
end

local function capQuests(book, keep)
    local n, oldest, oldestAt = 0, nil, nil
    for id, entry in pairs(book) do
        n = n + 1
        if id ~= keep then
            local at = lastSeen(entry)
            if oldest == nil or at < oldestAt
                or (at == oldestAt and type(id) == "number" and type(oldest) == "number" and id < oldest) then
                oldest, oldestAt = id, at
            end
        end
    end
    if n > QS.QUESTS_MAX and oldest ~= nil then book[oldest] = nil end
end

function QS.Record(book, change, at, now)
    if type(book) ~= "table" or type(change) ~= "table" or change.quest == nil then return false end
    local i = change.objective
    if not finite(i) then return false end
    if type(at) ~= "table" or at.map == nil or not (share(at.x) and share(at.y)) then return false end
    local entry = book[change.quest]
    if type(entry) ~= "table" then
        entry = {}
        book[change.quest] = entry
    end
    local list = entry[i]
    if type(list) ~= "table" then
        list = {}
        entry[i] = list
    end
    local stamp = finite(now) and now or nil
    for _, p in ipairs(list) do
        if type(p) == "table" and p.map == at.map and finite(p.x) and finite(p.y)
            and math.abs(p.x - at.x) < QS.NEAR and math.abs(p.y - at.y) < QS.NEAR then
            p.n = (finite(p.n) and p.n or 0) + 1
            p.at = stamp or p.at
            return true
        end
    end
    list[#list + 1] = { map = at.map, x = at.x, y = at.y, n = 1, at = stamp }
    if #list > QS.POINTS_MAX then
        -- The least often seen goes; of those, the one kept longest.
        local drop, dropN = 1, nil
        for k = 1, #list - 1 do
            local n = type(list[k]) == "table" and finite(list[k].n) and list[k].n or 0
            if dropN == nil or n < dropN then drop, dropN = k, n end
        end
        table.remove(list, drop)
    end
    capQuests(book, change.quest)
    return true
end

-- One saved list as a spot: its points on map, else one away point (on the
-- lowest other map, the same every time) and elsewhere.
local function spotOf(list, map)
    local spot = { points = {} }
    local away
    for _, p in ipairs(type(list) == "table" and list or {}) do
        if type(p) == "table" and p.map ~= nil and share(p.x) and share(p.y) then
            if p.map == map then
                spot.points[#spot.points + 1] = { map = p.map, x = p.x, y = p.y }
            elseif away == nil or (type(p.map) == "number" and type(away.map) == "number" and p.map < away.map) then
                away = { map = p.map, x = p.x, y = p.y }
            end
        end
    end
    if #spot.points == 0 and away ~= nil then
        spot.elsewhere = true
        if map ~= nil then spot.away = away end
    end
    return spot
end

function QS.Places(book, rows, map)
    if type(book) ~= "table" then return nil end
    local places = {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local entry = type(row) == "table" and book[row.id] or nil
        if type(entry) == "table" then
            local e = { objectives = {} }
            for i, list in pairs(entry) do
                if i == QS.TURN_IN then
                    e.turnIn = spotOf(list, map)
                elseif finite(i) then
                    e.objectives[i] = spotOf(list, map)
                end
            end
            places[row.id] = e
        end
    end
    return places
end

local function hasPoints(spot)
    return type(spot) == "table" and type(spot.points) == "table" and #spot.points > 0
end

-- The better of two spots: the primary's, unless it has no point on this
-- map and the learned one has, or it has no place at all.
local function better(p, l)
    if type(l) ~= "table" then return p end
    if type(p) ~= "table" then return l end
    if hasPoints(p) then return p end
    if hasPoints(l) then return l end
    if p.away == nil and l.away ~= nil then return l end
    return p
end

function QS.Merge(primary, learned)
    if type(learned) ~= "table" then return primary end
    if type(primary) ~= "table" then return learned end
    local out = {}
    for id, e in pairs(primary) do out[id] = e end
    for id, l in pairs(learned) do
        local p = out[id]
        if type(p) ~= "table" then
            out[id] = l
        elseif type(l) == "table" then
            local m = { objectives = {} }
            for i, s in pairs(type(p.objectives) == "table" and p.objectives or {}) do m.objectives[i] = s end
            for i, s in pairs(type(l.objectives) == "table" and l.objectives or {}) do
                m.objectives[i] = better(m.objectives[i], s)
            end
            m.turnIn = better(p.turnIn, l.turnIn)
            out[id] = m
        end
    end
    return out
end

local function spotText(p, mapName)
    local ok, name = pcall(mapName, p.map)
    name = ok and type(name) == "string" and name ~= "" and name or ("map " .. tostring(p.map))
    local line = ("%s %.1f, %.1f"):format(name, p.x * 100, p.y * 100)
    if finite(p.n) and p.n > 1 then line = line .. (" (%d times)"):format(p.n) end
    return line
end

function QS.Lines(book, titles, mapName)
    if type(mapName) ~= "function" then mapName = function() return nil end end
    local quests, spots = {}, 0
    for q, list in pairs(type(book) == "table" and book or {}) do
        if type(q) == "number" and type(list) == "table" then
            local parts = {}
            local order = {}
            for o in pairs(list) do
                if type(o) == "number" and o ~= QS.TURN_IN then order[#order + 1] = o end
            end
            table.sort(order)
            if list[QS.TURN_IN] ~= nil then order[#order + 1] = QS.TURN_IN end
            for _, o in ipairs(order) do
                local texts = {}
                for _, p in ipairs(type(list[o]) == "table" and list[o] or {}) do
                    if type(p) == "table" and share(p.x) and share(p.y) then
                        texts[#texts + 1] = spotText(p, mapName)
                    end
                end
                if #texts > 0 then
                    spots = spots + #texts
                    local what = o == QS.TURN_IN and "hand-in" or ("objective " .. o)
                    parts[#parts + 1] = what .. " at " .. table.concat(texts, ", ")
                end
            end
            if #parts > 0 then quests[#quests + 1] = { id = q, text = table.concat(parts, "; ") } end
        end
    end
    if #quests == 0 then return { QS.NONE } end
    table.sort(quests, function(a, b) return a.id < b.id end)
    local out = { ("%d quest%s, %d learned spot%s:"):format(#quests, #quests == 1 and "" or "s",
        spots, spots == 1 and "" or "s") }
    for i = 1, math.min(#quests, QS.LINES_MAX) do
        local e = quests[i]
        local title = type(titles) == "table" and titles[e.id] or nil
        local head = type(title) == "string" and title ~= "" and (title .. " (" .. e.id .. ")") or ("quest " .. e.id)
        out[#out + 1] = head .. ": " .. e.text
    end
    if #quests > QS.LINES_MAX then
        local more = #quests - QS.LINES_MAX
        out[#out + 1] = ("and %d more quest%s."):format(more, more == 1 and "" or "s")
    end
    return out
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function QS.Declare(k, diag)
    local api = {}
    local ctx, cancel
    local before = nil

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, QS.SETTING)
        return not (ok and v == false)
    end

    function api.Book()
        if not ctx then return nil end
        local b = ctx.store:get("account", QS.PATH)
        return type(b) == "table" and b or nil
    end

    local function look()
        if not on() then
            before = nil
            return
        end
        local client = ctx.client
        local rows = N.QuestLogRows(client)
        if rows == nil then return end
        local changes = QS.Changes(before, rows, function(id) return ask(client, "questDone", id) end)
        before = rows
        if #changes == 0 then return end
        local at = ask(client, "position")
        if type(at) ~= "table" then return end
        local book = api.Book() or {}
        local kept = false
        local now = ask(client, "clock")
        for _, change in ipairs(changes) do
            if QS.Record(book, change, at, now) then kept = true end
        end
        if kept then
            local ok, why = ctx.store:set("account", QS.PATH, book)
            if not ok then k.problems:add(QS.NAME, "save", tostring(why)) end
        end
    end

    k:Setting({ key = QS.SETTING, scope = "account", type = "bool", default = true,
        label = "Learn where my quest objectives are", group = "travel.route",
        help = "Remembers where you stood when a quest objective moved on or a quest was handed in; used by the quest arrow and the route when Questie gives no place.",
        synonyms = { "quest", "spots", "learn", "objectives", "route" } })

    k:Module({
        name = QS.NAME,
        needs = { "client", "store", "settings", "sched" },
        provides = { Book = api.Book },
        start = function(c)
            ctx = c
            before = nil
            cancel = c.sched:every(QS.NAME, QS.EVERY, look)
        end,
        stop = function()
            if cancel then cancel() end
            cancel, before = nil, nil
        end,
    })

    if type(diag) == "table" and type(diag.commands) == "table" then
        diag.commands[QS.WORD] = function()
            if not ctx then return end
            local client = ctx.client
            local titles = {}
            for _, row in ipairs(N.QuestLogRows(client) or {}) do
                if type(row) == "table" and row.id ~= nil then titles[row.id] = row.title end
            end
            local lines = QS.Lines(api.Book(), titles, function(m) return ask(client, "mapName", m) end)
            client.print(ns.id.title .. ": " .. lines[1])
            for i = 2, #lines do client.print(lines[i]) end
            if not on() then client.print("Learning is off (setting: Learn where my quest objectives are).") end
        end
        if type(diag.help) == "table" then diag.help[QS.WORD] = QS.HELP end
    end
    return api
end

ns.questSpots = QS.Declare(ns, ns.diag)
