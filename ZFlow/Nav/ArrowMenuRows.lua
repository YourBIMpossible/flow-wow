local _, ns = ...
-- Parity row A1-11, the logic half (lead sections 729, 731 and 733): the
-- sections of Flow's arrow right-click menu that Z-Flow's UI/ArrowMenu.lua
-- does not have yet, as plain data. Flow: Nav.lua:4402-4427 (the menu:
-- this step, then the route list), Menu.lua:664 RouteItems (route order,
-- includes, nearest, waypoint, party, steps shown, Flow windows) and
-- Nav.lua:5230 ArrowMenuItems (the arrow's look).
--
-- Only entries whose action Z-Flow already has are here. What Flow's menu
-- does that Z-Flow cannot do yet is in R.NEEDS; what another branch
-- already covers is in R.COVERED. UI/ArrowMenu.lua is the lead's (held):
-- it appends R.Rows to its own and turns a chosen key into R.Action (a
-- LEAD NEED). The drawing is the drawing lane's.
--
-- Nothing here draws, clicks or reads the client.
--   R.ENTRIES                ordered: { key, text, section, when, action }
--     when    "always" | "outOfFight" (as Flow's window(label, open,
--             noCombat): Setup is greyed in a fight) | "waypoint" (only
--             with a waypoint set)
--     action  { slash = text } runs that slash text (word, then the rest);
--             { toggle = key } flips that bool setting
--   R.Text(key) -> its words, read when asked: a window row is worded by
--             that panel's own title
--   R.Rows(state) -> rows    UI/ArrowMenu.lua's row shape: { key, text,
--             disabled?, checked? }. state: { inCombat, waypoint, settings
--             = { [key] = value } }; a fight not known is a fight, a
--             waypoint not known is none (greyed), a toggle not read is
--             neither ticked nor not.
--   R.Action(key) -> a copy of its action, or nil
local R = {}
ns.ArrowMenuRows = R

local function field(tbl, name, fallback)
    if type(tbl) == "table" and type(tbl[name]) == "string" and tbl[name] ~= "" then return tbl[name] end
    return fallback
end

-- The slash words are read when asked, so file order does not matter.
local function actions()
    return {
        ["windows.advice"] = { slash = field(ns.Advisor, "WORD", "advice") },     -- UI/Advisor.lua:87
        ["windows.setup"] = { slash = field(ns.SetupList, "WORD", "setup") },     -- UI/SetupList.lua:41
        ["windows.banker"] = { slash = field(ns.Banker, "WORD", "banker") },      -- Items/Banker.lua:35
        ["route.zoneFirst"] = { toggle = "nav.zoneFirst" },                       -- Settings/Rows.lua:37
        ["style.distance"] = { toggle = "arrow.byDistance" },                     -- UI/Arrow.lua:138
        ["waypoint.clear"] = { slash = "way clear" },                             -- UI/Arrow.lua:1580-1632
    }
end

-- Each panel's own title, read when asked (Zen-3, lead section 733).
local function texts()
    return {
        ["windows.advice"] = field(ns.Advisor, "TITLE", "Advice"),                -- UI/Advisor.lua:75
        ["windows.setup"] = field(ns.SetupList, "HEADER", "Setup checklist"),     -- UI/SetupList.lua:43
        ["windows.banker"] = field(ns.BankList, "TITLE", "Bank list"),            -- UI/BankList.lua:57
        -- Flow's "Finish the area you're in first"; Z-Flow's setting is by
        -- zone, worded as its own row (Settings/Rows.lua:37).
        ["route.zoneFirst"] = "Finish quests in this zone first",
        -- The setting row's own label (UI/Arrow.lua:151).
        ["style.distance"] = "Arrow colour by distance",
        -- Flow's "Clear your waypoint" (Menu.lua RouteItems).
        ["waypoint.clear"] = "Clear your waypoint",
    }
end

R.ENTRIES = {
    { key = "windows.advice", section = "windows", when = "always" },
    { key = "windows.setup", section = "windows", when = "outOfFight" },
    { key = "windows.banker", section = "windows", when = "always" },
    { key = "route.zoneFirst", section = "route", when = "always" },
    { key = "style.distance", section = "style", when = "always" },
    { key = "waypoint.clear", section = "waypoint", when = "waypoint" },
}
for _, e in ipairs(R.ENTRIES) do
    e.action = actions()[e.key]
    e.text = texts()[e.key]
end

function R.Text(key) return texts()[key] end

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
    local words = texts()
    local out = {}
    for _, e in ipairs(R.ENTRIES) do
        local row = { key = e.key, text = words[e.key] }
        if e.when == "outOfFight" and state.inCombat ~= false then row.disabled = true end
        if e.when == "waypoint" and state.waypoint ~= true then row.disabled = true end
        local a = actions()[e.key]
        if type(a) == "table" and a.toggle then
            local v = settings[a.toggle]
            if type(v) == "boolean" then row.checked = v end
        end
        out[#out + 1] = row
    end
    return out
end

-- Covered by another branch (Zen-3, lead section 733): not needs.
R.COVERED = {
    { key = "route.order", setting = "nav.routeSort", by = "triproute-modes (batch 3)",
      flow = "Menu.lua RouteItems: Shortest path / Most XP first / Custom route" },
    { key = "route.shown", setting = "nav.routeShown", by = "triproute-modes (batch 3)",
      flow = "Menu.lua RouteItems: N steps / All steps / this area" },
}

-- What Flow's menu does that Z-Flow has no action for (lead section 729:
-- a missing action is a need, not new code here).
R.NEEDS = {
    { key = "route.zonesSelected", flow = "Menu.lua RouteItems: Finish the selected zones first",
      need = "LEAD NEED", what = "a declared nav.zonesFirst setting (Import/FromFlow.lua:324 copies one no row declares)" },
    { key = "route.unhideAll", flow = "Menu.lua RouteItems: Unhide all steps (N)",
      need = "LEAD NEED", what = "an unhide-all action and the hidden count" },
    { key = "waypoint.prompt", flow = "Menu.lua RouteItems: Set a waypoint (coordinates, or a party member's name)...",
      need = "LEAD NEED", what = "a typed waypoint prompt" },
    { key = "waypoint.mapOnly", flow = "Menu.lua RouteItems: On the map, show only my waypoint while one is set",
      need = "LEAD NEED", what = "a declared nav.mapWaypointOnly setting (Import/FromFlow.lua:331 copies one)" },
    { key = "party.shared", flow = "Menu.lua RouteItems: Shared steps from <editor> / Drop the shared steps",
      need = "LEAD NEED", what = "which of Nav/PartyRoute.lua's Take/Keep is follow and which is drop" },
    { key = "windows.meters", flow = "Menu.lua RouteItems: the meters' own entries",
      need = "LEAD NEED", what = "a meters window" },
}
