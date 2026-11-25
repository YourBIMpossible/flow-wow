local _, ns = ...
-- A tracker row's click and its right-click menu (FLOW-PARITY A2-19), the
-- logic half: after legacy Flow's Modules/Nav/RouteTracker.lua (a step
-- row's OnClick, :332-360). The menu and the row are drawn by the drawing
-- lane (a MUSE NEED); this file says what they hold and what a click asks
-- for, as plain data. Pure Lua 5.1: no client calls.
--
--   TM.Click(row) -> what a left click does:
--     { action = "openQuest", quest } a quest's stop: open it in the quest
--       log (client.openQuest, a CLIENT NEED; Flow selected it with
--       C_QuestLog.SetSelectedQuest, Nav.lua:3362-3368)
--     { action = "blocked", why }     a held stop says why, as Flow printed
--     { action = "none" }             anything else
--   TM.Items(row, state) -> the right-click entries, in order:
--     { title = true, words }, then each { key, words, enabled, action }:
--       open   open the quest in the log (a quest's stop)
--       point  point the arrow here, as your waypoint (a stop with a place)
--       next   go here next on the route (state.canNext, not a held stop)
--       hide   hide this step (state.canHide)
--     then the route's order as tick rows (checked = the one in use):
--       sort:distance, sort:xp (state.sort, "distance" unless "xp")
--     state = { canNext, canHide, sort }: what the route can do now. The
--     route (Nav/TripRoute.lua) has no call yet to put a stop next or hide
--     one, so a caller leaves those false until it does. An entry a row or
--     the route cannot do is listed, not enabled: the menu keeps its shape.
-- Flow's focus items (custom routes) and the route menu's "what it
-- includes" are not here: the route modes are their own surface (lead
-- section 651).
ns.Nav = ns.Nav or {}
local N = ns.Nav
local TM = {}
N.TrackerMenu = TM

TM.OPEN = "Open it in your quest log"
TM.POINT = "Point the arrow here (your waypoint)"
TM.NEXT = "Go here next"
TM.HIDE = "Hide this step"
TM.STEP = "This step"
-- The order's words are Muse's (lead section 651); TripRoute's own when it
-- has them.
TM.SORTS = { "distance", "xp" }
TM.SORT_WORDS = { distance = "Shortest first", xp = "Most XP first" }

local function sortWords(sort)
    local T = N.TripRoute
    if type(T) == "table" and type(T.SORT_LABELS) == "table" and type(T.SORT_LABELS[sort]) == "string" then
        return T.SORT_LABELS[sort]
    end
    return TM.SORT_WORDS[sort]
end

local function placed(row)
    local p = row.place
    return type(p) == "table" and p.map ~= nil and type(p.x) == "number" and type(p.y) == "number"
end

function TM.Click(row)
    if type(row) ~= "table" then return { action = "none" } end
    if row.held ~= nil then return { action = "blocked", why = tostring(row.held) } end
    if row.quest ~= nil then return { action = "openQuest", quest = row.quest } end
    return { action = "none" }
end

function TM.Items(row, state)
    if type(row) ~= "table" then return {} end
    state = type(state) == "table" and state or {}
    local words = TM.STEP
    if type(row.label) == "string" and row.label ~= "" then words = row.label end
    local items = { { title = true, words = words } }
    items[#items + 1] = { key = "open", words = TM.OPEN, action = "openQuest", enabled = row.quest ~= nil }
    items[#items + 1] = { key = "point", words = TM.POINT, action = "point", enabled = placed(row) }
    items[#items + 1] = { key = "next", words = TM.NEXT, action = "next",
                          enabled = state.canNext == true and row.held == nil and placed(row) }
    items[#items + 1] = { key = "hide", words = TM.HIDE, action = "hide", enabled = state.canHide == true }
    local using = "distance"
    if state.sort == "xp" then using = "xp" end
    for _, sort in ipairs(TM.SORTS) do
        items[#items + 1] = { key = "sort:" .. sort, words = sortWords(sort), action = "sort", enabled = true,
                              checked = sort == using }
    end
    return items
end
