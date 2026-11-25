local _, ns = ...

-- Parity row R-05 (lead section 777): how long a run of each dungeon takes
-- you, as a running average, as Flow's Modules/Nav/Dungeons.lua:
--   D.LearnTime (:398-406)   the last 10 runs averaged; a run under 5 or
--                            over 240 minutes (a peek inside, a night
--                            away) does not count
--   the run (:2028-2037)     from going in to coming out; counted once you
--                            have been out 10 minutes (back in sooner: the
--                            same run)
-- Kept per character at PATH, by the dungeon's name as the game gives it
-- (client.instanceName), as { avg, n } in minutes. An old saved time stays
-- readable: a plain number (one run) or Flow's { avg, n }; Flow's own
-- times, imported at FLOW_PATH (Import/FromFlow.lua) by its dungeon key,
-- are read when the caller passes that key.
--   DT.LearnTime(rec, minutes) -> rec        DT.Read(v) -> { avg, n } | nil
--   DT.Line(rec) -> "about N minutes a run" | nil
--   DT.Step(state, inside, name, now) -> state, done | nil
--     inside: in a dungeon (client.instance kind "party"); done = { key,
--     minutes } when a run is counted
--   DT.Declare(k) -> api; api.Time(name[, key]) -> rec | nil; api.Line(...)
-- Reads: client.instance, client.instanceName, client.clock (all in
-- Core/Client.lua). The window that shows it is the drawing lane's.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local DT = {}
ns.Nav.DungeonTime = DT

DT.NAME = "dungeonTime"
DT.PATH = "learned.dungeonTimes"
DT.FLOW_PATH = "learned.facts.dungeonTimes"
DT.STATE = "state.dungeonIn"
DT.KEEP = 10          -- runs averaged (Flow)
DT.MIN, DT.MAX = 5, 240
DT.OUT = 600          -- seconds out before a run counts (Flow)
DT.EVERY = 30         -- seconds between looks
DT.ABOUT = "about %d minutes a run"

local function number(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function DT.LearnTime(rec, minutes)
    if not number(minutes) or minutes < DT.MIN or minutes > DT.MAX then return rec end
    if type(rec) ~= "table" or not number(rec.avg) then return { avg = minutes, n = 1 } end
    local n = math.min((tonumber(rec.n) or 1) + 1, DT.KEEP)
    return { avg = rec.avg + (minutes - rec.avg) / n, n = n }
end

function DT.Read(v)
    if number(v) then return { avg = v, n = 1 } end
    if type(v) == "table" and number(v.avg) then
        local n = tonumber(v.n) or 1
        return { avg = v.avg, n = n }
    end
    return nil
end

function DT.Line(rec)
    if type(rec) ~= "table" or not number(rec.avg) then return nil end
    return DT.ABOUT:format(math.floor(rec.avg + 0.5))
end

local function finish(st)
    if type(st.t) ~= "number" or type(st.left) ~= "number" then return nil end
    return { key = st.key, minutes = (st.left - st.t) / 60 }
end

function DT.Step(state, inside, name, now)
    local st = {}
    if type(state) == "table" then
        for k, v in pairs(state) do st[k] = v end
    end
    if not number(now) then return st, nil end
    if inside and type(name) == "string" and name ~= "" then
        if st.key == name then
            if st.left and now - st.left < DT.OUT then st.left = nil end
            if st.left then
                local done = finish(st)
                return { key = name, t = now }, done
            end
            return st, nil
        end
        local done = nil
        if st.key and st.left then done = finish(st) end
        return { key = name, t = now }, done
    end
    if st.key then
        if not st.left then
            st.left = now
            return st, nil
        end
        if now - st.left >= DT.OUT then return {}, finish(st) end
    end
    return st, nil
end

function DT.Declare(k)
    local api = {}
    local ctx

    local function read(name)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name])
        if ok then return v end
        return nil
    end

    local function look()
        if not ctx then return end
        local inst = read("instance")
        local inside = type(inst) == "table" and inst.inside == true and inst.kind == "party"
        local name = nil
        if inside then name = read("instanceName") end
        local st, done = DT.Step(ctx.store:get("char", DT.STATE), inside, name, read("clock"))
        ctx.store:set("char", DT.STATE, st)
        if done then
            local times = ctx.store:get("char", DT.PATH)
            local copy = {}
            if type(times) == "table" then
                for key, v in pairs(times) do copy[key] = v end
            end
            copy[done.key] = DT.LearnTime(DT.Read(copy[done.key]), done.minutes)
            ctx.store:set("char", DT.PATH, copy)
        end
    end

    function api.Time(name, key)
        if not ctx then return nil end
        local own = ctx.store:get("char", DT.PATH)
        local rec = nil
        if type(own) == "table" and name ~= nil then rec = DT.Read(own[name]) end
        if rec == nil and key ~= nil then
            local flow = ctx.store:get("char", DT.FLOW_PATH)
            if type(flow) == "table" then rec = DT.Read(flow[key]) end
        end
        return rec
    end
    function api.Line(name, key) return DT.Line(api.Time(name, key)) end

    k:Module({
        name = DT.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { Time = api.Time, Line = api.Line },
        start = function(c)
            ctx = c
            c.bus:on(DT.NAME, "PLAYER_ENTERING_WORLD", look)
            c.bus:on(DT.NAME, "ZONE_CHANGED_NEW_AREA", look)
            c.sched:every(DT.NAME, DT.EVERY, look)
        end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonTime = DT.Declare(ns)
