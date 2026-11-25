local _, ns = ...
-- Hard and elite quests held off the solo route (C-12; the rule of legacy
-- Flow's QuestData.lua HARD_ABOVE / ELITE_SOLO_ABOVE and Goals.lua's hold,
-- no text of it). Solo, with the setting on (default):
--   hard:  a quest HARD_ABOVE or more levels above you is held until you
--          are within HARD_ABOVE - 1 levels of it;
--   elite: an elite (group) quest is held until you are ELITE_SOLO_ABOVE
--          levels above it.
-- Grouped, or with the setting off, nothing is held. A level or tag not
-- known holds nothing on its own.
--
-- The elite tag: Questie's QuestieDB.IsGroupQuest(id) (its quest tag is
-- ELITE), read by Nav/RoutePickups.lua.
--
-- Pure:
--   H.Held{ level, elite, myLevel, grouped, on } -> held (true|false), why
-- With the add-on running:
--   H.On() -> the setting (true unless turned off)
--   H.HeldNow{ level, elite, myLevel } -> H.Held with the player's group
--     state (client.grouped) and the setting filled in
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local H = {}
N.QuestHold = H

H.NAME = "questHold"
H.SETTING = "nav.holdHard"
H.HARD_ABOVE = 3
H.ELITE_SOLO_ABOVE = 3
H.WHY_HARD = "hard: level %d, held until you are %d"
H.WHY_ELITE = "elite: held until you are %d"

local function int(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

function H.Held(a)
    if type(a) ~= "table" or a.on == false or a.grouped == true then return false end
    local level, my = int(a.level), int(a.myLevel)
    if not level or level <= 0 or not my then return false end
    if a.elite == true then
        local at = level + H.ELITE_SOLO_ABOVE
        if my < at then return true, H.WHY_ELITE:format(at) end
    end
    if level - my >= H.HARD_ABOVE then
        return true, H.WHY_HARD:format(level, level - H.HARD_ABOVE + 1)
    end
    return false
end

local current

function H.On()
    local s = current and current.settings
    if type(s) ~= "table" or type(s.get) ~= "function" then return true end
    local ok, v = pcall(s.get, s, H.SETTING)
    return not (ok and v == false)
end

function H.Grouped()
    local c = current and current.client
    if type(c) ~= "table" or type(c.grouped) ~= "function" then return nil end
    local ok, v = pcall(c.grouped)
    if ok and type(v) == "boolean" then return v end
    return nil
end

function H.HeldNow(a)
    if type(a) ~= "table" then return false end
    return H.Held({ level = a.level, elite = a.elite, myLevel = a.myLevel,
                    grouped = H.Grouped(), on = H.On() })
end

function H.Declare(k)
    k:Setting({ key = H.SETTING, scope = "account", type = "bool", default = true,
        label = "Hold hard and elite quests while solo", group = "travel.route",
        help = "Solo, a quest 3 or more levels above you stays off the route until you are within 2 levels of it,"
            .. " and an elite quest until you are 3 levels above it. In a group they are routed as usual.",
        synonyms = { "elite", "group", "hard", "solo", "route", "quest", "hold" } })
    k:Module({
        name = H.NAME,
        needs = { "client", "settings" },
        provides = { Held = H.HeldNow, On = H.On },
        start = function(c) current = c end,
        stop = function() current = nil end,
    })
end

H.Declare(ns)
