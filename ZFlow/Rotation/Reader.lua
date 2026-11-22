local _, ns = ...

-- The rotation reader: builds the snapshot's spell rows from what the client
-- says about each spell a class pack names. Pure: the client's answer comes
-- in through `spell`, a function of one spell id (Core/Client.lua's
-- client.spell), and nothing else is asked of the game.
--
-- A spell is asked about by id alone, so no unit is ever named: not the
-- player's, and nobody else's. No health or power amount is read; noPower is
-- the client's own yes or no (see R.FROM_AMOUNT in Snapshot.lua).
--
-- finisherReady is not built here: nothing reads it yet, so it stays absent.
--
-- Ids: a pack names spells by name and stores no ids. The caller hands in
-- `ids`, { [name] = spell id }, as read from the game. A name with no id is
-- not read; it is listed in `unread`, never given a row of guesses.

ns.RotationReader = {}
local RR = ns.RotationReader

-- The fields taken from the client's answer. Each is true, false or nil;
-- nil means the client did not say.
RR.FIELDS = { "known", "usable", "noPower" }

-- Every spell name in pack.spells, sorted.
function RR.SpellNames(pack)
    local names = {}
    if type(pack) == "table" and type(pack.spells) == "table" then
        for name in pairs(pack.spells) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

-- { rows = { [name] = { known =, usable =, noPower = } }, unread = { name, ... } }
-- rows go straight into the snapshot's `spells`. unread (sorted) names the
-- pack's spells that could not be asked about: no id, no reader, or a read
-- that failed.
function RR.SpellRows(pack, ids, spell)
    local out = { rows = {}, unread = {} }
    ids = type(ids) == "table" and ids or {}
    for _, name in ipairs(RR.SpellNames(pack)) do
        local id = ids[name]
        local ok, answer = false, nil
        if type(id) == "number" and type(spell) == "function" then
            ok, answer = pcall(spell, id)
        end
        if ok and type(answer) == "table" then
            local row = {}
            for _, f in ipairs(RR.FIELDS) do
                if type(answer[f]) == "boolean" then row[f] = answer[f] end
            end
            out.rows[name] = row
        else
            out.unread[#out.unread + 1] = name
        end
    end
    return out
end

-- The ids table SpellRows takes, built by asking `idOf` (a function of one
-- spell name, meant to be client.spellId) for each spell the pack names.
-- -> ids, missing
--   ids: { [name] = spell id }, only where the answer was a number.
--   missing (sorted): the pack's spells with no id: no function, an ask that
--   failed, or any other answer. They get no id and so are not read.
function RR.SpellIds(pack, idOf)
    local ids, missing = {}, {}
    for _, name in ipairs(RR.SpellNames(pack)) do
        local ok, id = false, nil
        if type(idOf) == "function" then ok, id = pcall(idOf, name) end
        if ok and type(id) == "number" and id == id then
            ids[name] = id
        else
            missing[#missing + 1] = name
        end
    end
    return ids, missing
end
