local _, ns = ...

-- The Warrior class pack (lead section 197; shape: ZFlow/Rotation/Pack.lua,
-- same rows as Classes/Paladin.lua and Classes/Druid.lua). Pure: every rule
-- reads the snapshot it is given (ZFlow/Rotation/Choose.lua lists the
-- fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself. Nothing here is
-- cast on another player. A pack suggests; it never casts.
--
-- Stances are read as the form name (Battle Stance, Defensive Stance,
-- Berserker Stance); no stance read with formKnown true is "none". Rage is
-- not read as an amount: no rule waits on it, the game marks a strike not
-- usable when there is too little (needs game test).
--
-- Evidence. Nothing in this pack was read from the game by this file, and the
-- repository holds no list of client observations for the Warrior, so
-- nothing is marked "observed". Every spell name, trainer level, list order,
-- timing and stat weight is a "first guess" written for section 197 with no
-- outside source: each needs a check in the game client.
--
-- Not in this pack yet (tasks):
--   * Berserker Rage as a fear breaker is in (N52 WARRIOR-1/4); the fear
--     type names it waits for ("FEAR", "FEAR_MECHANIC") are a first guess,
--     unchecked against the client's loss-of-control read;
--   * anything that waits on a rage amount: the client hides power amounts
--     from addon code (R.FROM_AMOUNT in Rotation/Snapshot.lua);
--   * anything that waits on a swing timer or a block, dodge or parry event:
--     no read for them yet. The reactive strikes wait on the game's usable
--     answer.

local GUESS = "first guess"
local NOTE = "written for lead section 197; no outside source; needs a check in the game client"

local BATTLE, DEFENSIVE, BERSERKER = "Battle Stance", "Defensive Stance", "Berserker Stance"

-- Read as off: true only when the current map was read and says false.
-- Not read (nil map or no answer for the spell) is not "off" (section 183).
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
-- Lead section 358 (as section 340 for Druid, Paladin, Shaman): not swinging,
-- by the driver's swing read (s.attacking, Rotation/Driver.lua attackingOf,
-- over Auto Attack and Attack). Where that read was not made, either name
-- read as off. One row for both names: the button casts the swing as
-- "Attack" (Rotation/Cast.lua C.ATTACK_SPELL).
local function swingOff(s)
    if s.attacking ~= nil then return s.attacking == false end
    return readOff(s, "Attack") or readOff(s, "Auto Attack")
end
local function inFight(s) return ns.Rotation.InFight(s) end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
-- No stance, and the form was read: not "not known".
local function noForm(s) return s.form == nil and s.formKnown == true end
-- In this stance, read as such.
local function inStance(s, name) return s.formKnown == true and s.form == name end
-- A buff on yourself missing or nearly out. Buffs not read: not wanted.
local function needBuff(s, name, secs)
    if type(s.buffs) ~= "table" then return false end
    local left = s.buffs[name]
    if left == nil then return true end
    return type(left) == "number" and left < secs
end
-- A debuff of yours missing on the target. Debuffs not read: not missing.
local function missingOnTarget(s, name)
    if type(s.targetDebuffs) ~= "table" then return false end
    return not s.targetDebuffs[name]
end
-- The game says it can be used now. Not read is not a yes.
local function usable(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.usable == true) and true or false
end
local function tank(s) return s.role == "tank" end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

-- N58 (lead section 241): the stance asked for. The one you cast and held
-- (or chose with the word), while known; else Defensive Stance for a tank,
-- Battle Stance for the rest. New: Flow had no stance choice.
local STANCE_NAMES = { BATTLE, DEFENSIVE, BERSERKER }
local IS_STANCE = { [BATTLE] = true, [DEFENSIVE] = true, [BERSERKER] = true }
function ns.WarriorStance(s)
    local kept = ns.OwnCasts and ns.OwnCasts.Kept(s, IS_STANCE, "stance") or nil
    if kept then return kept end
    if tank(s) then return DEFENSIVE end
    return BATTLE
end

-- One rule per stance, only for the one asked for. In no stance: that one.
-- A tank, the stance read and another one: that one too, as before.
-- Nothing kept: Battle Stance in no stance, Defensive Stance for a tank,
-- the same as the two rules before N58.
local function stanceRule(name)
    return { spell = name, kind = "buff",
             reason = "Not in " .. name .. ": the stance for your role, or the one you chose",
             when = function(s)
                 if ns.WarriorStance(s) ~= name then return false end
                 return noForm(s) or (tank(s) and s.formKnown == true and s.form ~= name)
             end }
end

local stance = tag({ stanceRule(BATTLE), stanceRule(DEFENSIVE), stanceRule(BERSERKER) })

local buffs = tag({
    { spell = "Battle Shout", kind = "buff", reason = "Shout missing or running out",
      when = function(s) return needBuff(s, "Battle Shout", 10) end },
})

local opener = tag({
    { spell = "Charge", target = true, reason = "An enemy, out of a fight: charge in",
      when = function(s) return s.hostile == true and outOfFight(s) and inStance(s, BATTLE) end },
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile == true and swingOff(s) end },
})

-- The reactive strikes: only when the game marks them usable.
local reactive = tag({
    { spell = "Execute", target = true, reason = "Execute can be used: use it",
      when = function(s)
          return s.hostile == true and usable(s, "Execute") and (inStance(s, BATTLE) or inStance(s, BERSERKER))
      end },
    { spell = "Overpower", target = true, reason = "Overpower can be used: use it",
      when = function(s) return s.hostile == true and usable(s, "Overpower") and inStance(s, BATTLE) end },
    { spell = "Revenge", target = true, reason = "Revenge can be used: use it",
      when = function(s) return s.hostile == true and usable(s, "Revenge") and inStance(s, DEFENSIVE) end },
})

local single = tag({
    { spell = "Rend", target = true, reason = "Rend is not on the target",
      when = function(s)
          return s.hostile == true and inFight(s) and missingOnTarget(s, "Rend") and s.form ~= BERSERKER
      end },
    { spell = "Sunder Armor", target = true, reason = "Tanking: Sunder Armor",
      when = function(s) return tank(s) and s.hostile == true and inFight(s) end },
    { spell = "Heroic Strike", target = true, reason = "Heroic Strike on the next swing",
      when = function(s) return s.hostile == true and inFight(s) and readOff(s, "Heroic Strike") end },
})

local aoe = tag({
    { spell = "Thunder Clap", reason = "Several enemies",
      when = function(s) return inFight(s) and inStance(s, BATTLE) end },
    { spell = "Demoralizing Shout", reason = "Several enemies, no shout on the target",
      when = function(s) return inFight(s) and missingOnTarget(s, "Demoralizing Shout") end },
    { spell = "Cleave", target = true, reason = "Cleave on the next swing",
      when = function(s) return s.hostile == true and inFight(s) and readOff(s, "Cleave") end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key rows (what each modifier holds), one per stance.
local battleKeys = {
    key = { "Heroic Strike", "Rend" },
    ctrl = { "Overpower", "Execute", "Thunder Clap" },
    shift = { "Charge", "Hamstring" },
    alt = { "Defensive Stance", "Berserker Stance" },
    more = { "Battle Shout", "Demoralizing Shout" },
}
local defensiveKeys = {
    key = { "Sunder Armor", "Revenge" },
    ctrl = { "Shield Bash", "Shield Block", "Taunt" },
    shift = { "Heroic Strike", "Demoralizing Shout" },
    alt = { "Battle Stance", "Berserker Stance" },
    more = { "Battle Shout", "Thunder Clap" },
}
local berserkerKeys = {
    key = { "Heroic Strike", "Execute" },
    ctrl = { "Pummel", "Intercept", "Berserker Rage" },
    shift = { "Whirlwind", "Cleave" },
    alt = { "Battle Stance", "Defensive Stance" },
    more = { "Battle Shout", "Demoralizing Shout" },
}
local noneKeys = {
    key = { "Battle Stance" },
    ctrl = { "Defensive Stance" },
    shift = { "Berserker Stance" },
    alt = { "Battle Shout" },
    more = { "Attack" },
}

-- Spells: the level is a first guess at the trainer level. A row is a fact
-- about the spell, not advice: several rows are spells no rule suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Attack"]             = sp(1,  { "DPS" }),
    ["Battle Stance"]      = sp(1,  { "DPS" }),
    ["Heroic Strike"]      = sp(1,  { "DPS" }, nil, "on the next swing"),
    ["Charge"]             = sp(4,  { "DPS" }, { BATTLE }),
    ["Rend"]               = sp(4,  { "DPS" }),
    ["Thunder Clap"]       = sp(6,  { "DPS" }, { BATTLE }),
    ["Hamstring"]          = sp(8,  { "Control" }),
    ["Battle Shout"]       = sp(1,  { "DPS" }),
    ["Defensive Stance"]   = sp(10, { "Tanking" }, nil, "from a class quest"),
    ["Sunder Armor"]       = sp(10, { "Tanking" }),
    ["Taunt"]              = sp(10, { "Tanking" }, { DEFENSIVE }),
    ["Overpower"]          = sp(12, { "DPS" }, { BATTLE }, "usable after the enemy dodges"),
    ["Shield Bash"]        = sp(12, { "Control" }, { BATTLE, DEFENSIVE }),
    ["Revenge"]            = sp(14, { "Tanking" }, { DEFENSIVE }, "usable after a block, dodge or parry"),
    ["Demoralizing Shout"] = sp(14, { "Survival" }),
    ["Shield Block"]       = sp(16, { "Tanking" }, { DEFENSIVE }),
    ["Cleave"]             = sp(20, { "DPS" }, nil, "on the next swing"),
    ["Execute"]            = sp(24, { "DPS" }, { BATTLE, BERSERKER }, "usable when the enemy is nearly dead"),
    ["Berserker Stance"]   = sp(30, { "DPS" }, nil, "from a class quest"),
    ["Intercept"]          = sp(30, { "Control" }, { BERSERKER }),
    ["Berserker Rage"]     = sp(32, { "Survival" }, { BERSERKER }),
    ["Whirlwind"]          = sp(36, { "DPS" }, { BERSERKER }),
    ["Pummel"]             = sp(38, { "Control" }, { BERSERKER }),
}

local function weights(values)
    return { evidence = GUESS, note = NOTE, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-22",
        method = "Written for lead section 197 on the shape of Classes/Paladin.lua and Classes/Druid.lua, "
            .. "through the shared chooser, key plan, gear weights and trainer list only. Client reads are "
            .. "snapshot fields; nothing added from outside the repository.",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. No guide, database or other addon used.",
    },

    roles = {
        dps  = { name = "Arms / Fury", evidence = GUESS },
        tank = { name = "Protection", evidence = GUESS },
    },

    resources = {
        { name = "Rage", forms = { "none", BATTLE, DEFENSIVE, BERSERKER }, evidence = GUESS },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Battle Shout", seconds = 10, evidence = GUESS },
    },

    lists = {
        default = join(stance, buffs, opener, reactive, single),
        aoe = join(stance, buffs, opener, reactive, aoe, single),
    },

    -- Nothing is cast on the group (Battle Shout reaches it, but is kept for yourself).
    groups = {},
    groupsNone = "A warrior has no buff cast on others: Battle Shout reaches the group but is kept as your own.",

    -- No heal of its own.
    heals = {
        self = {},
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only, each in the stances that allow it.
    interrupts = {
        { spell = "Pummel", forms = { [BERSERKER] = true }, evidence = GUESS },
        { spell = "Shield Bash", forms = { [BATTLE] = true, [DEFENSIVE] = true }, evidence = GUESS },
    },

    -- N52 WARRIOR-1/4 (lead section 233): Berserker Rage breaks a fear,
    -- shown only. The stance is not checked here: outside Berserker Stance
    -- the game answers not usable and the chooser passes it by. The fear
    -- type names (the loss-of-control read) are a first guess.
    breakers = {
        { spell = "Berserker Rage", types = { FEAR = true, FEAR_MECHANIC = true }, evidence = GUESS },
    },

    -- The class removes nothing.
    dispels = {},
    dispelsNone = "A warrior cannot remove a poison, curse, disease or magic from anyone.",

    keys = {
        none = noneKeys,
        [BATTLE] = battleKeys,
        [DEFENSIVE] = defensiveKeys,
        [BERSERKER] = berserkerKeys,
    },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_STRENGTH_SHORT = 1.0, ITEM_MOD_AGILITY_SHORT = 0.6, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.9,
            ITEM_MOD_HASTE_RATING_SHORT = 0.6, ITEM_MOD_MASTERY_RATING_SHORT = 0.6, ITEM_MOD_VERSATILITY = 0.6,
            ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0, RESISTANCE0_NAME = 0.07,
        }),
        tank = weights({
            ITEM_MOD_STAMINA_SHORT = 1.0, RESISTANCE0_NAME = 0.10, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1.2,
            ITEM_MOD_DODGE_RATING_SHORT = 1.0, ITEM_MOD_PARRY_RATING_SHORT = 0.9, ITEM_MOD_BLOCK_RATING_SHORT = 0.6,
            ITEM_MOD_BLOCK_VALUE_SHORT = 0.3, ITEM_MOD_STRENGTH_SHORT = 0.6, ITEM_MOD_AGILITY_SHORT = 0.5,
            ITEM_MOD_HIT_RATING_SHORT = 0.5, ITEM_MOD_VERSATILITY = 0.7, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.6,
        }),
    },

    -- G15, lead section 280: the weapon speed each role likes, and why, for
    -- the speed line on a weapon's tooltip (Gear/WeaponSpeed.lua). "any":
    -- speed does not matter for the role. Not counted in the score.
    weaponSpeed = {
        evidence = GUESS,
        note = "written for lead section 280 from the game's rules as remembered; no outside source;"
            .. " not read from the game",
        dps = { prefer = "slow",
                why = "Mortal Strike, Whirlwind and Overpower hit for weapon damage, so a slow weapon hits harder"
                    .. " for the same rage",
                offhand = { prefer = "fast", why = "more off hand swings bring rage more often" } },
        tank = { prefer = "fast", why = "more swings to turn into Heroic Strike, so threat comes steadily" },
    },

    -- What the class can equip, by item class and subclass ids.
    -- Armor (4): 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield.
    -- Weapons (2): 0/1 axes, 2 bow, 3 gun, 4/5 maces, 6 polearm, 7/8 swords,
    -- 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 20 fishing pole.
    proficiency = {
        evidence = GUESS, note = NOTE,
        [4] = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
        [2] = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
                [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
    },

    spells = spells,

    -- Not authored: see the header.
    talentBuilds = {
        { name = "Arms levelling build", role = "dps", evidence = GUESS, note = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game",
          trees = { "Arms", "Fury", "Protection" },
          order = {
              { "Improved Heroic Strike", 3, why = "Heroic Strike costs less rage." },
              { "Deflection", 2, why = "You parry more, so you take less damage." },
              { "Improved Charge", 2, why = "Charge gives more rage to start the fight." },
              { "Tactical Mastery", 3, why = "You keep rage when you change stance, for Overpower and Hamstring." },
              { "Anger Management", 1, why = "You gain rage slowly even out of a hit." },
              { "Deep Wounds", 3, why = "Your critical hits make the enemy bleed." },
              { "Improved Overpower", 1, why = "Overpower lands more critical hits." },
              { "Two-Handed Weapon Specialization", 5, why = "More damage with the two-handed weapon you level with." },
              { "Impale", 2, why = "Your critical hits with abilities deal more damage." },
              { "Sweeping Strikes", 1, why = "Your next few attacks also hit a second enemy." },
              { "Axe Specialization", 5, why = "More critical hits with an axe." },
              { "Improved Hamstring", 2, why = "Hamstring now and then roots the enemy, so it cannot run off." },
              { "Mortal Strike", 1, why = "A heavy strike that also cuts the healing the enemy takes." },
          },
        },
    },

    options = {
        -- P-SELFBUFF: the self-buff rows (Tests/Rotation/SelfBuffRows.lua):
        -- rows are buff rules in the lists; none do not apply as a row (why);
        -- waits are not suggested until the read named in on is there.
        selfBuffs = {
            rows = { "Battle Shout", "Battle Stance", "Defensive Stance", "Berserker Stance" },
            none = {
                { what = "sharpening stone", why = "the use of an item, not a spell: the weapon enchant reminder (Rotation/Enchant.lua) says when it runs out" },
            },
            waits = {},
        },
        crowdControl = { none = "Intimidating Shout and Hamstring do not hold one chosen second enemy" },
        threatDrop = { none = "no warrior ability drops threat" },
        -- N50 / GAP DRUID-2 (P-SELFBUFF): the known-spell tree. Talent spells,
        -- in order: the first you know names your tree (snapshot.tree,
        -- Rotation/Driver.lua). Which spell is a talent of which tree: a first
        -- guess from the 1.12 talent trees as remembered, not read from the game.
        trees = {
            { spell = "Bloodthirst", tree = "Fury", evidence = GUESS },
            { spell = "Mortal Strike", tree = "Arms", evidence = GUESS },
            { spell = "Shield Slam", tree = "Protection", evidence = GUESS },
            { spell = "Death Wish", tree = "Fury", evidence = GUESS },
            { spell = "Sweeping Strikes", tree = "Arms", evidence = GUESS },
            { spell = "Concussion Blow", tree = "Protection", evidence = GUESS },
            { spell = "Last Stand", tree = "Protection", evidence = GUESS },
            { spell = "Piercing Howl", tree = "Fury", evidence = GUESS },
        },
        -- The strikes that land on the next swing; data only, the driver does
        -- not read it yet.
        nextSwing = { "Heroic Strike", "Cleave" },
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "formKnown", "buffs", "targetDebuffs" },
        -- N58 (lead section 241): the stance you cast is kept for your role
        -- once held 6 s; one swapped for a single ability and back inside
        -- that time is not. `stance <name>` chooses one, `stance auto` goes
        -- back. pick (PC-1): the stance asked for now; a cast of it is not
        -- kept.
        sticky = {
            { prefix = "", only = IS_STANCE, key = "stance", word = "stance", names = STANCE_NAMES,
              window = 6, pick = function(s) return ns.WarriorStance(s) end },
        },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.WARRIOR = pack
if type(ns.Register) == "function" then ns:Register("classPack", "WARRIOR", pack) end
