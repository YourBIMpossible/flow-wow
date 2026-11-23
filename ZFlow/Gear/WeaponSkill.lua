local _, ns = ...

-- Weapon skills you have not trained yet (G16, with G12's untrained
-- wording). Pure: the item, the can-use answers and the skill lines you
-- know come in as data; nothing here reads the game.
--
--   yes    = GearWeaponSkill.Trained(subclassID, skills)
--   use    = GearWeaponSkill.Apply(use, packUse, item, skills)
--   wanted = GearWeaponSkill.Wanted(gear, who)
--
--   skills   client.weaponSkills(): { [skill line name] = true } for the
--            skill lines you know, as the client spells them; nil: not read
--   Trained  true, false, or nil when not known: skills not read, a kind
--            with no skill name here, or none of GearWeaponSkill.SKILL's
--            names among your lines at all (every class knows a weapon
--            skill, so those are not this client's words: never a no)
--   Apply    the can-use answer Gear/Verdict.lua goes by, changed only for
--            a weapon (item class 2) the class pack allows (packUse.can is
--            true) whose skill you have not trained, when the game does not
--            already say yes: { can = false, why = "untrained", reason =
--            GearWeaponSkill.REASON, skill, source = "skills" }. Anything
--            else comes back as it came: a kind the class can never use
--            keeps today's line, and skills not read change nothing.
--   Wanted   { subclassID, skill } when the item is an untrained weapon of
--            that kind and an upgrade for one of the pack's roles; else nil.
--            who = { pack, level, skills }, as Gear/Verdict.lua takes.
--
-- The skill names are the game's English skill lines by weapon subclass.
-- LOOK ONLY: nothing here trains, buys or equips anything.

local W = {}
ns.GearWeaponSkill = W

W.WEAPON = 2
W.REASON = "not trained (a weapon master teaches it)"
W.SKILL = {
    [0] = "Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "Maces",
    [5] = "Two-Handed Maces", [6] = "Polearms", [7] = "Swords", [8] = "Two-Handed Swords",
    [10] = "Staves", [13] = "Fist Weapons", [15] = "Daggers", [16] = "Thrown",
    [18] = "Crossbows", [19] = "Wands",
}

local function anyKnown(skills)
    for _, name in pairs(W.SKILL) do
        if skills[name] == true then return true end
    end
    return false
end

function W.Trained(subclassID, skills)
    local name = W.SKILL[subclassID]
    if type(name) ~= "string" or type(skills) ~= "table" then return nil end
    if not anyKnown(skills) then return nil end
    return skills[name] == true
end

function W.Apply(use, packUse, item, skills)
    if type(item) ~= "table" or item.classID ~= W.WEAPON then return use end
    if type(packUse) ~= "table" or packUse.can ~= true then return use end
    if type(use) == "table" and use.can == true then return use end
    if W.Trained(item.subclassID, skills) ~= false then return use end
    return { can = false, why = "untrained", reason = W.REASON, skill = W.SKILL[item.subclassID],
             source = "skills" }
end

local function rolesOf(pack)
    local out = {}
    if type(pack) == "table" and type(pack.weights) == "table" then
        for role, w in pairs(pack.weights) do
            if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
        end
    end
    table.sort(out)
    return out
end

function W.Wanted(gear, who)
    if type(gear) ~= "table" or gear.classID ~= W.WEAPON or type(who) ~= "table" then return nil end
    local roles = rolesOf(who.pack)
    for i = 1, #roles do
        local lines, detail = ns.GearVerdict.Lines(gear,
            { pack = who.pack, role = roles[i], level = who.level, skills = who.skills })
        if lines == nil or type(detail) ~= "table" or type(detail.use) ~= "table"
            or detail.use.why ~= "untrained" then
            return nil
        end
        if type(detail.result) == "table" and detail.result.verdict == "upgrade" then
            return { subclassID = gear.subclassID, skill = detail.use.skill }
        end
    end
    return nil
end
