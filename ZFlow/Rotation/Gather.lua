local _, ns = ...

-- Gathering tracking (lead sections 226/227, P-GATHER, upstream #31): a
-- player who knows a gathering tracking spell and has its profession, with
-- that tracking off, is offered the spell out of a fight, on the rotation
-- icon and the existing key, as Flow did (Modules/Rotation/Actions.lua
-- "gather:find").
--
-- Runtime entry point: the rotation driver's tick (Rotation/Driver.lua
-- D.Step) asks the chooser, whose last step, "track" (Rotation/Choose.lua),
-- is G.Step here; its suggestion reaches the rotation icon and the key's
-- attributes (Rotation/Cast.lua) as any suggestion does: a spell on
-- yourself, the key's "spell" type. Nothing new is pressed or cast: the key
-- acts only on the player's own press.
--
--   G.LIST          { { profession, spell } }   Mining -> Find Minerals,
--                   Herbalism -> Find Herbs (first guess at the names)
--   G.Read(client, field) -> the snapshot's gather fields (the driver asks):
--     gatherOn      the setting G.SETTING (nil before the module starts)
--     professions   { [name] = true } from client.professions(), or nil
--     tracking      { [spell] = true | false } from client.tracking(spell)
--                   for G.LIST, or nil when none could be read
--     trackKnown    { [spell] = true | false }: the spell learned (its row
--                   from client.spellId and client.spell); nil when the
--                   client cannot read tracking at all or no row was read
--   G.Step(snapshot) -> suggestion | nil, why   pure; the chooser's step:
--     out of a fight only; nothing while any gathering tracking is on (one
--     tracking at a time: it never switches away from one the player chose);
--     a spell not known, a profession not had, or a read not given: nothing.
--   G.Self(snapshot, skip) -> { spell, unit = "player" } | nil   pure; the
--     self button's offer (recovery R2, lead section 564; Flow 6d4ad1c7
--     "gather:track"): G.Step's spell, when you are read as alive and the
--     Flow button (skip = { spell }) does not hold it already. The
--     rotation's "track" step is last, so with anything else to suggest it
--     never showed; the self button shows it then (Rotation/FlowButton.lua
--     refresh, after the self buffs). The player's click or key casts it.
--   G.Declare(k) -> api    the module: the settings row, and the setting
--                          read for G.Read.
-- Not tested in game: the tracking and profession reads are first guesses.

local G = {}
ns.Gather = G

G.NAME = "gatherTrack"
G.SETTING = "rotation.gatherTracking"
G.LIST = {
    { profession = "Mining", spell = "Find Minerals" },
    { profession = "Herbalism", spell = "Find Herbs" },
}

local ctx = nil

local function each(fn)
    local out, any = {}, false
    for _, g in ipairs(G.LIST) do
        local ok, v = pcall(fn, g)
        if ok and type(v) == "boolean" then
            out[g.spell] = v
            any = true
        end
    end
    return any and out or nil
end

function G.Read(client, field)
    if type(client) ~= "table" then return nil end
    if field == "gatherOn" then
        if not ctx or type(ctx.settings) ~= "table" then return nil end
        return ctx.settings:get(G.SETTING) ~= false
    end
    if field == "professions" then
        if type(client.professions) ~= "function" then return nil end
        local ok, p = pcall(client.professions)
        return (ok and type(p) == "table") and p or nil
    end
    -- GT-2: on a mount or a flight path a cast would dismount or fail.
    if field == "mounted" or field == "onTaxi" then
        local read = client[field]
        if type(read) ~= "function" then return nil end
        local ok, v = pcall(read)
        if ok and type(v) == "boolean" then return v end
        return nil
    end
    -- GT-1: any tracking at all on (Flow's X.AnyTracked).
    if field == "trackingAny" then
        if type(client.anyTracking) ~= "function" then return nil end
        local ok, v = pcall(client.anyTracking)
        if ok and type(v) == "boolean" then return v end
        return nil
    end
    if type(client.tracking) ~= "function" then return nil end
    if field == "tracking" then
        return each(function(g) return client.tracking(g.spell) end)
    end
    if field == "trackKnown" then
        if type(client.spellId) ~= "function" or type(client.spell) ~= "function" then return nil end
        return each(function(g)
            local id = client.spellId(g.spell)
            if type(id) ~= "number" then return false end
            local row = client.spell(id)
            if type(row) ~= "table" or row.known == nil then return nil end
            return row.known == true
        end)
    end
    return nil
end

function G.Step(s)
    if type(s) ~= "table" then return nil, "nothing to read" end
    if s.gatherOn == false then return nil, "gathering tracking is switched off" end
    if not ns.Rotation.OutOfFight(s) then return nil, "not out of a fight" end
    -- GT-2 (Flow's X.TrackAllowed): on foot, not on a flight path, not
    -- eating or drinking; each must be read, as a cast would dismount the
    -- player or stand them up.
    if s.mounted ~= false then return nil, s.mounted and "mounted" or "not known whether you are mounted" end
    if s.onTaxi ~= false then
        return nil, s.onTaxi and "on a flight path" or "not known whether you are on a flight path"
    end
    -- Section 237 GK-1: the one eating list, ns.BuffFood.EATING
    -- (Rotation/BuffFood.lua), the food offer's too.
    local eating = ns.BuffFood.Eating(s.buffs)
    if eating == nil then return nil, "not known whether you are eating or drinking" end
    if eating then return nil, "eating or drinking" end
    -- GT-1: any tracking on is the player's choice and is left alone.
    if s.trackingAny ~= false then
        return nil, s.trackingAny and "a tracking is already on" or "not known whether a tracking is on"
    end
    local prof, known, on = s.professions, s.trackKnown, s.tracking
    if type(prof) ~= "table" or type(known) ~= "table" or type(on) ~= "table" then
        return nil, "not known which gathering tracking you have"
    end
    for _, g in ipairs(G.LIST) do
        if on[g.spell] == true then return nil, g.spell .. " is already on" end
    end
    for _, g in ipairs(G.LIST) do
        if prof[g.profession] == true and known[g.spell] == true and on[g.spell] == false then
            return { spell = g.spell, kind = "buff", unit = "player", reason = "Turn on " .. g.spell }
        end
    end
    return nil, "no gathering tracking to turn on"
end

function G.Self(s, skip)
    if type(s) ~= "table" or s.dead ~= false then return nil end
    local step = G.Step(s)
    if type(step) ~= "table" or type(step.spell) ~= "string" then return nil end
    if type(skip) == "table" and skip.spell == step.spell then return nil end
    return { spell = step.spell, unit = "player" }
end

function G.Declare(k)
    local api = {}
    k:Module({
        name = G.NAME,
        needs = { "settings" },
        settings = { {
            key = G.SETTING, scope = "char", type = "bool", default = true,
            label = "Offer gathering tracking",
            help = "Out of a fight, the self button (or the Flow button, with nothing else to cast) offers "
                .. "Find Minerals or Find Herbs when you have the profession and no tracking is on. "
                .. "Your click or key casts it; nothing is cast by itself.",
            group = "professions", synonyms = { "tracking", "herbs", "minerals", "mining", "herbalism", "gather" },
        } },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gatherTrack = G.Declare(ns)
