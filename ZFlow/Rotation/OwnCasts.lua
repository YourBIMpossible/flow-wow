local _, ns = ...

-- The seal and the blessing you put up yourself (CF-32, lead sections 226,
-- 227). It watches your own casts that went off (UNIT_SPELLCAST_SUCCEEDED,
-- unit "player"); a cast whose name matches a row of your class pack's
-- options.sticky is kept for this character, one name per row's key, until
-- you cast another for that key. The rotation reads what is kept as
-- snapshot.chosen and the pack suggests it while you know it.
--
--   options.sticky = { { prefix = "Seal of ", key = "seal" },
--                      { prefix = "Blessing of ", key = "blessing",
--                        only = { ["Blessing of Kings"] = true, ... } } }
--
-- Kept for the character at state.ownCasts: { seal = name, blessing =
-- name }, spell names only. Kept over a reload and over the end of a fight.
--
-- It only watches and keeps names: nothing is cast, pressed or set.
--
-- Client reads, each asked in a pcall; a read not given or not answered
-- keeps nothing, never a guess:
--   client.class()        -> the class token, for the pack
--   client.spellName(id)  -> the spell's name or nil
--
-- Pure:
--   OC.Note(rows, name)   -> the key of the first row the name matches, or nil
-- Module (ns.use("ownCasts")):
--   Chosen()              -> a copy of what is kept, or nil when nothing is
-- Not tested in game.

local OC = {}
ns.OwnCasts = OC

OC.NAME = "ownCasts"
OC.PATH = "state.ownCasts"
OC.EVENT = "UNIT_SPELLCAST_SUCCEEDED"   -- unit, castGUID, spellID

-- A name matches a row that starts it with the row's prefix (and has more
-- after it), and, when the row has `only`, is in that set.
function OC.Note(rows, name)
    if type(rows) ~= "table" or type(name) ~= "string" then return nil end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.prefix) == "string" and row.prefix ~= ""
            and type(row.key) == "string" and row.key ~= ""
            and #name > #row.prefix and string.sub(name, 1, #row.prefix) == row.prefix
            and (row.only == nil or (type(row.only) == "table" and row.only[name] == true)) then
            return row.key
        end
    end
    return nil
end

function OC.Declare(k, packs)
    local client
    local api = {}

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    local function rows()
        local class = client and read(client.class) or nil
        local all = packs or ns.Packs
        if type(class) ~= "string" or type(all) ~= "table" then return nil end
        local pack = all[class]
        local options = type(pack) == "table" and pack.options or nil
        return type(options) == "table" and options.sticky or nil
    end

    -- What is kept, copied: only string keys with string names. nil when
    -- nothing is kept (the normal "no cast yet").
    function api.chosen()
        local saved = k.store:get("char", OC.PATH)
        if type(saved) ~= "table" then return nil end
        local out, any = {}, false
        for key, name in pairs(saved) do
            if type(key) == "string" and type(name) == "string" then
                out[key] = name
                any = true
            end
        end
        return any and out or nil
    end

    local function cast(unit, _, id)
        if unit ~= "player" or not client or type(id) ~= "number" then return end
        local name = read(client.spellName, id)
        if type(name) ~= "string" then return end
        local key = OC.Note(rows(), name)
        if not key then return end
        k.store:set("char", OC.PATH .. "." .. key, name)
    end

    k:Module({
        name = OC.NAME,
        needs = { "client", "store" },
        provides = { Chosen = api.chosen },
        start = function(ctx)
            client = ctx.client
            client.listen(OC.EVENT, cast)
        end,
    })

    return api
end

-- The addon's own.
ns.ownCasts = OC.Declare(ns)
