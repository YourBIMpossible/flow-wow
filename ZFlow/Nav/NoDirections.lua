local _, ns = ...
-- Z-Flow: the arrow's words when there is nothing to point at and no quest
-- data (parity row A1-16, lead section 485): "No directions yet", then
-- "Install Questie + QuestieDB for quest locations". Said only while the
-- installed Questie's database cannot be asked (client.questieModule
-- ("QuestieDB") gives no table); with Questie, nil, and the arrow's own
-- why line (UI/Arrow.lua Arrow.WhyStep) stands.
-- UI/Arrow.lua shows the two lines on the quest arrow (the lead-owned hook)
-- when it has no quest step.
-- Compared with Flow Modules/Nav/Nav.lua (no choice, #goals == 0 and no
-- ns.quests:Source()): the same two lines. Flow's away hint (the dungeon
-- run on the other continent, awayHint) is not here.
-- LOOK ONLY. Not tested in game.
--
-- Pure:
--   ND.Words(hasData) -> { title, sub } or nil
-- Module "noDirections" provides Now() -> { title, sub } or nil.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local ND = {}
N.NoDirections = ND

ND.NAME = "noDirections"
ND.TITLE = "No directions yet"
ND.SUB = "Install Questie + QuestieDB for quest locations"

function ND.Words(hasData)
    if hasData then return nil end
    return { title = ND.TITLE, sub = ND.SUB }
end

function ND.Declare(k)
    local api = {}
    local ctx

    local function hasData()
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c.questieModule) ~= "function" then return false end
        local ok, db = pcall(c.questieModule, "QuestieDB")
        return ok and type(db) == "table"
    end

    function api.Now()
        if not ctx then return nil end
        return ND.Words(hasData())
    end

    k:Module({
        name = ND.NAME,
        needs = { "client" },
        provides = { Now = function() return api.Now() end },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.noDirections = ND.Declare(ns)
