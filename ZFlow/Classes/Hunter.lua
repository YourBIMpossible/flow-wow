local _, ns = ...

-- The Hunter class pack (shape: ZFlow/Rotation/Pack.lua, the same rows as
-- Classes/Paladin.lua and Classes/Druid.lua). Lead section 197; the plan is
-- in from-zen RESULTS ("pet-state contract and Hunter plan"). Pure: every
-- rule reads the snapshot it is given (ZFlow/Rotation/Choose.lua lists the
-- fields, the pet among them) and nothing else.
--
-- Scope: damage on your own target, your own aspect and your own pet. It
-- suggests only: no pet command, no cast, nothing pressed for you. Nothing
-- here heals, buffs or revives another player.
--
-- Evidence. No hunter file existed before this one, and the repository holds
-- no client observations for the class, so nothing is "observed". Spell
-- names, trainer levels, list order, what the class can equip and the role
-- name are a "first guess" from general knowledge of the class, written for
-- Z-Flow; each needs a check in the game client. The stat weights are an
-- "authored" model with their note. No guide, database or other addon used.
--
-- Left out, on purpose:
--   * Mend Pet: it needs the pet's health, and no pet health is read (D1);
--   * ammunition: no read for it; a shot without ammunition is refused by
--     the game (its usable / noPower answer), and that is all used here;
--   * traps, Feign Death, Disengage, Concussive Shot, Scatter Shot, Aimed
--     Shot and Rapid Fire as advice (situational or talents; the spells are
--     listed, and on the key row where they fit, but no rule asks for them);
--   * starting a melee swing: there is no "Attack" row, so the engage step
--     never sends a hunter into melee.

local GUESS = "first guess"
local MADE = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game"

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
local function hostile(s) return s.hostile == true end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
-- Read as off / on (section 183): a current map not read, or a spell left
-- out of it, is neither, and the rule that wants one does not fire.
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
local function readOn(s, name) return type(s.current) == "table" and s.current[name] == true end
-- Target debuffs not read: not known, so not missing (section 186).
local function missingOnTarget(s, name)
    if type(s.targetDebuffs) ~= "table" then return false end
    return not s.targetDebuffs[name]
end
-- In melee reach: that spell's range read as yes. Not read, or no, is not
-- in reach, so a melee rule never reaches the out-of-range step: a hunter
-- with the shots on cooldown is not sent into melee.
local function inReach(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.inRange == true) and true or false
end

-- Is an aspect on? true, false, or nil when your buffs were not read. Any
-- aspect counts: one you chose (the cheetah, the pack) is left alone.
function ns.HunterHasAspect(s)
    if type(s.buffs) ~= "table" then return nil end
    for name in pairs(s.buffs) do
        if type(name) == "string" and string.sub(name, 1, 10) == "Aspect of " then return true end
    end
    return false
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local aspect = tag({
    { spell = "Aspect of the Hawk", kind = "buff", reason = "No aspect is on",
      when = function(s) return ns.HunterHasAspect(s) == false end },
    { spell = "Aspect of the Monkey", kind = "buff", reason = "No aspect is on",
      when = function(s) return ns.HunterHasAspect(s) == false and not knows(s, "Aspect of the Hawk") end },
})

-- Your pet, only when it was read (R.NoPet, R.PetDead, R.PetUp answer nil
-- then) and only out of a fight. Suggested, never done for you.
local pet = tag({
    { spell = "Call Pet", kind = "buff", reason = "No pet is out: call it",
      when = function(s) return outOfFight(s) and ns.Rotation.NoPet(s) == true end },
    { spell = "Revive Pet", kind = "buff", reason = "Your pet is dead: revive it",
      when = function(s) return outOfFight(s) and ns.Rotation.PetDead(s) == true end },
    { spell = "Feed Pet", kind = "buff", reason = "Your pet is unhappy: feed it",
      when = function(s) return outOfFight(s) and ns.Rotation.PetUp(s) == true and s.pet.happiness == "unhappy" end },
})

local mark = tag({
    { spell = "Hunter's Mark", target = true, reason = "Your target is not marked",
      when = function(s) return hostile(s) and missingOnTarget(s, "Hunter's Mark") end },
})
local sting = tag({
    { spell = "Serpent Sting", target = true, reason = "Serpent Sting is not on your target",
      when = function(s) return hostile(s) and missingOnTarget(s, "Serpent Sting") end },
})
local autoShot = tag({
    { spell = "Auto Shot", target = true, reason = "Start shooting",
      when = function(s) return hostile(s) and readOff(s, "Auto Shot") end },
})
local arcane = tag({
    { spell = "Arcane Shot", target = true, reason = "Arcane Shot", when = hostile },
})
local multi = tag({
    { spell = "Multi-Shot", target = true, reason = "Several enemies: Multi-Shot", when = hostile },
})
local melee = tag({
    { spell = "Raptor Strike", target = true, reason = "In melee: Raptor Strike",
      when = function(s) return hostile(s) and inReach(s, "Raptor Strike") and not readOn(s, "Raptor Strike") end },
    { spell = "Mongoose Bite", target = true, reason = "In melee: Mongoose Bite",
      when = function(s) return hostile(s) and inReach(s, "Mongoose Bite") end },
    { spell = "Wing Clip", target = true, reason = "In melee: Wing Clip, then step back to shoot",
      when = function(s) return hostile(s) and inReach(s, "Wing Clip") and missingOnTarget(s, "Wing Clip") end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key row (what each modifier holds). No forms: one row.
local keys = {
    key = { "Arcane Shot", "Auto Shot" },
    ctrl = { "Serpent Sting", "Hunter's Mark" },
    shift = { "Multi-Shot", "Concussive Shot" },
    alt = { "Raptor Strike", "Mongoose Bite", "Wing Clip" },
    more = { "Hunter's Mark", "Concussive Shot", "Wing Clip" },
}

-- Spells: the level is a first guess at the trainer level (not read from a
-- WoW: Forever trainer). No level: a talent. A row is a fact about the
-- spell, not advice: several rows are spells no rule here suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Auto Shot"]            = sp(1,  { "DPS" }, nil, "on or off: read through current"),
    ["Raptor Strike"]        = sp(1,  { "DPS" }, nil, "melee; on the next swing"),
    ["Aspect of the Monkey"] = sp(4,  { "Survival" }),
    ["Serpent Sting"]        = sp(4,  { "DPS" }),
    ["Arcane Shot"]          = sp(6,  { "DPS" }),
    ["Hunter's Mark"]        = sp(6,  { "DPS" }),
    ["Concussive Shot"]      = sp(8,  { "Control" }),
    ["Aspect of the Hawk"]   = sp(10, { "DPS" }),
    ["Call Pet"]             = sp(10, { "Pet" }, nil, "from the class quest that teaches taming"),
    ["Revive Pet"]           = sp(10, { "Pet" }, nil, "from the class quest that teaches taming"),
    ["Feed Pet"]             = sp(10, { "Pet" }, nil, "from the class quest that teaches taming"),
    ["Mend Pet"]             = sp(12, { "Pet" }, nil, "no rule: it needs the pet's health, which is not read (D1)"),
    ["Wing Clip"]            = sp(12, { "Control" }),
    ["Mongoose Bite"]        = sp(16, { "DPS" }, nil, "usable only after the target dodges"),
    ["Multi-Shot"]           = sp(18, { "DPS" }),
    ["Aspect of the Cheetah"] = sp(20, { "Travel" }),
    ["Disengage"]            = sp(20, { "Survival" }),
    ["Freezing Trap"]        = sp(20, { "Control" }),
    ["Rapid Fire"]           = sp(26, { "DPS" }),
    ["Feign Death"]          = sp(30, { "Survival" }),
    ["Aspect of the Pack"]   = sp(40, { "Travel" }),
    ["Volley"]               = sp(40, { "DPS" }),
    ["Aimed Shot"]           = sp(nil, { "DPS" }, nil, "a Marksmanship talent"),
}

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-23",
        method = "Written for this pack (lead section 197) on the shape of Classes/Paladin.lua and Classes/Druid.lua. "
            .. "No earlier hunter file existed in the repository; proficiency follows Modules/Gear/Score.lua's HUNTER "
            .. "row, with mail from level 40 (D3).",
        facts = "No value here was read from the game and none comes from a list of client observations. Every "
            .. "fact is marked first guess and needs a check in the game client; the stat weights are an authored "
            .. "model. No guide, database or other addon used.",
    },

    -- One damage role (D2: "Marksmanship", a first guess at the name).
    roles = {
        dps = { name = "Marksmanship", evidence = GUESS },
    },

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS },
    },

    -- Kept on yourself while it is on: an aspect has no time running out.
    maintain = {
        { spell = "Aspect of the Hawk", evidence = GUESS, note = "no duration: kept up while it is on" },
    },

    lists = {
        default = join(aspect, pet, mark, sting, autoShot, arcane, melee),
        aoe = join(aspect, pet, mark, sting, autoShot, multi, arcane, melee),
    },

    -- Does not apply: no hunter spell here is cast on the group (Trueshot
    -- Aura is a talent on yourself; Aspect of the Pack is your own aspect).
    groups = {},

    -- Does not apply: the hunter has no heal for itself; Mend Pet heals the
    -- pet only and waits on the pet's health (D1).
    heals = {
        self = {},
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- Does not apply: no trained hunter spell stops a cast (Scatter Shot and
    -- Wyvern Sting are talents, not authored here).
    interrupts = {},

    -- Does not apply: no hunter spell breaks a root or a stun on yourself.
    breakers = {},

    -- Does not apply: the hunter cannot remove a poison, curse, disease or
    -- magic from itself.
    dispels = {},

    keys = { none = keys },

    -- Stat weights: relative numbers, score = sum(stat * weight). Damage only.
    weights = {
        dps = {
            evidence = "authored",
            provenance = "Authored by Flow, 2026-11-23 (lead section 197). Facts used: a hunter's damage comes from "
                .. "agility and attack power with a ranged weapon; stamina and intellect keep it going. Method: agility "
                .. "first, a ranged weapon's damage high, the rest below; the same keys as the other packs. A "
                .. "recommendation, not a game fact. No guide, database or other addon used.",
            values = {
                ITEM_MOD_AGILITY_SHORT = 1.0, ITEM_MOD_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_STAMINA_SHORT = 0.35,
                ITEM_MOD_INTELLECT_SHORT = 0.25, ITEM_MOD_SPIRIT_SHORT = 0.05, ITEM_MOD_STRENGTH_SHORT = 0.1,
                ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.9, ITEM_MOD_HASTE_RATING_SHORT = 0.5,
                ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0, RESISTANCE0_NAME = 0.05,
            },
        },
    },

    -- What the class can equip, by item class and subclass ids, from
    -- Modules/Gear/Score.lua's HUNTER row. Armor (4): 0 misc, 1 cloth,
    -- 2 leather, 3 mail from level 40 (D3: a level in place of true).
    -- Weapons (2): 0/1 axes, 2 bows, 3 guns, 6 polearms, 7/8 swords,
    -- 10 staves, 13 fist, 15 daggers, 16 thrown, 18 crossbows, 20 fishing pole.
    proficiency = {
        evidence = GUESS, note = MADE,
        [4] = { [0] = true, [1] = true, [2] = true, [3] = 40 },
        [2] = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true,
                [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
    },

    spells = spells,

    -- Not authored yet.
    talentBuilds = {},

    options = {
        -- Reads the rules lean on; one not given is named by diag (187, 197).
        reads = { "buffs", "targetDebuffs", "pet" },
        -- The shots have a minimum range: out of range is too far or too
        -- close (Choose.lua farOpener, Diag's rotation line).
        minRange = true,
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.HUNTER = pack
if type(ns.Register) == "function" then ns:Register("classPack", "HUNTER", pack) end
