local _, ns = ...

-- Parity row A1-13, the data half (lead section 825.2): the card for one
-- step, as Flow's Modules/Nav/Nav.lua N:ShowStop (:4232-4278): the step's
-- title, its distance and travel text (:4237-4240), the body lines (the
-- tooltip minus title and task, :4242-4248) and three links (:4250-4263,
-- made in buildCard :4205-4227): the quest log one only when the quest is
-- in the log (:4252-4256), the map one, and go here next. Pure: no client
-- read, nothing drawn, nothing done.
--
--   SC.Card(step, facts) -> card or nil (no step, or a step with no label)
--     step   a stop as Nav/TripRoute.lua View()/Current() gives it:
--            { label, title, detail, details, quest, objective, turnIn,
--              kind, place = { map, x, y }, held }
--     facts  what the caller already read, all optional:
--            inLog          set of quest ids in the log ({ [id] = true })
--            canSelectQuest true when a way to select a quest in the log
--                           exists (none yet: a CLIENT NEED, see below)
--            distance       distance and travel text, e.g. "120 yd"
--            index          the step's place on the route (1 = next)
--            canFirst       true when a way to put a step first exists:
--                           SC.CanFirst(the tripRoute module), which
--                           offers First(n) (Nav/TripRoute.lua, section 826)
--   SC.Run(key, step, facts) -> call or nil (the action is off)
--
-- The window is a MUSE NEED. It draws this, top to bottom:
--   card = {
--     title    = string,        the step's label
--     sub      = string or nil, what to do: the objective, or a hand-in line
--     distance = string or nil, as the caller gave it
--     lines    = { string, ... }, body lines (Nav/StepDetail.lua's title
--                and detail rows for this step alone)
--     actions  = { { key, label, enabled, why }, ... } in this order:
--                "questLog", "map", "first"; why is set when enabled is
--                false. Flow hid the quest link when off; the window may
--                hide or grey an action that is off.
--   }
-- A click calls SC.Run(action.key, step, facts) and makes the call it gets:
--   { call = "questLog", quest = id }  CLIENT NEED: no client call selects a
--                                      quest in the log (Flow:
--                                      C_QuestLog.SetSelectedQuest, :4286)
--   { call = "showMap", map = id }     client.showMap(map) (Core/Client.lua)
--   { call = "first", index = n }      tripRoute.First(n) (Nav/TripRoute.lua;
--                                      Flow: N:Select(key), :4224)
--   SC.CanFirst(route) -> true when route offers First
-- Not tested in game.
ns.Nav = ns.Nav or {}
local SC = {}
ns.Nav.StepCard = SC

SC.QUEST_LOG = "Quest log"
SC.MAP = "Map"
SC.FIRST = "Do this next"
SC.HAND_IN = "Hand the quest in"
SC.WHY_NOT_IN_LOG = "That quest is not in your log."
SC.WHY_NO_QUEST = "This step has no quest."
SC.WHY_CANT_SELECT = "The quest log can't be opened at a quest yet."
SC.WHY_NO_PLACE = "This step has no place on a map."
SC.WHY_NOT_ON_ROUTE = "This step is not on your route."
SC.WHY_ALREADY = "This is already your next step."
SC.WHY_CANT_FIRST = "Steps can't be moved to the front yet."

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function factsOf(facts)
    if type(facts) == "table" then return facts end
    return {}
end

local function questOff(step, f)
    local q = step.quest
    if type(q) ~= "number" then return SC.WHY_NO_QUEST end
    if type(f.inLog) ~= "table" or not f.inLog[q] then return SC.WHY_NOT_IN_LOG end
    if f.canSelectQuest ~= true then return SC.WHY_CANT_SELECT end
    return nil
end

local function placeMap(step)
    local p = step.place
    if type(p) == "table" and type(p.map) == "number" then return p.map end
    return nil
end

local function mapOff(step)
    if placeMap(step) == nil then return SC.WHY_NO_PLACE end
    return nil
end

-- Whether a route offers "put a step first" (Nav/TripRoute.lua api.First).
function SC.CanFirst(route)
    return type(route) == "table" and type(route.First) == "function"
end

local function firstOff(f)
    if type(f.index) ~= "number" then return SC.WHY_NOT_ON_ROUTE end
    if f.index <= 1 then return SC.WHY_ALREADY end
    if f.canFirst ~= true then return SC.WHY_CANT_FIRST end
    return nil
end

local function act(key, label, why)
    return { key = key, label = label, enabled = why == nil, why = why }
end

function SC.Card(step, facts)
    if type(step) ~= "table" or not text(step.label) then return nil end
    local f = factsOf(facts)
    local sub = text(step.objective)
    if not sub and step.turnIn then sub = SC.HAND_IN end
    local lines = {}
    local SD = ns.Nav.StepDetail
    if type(SD) == "table" then
        for _, r in ipairs(SD.Rows({ stops = { step } })) do
            if r.kind == "title" or r.kind == "detail" then lines[#lines + 1] = r.text end
        end
    end
    return {
        title = step.label,
        sub = sub,
        distance = text(f.distance),
        lines = lines,
        actions = {
            act("questLog", SC.QUEST_LOG, questOff(step, f)),
            act("map", SC.MAP, mapOff(step)),
            act("first", SC.FIRST, firstOff(f)),
        },
    }
end

function SC.Run(key, step, facts)
    if type(step) ~= "table" then return nil end
    local f = factsOf(facts)
    if key == "questLog" and questOff(step, f) == nil then
        return { call = "questLog", quest = step.quest }
    end
    if key == "map" and mapOff(step) == nil then
        return { call = "showMap", map = placeMap(step) }
    end
    if key == "first" and firstOff(f) == nil then
        return { call = "first", index = f.index }
    end
    return nil
end
