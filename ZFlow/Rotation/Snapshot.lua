local _, ns = ...

-- The snapshot: a plain value of everything a decision reads. Built once,
-- then handed to ns.Choose; nothing reads the game while deciding.
--
--   ns.SnapshotOf(fields) -> snapshot, ignored
--     A complete snapshot from a table of fields. Missing fields take the
--     default below; tables are copied, so the snapshot shares nothing with
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

-- kind: "flag" (true or false), "value" (kept as given, nil when not given),
-- "number" (a number, else nil: an unread number stays unknown, never 0),
-- "map" (a table of plain values, copied), "spells" (the spell rows).
R.SNAPSHOT_FIELDS = {
    { "inCombat", "flag" }, { "hostile", "flag" }, { "resting", "flag" }, { "dead", "flag" },
    { "role", "value" }, { "tree", "value" }, { "fightType", "value" },
    { "form", "value" }, { "stealthed", "flag" }, { "combo", "number" }, { "outOfMana", "flag" },
    { "casting", "value" }, { "targetCasting", "value" },
    { "targetNear", "flag" }, { "targetMelee", "flag" }, { "targetOnYou", "flag" }, { "hittingYou", "flag" },
    { "canSpareMana", "flag" }, { "attacking", "flag" }, { "canStartAttack", "flag" }, { "engageGaveUp", "flag" },
    { "loc", "value" }, { "lowHealth", "flag" }, { "hpPct", "number" }, { "hurt", "number" },
    { "buffs", "map" }, { "targetDebuffs", "map" }, { "debuffTypes", "map" }, { "current", "map" },
    { "spells", "spells" },
}
-- A spell row: known, usable and onCooldown are flags, but usable and inRange
-- keep "not read" (nil) apart from "no" (false): the chooser treats a range
-- or a usable state nobody read as fine.
R.SPELL_FIELDS = { "known", "usable", "onCooldown", "inRange", "castMs" }

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
            local r = { known = row.known and true or false, onCooldown = row.onCooldown and true or false }
            if row.usable ~= nil then r.usable = row.usable and true or false end
            if row.inRange ~= nil then r.inRange = row.inRange and true or false end
            if type(row.castMs) == "number" then r.castMs = row.castMs end
            out[name] = r
        end
    end
    return out
end

local function shape(kind, v)
    if kind == "flag" then return v and true or false end
    if kind == "number" then return type(v) == "number" and v or nil end
    if kind == "map" then return copyMap(v) end
    if kind == "spells" then return copySpells(v) end
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

function ns.Snapshot(read)
    local fields = {}
    if type(read) == "function" then
        for _, f in ipairs(R.SNAPSHOT_FIELDS) do
            fields[f[1]] = read(f[1])
        end
    end
    return ns.SnapshotOf(fields)
end
