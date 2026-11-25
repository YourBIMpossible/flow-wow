local _, ns = ...
-- The prepared dungeon run (FLOW-PARITY B-50 wiring), a port of legacy
-- Flow's Modules/Nav/Dungeons.lua D:Prepare, D:Cancel, D:RunOnly,
-- D:SetRunOnly and D:PrepOn (:1032-1052, :1231-1241, :1300). "Plan the run"
-- in the Dungeon Quests window (UI/DungeonWindow.lua) prepares a run and
-- puts only its steps on the route. The dungeon route's choices
-- (Nav/DungeonMode.lua) then leave the route (the run is kept), go back on
-- it, turn "Get ready on the way" on or off, or cancel the run.
--
-- Saved per character: C.PATH { key, name, wing, only, total } and the
-- get-ready choice under DR.PREP_PATH (on unless turned off, as in Flow).
--
-- Pure:
--   DR.Act(state, action) -> state, effect   effect "off" (the route is
--     turned off), "plan" (the run is planned again) or nil
--   DR.Done(total, left) -> done             planned steps less those left
--   DR.ModeState(state, routeOn, extra) -> DungeonMode.Items' state | nil
-- Module "dungeonRun" provides Prepared, SetPlanner, Act, Line, Items,
-- PrepOn, State. Not tested in game.
local DR = {}
ns.DungeonRun = DR

DR.NAME = "dungeonRun"
DR.PATH = "nav.dungeonRun"
DR.PREP_PATH = "nav.dungeonPrep"

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function DR.Act(state, action)
    if type(state) ~= "table" or state.key == nil then return nil, nil end
    if action == "leave" then
        local s = copy(state); s.only = false
        return s, "off"
    end
    if action == "back" then
        local s = copy(state); s.only = true
        return s, "plan"
    end
    if action == "prep" then
        local s = copy(state); s.prep = state.prep == false
        if s.only == true then return s, "plan" end
        return s, nil
    end
    if action == "cancel" then return nil, "off" end
    return state, nil
end

function DR.Done(total, left)
    if type(total) ~= "number" then return 0 end
    if type(left) ~= "number" then return total end
    return math.max(0, total - left)
end

function DR.ModeState(state, routeOn, extra)
    if type(state) ~= "table" or type(state.name) ~= "string" then return nil end
    return { name = state.name, on = state.only == true and routeOn ~= false,
             prep = state.prep ~= false, extra = extra }
end

function DR.Declare(k)
    local api = {}
    local ctx, planner

    local function store() return ctx and ctx.store or k.store end

    local function load()
        local s = store()
        if type(s) ~= "table" then return nil end
        local v = s:get("char", DR.PATH)
        if type(v) ~= "table" or v.key == nil then return nil end
        local out = copy(v)
        out.prep = s:get("char", DR.PREP_PATH) ~= false
        return out
    end

    local function save(state)
        local s = store()
        if type(s) ~= "table" then return end
        local saved
        if state then saved = { key = state.key, name = state.name, wing = state.wing, only = state.only,
                                total = state.total } end
        local ok, why = s:set("char", DR.PATH, saved)
        if not ok then k.problems:add(DR.NAME, "save", tostring(why)) end
        if state then
            local okP, whyP = s:set("char", DR.PREP_PATH, state.prep ~= false)
            if not okP then k.problems:add(DR.NAME, "save", tostring(whyP)) end
        end
    end

    local function trip()
        local tr = k.use and k.use("tripRoute")
        if type(tr) == "table" then return tr end
        return nil
    end

    -- Called by "Plan the run" once the run is on the route.
    function api.Prepared(key, name, wing, total)
        local was = load()
        save({ key = key, name = tostring(name), wing = wing, only = true, total = total,
               prep = not was or was.prep ~= false })
    end

    -- The window's planner: fn(key, wing, prep) -> total | nil.
    function api.SetPlanner(fn)
        if type(fn) == "function" then planner = fn end
    end

    function api.PrepOn()
        local s = store()
        if type(s) ~= "table" then return true end
        return s:get("char", DR.PREP_PATH) ~= false
    end

    function api.State() return load() end

    function api.Act(action)
        local state, effect = DR.Act(load(), action)
        if effect == "off" then
            local tr = trip()
            if tr and type(tr.Off) == "function" then pcall(tr.Off) end
        end
        if effect == "plan" and state and planner then
            local ok, total = pcall(planner, state.key, state.wing, state.prep ~= false)
            if ok and type(total) == "number" then state.total = total end
        end
        save(state)
        return state
    end

    local function left()
        local tr = trip()
        if not tr or type(tr.Current) ~= "function" then return nil end
        local ok, cur = pcall(tr.Current)
        if ok and type(cur) == "table" and type(cur.stops) == "table" then return #cur.stops end
        return nil
    end

    -- B-50: the line under the arrow (UI/Arrow.lua hook, the lead's).
    function api.Line()
        local state = load()
        if not state then return nil end
        local M = ns.DungeonMode
        if not M then return nil end
        return M.Line(state.name, state.only == true, DR.Done(state.total, left()), state.total or 0)
    end

    -- B-50: the click menu's items (drawn by Muse's menu).
    function api.Items(extra)
        local M = ns.DungeonMode
        if not M then return {} end
        return M.Items(DR.ModeState(load(), true, extra))
    end

    k:Module({
        name = DR.NAME,
        needs = { "store" },
        provides = { Prepared = api.Prepared, SetPlanner = api.SetPlanner, Act = api.Act, Line = api.Line,
                     Items = api.Items, PrepOn = api.PrepOn, State = api.State },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

ns.dungeonRun = DR.Declare(ns)
