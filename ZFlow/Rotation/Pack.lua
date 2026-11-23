local _, ns = ...

-- The class pack: one table per class holding everything Flow says about
-- that class. Pure data plus pure predicates: a pack never calls the client.
--
-- Row shape (docs/ZFLOW-TARGET.md, section 4):
--   provenance   { author, date, method, facts }  who wrote the pack and how
--   roles        { dps = { name, evidence }, heal = ..., tank = ... }
--   resources    { { name, forms, evidence }, ... }
--   maintain     { { spell, seconds, evidence }, ... }  buffs kept on yourself
--   lists        { default = { rule, ... }, aoe = { ... } }
--   groups       { { spell, aura, who, slot, minutes, rebuff, when, evidence }, ... }
--                out-of-combat buffs for your group, only shown (P-PARTY,
--                Rotation/Group.lua; also the tooltip, Rotation/GroupTip.lua):
--                aura the buff names that count as this one (default the
--                spell); who "all" or a list of kinds (tank, healer, melee,
--                caster, ranged) and class tokens; slot: rows sharing one
--                give each player only the first that fits (a paladin's
--                blessings); rebuff: seconds left at which it counts as
--                missing (default 30); when(snapshot): yours to cast now
--   heals        { self = { spell, ... }, hots = { ... }, lingers = { [spell] = seconds } }
--   interrupts   { { spell, near, forms = { [formName or "none"] = true }, evidence }, ... }
--   breakers     { { spell, types = { ROOT = true }, any, form, evidence }, ... }
--   dispels      { { spell, types = { Poison = true }, evidence }, ... }  yours; the
--                same rows are only shown for your group (P-PARTY)
--   keys         { [formName or "none" or "stealth"] = { key, ctrl, shift, alt, more } }
--   weights      { [role] = { evidence, values = { [stat] = number } } } or nil per role
--   proficiency  { evidence, [itemClass] = { [subclass] = true or n } }  n: from level n
--   weaponSpeed  { evidence, [role] = { prefer, why, ranged = { prefer, why },
--                offhand = { prefer, why } } }: an entry for every role with
--                weights (lead section 280). prefer: "slow", "medium", "fast",
--                or "any" when speed does not matter for the role; why: the
--                reason, in words. ranged and offhand are optional parts for
--                a weapon of the ranged slot and one that only goes in the
--                off hand (Gear/WeaponSpeed.lua). Shown on a weapon's
--                tooltip; never counted in a score.
--   spells       { [name] = { evidence, level, improves, needs, note } }
--   talentBuilds { { name, role, evidence, order = { { "Talent", ranks, why = "..." }, ... } }, ... }
--     (why is optional; a reason given must be words, section 242)
--   options      { ... }
--
-- A rule: { spell, kind, reason, target, adaptive, when = function(snapshot), evidence, provenance }.
--
-- Evidence classes (the three-class policy; the third class, third-party
-- data, is never stored, so it has no name here):
--   "observed"     read from the game by Flow
--   "first guess"  a value nobody has read from the game yet
--   "authored"     a model written by Flow; needs a provenance note

ns.Pack = {}
local P = ns.Pack

P.KEYS = {
    "provenance", "roles", "resources", "maintain", "lists", "groups", "heals", "interrupts",
    "breakers", "dispels", "keys", "weights", "proficiency", "weaponSpeed", "spells", "talentBuilds",
    "options",
}
P.SPEEDS = { slow = true, medium = true, fast = true, any = true }
P.SPEED_PARTS = { "ranged", "offhand" }
P.PROVENANCE_KEYS = { "author", "date", "method", "facts" }
P.EVIDENCE = { ["observed"] = true, ["first guess"] = true, ["authored"] = true }
-- P-PARTY: what a group row's `who` may name: the kinds Rotation/GroupTip.lua
-- tells a player by, and the class tokens.
P.GROUP_KINDS = { tank = true, healer = true, melee = true, caster = true, ranged = true }
P.CLASSES = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true, DEATHKNIGHT = true,
}

local function add(problems, fmt, ...)
    problems[#problems + 1] = string.format(fmt, ...)
end

-- An evidence class on a row; an authored row needs its provenance note.
local function checkEvidence(row, where, problems)
    local e = row.evidence
    if e == nil then
        add(problems, "%s: no evidence class", where)
    elseif not P.EVIDENCE[e] then
        add(problems, "%s: unknown evidence class \"%s\"", where, tostring(e))
    elseif e == "authored" and type(row.provenance) ~= "string" then
        add(problems, "%s: authored without a provenance note", where)
    end
end

local function checkProvenance(prov, problems)
    if type(prov) ~= "table" then
        add(problems, "missing provenance block")
        return
    end
    for _, key in ipairs(P.PROVENANCE_KEYS) do
        if type(prov[key]) ~= "string" or prov[key] == "" then
            add(problems, "missing provenance block: no %s", key)
        end
    end
end

-- Every spell a pack names must be in pack.spells.
local function needSpell(pack, name, where, problems)
    if type(name) ~= "string" then
        add(problems, "%s: spell is not a name", where)
    elseif type(pack.spells) == "table" and pack.spells[name] == nil then
        add(problems, "unknown required spell \"%s\" (%s)", name, where)
    end
end

local function checkRules(pack, rules, where, problems)
    if type(rules) ~= "table" then return end
    for i, rule in ipairs(rules) do
        local at = string.format("%s[%d]", where, i)
        if type(rule) ~= "table" then
            add(problems, "%s: not a table", at)
        else
            needSpell(pack, rule.spell, at, problems)
            if rule.when ~= nil and type(rule.when) ~= "function" then
                add(problems, "%s: when is not a function", at)
            end
            checkEvidence(rule, at, problems)
        end
    end
end

local function checkNames(pack, names, where, problems)
    if type(names) == "string" then
        needSpell(pack, names, where, problems)
    elseif type(names) == "table" then
        for i, name in ipairs(names) do
            needSpell(pack, name, string.format("%s[%d]", where, i), problems)
        end
    end
end

-- One weaponSpeed entry, or one of its parts: a speed and a reason in words.
local function checkSpeed(row, where, problems)
    if type(row) ~= "table" then
        add(problems, "%s: no entry", where)
        return
    end
    if not P.SPEEDS[row.prefer] then add(problems, "%s: no preferred speed", where) end
    if type(row.why) ~= "string" or row.why == "" then add(problems, "%s: no reason", where) end
end

-- ns.PackCheck(pack) -> ok, problems
-- problems: a sorted list of plain sentences, empty when ok.
function ns.PackCheck(pack)
    if type(pack) ~= "table" then
        return false, { "pack is not a table" }
    end
    local problems = {}
    for _, key in ipairs(P.KEYS) do
        if key ~= "provenance" and pack[key] == nil then add(problems, "missing key \"%s\"", key) end
    end
    checkProvenance(pack.provenance, problems)

    if type(pack.spells) == "table" then
        for name, row in pairs(pack.spells) do
            if type(row) ~= "table" then
                add(problems, "spells[\"%s\"]: not a table", tostring(name))
            else
                checkEvidence(row, string.format("spells[\"%s\"]", tostring(name)), problems)
            end
        end
    end

    if type(pack.lists) == "table" then
        if pack.lists.default == nil then add(problems, "missing key \"lists.default\"") end
        for name, rules in pairs(pack.lists) do
            checkRules(pack, rules, "lists." .. tostring(name), problems)
        end
    end
    for _, key in ipairs({ "maintain", "groups", "interrupts", "breakers", "dispels" }) do
        checkRules(pack, pack[key], key, problems)
    end

    -- Look only for other players (P-PARTY): a pack's dispels are your own;
    -- your group's are only shown, from the same rows, never cast.
    if type(pack.dispels) == "table" then
        for i, rule in ipairs(pack.dispels) do
            if type(rule) == "table" and (rule.group or (rule.unit ~= nil and rule.unit ~= "player")) then
                add(problems, "dispels[%d]: a group dispel entry (a pack's dispels are your own; "
                    .. "your group's are only shown, from the same rows, never cast)", i)
            end
        end
    end

    -- P-PARTY: the group rows (Rotation/Group.lua). Their spell, when and
    -- evidence are checked above with the other rule lists.
    if type(pack.groups) == "table" then
        for i, row in ipairs(pack.groups) do
            if type(row) == "table" then
                local at = string.format("groups[%d]", i)
                local who = row.who
                if who ~= "all" then
                    if type(who) ~= "table" or #who == 0 then
                        add(problems, "%s: who is not \"all\" or a list of kinds and classes", at)
                    else
                        for j, w in ipairs(who) do
                            if not (P.GROUP_KINDS[w] or P.CLASSES[w]) then
                                add(problems, "%s: who[%d] is not a kind or a class", at, j)
                            end
                        end
                    end
                end
                if row.aura ~= nil then
                    local fine = type(row.aura) == "table" and #row.aura > 0
                    if fine then
                        for _, name in ipairs(row.aura) do
                            if type(name) ~= "string" or name == "" then fine = false end
                        end
                    end
                    if not fine then add(problems, "%s: aura is not a list of buff names", at) end
                end
                if row.slot ~= nil and (type(row.slot) ~= "string" or row.slot == "") then
                    add(problems, "%s: slot is not a name", at)
                end
                for _, key in ipairs({ "minutes", "rebuff" }) do
                    local v = row[key]
                    if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0) then
                        add(problems, "%s: %s is not a number", at, key)
                    end
                end
                if row.unit ~= nil then
                    add(problems, "%s: names a unit; group rows are only shown, never cast on anyone", at)
                end
            end
        end
    end
    if pack.groupBuffs ~= nil then add(problems, "groupBuffs: the group rows are in groups now") end

    if type(pack.heals) == "table" then
        if pack.heals.self == nil then add(problems, "missing key \"heals.self\"") end
        checkNames(pack, pack.heals.self, "heals.self", problems)
        checkNames(pack, pack.heals.hots, "heals.hots", problems)
        if type(pack.heals.lingers) == "table" then
            for name in pairs(pack.heals.lingers) do
                needSpell(pack, name, "heals.lingers", problems)
            end
        end
    end

    if type(pack.keys) == "table" then
        for form, row in pairs(pack.keys) do
            if type(row) == "table" then
                for slot, names in pairs(row) do
                    if slot ~= "form" then
                        checkNames(pack, names, string.format("keys[\"%s\"].%s", tostring(form), tostring(slot)), problems)
                    end
                end
            end
        end
    end

    for _, key in ipairs({ "roles", "weights" }) do
        if type(pack[key]) == "table" then
            for name, row in pairs(pack[key]) do
                if type(row) == "table" then
                    checkEvidence(row, string.format("%s.%s", key, tostring(name)), problems)
                end
            end
        end
    end
    for _, key in ipairs({ "resources", "talentBuilds" }) do
        if type(pack[key]) == "table" then
            for i, row in ipairs(pack[key]) do
                if type(row) == "table" then checkEvidence(row, string.format("%s[%d]", key, i), problems) end
            end
        end
    end
    -- Section 242, DRUID-3: a talent reason, when given, is words.
    for i, build in ipairs(type(pack.talentBuilds) == "table" and pack.talentBuilds or {}) do
        local order = type(build) == "table" and build.order or nil
        for j, entry in ipairs(type(order) == "table" and order or {}) do
            if type(entry) == "table" and entry.why ~= nil
                and (type(entry.why) ~= "string" or entry.why == "") then
                problems[#problems + 1] = string.format("talentBuilds[%d].order[%d]: the reason is not words", i, j)
            end
        end
    end
    if type(pack.proficiency) == "table" then checkEvidence(pack.proficiency, "proficiency", problems) end
    -- Lead section 280: every role with weights says its weapon speed.
    if type(pack.weaponSpeed) == "table" then
        checkEvidence(pack.weaponSpeed, "weaponSpeed", problems)
        local weights = {}
        if type(pack.weights) == "table" then weights = pack.weights end
        for role, row in pairs(weights) do
            if type(role) == "string" and type(row) == "table" then
                local where = "weaponSpeed." .. role
                local entry = pack.weaponSpeed[role]
                checkSpeed(entry, where, problems)
                if type(entry) == "table" then
                    for _, part in ipairs(P.SPEED_PARTS) do
                        if entry[part] ~= nil then checkSpeed(entry[part], where .. "." .. part, problems) end
                    end
                end
            end
        end
    end

    table.sort(problems)
    return #problems == 0, problems
end

-- With the kernel loaded, class packs are a declared kind: a pack that does
-- not pass PackCheck is recorded as a problem and not registered.
if type(ns.Kind) == "function" then
    ns:Kind{ name = "classPack", row = function(row)
        local ok, problems = ns.PackCheck(row)
        return ok, ok and nil or table.concat(problems, "; ")
    end }
end
