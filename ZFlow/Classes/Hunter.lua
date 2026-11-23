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
-- Not in this pack yet (tasks):
--   * Mend Pet: it needs the pet's health, and no pet health is read (D1);
--   * ammunition: no read for it yet; a shot without ammunition is refused
--     by the game (its usable / noPower answer), and that is all used here;
--   * traps, Disengage, Concussive Shot, Scatter Shot, Aimed
--     Shot and Rapid Fire as advice: no rule asks for them yet (situational
--     or talents; the spells are listed, and on the key row where they fit);
--   * starting a melee swing: there is no "Attack" row yet, so the engage
--     step never sends a hunter into melee.
--
-- Not seen in the game, named on their own (review notes, lead section 208):
--   * HU2: ns.HunterHasAspect matches the English prefix "Aspect of " on
--     the buff names; a client in another language would read no aspect on
--     and ask for the hawk. Unchecked against a real buff list;
--   * N58 (lead section 241): the cheetah and the pack are told apart from
--     the other aspects by their English names; another language would
--     count them as an aspect to fight in;
--   * HU4: the pet's happiness is read from GetPetHappiness() as 1, 2, 3 =
--     "unhappy", "content", "happy" (Core/Client.lua); that mapping, and
--     Feed Pet firing on "unhappy" alone, are unchecked in the client.

local GUESS = "first guess"
local MADE = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game"

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
local function hostile(s) return s.hostile == true end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
-- Read as off (section 183): a current map not read, or a spell left out
-- of it, is not off, and the rule that wants it off does not fire.
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
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

-- N58 (lead section 241): the aspects the aspect word names (the ones in
-- this pack's spell list). The cheetah and the pack are for travel: a cast
-- of either is never kept, and in a fight neither counts as your aspect.
local ASPECTS = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack" }
local TRAVEL = { ["Aspect of the Cheetah"] = true, ["Aspect of the Pack"] = true }
local IS_ASPECT, IS_FIGHT_ASPECT = {}, {}
for _, name in ipairs(ASPECTS) do
    IS_ASPECT[name] = true
    if not TRAVEL[name] then IS_FIGHT_ASPECT[name] = true end
end

-- Is an aspect on? true, false, or nil when your buffs were not read. Out
-- of a fight (or the fight not read) any aspect counts: one you chose (the
-- cheetah, the pack) is left alone. N58 (lead section 241): in a fight
-- (inCombat true) the cheetah and the pack do not count, so the aspect to
-- fight in is asked for.
function ns.HunterHasAspect(s)
    if type(s.buffs) ~= "table" then return nil end
    local fight = s.inCombat == true
    for name in pairs(s.buffs) do
        if type(name) == "string" and string.sub(name, 1, 10) == "Aspect of "
            and not (fight and TRAVEL[name]) then
            return true
        end
    end
    return false
end

-- N58: the aspect to put up when none is on: the one you cast or chose,
-- while known; else the hawk, as before (the monkey rule covers a hawk not
-- known). A travel aspect chosen with the word holds out of a fight only.
-- New: Flow had no aspect choice.
function ns.HunterAspect(s)
    local OC = ns.OwnCasts
    local set = (s.inCombat == true) and IS_FIGHT_ASPECT or IS_ASPECT
    local kept = OC and OC.Kept(s, set, "aspect") or nil
    return kept or "Aspect of the Hawk"
end

-- N58: the aspect the rotation asks for now (PC-1: a cast of it is not
-- kept): the hawk not known is the monkey, as the rules below.
local function aspectNow(s)
    local want = ns.HunterAspect(s)
    if want == "Aspect of the Hawk" and not knows(s, want) then return "Aspect of the Monkey" end
    return want
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

-- N58: one rule per aspect; each asks only for the one ns.HunterAspect
-- gives. The monkey also stands in for a hawk not known, as before.
local function aspectRule(name)
    return { spell = name, kind = "buff", reason = "No aspect is on",
             when = function(s) return ns.HunterHasAspect(s) == false and ns.HunterAspect(s) == name end }
end

local aspect = tag({
    aspectRule("Aspect of the Hawk"),
    { spell = "Aspect of the Monkey", kind = "buff", reason = "No aspect is on",
      when = function(s)
          if ns.HunterHasAspect(s) ~= false then return false end
          local want = ns.HunterAspect(s)
          return want == "Aspect of the Monkey" or (want == "Aspect of the Hawk" and not knows(s, want))
      end },
    aspectRule("Aspect of the Cheetah"),
    aspectRule("Aspect of the Pack"),
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
      -- Strict, as Auto Shot: only when the queued read was given and says
      -- no. Not read is not "not queued" (review note HU3).
      when = function(s) return hostile(s) and inReach(s, "Raptor Strike") and readOff(s, "Raptor Strike") end },
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
    ["Scare Beast"]          = sp(14, { "Control" }),
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
    groupsNone = "No hunter spell is a buff you cast on your group: Trueshot Aura and Aspect of the Pack are your own.",

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
    dispelsNone = "A hunter cannot remove a poison, curse, disease or magic from anyone.",

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

    -- G15, lead section 280: the weapon speed each role likes, and why, for
    -- the speed line on a weapon's tooltip (Gear/WeaponSpeed.lua). "any":
    -- speed does not matter for the role. Not counted in the score.
    weaponSpeed = {
        evidence = GUESS,
        note = "written for lead section 280 from the game's rules as remembered; no outside source;"
            .. " not read from the game",
        dps = { prefer = "any", why = "shots do the damage; a melee weapon is carried for its stats",
                ranged = { prefer = "slow",
                           why = "Aimed Shot and Multi-Shot hit for weapon damage, so a slow bow or gun hits"
                               .. " harder per shot" } },
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
    talentBuilds = {
        { name = "Beast Mastery levelling build", role = "dps", evidence = GUESS, note = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game",
          trees = { "Beast Mastery", "Marksmanship", "Survival" },
          order = {
              { "Improved Aspect of the Hawk", 5, why = "Your ranged attacks now and then gain speed, with the aspect you keep on." },
              { "Endurance Training", 5, why = "Your pet has more health, so it holds the enemy longer." },
              { "Unleashed Fury", 5, why = "Your pet hits harder, and it does much of your killing." },
              { "Ferocity", 5, why = "Your pet lands more critical hits." },
              { "Spirit Bond", 2, why = "You and your pet heal over time, so fewer rests between pulls." },
              { "Intimidation", 1, why = "A pet attack that stuns the enemy and pulls it back off you." },
              { "Bestial Swiftness", 1, why = "Your pet runs faster outdoors, so it reaches the enemy first." },
              { "Improved Mend Pet", 2, why = "Mend Pet costs less and can clear a curse or poison from your pet." },
              { "Bestial Discipline", 2, why = "Your pet builds focus faster, so it uses its attacks more often." },
              { "Frenzy", 5, why = "Your pet attacks faster after its critical hits." },
              { "Bestial Wrath", 1, why = "A cooldown that makes your pet hit much harder for a short time." },
          },
        },
    },

    options = {
        crowdControl = { { spell = "Scare Beast", creatures = { beast = true } } },
        threatDrop = { spell = "Feign Death" },
        -- N50 / GAP DRUID-2 (P-SELFBUFF): the known-spell tree. Talent spells,
        -- in order: the first you know names your tree (snapshot.tree,
        -- Rotation/Driver.lua). Which spell is a talent of which tree: a first
        -- guess from the 1.12 talent trees as remembered, not read from the game.
        trees = {
            { spell = "Trueshot Aura", tree = "Marksmanship", evidence = GUESS },
            { spell = "Bestial Wrath", tree = "Beast Mastery", evidence = GUESS },
            { spell = "Wyvern Sting", tree = "Survival", evidence = GUESS },
            { spell = "Intimidation", tree = "Beast Mastery", evidence = GUESS },
            { spell = "Counterattack", tree = "Survival", evidence = GUESS },
            { spell = "Scatter Shot", tree = "Marksmanship", evidence = GUESS },
            { spell = "Aimed Shot", tree = "Marksmanship", evidence = GUESS },
            { spell = "Deterrence", tree = "Survival", evidence = GUESS },
        },
        -- Reads the rules lean on; one not given is named by diag (187, 197).
        reads = { "buffs", "targetDebuffs", "pet" },
        -- The shots have a minimum range: out of range is too far or too
        -- close (Choose.lua farOpener, Diag's rotation line).
        minRange = true,
        -- N58 (lead section 241): the aspect you cast is the one asked for
        -- (OwnCasts.lua). The cheetah and the pack are for travel, never
        -- kept from a cast. word: the word that chooses one of `names`.
        -- pick (PC-1): the one asked for now; a cast of it is not kept.
        sticky = {
            { prefix = "Aspect of ", key = "aspect", word = "aspect", names = ASPECTS, only = IS_ASPECT,
              temporary = function(name) return TRAVEL[name] == true end,
              pick = aspectNow },
        },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.HUNTER = pack
if type(ns.Register) == "function" then ns:Register("classPack", "HUNTER", pack) end
