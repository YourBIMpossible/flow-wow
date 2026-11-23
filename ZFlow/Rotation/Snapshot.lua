local _, ns = ...

-- The snapshot: a plain value of everything a decision reads. Built once,
-- then handed to ns.Choose; nothing reads the game while deciding.
--
--   ns.SnapshotOf(fields) -> snapshot, ignored
--     A complete snapshot from a table of fields. Missing fields take the
--     default below (a flag not given stays nil: not known is not "no"); tables are copied, so the snapshot shares nothing with
--     what it was given. ignored: the sorted names of fields it does not
--     know (they are left out, not guessed at).
--
--   ns.Snapshot(read) -> snapshot, ignored
--     The same, with each field asked from read(fieldName). read is given
--     by the caller (the kernel's client layer in the game, a fake in
--     tests): this file calls nothing in the client itself.
--
-- The fields are the ones ns.Choose documents (ZFlow/Rotation/Choose.lua).

ns.Rotation = ns.Rotation or {}
local R = ns.Rotation

-- kind: "flag" (true or false, nil when not given), "value" (kept as given, nil when not given),
-- "number" (a number, else nil: an unread number stays unknown, never 0),
-- "map" (a table of plain values, copied; nil when not read), "spells" (the spell rows).
R.SNAPSHOT_FIELDS = {
    { "inCombat", "flag" }, { "hostile", "flag" }, { "resting", "flag" }, { "dead", "flag" },
    { "role", "value" }, { "tree", "value" }, { "fightType", "value" },
    { "form", "value" }, { "formKnown", "flag" }, { "stealthed", "flag" }, { "finisherReady", "flag" },
    { "casting", "value" }, { "targetCasting", "value" },
    { "targetNear", "flag" }, { "targetMelee", "flag" }, { "targetOnYou", "flag" }, { "hittingYou", "flag" },
    { "attacking", "flag" }, { "canStartAttack", "flag" }, { "engageGaveUp", "flag" },
    { "loc", "value" }, { "lowHealth", "flag" }, { "hurt", "number" },
    { "buffs", "map" }, { "targetDebuffs", "map" }, { "debuffTypes", "map" },
    -- PRIEST-3 (P-SELFBUFF): your own debuffs by name (Weakened Soul); nil when not read.
    { "debuffs", "map" },
    { "current", "map" },
    -- Lead section 197: your pet (Choose.lua, R.PetUp); nil when not read.
    { "pet", "map" },
    { "conjured", "map" },
    -- Section 226 (CF-30): the best Well Fed food in your bags for your role,
    -- { name, item, score }; {} when the bags hold none; nil when not read.
    { "buffFood", "map" },
    -- Section 230 (BF-2, BF-3): mounted, on a flight path (nil when not
    -- read), and the Well Fed food setting (nil without the driver's table).
    { "mounted", "flag" }, { "onTaxi", "flag" }, { "foodOn", "flag" },
    -- Section 235 item 4: a fishing pole in your main hand (nil: not read).
    { "fishingPole", "flag" },
    -- N8 (lead section 238): healthstone and healing potion, { stone,
    -- stoneName, stoneWait, potion, potionName, potionWait, alt }; nil when
    -- not read or the setting is off (Rotation/Driver.lua).
    { "healItem", "map" },
    -- P-GATHER (Rotation/Gather.lua): gathering tracking, read by G.Read.
    { "tracking", "map" }, { "trackKnown", "map" }, { "professions", "map" }, { "gatherOn", "flag" },
    -- GT-1 (Rotation/Gather.lua): any tracking on. Mounted and on a flight path are the two flags above.
    { "trackingAny", "flag" },
    -- CF-32, N12: the seals and blessings you cast or chose, by key
    -- (Rotation/OwnCasts.lua); nil when there is none.
    { "chosen", "map" },
    -- N13: the buffs on you that you put up yourself (client.ownBuffs),
    -- the same shape as buffs; nil when not read.
    { "ownBuffs", "map" },
    -- PC-3: whether you are in a group (client.grouped); nil when not read.
    { "grouped", "flag" },
    -- P-PARTY (Rotation/Group.lua): the other players in your party, a list
    -- of { unit, name, class, role, kind, power, dead, connected, reach,
    -- has, debuffTypes } (kind "party"); nil when not read. The names are
    -- for the live caption only: never saved. groupOn: the setting.
    { "party", "party" }, { "groupOn", "flag" },
    { "spells", "spells" },
}
-- Names that would be made from a health or power amount. This client hides
-- those amounts from addon code (comparing one raises an error), so the
-- snapshot has no such field: the reader is never asked for one, and one
-- handed in is left out and named in `ignored`. What stands in for them:
--   health        lowHealth (the game's own warning) and hurt (our estimate)
--   out of power  spells[name].noPower (the game refuses the spell for power)
--   mana to spare the spell's own usable flag
--   combo points  finisherReady: true only when the reader can tell, without
--                 a hidden amount, that a finisher is due. Not given, no
--                 finisher is suggested.
R.FROM_AMOUNT = { hpPct = "health", outOfMana = "power", canSpareMana = "power", combo = "power" }
-- A spell row: known, usable, onCooldown, inRange and noPower keep "not read"
-- (nil) apart from "no" (false): the chooser treats a range or a usable
-- state nobody read as fine, never reads "lacks power" into a row nobody
-- read, and does not suggest a spell whose known or whose cooldown nobody
-- read (a cooldown not read is not "ready").
R.SPELL_FIELDS = { "known", "usable", "onCooldown", "inRange", "noPower", "castMs" }

local kindOf = {}
for _, f in ipairs(R.SNAPSHOT_FIELDS) do kindOf[f[1]] = f[2] end

local function copyMap(t)
    local out = {}
    if type(t) == "table" then
        for k, v in pairs(t) do
            if type(v) ~= "table" and type(v) ~= "function" then out[k] = v end
        end
    end
    return out
end

local function copySpells(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for name, row in pairs(t) do
        if type(name) == "string" and type(row) == "table" then
            local r = {}
            if row.onCooldown ~= nil then r.onCooldown = row.onCooldown and true or false end
            if row.known ~= nil then r.known = row.known and true or false end
            if row.usable ~= nil then r.usable = row.usable and true or false end
            if row.inRange ~= nil then r.inRange = row.inRange and true or false end
            if row.noPower ~= nil then r.noPower = row.noPower and true or false end
            if type(row.castMs) == "number" then r.castMs = row.castMs end
            out[name] = r
        end
    end
    return out
end

-- P-PARTY: the party list, row by row: the plain fields kept by type, the
-- three maps copied (nil when not read). A row with no unit is left out.
local PARTY_TEXT = { "unit", "name", "class", "role", "kind" }
local PARTY_FLAGS = { "dead", "connected" }
local PARTY_MAPS = { "reach", "has", "debuffTypes" }
local function copyParty(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, row in ipairs(list) do
        if type(row) == "table" and type(row.unit) == "string" and row.unit ~= "" then
            local r = {}
            for _, f in ipairs(PARTY_TEXT) do
                if type(row[f]) == "string" then r[f] = row[f] end
            end
            if type(row.power) == "number" then r.power = row.power end
            for _, f in ipairs(PARTY_FLAGS) do
                if type(row[f]) == "boolean" then r[f] = row[f] end
            end
            for _, f in ipairs(PARTY_MAPS) do
                if type(row[f]) == "table" then r[f] = copyMap(row[f]) end
            end
            out[#out + 1] = r
        end
    end
    return out
end

local function shape(kind, v)
    if kind == "flag" then
        if v == nil then return nil end
        return v and true or false
    end
    if kind == "number" then return type(v) == "number" and v or nil end
    -- A map nobody read stays nil (not known), never an empty map: an empty
    -- map says "read, and nothing there" (section 183).
    if kind == "map" then
        if type(v) ~= "table" then return nil end
        return copyMap(v)
    end
    if kind == "spells" then return copySpells(v) end
    if kind == "party" then return copyParty(v) end
    if type(v) == "table" or type(v) == "function" then return nil end
    return v
end

function ns.SnapshotOf(fields)
    fields = type(fields) == "table" and fields or {}
    local s, ignored = {}, {}
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do
        s[f[1]] = shape(f[2], fields[f[1]])
    end
    for k in pairs(fields) do
        if not kindOf[k] then ignored[#ignored + 1] = tostring(k) end
    end
    table.sort(ignored)
    return s, ignored
end

-- Conjured food and water (lead section 197): snapshot.conjured is
-- { [conjure spell] = how many of what it makes are in your bags }, read by
-- the driver for the items a pack names in options.conjure. R.Conjured(s,
-- spell) is that count, or nil when it was not read: a pack asks for the
-- spell only on a count it read, never on nil.
function R.Conjured(s, spell)
    local map = type(s) == "table" and s.conjured or nil
    local n = type(map) == "table" and map[spell] or nil
    if type(n) ~= "number" or n ~= n then return nil end
    return n
end

function ns.Snapshot(read)
    local fields = {}
    if type(read) == "function" then
        for _, f in ipairs(R.SNAPSHOT_FIELDS) do
            fields[f[1]] = read(f[1])
        end
    end
    return ns.SnapshotOf(fields)
end
