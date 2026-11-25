local _, ns = ...
-- The low-level quests route option (A2-05; the rule of legacy Flow's
-- Goals.lua lowQuests route kind, no text of it). Off (default): pick-ups
-- more than RoutePickups.BELOW levels under you (grey ones) stay off the
-- route, as before. On: they are kept; the other cuts (above you, in your
-- log, done, not for you, an earlier quest first) still hold.
--
-- The cut-off is the existing level window (Nav/RoutePickups.lua P.BELOW
-- on Questie's quest level); no new game read.
--
-- With the add-on running:
--   L.On() -> the setting (false unless turned on)
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local L = {}
N.LowQuests = L

L.NAME = "lowQuests"
L.SETTING = "nav.lowQuests"

local current

function L.On()
    local s = current and current.settings
    if type(s) ~= "table" or type(s.get) ~= "function" then return false end
    local ok, v = pcall(s.get, s, L.SETTING)
    return ok and v == true
end

function L.Declare(k)
    k:Setting({ key = L.SETTING, scope = "account", type = "bool", default = false,
        label = "Low-level quests on the route", group = "travel.route",
        help = "Also route quests to pick up that are well under your level, grey ones too:"
            .. " for doing every quest in a zone. Off: they are left off the route.",
        synonyms = { "low", "grey", "gray", "level", "route", "quest", "zone" } })
    k:Module({
        name = L.NAME,
        needs = { "settings" },
        provides = { On = L.On },
        start = function(c) current = c end,
        stop = function() current = nil end,
    })
end

L.Declare(ns)
