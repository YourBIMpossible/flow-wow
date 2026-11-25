local _, ns = ...
-- Battleground quests on the pick-ups route (row A2-06; the rule of legacy
-- Flow's Goals.lua routeKind "battlegrounds" and IsBattleground, no text of
-- it). A quest is a battleground quest when Questie files it (its
-- zoneOrSort, Database/QuestieDB.lua:1543) under a battleground zone or
-- under the "Battlegrounds" sort: Database/Constants.lua:10
-- (BATTLEGROUNDS = -25); the zones Alterac Valley 2597, Warsong Gulch 3277,
-- Arathi Basin 3358 (Localization/lookups/lookupZones.lua:3053-3055).
-- With the setting off (default) they stay off the route; on, they are
-- offered like any other pick-up.
--
-- Pure:
--   B.Is(q) -> true when q.zoneOrSort marks a battleground quest
-- With the add-on running:
--   B.On() -> the setting (false unless turned on)
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local B = {}
N.BattlegroundQuests = B

B.NAME = "battlegroundQuests"
B.SETTING = "nav.battlegroundQuests"
B.SORT = -25
B.ZONES = { [2597] = true, [3277] = true, [3358] = true }

function B.Is(q)
    if type(q) ~= "table" then return false end
    local z = tonumber(q.zoneOrSort)
    if not z then return false end
    return z == B.SORT or B.ZONES[z] == true
end

local current

function B.On()
    local s = current and current.settings
    if type(s) ~= "table" or type(s.get) ~= "function" then return false end
    local ok, v = pcall(s.get, s, B.SETTING)
    return ok and v == true
end

function B.Declare(k)
    k:Setting({ key = B.SETTING, scope = "account", type = "bool", default = false,
        label = "Battleground quests on the route", group = "travel.route",
        help = "Quests filed under a battleground (Warsong Gulch, Arathi Basin, Alterac Valley)."
            .. " Off: they stay off the pick-ups route. On: they are offered like other quests.",
        synonyms = { "battleground", "bg", "pvp", "warsong", "arathi", "alterac", "route", "quest" } })
    k:Module({
        name = B.NAME,
        needs = { "settings" },
        provides = { On = B.On, Is = B.Is },
        start = function(c) current = c end,
        stop = function() current = nil end,
    })
end

B.Declare(ns)
