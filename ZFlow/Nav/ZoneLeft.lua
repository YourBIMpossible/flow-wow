local _, ns = ...
-- Z-Flow "what is still worth doing here" (S37): before the player leaves
-- a zone, say which of their own quests still have something to do on this
-- map, and say once, on crossing into another zone, what was left behind.
-- LOOK ONLY: lines of chat. Nothing is accepted, handed in, targeted, cast
-- or moved, and the route is not changed. No quest or place data is
-- authored here: the quests are the player's quest log and the places are
-- what Nav/QuestRead.lua (Questie at runtime) and Nav/QuestSpots.lua (the
-- player's own play) give, counted the way the route counts its stops
-- (Nav/TripRoute.lua T.Stops).
--
-- The word (`<slash> zone`) lists them. The line on leaving is said only
-- while the setting N.LEAVING_SETTING ("Finish quests in this zone first")
-- is on, and only when the client names both the zone left and the zone
-- entered. The zone is named where the client names its map
-- (client.mapName, C_Map.GetMapInfo); where it does not, the lines say
-- "here" and "the zone behind you".
--
-- Pure:
--   Z.Left(rows, places, here) -> list, elsewhere
--     rows, places, here as T.Stops takes them
--     list       { { quest = id, title, steps = n, turnIn = bool } }, in
--                quest log order: quests with a stop on the player's map
--     elsewhere  how many other quests have something left, none of it on
--                this map
--   Z.Lines(list, elsewhere, name) -> the word's lines
--   Z.Notice(list, name) -> the one line on leaving, or nil with nothing left
--     name  the zone's name, or nil when the client does not give it
-- Module "zoneLeft" provides Left, Lines. Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local Z = {}
N.ZoneLeft = Z

Z.NAME = "zoneLeft"
Z.WORD = "zone"
Z.HELP = "what is still worth doing here before you leave: your quests with something left on this map"
Z.NAMED = 3              -- quests named in the line on leaving

Z.HEADER_ONE = "Still worth doing here before you leave: 1 quest"
Z.HEADER = "Still worth doing here before you leave: %d quests"
Z.NONE = "Nothing is left for your quests on this map: you can move on."
Z.HEADER_ONE_IN = "Still worth doing in %s before you leave: 1 quest"
Z.HEADER_IN = "Still worth doing in %s before you leave: %d quests"
Z.NONE_IN = "Nothing is left for your quests in %s: you can move on."
Z.STEP_ONE = "  %s: 1 step left here"
Z.STEPS = "  %s: %d steps left here"
Z.TURN_IN = "  %s: ready to hand in here"
Z.ELSEWHERE_ONE = "1 other quest is for somewhere else %s."
Z.ELSEWHERE = "%d other quests are for somewhere else %s."
Z.ROUTE_TIP = "Type %s %s to walk them in order with the arrow."
Z.WHY_NO_MAP = "Your map is not known yet; try again in a moment."
Z.WHY_NO_LOG = "Your quest log could not be read."
Z.LEFT_ONE = "You left 1 quest unfinished in the zone behind you: %s. Go back for it, or carry on."
Z.LEFT = "You left %d quests unfinished in the zone behind you: %s. Go back for them, or carry on."
Z.LEFT_ONE_IN = "You left 1 quest unfinished in %s: %s. Go back for it, or carry on."
Z.LEFT_IN = "You left %d quests unfinished in %s: %s. Go back for them, or carry on."
Z.MORE = "%s and %d more"
Z.NAME_MAX = 60          -- bytes: a longer name is not a zone's name

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function Z.Left(rows, places, here)
    local T = N.TripRoute
    if not (T and type(T.Stops) == "function") then return {}, 0 end
    local stops, left = T.Stops(rows, places or {}, here)
    local byQuest, list = {}, {}
    for _, s in ipairs(stops) do
        local e = byQuest[s.quest]
        if not e then
            e = { quest = s.quest, title = s.label, steps = 0, turnIn = false }
            byQuest[s.quest] = e
        end
        e.steps = e.steps + 1
        if s.turnIn then e.turnIn = true end
    end
    -- In quest log order, as the player reads their own log.
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local e = type(row) == "table" and byQuest[row.id] or nil
        if e and not e.listed then
            e.listed = true
            list[#list + 1] = { quest = e.quest, title = e.title, steps = e.steps, turnIn = e.turnIn }
        end
    end
    local elsewhere, seen = 0, {}
    for _, l in ipairs(left) do
        if l.why == T.NOT_HERE and not byQuest[l.quest] and not seen[l.quest] then
            seen[l.quest] = true
            elsewhere = elsewhere + 1
        end
    end
    return list, elsewhere
end

local function waits()
    return type(N.LeavingWaits) == "function" and N.LeavingWaits(nil) or "(after this zone)"
end

-- A zone name fit to say: a short string, with nothing that would be read
-- as a format or a colour code. Else nil.
function Z.Named(name)
    if type(name) ~= "string" or name == "" or #name > Z.NAME_MAX then return nil end
    if name:find("[%%|%c]") then return nil end
    return name
end

function Z.Lines(list, elsewhere, name)
    list = type(list) == "table" and list or {}
    elsewhere = type(elsewhere) == "number" and elsewhere or 0
    name = Z.Named(name)
    local lines = {}
    if #list == 0 then
        lines[1] = name and Z.NONE_IN:format(name) or Z.NONE
    elseif name then
        lines[1] = #list == 1 and Z.HEADER_ONE_IN:format(name) or Z.HEADER_IN:format(name, #list)
    else
        lines[1] = #list == 1 and Z.HEADER_ONE or Z.HEADER:format(#list)
    end
    if #list > 0 then
        for _, e in ipairs(list) do
            local title = tostring(e.title)
            if e.turnIn then
                lines[#lines + 1] = Z.TURN_IN:format(title)
            elseif e.steps == 1 then
                lines[#lines + 1] = Z.STEP_ONE:format(title)
            else
                lines[#lines + 1] = Z.STEPS:format(title, e.steps)
            end
        end
    end
    if elsewhere == 1 then
        lines[#lines + 1] = Z.ELSEWHERE_ONE:format(waits())
    elseif elsewhere > 1 then
        lines[#lines + 1] = Z.ELSEWHERE:format(elsewhere, waits())
    end
    return lines
end

function Z.Notice(list, name)
    if type(list) ~= "table" or #list == 0 then return nil end
    name = Z.Named(name)
    local names = {}
    for i = 1, math.min(#list, Z.NAMED) do names[i] = tostring(list[i].title) end
    local said = table.concat(names, ", ")
    if #list > Z.NAMED then said = Z.MORE:format(said, #list - Z.NAMED) end
    if name then
        if #list == 1 then return Z.LEFT_ONE_IN:format(name, said) end
        return Z.LEFT_IN:format(#list, name, said)
    end
    if #list == 1 then return Z.LEFT_ONE:format(said) end
    return Z.LEFT:format(#list, said)
end

function Z.Declare(k, diag)
    local api = {}
    local ctx
    local cancels = {}
    local last            -- { zone, map }: where the player last was

    local function client() return ctx and ctx.client or k.client end

    local function tell(line)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        c.print(id.title .. ": " .. tostring(line))
    end

    local function noticeOn()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, N.LEAVING_SETTING)
        return not (ok and v == false)
    end

    -- What is left on a map: the player's own spot when it is their map.
    local function leftOn(map)
        local c = client()
        local rows = N.QuestLogRows and N.QuestLogRows(c) or nil
        if rows == nil then return nil, nil, Z.WHY_NO_LOG end
        local here = { map = map }
        local pos = ask(c, "position")
        if type(pos) == "table" and pos.map == map then here.x, here.y = pos.x, pos.y end
        local places = N.QuestiePlaces and N.QuestiePlaces(c, rows, map) or nil
        local QS = N.QuestSpots
        if QS and ctx and ctx.store then
            local ok, merged = pcall(function()
                return QS.Merge(places, QS.Places(ctx.store:get("account", QS.PATH), rows, map))
            end)
            if ok then places = merged end
        end
        return Z.Left(rows, places or {}, here)
    end

    -- The name of the zone a map is in, as the client says it, or nil.
    local function nameOf(zone, map)
        local c = client()
        return Z.Named(ask(c, "mapName", zone)) or Z.Named(ask(c, "mapName", map))
    end

    function api.Left()
        local pos = ask(client(), "position")
        local map = type(pos) == "table" and pos.map or nil
        if map == nil then return nil, nil, Z.WHY_NO_MAP end
        return leftOn(map)
    end

    function api.Lines()
        local list, elsewhere, why = api.Left()
        if not list then return { why } end
        local c = client()
        local z, pos = ask(c, "zone"), ask(c, "position")
        local lines = Z.Lines(list, elsewhere,
            nameOf(type(z) == "table" and z.zone or nil, type(pos) == "table" and pos.map or nil))
        local T = N.TripRoute
        if #list > 0 and T and T.WORD then
            local id = k.id or ns.id
            lines[#lines + 1] = Z.ROUTE_TIP:format(tostring(id.slash), T.WORD)
        end
        return lines
    end

    -- The player's zone changed: say once what was left behind.
    local function moved()
        local c = client()
        local z = ask(c, "zone")
        local zone = type(z) == "table" and z.zone or nil
        local pos = ask(c, "position")
        local map = type(pos) == "table" and pos.map or nil
        if zone == nil or map == nil then return end
        local was = last
        last = { zone = zone, map = map }
        if not was or was.zone == zone or not noticeOn() then return end
        local list = leftOn(was.map)
        local line = Z.Notice(list, nameOf(was.zone, was.map))
        if line then tell(line) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Z.WORD] = function()
            for _, line in ipairs(api.Lines()) do tell(line) end
        end
        if type(diag.help) == "table" then diag.help[Z.WORD] = Z.HELP end
    end

    k:Module({
        name = Z.NAME,
        needs = { "client", "store", "settings" },
        provides = { Left = api.Left, Lines = api.Lines },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                local ok, cancel = pcall(c.client.listen, event, function() pcall(moved) end)
                if ok and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            pcall(moved)
        end,
        stop = function()
            for _, fn in ipairs(cancels) do pcall(fn) end
            cancels, last, ctx = {}, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads. It says nothing until
-- the word is typed or the player crosses into another zone.
ns.zoneLeft = Z.Declare(ns, ns.diag)
