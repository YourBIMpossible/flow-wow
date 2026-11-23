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
--   groups       { { spell, evidence }, ... }  out-of-combat group buffs
--   heals        { self = { spell, ... }, hots = { ... }, lingers = { [spell] = seconds } }
--   interrupts   { { spell, near, forms = { [formName or "none"] = true }, evidence }, ... }
--   breakers     { { spell, types = { ROOT = true }, any, form, evidence }, ... }
--   dispels      { { spell, types = { Poison = true }, evidence }, ... }  yourself only
--   keys         { [formName or "none" or "stealth"] = { key, ctrl, shift, alt, more } }
--   weights      { [role] = { evidence, values = { [stat] = number } } } or nil per role
--   proficiency  { evidence, [itemClass] = { [subclass] = true } }
--   spells       { [name] = { evidence, level, improves, needs, note } }
--   talentBuilds { { name, role, evidence, order = { ... } }, ... }
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
    "breakers", "dispels", "keys", "weights", "proficiency", "spells", "talentBuilds", "options",
}
P.PROVENANCE_KEYS = { "author", "date", "method", "facts" }
P.EVIDENCE = { ["observed"] = true, ["first guess"] = true, ["authored"] = true }

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

    -- Removing things from other players is not advised: a pack's dispels are for yourself.
    if type(pack.dispels) == "table" then
        for i, rule in ipairs(pack.dispels) do
            if type(rule) == "table" and (rule.group or (rule.unit ~= nil and rule.unit ~= "player")) then
                add(problems, "dispels[%d]: a group dispel entry", i)
            end
        end
    end

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
    if type(pack.proficiency) == "table" then checkEvidence(pack.proficiency, "proficiency", problems) end

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
