local _, ns = ...
-- Parity row A1-11, the logic half (lead sections 729 and 731): the
-- sections of Flow's arrow right-click menu that Z-Flow's UI/ArrowMenu.lua
-- does not have yet, as plain data. Flow: Nav.lua:4402-4427 (the menu:
-- this step, then the route list), Menu.lua:664 RouteItems (route order,
-- includes, nearest, waypoint, party, steps shown, Flow windows) and
-- Nav.lua:5230 ArrowMenuItems (the arrow's look).
--
-- Only entries whose action Z-Flow already has are here; what Flow's menu
-- does that Z-Flow cannot do yet is in R.NEEDS, not built. UI/ArrowMenu.lua
-- is the lead's (held): it appends R.Rows to its own and turns a chosen
-- key into R.Action (a LEAD NEED). The drawing is the drawing lane's.
--
-- Nothing here draws, clicks or reads the client.
--   R.ENTRIES                ordered: { key, text, section, when, action }
--     when    "always" | "outOfFight" (as Flow's window(label, open,
--             noCombat): Settings and Setup are greyed in a fight)
--     action  { slash = word } runs that slash word; { toggle = key }
--             flips that bool setting
--   R.Rows(state) -> rows    UI/ArrowMenu.lua's row shape: { key, text,
--             disabled?, checked? }. state: { inCombat, settings = {
--             [key] = value } }; a fight not known is a fight (greyed);
--             a toggle not read is neither ticked nor not.
--   R.Action(key) -> a copy of its action, or nil
--   R.NEEDS                  { key, flow, need, what } for each missing one
local R = {}
ns.ArrowMenuRows = R

local function word(tbl, fallback)
    if type(tbl) == "table" and type(tbl.WORD) == "string" then return tbl.WORD end
    return fallback
end

-- The slash words are read when asked, so file order does not matter.
local function actions()
    return {
        ["windows.advice"] = { slash = word(ns.Advisor, "advice") },     -- UI/Advisor.lua:87
        ["windows.setup"] = { slash = word(ns.SetupList, "setup") },     -- UI/SetupList.lua:41
        ["windows.banker"] = { slash = word(ns.Banker, "banker") },      -- Items/Banker.lua:35
        ["route.zoneFirst"] = { toggle = "nav.zoneFirst" },              -- Settings/Rows.lua:37
    }
end

R.ENTRIES = {
    -- Flow Menu.lua RouteItems, "Flow windows": Flow Improvements.
    { key = "windows.advice", text = "Flow Improvements", section = "windows", when = "always" },
    -- Flow Setup: greyed in a fight, as Flow's.
    { key = "windows.setup", text = "Flow Setup", section = "windows", when = "outOfFight" },
    { key = "windows.banker", text = "Flow Banker", section = "windows", when = "always" },
    -- Flow Nav.lua:5230 ArrowMenuItems, "Finish the area you're in first":
    -- Z-Flow's own setting is by zone (Settings/Rows.lua:37), worded as its row.
    { key = "route.zoneFirst", text = "Finish quests in this zone first", section = "route", when = "always" },
}
for _, e in ipairs(R.ENTRIES) do e.action = actions()[e.key] end

function R.Action(key)
    local a = actions()[key]
    if type(a) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    return out
end

function R.Rows(state)
    if type(state) ~= "table" then state = {} end
    local settings = state.settings
    if type(settings) ~= "table" then settings = {} end
    local out = {}
    for _, e in ipairs(R.ENTRIES) do
        local row = { key = e.key, text = e.text }
        if e.when == "outOfFight" and state.inCombat ~= false then row.disabled = true end
        local a = actions()[e.key]
        if type(a) == "table" and a.toggle then
            local v = settings[a.toggle]
            if type(v) == "boolean" then row.checked = v end
        end
        out[#out + 1] = row
    end
    return out
end

-- What Flow's menu does that Z-Flow has no action for (lead section 729:
-- a missing action is a need, not new code here).
R.NEEDS = {
    { key = "route.order", flow = "Menu.lua RouteItems: Shortest path / Most XP first / Custom route, Clear your custom route",
      need = "LEAD NEED", what = "a route-order choice (Nav/RoutePlan.lua says its order is short, not chosen)" },
    { key = "route.zonesSelected", flow = "Menu.lua RouteItems: Finish the selected zones first",
      need = "LEAD NEED", what = "a declared nav.zonesFirst setting (Import/FromFlow.lua:324 copies one no row declares)" },
    { key = "route.unhideAll", flow = "Menu.lua RouteItems: Unhide all steps (N)",
      need = "LEAD NEED", what = "an unhide-all action and the hidden count" },
    { key = "route.shown", flow = "Menu.lua RouteItems: N steps / All steps / this area",
      need = "LEAD NEED", what = "a choice of how many steps the route shows" },
    { key = "waypoint.prompt", flow = "Menu.lua RouteItems: Set a waypoint (coordinates, or a party member's name)...",
      need = "LEAD NEED", what = "a typed waypoint prompt" },
    { key = "waypoint.mapOnly", flow = "Menu.lua RouteItems: On the map, show only my waypoint while one is set",
      need = "LEAD NEED", what = "a declared nav.mapWaypointOnly setting (Import/FromFlow.lua:331 copies one)" },
    { key = "waypoint.clear", flow = "Nav.lua:4410-4415 and RouteItems: Clear your waypoint (back to the route)",
      need = "LEAD NEED", what = "a clear-waypoint action" },
    { key = "party.shared", flow = "Menu.lua RouteItems: Shared steps from <editor> / Drop the shared steps",
      need = "LEAD NEED", what = "which of Nav/PartyRoute.lua's Take/Keep is follow and which is drop" },
    { key = "windows.meters", flow = "Menu.lua RouteItems: the meters' own entries",
      need = "LEAD NEED", what = "a meters window" },
    { key = "style.distance", flow = "Nav.lua:5230 ArrowMenuItems: Colour by distance",
      need = "LEAD NEED", what = "an arrow colour-by-distance setting (UI/RouteColor.lua is held)" },
}
