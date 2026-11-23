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

function G.Declare(k)
    local api = {}
    k:Module({
        name = G.NAME,
        needs = { "settings" },
        settings = { {
            key = G.SETTING, scope = "char", type = "bool", default = true,
            label = "Offer gathering tracking",
            help = "Out of a fight, the rotation icon offers Find Minerals or Find Herbs when you have the "
                .. "profession and that tracking is off. It casts nothing by itself.",
            group = "Rotation",
        } },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gatherTrack = G.Declare(ns)
