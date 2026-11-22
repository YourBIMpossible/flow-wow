local _, ns = ...
-- Z-Flow view state: the state table the arrow view takes (see the header of
-- N.ArrowView in Nav/ArrowView.lua), built from a client's reads. Pure given
-- a client: no frames, nothing remembered.
-- Needs Nav/GuideRead.lua.
--
-- The reads are N.GuideRead's: client.position() (shares of a map),
-- client.mapSize(map) (yards), client.zone() and client.facing(). A share
-- becomes yards as x * w and y * h. What the client does not say stays nil
-- (distance, player) or false (here, bearingKnown, facingKnown). Nothing is
-- guessed.
--
-- The state holds only the fields the arrow view names. The turn of each
-- arrow, and why a distance is missing, come back beside it.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local VIEW = { "layout", "screenW", "screenH", "size", "defaultPoint", "gate", "palette" }

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
    end

    local ps = type(guide.prof) == "table" and guide.prof or nil
    local prof = common(p, ps)
    prof.bearingKnown = p.bearingKnown and true or false
    if ps then
        if ps.on ~= nil then prof.on = ps.on and true or false end
        prof.own = flat(ps.own)
    end

    state.quest, state.prof = quest, prof
    return state, { quest = beside(q), prof = beside(p) }
end
