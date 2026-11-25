local _, ns = ...
-- Z-Flow view state: the state table the arrow view takes (see the header of
-- N.ArrowView in Nav/ArrowView.lua), built from a client's reads. No frames.
-- One thing is remembered, per client: whether the echo stood slid below
-- the quest arrow at the read before (see `slidOf`).
-- Needs Nav/GuideRead.lua.
--
-- The reads are N.GuideRead's: client.position() (shares of a map),
-- client.mapSize(map) (yards), client.zone(), client.facing(), and
-- client.mapCorners(map) for a step on another map (S44). A share
-- becomes yards as x * w and y * h. What the client does not say stays nil
-- (distance, player) or false (here, bearingKnown, facingKnown). Nothing is
-- guessed.
--
-- The state holds only the fields the arrow view names. The turn of each
-- arrow, and why a distance is missing, come back beside it.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local VIEW = { "layout", "screenW", "screenH", "size", "defaultPoint", "gate", "palette" }

-- Lead section 510 (CHANGES-1): the echo's last place, per client. N.EchoSlid
-- moves its 30 degree edge by N.ECHO_BAND towards the other side of the
-- answer before, so a player walking along the edge does not see the echo
-- jump at every update. The answer before has to be kept somewhere that
-- outlives one update: here, by the client the reads came from. Weak keys:
-- a client that is gone takes its answer with it.
local slidOf = setmetatable({}, { __mode = "k" })

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function flat(tbl)
    if type(tbl) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(tbl) do out[k] = v end
    return out
end

-- The fields both arrows share, from one leg of the guide's answer.
local function common(leg, step)
    local out = { hasStep = leg.hasStep and true or false, here = leg.here and true or false }
    out.target = flat(leg.target)
    if finite(leg.distance) then out.distance = leg.distance end
    if type(step) == "table" and finite(step.textHeight) then out.textHeight = step.textHeight end
    return out
end

local function beside(leg)
    local out = {}
    if finite(leg.turn) then out.turn = leg.turn end
    if leg.why ~= nil then out.why = leg.why end
    if leg.label ~= nil then out.label = leg.label end
    if leg.compass ~= nil then out.compass = leg.compass end
    return out
end

-- client: asked as N.GuideRead asks it.
-- guide = { quest, prof, separate, view, link }: what N.GuideRead takes.
--   A step may also carry what the arrow view shows for it:
--     quest: overlay, travel, textHeight.
--     prof: on (false = the setting is off), own = { r, g, b }, textHeight.
--   link: optional, N.GuideLink's answer or any link of offsets.
-- -> state, more
--   state: exactly what N.ArrowView(state) takes.
--   more = { quest = { turn, why, label, compass }, prof = { the same } }:
--     turn in radians (N.ArrowTurn), nil = unknown; why = the guide's reason
--     for no distance; compass = the guide's compass word, nil = none.
function N.ViewState(client, guide)
    guide = type(guide) == "table" and guide or {}
    local g = N.GuideRead(client, guide)
    local q = type(g.quest) == "table" and g.quest or {}
    local p = type(g.prof) == "table" and g.prof or {}

    local state = {}
    if type(guide.view) == "table" then
        for _, k in ipairs(VIEW) do state[k] = guide.view[k] end
    end
    state.player = flat(g.player)
    state.facingKnown = g.facingKnown and true or false

    local qs = type(guide.quest) == "table" and guide.quest or nil
    local quest = common(q, qs)
    if qs then
        if qs.overlay ~= nil then quest.overlay = qs.overlay and true or false end
        if qs.travel ~= nil then quest.travel = qs.travel and true or false end
        -- R7: what the step is ("waypoint", "profession"), for RC.Of.
        if type(qs.family) == "string" then
            quest.family = qs.family
        elseif type(qs.kind) == "string" then
            quest.family = qs.kind
        end
    end

    local ps = type(guide.prof) == "table" and guide.prof or nil
    local prof = common(p, ps)
    prof.bearingKnown = p.bearingKnown and true or false
    if ps then
        if ps.on ~= nil then prof.on = ps.on and true or false end
        prof.own = flat(ps.own)
    end

    state.quest, state.prof = quest, prof
    -- How far apart the two steps lie, as the player sees them: the echo
    -- is tucked under the quest arrow or stands below it by this (lead
    -- section 476). Bearings, not turns: it is known without a facing.
    -- echoSlid is the answer of the read before: N.ArrowView decides from
    -- it, any number of times, and gets the answer kept here for the next
    -- read. With no spread (a step is gone or has no bearing) nothing is
    -- kept: the next spread is judged at the plain edge.
    if finite(g.spread) then
        state.spread = g.spread
        if type(client) == "table" then
            state.echoSlid = slidOf[client]
            slidOf[client] = N.EchoSlid(g.spread, state.echoSlid)
        end
    elseif type(client) == "table" then
        slidOf[client] = nil
    end
    return state, { quest = beside(q), prof = beside(p) }
end
