local _, ns = ...

-- The Warlock class pack (shape: ZFlow/Rotation/Pack.lua, the rows of
-- Classes/Paladin.lua, Classes/Druid.lua and Classes/Hunter.lua). Lead
-- sections 197 and 206. Pure: every rule reads the snapshot it is given
-- (ZFlow/Rotation/Choose.lua lists the fields, the pet among them) and
-- nothing else.
--
-- Scope: damage on your own target, your own armor and your own demon. It
-- suggests only: no pet command, no cast, nothing pressed for you. Nothing
-- here buffs, heals or summons for another player.
--
-- The pet: the shared pet read (the accepted contract, from-zen 03:21Z;
-- R.NoPet, R.PetDead, R.PetUp). Summoning is asked for only when the pet was
-- read, and only out of a fight.
--
-- Evidence. No warlock file existed before this one, and the repository
-- holds no client observations for the class, so nothing is "observed".
-- What the class can equip follows the old Modules/Gear/Score.lua WARLOCK
-- row. Spell names, trainer levels, list order, stat weights and the talent
-- order are a "first guess" written for this pack from general knowledge of
-- the class; each needs a check in the game client. No guide, database or
-- other addon used.
--
-- Accepted gaps, stated (as sections 200 and 203 did for other classes):
--   * soul shards: no shard read exists in the shared system. A summon that
--     needs a shard is refused by the game when there is none (its usable
--     or noPower answer), and that answer is all used here;
--   * channelled spells (Drain Life, Drain Soul, Drain Mana, Health Funnel,
--     Rain of Fire, Hellfire): no read of your own channel, so a suggestion
--     could cut one short. They are listed, not suggested;
--   * Life Tap: it trades your health for mana, and no health amount is
--     read (R.FROM_AMOUNT); listed, not suggested;
--   * the demon's own abilities (Spell Lock, Devour Magic, Sacrifice): pet
--     commands, never sent or suggested;
--   * Fear, Howl of Terror, Death Coil as steps: situational; on the key rows.

local GUESS = "first guess"
local MADE = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game"

local ARMORS = { "Demon Armor", "Demon Skin" }
-- The demon to summon: the first one known, in this order.
local DEMONS = { "Summon Voidwalker", "Summon Imp" }

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
local function hostile(s) return s.hostile == true end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
-- Read as off (section 183): a current map not read is neither on nor off.
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
-- Target debuffs not read: not known, so not missing (section 186).
local function missingOnTarget(s, name)
    if type(s.targetDebuffs) ~= "table" then return false end
    return not s.targetDebuffs[name]
end

local function firstKnown(s, list)
    for _, name in ipairs(list) do
        if knows(s, name) then return name end
    end
    return nil
end

-- Is an armor up? nil when your buffs were not read.
local function armorUp(s)
    if type(s.buffs) ~= "table" then return nil end
    for _, name in ipairs(ARMORS) do
        if s.buffs[name] then return true end
    end
    return false
end

local function wantsArmor(s, name)
    return outOfFight(s) and firstKnown(s, ARMORS) == name and armorUp(s) == false
end

-- No demon out, or a dead one: read, and out of a fight.
local function wantsDemon(s, name)
    if not outOfFight(s) or firstKnown(s, DEMONS) ~= name then return false end
    return ns.Rotation.NoPet(s) == true or ns.Rotation.PetDead(s) == true
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local armor = tag({
    { spell = "Demon Armor", kind = "buff", reason = "No armor is on",
      when = function(s) return wantsArmor(s, "Demon Armor") end },
    { spell = "Demon Skin", kind = "buff", reason = "No armor is on",
      when = function(s) return wantsArmor(s, "Demon Skin") end },
})

local demon = tag({
    { spell = "Summon Voidwalker", kind = "buff", reason = "No demon is out: summon your voidwalker",
      when = function(s) return wantsDemon(s, "Summon Voidwalker") end },
    { spell = "Summon Imp", kind = "buff", reason = "No demon is out: summon your imp",
      when = function(s) return wantsDemon(s, "Summon Imp") end },
})

local dots = tag({
    { spell = "Curse of Agony", target = true, reason = "Curse of Agony is not on your target",
      when = function(s) return hostile(s) and missingOnTarget(s, "Curse of Agony") end },
    { spell = "Corruption", target = true, reason = "Corruption is not on your target",
      when = function(s) return hostile(s) and missingOnTarget(s, "Corruption") end },
    { spell = "Immolate", target = true, reason = "Immolate is not on your target",
      when = function(s) return hostile(s) and missingOnTarget(s, "Immolate") end },
})

local filler = tag({
    { spell = "Shadow Bolt", target = true, reason = "Shadow Bolt", when = hostile },
    -- The wand: last, when nothing above can be cast. Never pressed while it
    -- shoots: that would stop it.
    { spell = "Shoot", target = true, reason = "Nothing else to cast: your wand",
      when = function(s) return hostile(s) and readOff(s, "Shoot") end },
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
    key = { "Shadow Bolt", "Immolate" },
    ctrl = { "Corruption", "Curse of Agony" },
    shift = { "Fear", "Immolate" },
    alt = { "Death Coil", "Howl of Terror", "Fear" },
    more = { "Fear", "Death Coil", "Corruption" },
}

-- Spells: the level is a first guess at the trainer level (not read from a
-- WoW: Forever trainer). No level: a talent. A row is a fact about the
-- spell, not advice: several rows are spells no rule here suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local CHANNEL = "channelled: not suggested (no channel read)"
local spells = {
    ["Shadow Bolt"]       = sp(1,  { "DPS" }),
    ["Demon Skin"]        = sp(1,  { "Survival" }),
    ["Summon Imp"]        = sp(1,  { "DPS" }),
    ["Immolate"]          = sp(1,  { "DPS" }),
    ["Corruption"]        = sp(4,  { "DPS" }),
    ["Curse of Weakness"] = sp(4,  { "Survival" }),
    ["Life Tap"]          = sp(6,  { "Mana" }, nil, "trades health for mana: not suggested (no health read)"),
    ["Curse of Agony"]    = sp(8,  { "DPS" }),
    ["Fear"]              = sp(8,  { "Control" }),
    ["Drain Soul"]        = sp(10, { "Utility" }, nil, CHANNEL),
    ["Summon Voidwalker"] = sp(10, { "Survival" }, { "a soul shard" }),
    ["Health Funnel"]     = sp(12, { "Utility" }, nil, CHANNEL),
    ["Drain Life"]        = sp(14, { "Survival" }, nil, CHANNEL),
    ["Unending Breath"]   = sp(16, { "Utility" }),
    ["Create Healthstone"] = sp(10, { "Survival" }, { "a soul shard" }),
    ["Searing Pain"]      = sp(18, { "DPS" }),
    ["Demon Armor"]       = sp(20, { "Survival" }),
    ["Rain of Fire"]      = sp(20, { "DPS" }, nil, CHANNEL),
    ["Summon Succubus"]   = sp(20, { "DPS" }, { "a soul shard" }),
    ["Drain Mana"]        = sp(24, { "Mana" }, nil, CHANNEL),
    ["Curse of Tongues"]  = sp(26, { "Control" }),
    ["Hellfire"]          = sp(30, { "DPS" }, nil, CHANNEL),
    ["Summon Felhunter"]  = sp(30, { "Control" }, { "a soul shard" }),
    ["Death Coil"]        = sp(42, { "Control" }),
    ["Howl of Terror"]    = sp(40, { "Control" }),
    ["Shoot"]             = sp(nil, { "DPS" }, { "a wand" }),
}

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-23",
        method = "Written for this pack (lead sections 197 and 206) on the shape of Classes/Paladin.lua, "
            .. "Classes/Druid.lua and Classes/Hunter.lua, on the shared pet read. No earlier warlock file "
            .. "existed in the repository; proficiency follows Modules/Gear/Score.lua's WARLOCK row. The list "
            .. "order: armor and a demon out of a fight, then the curse, Corruption and Immolate while they are "
            .. "not on the target, Shadow Bolt, and the wand when nothing else can be cast.",
        facts = "No value here was read from the game and none comes from a list of client observations. Every "
            .. "fact is marked first guess and needs a check in the game client. No guide, database or other "
            .. "addon used.",
    },

    -- One damage role (a first guess at the name).
    roles = {
        dps = { name = "Affliction", evidence = GUESS },
    },

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS },
    },

    -- Kept on yourself: armor (recast with less than this many seconds left).
    maintain = {
        { spell = "Demon Skin", seconds = 30, evidence = GUESS },
    },

    -- No aoe list: the warlock's spells for several enemies are channelled
    -- (Rain of Fire, Hellfire) and not suggested (see the gaps above).
    lists = {
        default = join(armor, demon, dots, filler),
    },

    -- Does not apply: nothing is cast on the group (Unending Breath and the
    -- like on others are for other players).
    groups = {},

    -- Does not apply: the warlock's heals for itself are channelled (Drain
    -- Life) or trade health (Life Tap); Health Funnel heals the demon and
    -- waits on a pet health read (D1: no).
    heals = {
        self = {},
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- Does not apply: the warlock's own interrupt is the felhunter's Spell
    -- Lock, a pet command, never sent or suggested.
    interrupts = {},

    -- Does not apply: no warlock spell breaks a root or a stun on yourself.
    breakers = {},

    -- Does not apply: the warlock cannot remove a curse, poison, disease or
    -- magic from itself (Devour Magic is the felhunter's, a pet command).
    dispels = {},

    keys = { none = keys },

    -- Stat weights: relative numbers, score = sum(stat * weight). Damage only:
    -- spell power and intellect lead (mana, spell crit), stamina to live and to
    -- tap; hit and crit next; the wand's damage a little.
    weights = {
        dps = { evidence = GUESS, note = MADE, values = {
            ITEM_MOD_SPELL_POWER_SHORT = 1.0, ITEM_MOD_INTELLECT_SHORT = 0.9, ITEM_MOD_STAMINA_SHORT = 0.6,
            ITEM_MOD_HIT_RATING_SHORT = 0.8, ITEM_MOD_CRIT_RATING_SHORT = 0.6, ITEM_MOD_HASTE_RATING_SHORT = 0.5,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.4, ITEM_MOD_VERSATILITY = 0.4, ITEM_MOD_SPIRIT_SHORT = 0.3,
            ITEM_MOD_MANA_REGENERATION_SHORT = 0.7, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.5, RESISTANCE0_NAME = 0.02,
        } },
    },

    -- What the class can equip, by item class and subclass ids, following
    -- Modules/Gear/Score.lua. Armor (4): 0 misc, 1 cloth.
    -- Weapons (2): 7 one-handed swords, 10 staves, 15 daggers, 19 wands, 20 fishing poles.
    proficiency = {
        evidence = GUESS, note = "follows Modules/Gear/Score.lua CLASS_PROFICIENCY WARLOCK; authorship unrecorded",
        [4] = { [0] = true, [1] = true },
        [2] = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    },

    spells = spells,

    talentBuilds = {
        { name = "Affliction levelling build", role = "dps", evidence = GUESS, note = MADE,
          trees = { "Affliction", "Demonology", "Destruction" },
          order = {
              { "Improved Corruption", 5 }, { "Improved Curse of Agony", 3 }, { "Suppression", 2 },
              { "Amplify Curse", 1 }, { "Nightfall", 2 }, { "Fel Concentration", 5 }, { "Grim Reach", 2 },
              { "Siphon Life", 1 }, { "Shadow Mastery", 5 },
          } },
    },

    options = {
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "buffs", "targetDebuffs", "pet" },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.WARLOCK = pack
if type(ns.Register) == "function" then ns:Register("classPack", "WARLOCK", pack) end
