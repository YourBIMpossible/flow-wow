local _, ns = ...

-- The Druid class pack (shape: ZFlow/Rotation/Pack.lua). Ported from
-- Classes/Druid/Rotation.lua, Data.lua and Spells.lua on the zflow branch.
-- Pure: every rule reads the snapshot it is given (ZFlow/Rotation/Choose.lua
-- lists the fields) and nothing else.
--
-- Evidence. Nothing in this pack was read from the game by this file, so
-- nothing is marked "observed". Two classes are used:
--   "first guess"  carried over from the old Druid files, whose commits name
--                  no source (spell names, trainer levels, list order, stat
--                  weights, talent order): unread, to be replaced by what the
--                  game shows.
--   "authored"     a model written by Flow, with its provenance note beside it.
--
-- Not ported, on purpose:
--   * removing poisons or curses from other players (the old dispel list was
--     used on the group; here it is for yourself only);
--   * the class-quest ids and quest names for Bear Form and Aquatic Form
--     (their source is unrecorded);
--   * the per-talent "why" lines (they stay in Classes/Druid/Data.lua).

local GUESS = "first guess"
local OLD = "carried over from Classes/Druid on zflow; authorship unrecorded"

local BEAR = { ["Bear Form"] = true, ["Dire Bear Form"] = true }

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
local function inCat(s) return s.form == "Cat Form" end
local function inBear(s) return BEAR[s.form or ""] == true end
local function caster(s) return s.form == nil or s.form == "Moonkin Form" end
local function inAnimal(s) return inCat(s) or inBear(s) end
local function stealthed(s) return s.stealthed == true end
-- Read as not stealthed. A stealth nobody read (nil) is neither: Prowl and
-- the swing wait for the reader's no.
local function unstealthed(s) return s.stealthed == false end
-- Combo points are a hidden amount here: a finisher waits for the reader's say-so.
local function finisher(s) return s.finisherReady == true end
-- The game refuses the spell for lack of power (read, not guessed).
local function lacksPower(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known and r.noPower == true) and true or false
end
local function current(s, name) return (s.current and s.current[name]) and true or false end
-- Missing, or with less than secs left (a buff the snapshot gives as true has time left).
local function needBuff(s, name, secs)
    local left = s.buffs and s.buffs[name]
    if not left then return true end
    return type(left) == "number" and left < secs
end
local function missingOnTarget(s, name)
    return not (s.targetDebuffs and s.targetDebuffs[name])
end
-- A fight on, or not known (ns.Rotation.InFight); known to be out of one.
local function inFight(s) return ns.Rotation.InFight(s) end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
local function fight(s) return (s.hostile == true or inFight(s)) and true or false end

-- A tank, a fight to take (enemy targeted or in combat), not in Bear yet.
function ns.DruidWantsBear(role, fightNow, bear)
    return (role == "tank" and fightNow and not bear) and true or false
end

local CAT_PROVENANCE = "Authored by Flow, 2026-11-21 (commit f672471). No guide, database or other addon used. "
    .. "Facts used: the role Flow plays you as; the form the game reports; the tree holding most of your talent points; "
    .. "that Flow's cat list needs Cat Form and its caster list needs no form or Moonkin Form. "
    .. "Method: the mirror of the Bear Form rule for a tank. A dps druid who knows Cat Form is given the cat list, so with "
    .. "a fight to take Flow asks for the form that list needs. Left alone: any form you are already in, and a druid "
    .. "whose talents are mostly Balance. Talents unread or tied: not Balance. A recommendation, not a game fact."

-- dps, a fight to take, in no form at all, and not a Balance build.
-- form: nil = no form; tree: nil = unknown.
function ns.DruidWantsCat(role, fightNow, form, tree)
    return (role == "dps" and fightNow and form == nil and tree ~= "Balance") and true or false
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local buffs = tag({
    { spell = "Mark of the Wild", kind = "buff", reason = "Mark of the Wild missing or running out",
      when = function(s) return outOfFight(s) and caster(s) and needBuff(s, "Mark of the Wild", 60) end },
    { spell = "Thorns", kind = "buff", reason = "Thorns missing or running out",
      when = function(s) return outOfFight(s) and caster(s) and needBuff(s, "Thorns", 30) end },
    { spell = "Dire Bear Form", kind = "buff", reason = "Tanking: Bear Form",
      when = function(s) return ns.DruidWantsBear(s.role, fight(s), inBear(s)) end },
    { spell = "Bear Form", kind = "buff", reason = "Tanking: Bear Form",
      when = function(s)
          return ns.DruidWantsBear(s.role, fight(s), inBear(s)) and not knows(s, "Dire Bear Form")
      end },
    { spell = "Cat Form", kind = "buff", reason = "Suggested for DPS: Cat Form",
      evidence = "authored", provenance = CAT_PROVENANCE,
      when = function(s) return ns.DruidWantsCat(s.role, fight(s), s.form, s.tree) end },
    { spell = "Prowl", kind = "buff", reason = "Prowl before you pull: your key then holds your opener from stealth",
      when = function(s) return outOfFight(s) and s.hostile and inCat(s) and unstealthed(s) end },
})

local melee = tag({
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and inAnimal(s) and unstealthed(s) and not current(s, "Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and inAnimal(s) and unstealthed(s) and not current(s, "Auto Attack") end },
})

local cat = tag({
    { spell = "Ravage", target = true, reason = "Open from stealth (from behind the mob)",
      when = function(s) return s.hostile and inCat(s) and stealthed(s) end },
    { spell = "Pounce", target = true, reason = "Open from stealth (it stuns)",
      when = function(s) return s.hostile and inCat(s) and stealthed(s) end },
    { spell = "Shred", target = true, reason = "Open from stealth (from behind the mob)",
      when = function(s) return s.hostile and inCat(s) and stealthed(s) end },
    { spell = "Ferocious Bite", target = true, reason = "Spend your combo points",
      when = function(s) return s.hostile and inCat(s) and finisher(s) end },
    { spell = "Rip", target = true, reason = "Spend combo points (bleed)",
      when = function(s)
          return s.hostile and inCat(s) and finisher(s) and not knows(s, "Ferocious Bite")
              and missingOnTarget(s, "Rip")
      end },
    { spell = "Rake", target = true, reason = "Rake bleed missing",
      when = function(s) return s.hostile and inCat(s) and missingOnTarget(s, "Rake") end },
    { spell = "Claw", target = true, reason = "Build combo points",
      when = function(s) return s.hostile and inCat(s) end },
})

local bear = tag({
    { spell = "Demoralizing Roar", reason = "Weaken what is hitting you",
      when = function(s) return inFight(s) and s.hostile and inBear(s) and missingOnTarget(s, "Demoralizing Roar") end },
    { spell = "Maul", target = true, reason = "Maul on your next swing",
      when = function(s) return s.hostile and inBear(s) and not current(s, "Maul") end },
})

local bearAoe = tag({
    { spell = "Swipe", target = true, reason = "Several enemies",
      when = function(s) return s.hostile and inBear(s) end },
})

local roots = tag({
    { spell = "Nature's Grasp", kind = "buff", reason = "It is hitting you: Nature's Grasp may root it on its next hit",
      when = function(s)
          return inFight(s) and s.hostile and caster(s) and s.targetMelee and s.targetOnYou and s.hittingYou
              and missingOnTarget(s, "Entangling Roots") and needBuff(s, "Nature's Grasp", 0)
      end },
    { spell = "Entangling Roots", target = true, reason = "Root it before it reaches you, then cast",
      when = function(s)
          return s.hostile and caster(s) and s.targetMelee and missingOnTarget(s, "Entangling Roots")
              and (outOfFight(s) or s.targetOnYou == true)
      end },
})

local casterDamage = tag({
    { spell = "Moonfire", target = true, reason = "Moonfire missing on the target",
      when = function(s) return s.hostile and caster(s) and missingOnTarget(s, "Moonfire") end },
    { spell = "Wrath", target = true, reason = "Wrath",
      when = function(s) return s.hostile and caster(s) end },
    { spell = "Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(s) return s.hostile and caster(s) and lacksPower(s, "Wrath") and not current(s, "Attack") end },
    { spell = "Auto Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(s) return s.hostile and caster(s) and lacksPower(s, "Wrath") and not current(s, "Auto Attack") end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key rows per form (what each modifier holds).
local casterKeys = { key = "Wrath", ctrl = { "Moonfire", "Entangling Roots" }, shift = { "Entangling Roots", "Nature's Grasp" },
                     alt = { "Nature's Grasp", "War Stomp" }, more = { "Entangling Roots", "Nature's Grasp", "War Stomp" } }
local bearKeys = { key = "Maul", ctrl = { "Swipe", "Demoralizing Roar" }, shift = { "Bash", "Growl", "Demoralizing Roar" },
                   alt = { "Enrage", "Growl" }, more = { "Demoralizing Roar", "Growl", "Enrage" } }
local catKeys = { key = "Claw", ctrl = { "Ferocious Bite", "Rip", "Rake" }, shift = { "Rake", "Rip" },
                  alt = { "Tiger's Fury", "Dash" }, more = { "Rip", "Prowl" } }
local prowlKeys = { form = "Cat Form", key = { "Ravage", "Pounce", "Shred", "Rake", "Claw" },
                    ctrl = catKeys.ctrl, shift = catKeys.shift, alt = catKeys.alt, more = catKeys.more }

-- Spells: the level is the level the old file gave for the trainer (a first
-- guess: it names no source and was not read from a WoW: Forever trainer).
-- No level: the old files gave none.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Wrath"]                 = sp(1,  { "DPS" }),
    ["Healing Touch"]         = sp(1,  { "Healing", "Survival" }),
    ["Mark of the Wild"]      = sp(1,  { "Stats" }),
    ["Moonfire"]              = sp(4,  { "DPS" }),
    ["Rejuvenation"]          = sp(4,  { "Healing", "Survival" }),
    ["Thorns"]                = sp(6,  { "DPS", "Survival" }),
    ["Entangling Roots"]      = sp(8,  { "Control" }),
    ["Bear Form"]             = sp(10, { "Survival", "Threat" }, nil, "class quest"),
    ["Demoralizing Roar"]     = sp(10, { "Survival" }, "Bear Form"),
    ["Growl"]                 = sp(10, { "Threat" }, "Bear Form"),
    ["Maul"]                  = sp(10, { "DPS", "Threat" }, "Bear Form"),
    ["Nature's Grasp"]        = sp(10, { "Control" }),
    ["Regrowth"]              = sp(12, { "Healing" }),
    ["Enrage"]                = sp(12, { "Threat" }, "Bear Form"),
    ["Bash"]                  = sp(14, { "Control" }, "Bear Form"),
    ["Cure Poison"]           = sp(14, { "Survival" }),
    ["Swipe"]                 = sp(16, { "DPS", "Threat" }, "Bear Form"),
    ["Aquatic Form"]          = sp(16, { "Travel" }, nil, "class quest"),
    ["Faerie Fire"]           = sp(18, { "DPS" }),
    ["Hibernate"]             = sp(18, { "Control" }),
    ["Cat Form"]              = sp(20, { "DPS" }),
    ["Claw"]                  = sp(20, { "DPS" }, "Cat Form"),
    ["Rake"]                  = sp(20, { "DPS" }, "Cat Form"),
    ["Prowl"]                 = sp(20, { "Control" }, "Cat Form"),
    ["Starfire"]              = sp(20, { "DPS" }),
    ["Rebirth"]               = sp(20, { "Group" }),
    ["Shred"]                 = sp(22, { "DPS" }, "Cat Form"),
    ["Rip"]                   = sp(24, { "DPS" }, "Cat Form"),
    ["Tiger's Fury"]          = sp(24, { "DPS" }, "Cat Form"),
    ["Remove Curse"]          = sp(24, { "Survival" }),
    ["Dash"]                  = sp(26, { "Travel" }, "Cat Form"),
    ["Travel Form"]           = sp(30, { "Travel" }),
    ["Tranquility"]           = sp(30, { "Healing", "Group" }),
    ["Ferocious Bite"]        = sp(32, { "DPS" }, "Cat Form"),
    ["Pounce"]                = sp(36, { "DPS", "Control" }, "Cat Form"),
    ["Frenzied Regeneration"] = sp(36, { "Survival" }, "Bear Form"),
    ["Dire Bear Form"]        = sp(40, { "Survival", "Threat" }, "Bear Form"),
    ["Innervate"]             = sp(40, { "Mana" }),
    ["Hurricane"]             = sp(40, { "DPS" }),
    -- Named by the lists or key rows, with no trainer row in the old file.
    ["Ravage"]                = sp(nil, { "DPS" }, "Cat Form"),
    ["Abolish Poison"]        = sp(nil, { "Survival" }),
    ["Attack"]                = sp(nil, { "DPS" }, nil, "the swing; the client names it Attack or Auto Attack"),
    ["Auto Attack"]           = sp(nil, { "DPS" }, nil, "the swing; the client names it Attack or Auto Attack"),
    ["War Stomp"]             = sp(nil, { "Control" }, nil, "a racial (tauren), not a class spell"),
}

local function weights(values)
    return { evidence = GUESS, note = OLD, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-21",
        method = "Ported rule for rule from Classes/Druid/Rotation.lua, Data.lua and Spells.lua on the zflow branch "
            .. "(tag zflow-cp0). Client reads replaced by snapshot fields; nothing added from outside the repository.",
        facts = "No value here was read from the game by this file. Carried-over values are marked first guess; "
            .. "the Cat Form rule is an authored model with its own note. No guide, database or other addon used.",
    },

    roles = {
        dps  = { name = "Feral (Cat)", evidence = GUESS },
        heal = { name = "Restoration", evidence = GUESS },
        tank = { name = "Feral (Bear)", evidence = GUESS },
    },

    resources = {
        { name = "Mana", forms = { "none", "Moonkin Form" }, evidence = GUESS },
        { name = "Rage", forms = { "Bear Form", "Dire Bear Form" }, evidence = GUESS },
        { name = "Energy", forms = { "Cat Form" }, evidence = GUESS },
        { name = "Combo Points", forms = { "Cat Form" }, evidence = GUESS },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Mark of the Wild", seconds = 60, evidence = GUESS },
        { spell = "Thorns", seconds = 30, evidence = GUESS },
    },

    lists = {
        default = join(buffs, melee, cat, bear, roots, casterDamage),
        aoe = join(buffs, melee, cat, bearAoe, bear, casterDamage),   -- (several mobs: no roots, they keep coming)
    },

    -- Out of a fight only; the chooser in this batch does not use them.
    groups = {
        { spell = "Mark of the Wild", minutes = 30, rebuff = 60, evidence = GUESS },
        { spell = "Thorns", minutes = 10, rebuff = 30, evidence = GUESS },
    },

    -- Read on another player's tooltip (Rotation/GroupTip.lua): text only,
    -- nothing is cast. aura: the buffs that count as this one. who: "all",
    -- or the kinds and classes it is worth having on. First guesses.
    groupBuffs = {
        { spell = "Mark of the Wild", aura = { "Mark of the Wild", "Gift of the Wild" }, who = "all", evidence = GUESS },
        { spell = "Thorns", who = { "tank", "WARRIOR" }, evidence = GUESS },
    },

    heals = {
        self = { "Regrowth", "Healing Touch", "Rejuvenation" },
        hots = { "Rejuvenation" },
        hotDuration = { Rejuvenation = 12 },
        lingers = { Regrowth = 21 },
        evidence = GUESS,
    },

    interrupts = {
        { spell = "Bash", evidence = GUESS },   -- Bear Form: a stun in melee reach
    },

    -- Changing form frees you from roots (not into the form you are in).
    breakers = {
        { spell = "Travel Form", types = { ROOT = true }, form = true, evidence = GUESS },
        { spell = "Cat Form", types = { ROOT = true }, form = true, evidence = GUESS },
        { spell = "Bear Form", types = { ROOT = true }, form = true, evidence = GUESS },
        { spell = "Dire Bear Form", types = { ROOT = true }, form = true, evidence = GUESS },
    },

    -- On yourself, out of a fight, in caster form.
    dispels = {
        { spell = "Remove Curse", types = { Curse = true }, when = caster, evidence = GUESS },
        { spell = "Abolish Poison", types = { Poison = true }, when = caster, evidence = GUESS },
        { spell = "Cure Poison", types = { Poison = true }, when = caster, evidence = GUESS },
    },

    keys = {
        none = casterKeys, ["Moonkin Form"] = casterKeys,
        ["Bear Form"] = bearKeys, ["Dire Bear Form"] = bearKeys,
        ["Cat Form"] = catKeys, stealth = prowlKeys,
    },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_AGILITY_SHORT = 1.0, ITEM_MOD_STRENGTH_SHORT = 0.9, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_INTELLECT_SHORT = 0.3, ITEM_MOD_SPIRIT_SHORT = 0.15, ITEM_MOD_ATTACK_POWER_SHORT = 0.45,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.8, ITEM_MOD_HASTE_RATING_SHORT = 0.5,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.5, ITEM_MOD_VERSATILITY = 0.5, ITEM_MOD_SPELL_POWER_SHORT = 0.25,
            RESISTANCE0_NAME = 0.05,
        }),
        heal = weights({
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9, ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5, ITEM_MOD_SPIRIT_SHORT = 0.45, ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.5, ITEM_MOD_HASTE_RATING_SHORT = 0.7, ITEM_MOD_MASTERY_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.5, RESISTANCE0_NAME = 0.05,
        }),
        tank = weights({
            ITEM_MOD_STAMINA_SHORT = 1.0, RESISTANCE0_NAME = 0.12, ITEM_MOD_AGILITY_SHORT = 0.7,
            ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1.0, ITEM_MOD_DODGE_RATING_SHORT = 1.0, ITEM_MOD_STRENGTH_SHORT = 0.5,
            ITEM_MOD_HIT_RATING_SHORT = 0.5, ITEM_MOD_ATTACK_POWER_SHORT = 0.25, ITEM_MOD_INTELLECT_SHORT = 0.15,
            ITEM_MOD_VERSATILITY = 0.7,
        }),
    },

    -- What the class can equip, by item class and subclass ids.
    -- Armor (4): 0 misc, 1 cloth, 2 leather, 8 idol.
    -- Weapons (2): 4/5 maces, 6 polearm, 10 staff, 13 fist, 15 dagger, 20 fishing pole.
    proficiency = {
        evidence = GUESS, note = OLD,
        [4] = { [0] = true, [1] = true, [2] = true, [8] = true },
        [2] = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true, [20] = true },
    },

    spells = spells,

    talentBuilds = {
        { name = "Feral (Cat) levelling build", role = "dps", alsoFor = { "tank" },
          evidence = GUESS, note = OLD,
          trees = { "Balance", "Feral", "Restoration" },
          order = {
              { "Improved Wrath", 5 }, { "Ferocity", 5 }, { "Feral Swiftness", 2 }, { "Thick Hide", 3 },
              { "Sharpened Claws", 2 }, { "Savage Fury", 2 }, { "Feral Charge", 1 }, { "Blood Frenzy", 2 },
              { "Predatory Strikes", 3 }, { "Leader of the Pack", 1 }, { "Shredding Attacks", 3 },
              { "Predatory Discipline", 1 }, { "Rend and Tear", 5 }, { "Primal Bite", 1 }, { "Shifting Power", 1 },
              { "Heart of the Wild", 5 }, { "Furor", 5 }, { "Natural Instinct", 2 }, { "Lacerate", 1 },
              { "Brutal Impact", 1 },
          } },
    },

    options = {
        shapeshifts = true,
        nextSwing = { "Maul" },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.DRUID = pack
if type(ns.Register) == "function" then ns:Register("classPack", "DRUID", pack) end
