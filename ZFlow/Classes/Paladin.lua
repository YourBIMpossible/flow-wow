local _, ns = ...

-- The Paladin class pack (shape: ZFlow/Rotation/Pack.lua, same rows as
-- Classes/Druid.lua). Ported from Classes/Paladin/Rotation.lua, Data.lua and
-- Spells.lua on the zflow branch. Pure: every rule reads the snapshot it is
-- given (ZFlow/Rotation/Choose.lua lists the fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself. Nothing here heals,
-- buffs, cleanses, shields or revives another player.
--
-- Evidence. Nothing in this pack was read from the game by this file, and the
-- repository holds no list of client observations for the Paladin, so nothing
-- is marked "observed". Every spell name, trainer level, list order, timing
-- and stat weight is a "first guess" carried over from the old Paladin files,
-- whose commits name no source: each needs a check in the game client.
--
-- Not ported, on purpose:
--   * anything for other players: Righteous Fury and the tank seal (group
--     play), Blessing of Kings and the group blessings, Lay on Hands,
--     Blessing of Protection, Cleanse and Purify on anyone but yourself;
--   * the seal and the blessing "learned from your own cast" and the commands
--     that set them (they need memory and client events; a pure rule has
--     neither). Here a blessing or a seal you put up yourself is left alone;
--   * Holy Strike, Seal of Fury, Consecration and Blessing of Kings (their
--     rows were taken out of the old spell list as guide-reported);
--   * Judgment, Crusader Strike, Shield of the Righteous and Word of Glory
--     (named in the old lists, with no row in the old spell list);
--   * the advice to use Divine Protection or Divine Shield (the chooser has
--     no step for it; both are on the Alt key row).

local GUESS = "first guess"
local OLD = "carried over from Classes/Paladin on zflow; authorship unrecorded"

-- Any of these up means an aura is on (as a buff, or as the stance shown).
local AURAS = {
    ["Devotion Aura"] = true, ["Retribution Aura"] = true, ["Concentration Aura"] = true,
    ["Shadow Resistance Aura"] = true, ["Frost Resistance Aura"] = true, ["Fire Resistance Aura"] = true,
    ["Sanctity Aura"] = true, ["Crusader Aura"] = true,
}

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
local function current(s, name) return (s.current and s.current[name]) and true or false end
local function fight(s) return (s.hostile or s.inCombat) and true or false end

local function hasAura(s)
    if AURAS[s.form or ""] then return true end
    for name in pairs(s.buffs or {}) do
        if AURAS[name] then return true end
    end
    return false
end

-- The longest time left on a buff whose name starts with the prefix:
-- nil = none up; true = up, time not shown; a number = seconds left.
local function longest(s, prefix)
    local best
    for name, left in pairs(s.buffs or {}) do
        if type(name) == "string" and string.sub(name, 1, #prefix) == prefix and left then
            if left == true or best == true then
                best = true
            elseif type(left) == "number" and (best == nil or left > best) then
                best = left
            end
        end
    end
    return best
end

-- A blessing is wanted out of a fight, with none up or the one up nearly out.
function ns.PaladinWantsBlessing(s)
    if s.inCombat then return false end
    local left = longest(s, "Blessing of ")
    if left == nil then return true end
    return type(left) == "number" and left < 30
end

-- A seal is wanted when none is up; with a fight on or about to start, also
-- when the one up is nearly out (3 s in the fight, 8 s before the pull).
function ns.PaladinWantsSeal(s)
    local left = longest(s, "Seal of ")
    if left == nil then return true end
    if not fight(s) or type(left) ~= "number" then return false end
    return left < (s.inCombat and 3 or 8)
end

local function sealUp(s) return longest(s, "Seal of ") ~= nil end
local function wisdom(s) return s.role == "heal" and knows(s, "Blessing of Wisdom") end
local function command(s) return s.role ~= "heal" and s.role ~= "tank" and knows(s, "Seal of Command") end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local buffs = tag({
    { spell = "Devotion Aura", kind = "buff", reason = "No aura is on",
      when = function(s) return not hasAura(s) end },
    { spell = "Blessing of Wisdom", kind = "buff", reason = "Blessing missing or running out",
      when = function(s) return wisdom(s) and ns.PaladinWantsBlessing(s) end },
    { spell = "Blessing of Might", kind = "buff", reason = "Blessing missing or running out",
      when = function(s) return not wisdom(s) and ns.PaladinWantsBlessing(s) end },
    { spell = "Seal of Command", kind = "buff", reason = "Seal missing or running out",
      when = function(s) return command(s) and ns.PaladinWantsSeal(s) end },
    { spell = "Seal of Righteousness", kind = "buff", reason = "Seal missing or running out",
      when = function(s) return not command(s) and ns.PaladinWantsSeal(s) end },
})

local melee = tag({
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and not current(s, "Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and not current(s, "Auto Attack") end },
})

local execute = tag({
    { spell = "Hammer of Wrath", target = true, reason = "Hammer of Wrath can be cast: use it",
      -- Only when the snapshot says the game lets it be cast now (the old
      -- file asked the client the same way): unknown is not a yes.
      when = function(s)
          local r = s.spells and s.spells["Hammer of Wrath"]
          return (s.hostile and r and r.usable == true) and true or false
      end },
})

local single = tag({
    { spell = "Judgement", target = true, reason = "Your seal is up: judge it",
      when = function(s) return s.hostile and sealUp(s) end },
})

local aoe = tag({
    { spell = "Holy Wrath", reason = "Several enemies",
      when = function(s) return s.inCombat end },
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
    key = { "Judgement", "Seal of Righteousness" },
    ctrl = { "Exorcism", "Hammer of Wrath", "Hammer of Justice" },
    shift = { "Hammer of Justice", "Hammer of Wrath" },
    alt = { "Divine Protection", "Divine Shield", "Hammer of Justice" },
    more = { "Hammer of Wrath", "Hammer of Justice", "Divine Protection" },
}

-- Spells: the level is the level the old file gave for the trainer (a first
-- guess: it names no source and was not read from a WoW: Forever trainer).
-- No level: the old files gave none. A row is a fact about the spell, not
-- advice: several rows are spells no rule here suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Holy Light"]            = sp(1,  { "Healing" }),
    ["Seal of Righteousness"] = sp(1,  { "DPS" }),
    ["Devotion Aura"]         = sp(1,  { "Survival" }),
    ["Blessing of Might"]     = sp(4,  { "DPS" }),
    ["Judgement"]             = sp(4,  { "DPS" }, nil, "whether it uses up the seal was never checked in the game"),
    ["Divine Protection"]     = sp(6,  { "Survival" }),
    ["Seal of the Crusader"]  = sp(6,  { "DPS" }),
    ["Hammer of Justice"]     = sp(8,  { "Control" }),
    ["Purify"]                = sp(8,  { "Utility" }),
    ["Lay on Hands"]          = sp(10, { "Healing" }),
    ["Blessing of Protection"] = sp(10, { "Survival" }),
    ["Redemption"]            = sp(12, { "Utility" }, nil, "the old file says: from a class quest"),
    ["Blessing of Wisdom"]    = sp(14, { "Mana" }),
    ["Retribution Aura"]      = sp(16, { "DPS" }),
    ["Righteous Fury"]        = sp(16, { "Tanking" }),
    ["Blessing of Freedom"]   = sp(18, { "Utility" }),
    ["Exorcism"]              = sp(20, { "DPS" }),
    ["Flash of Light"]        = sp(20, { "Healing" }),
    ["Seal of Justice"]       = sp(22, { "Control" }),
    ["Concentration Aura"]    = sp(22, { "Utility" }),
    ["Turn Undead"]           = sp(24, { "Control" }),
    ["Blessing of Salvation"] = sp(26, { "Utility" }),
    ["Seal of Light"]         = sp(30, { "Healing" }),
    ["Divine Intervention"]   = sp(30, { "Utility" }),
    ["Divine Shield"]         = sp(34, { "Survival" }),
    ["Seal of Wisdom"]        = sp(38, { "Mana" }),
    ["Summon Warhorse"]       = sp(40, { "Travel" }),
    ["Cleanse"]               = sp(42, { "Utility" }),
    ["Hammer of Wrath"]       = sp(44, { "DPS" }),
    ["Holy Wrath"]            = sp(50, { "DPS" }),
    ["Seal of Command"]       = sp(nil, { "DPS" }, nil, "the old file calls it a Retribution talent"),
    ["Attack"]                = sp(nil, { "DPS" }),
    ["Auto Attack"]           = sp(nil, { "DPS" }),
}

local function weights(values)
    return { evidence = GUESS, note = OLD, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-21",
        method = "Ported from Classes/Paladin/Rotation.lua, Data.lua and Spells.lua on the zflow branch "
            .. "(tag zflow-cp1), keeping damage on your own target and care for yourself only. Client reads "
            .. "replaced by snapshot fields; nothing added from outside the repository.",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. No guide, database or other addon used.",
    },

    roles = {
        dps  = { name = "Retribution", evidence = GUESS },
        heal = { name = "Holy", evidence = GUESS },
        tank = { name = "Protection", evidence = GUESS },
    },

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Blessing of Might", seconds = 30, evidence = GUESS },
        { spell = "Seal of Righteousness", seconds = 3, evidence = GUESS },
    },

    lists = {
        default = join(buffs, melee, execute, single),
        aoe = join(buffs, melee, aoe, execute, single),
    },

    -- Nothing is cast on the group.
    groups = {},

    heals = {
        self = { "Flash of Light", "Holy Light" },
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only: a stun, used when it starts a cast.
    interrupts = {
        { spell = "Hammer of Justice", evidence = GUESS },
    },

    breakers = {},

    -- On yourself, out of a fight.
    dispels = {
        { spell = "Cleanse", types = { Poison = true, Disease = true, Magic = true }, evidence = GUESS },
        { spell = "Purify", types = { Poison = true, Disease = true }, evidence = GUESS },
    },

    keys = { none = keys },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_STRENGTH_SHORT = 1.0, ITEM_MOD_AGILITY_SHORT = 0.6, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_INTELLECT_SHORT = 0.2, ITEM_MOD_SPIRIT_SHORT = 0.1, ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.9, ITEM_MOD_HASTE_RATING_SHORT = 0.6,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.6, ITEM_MOD_VERSATILITY = 0.6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0,
            RESISTANCE0_NAME = 0.07,
        }),
        heal = weights({
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9, ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5, ITEM_MOD_SPIRIT_SHORT = 0.35, ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.6, ITEM_MOD_HASTE_RATING_SHORT = 0.7, ITEM_MOD_MASTERY_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.5, ITEM_MOD_STRENGTH_SHORT = 0.05, RESISTANCE0_NAME = 0.07,
        }),
        tank = weights({
            ITEM_MOD_STAMINA_SHORT = 1.0, RESISTANCE0_NAME = 0.10, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1.2,
            ITEM_MOD_DODGE_RATING_SHORT = 1.0, ITEM_MOD_PARRY_RATING_SHORT = 0.9, ITEM_MOD_BLOCK_RATING_SHORT = 0.6,
            ITEM_MOD_BLOCK_VALUE_SHORT = 0.3, ITEM_MOD_STRENGTH_SHORT = 0.5, ITEM_MOD_AGILITY_SHORT = 0.4,
            ITEM_MOD_INTELLECT_SHORT = 0.25, ITEM_MOD_SPELL_POWER_SHORT = 0.3, ITEM_MOD_HIT_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.7, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.6,
        }),
    },

    -- What the class can equip, by item class and subclass ids, as the old
    -- file gave them. Armor (4): 0, 1, 2, 3, 4, 6, 7. Weapons (2): 0, 1, 4, 5, 6, 7, 8, 20.
    proficiency = {
        evidence = GUESS, note = OLD,
        [4] = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true },
        [2] = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [20] = true },
    },

    spells = spells,

    -- The old talent plan is empty.
    talentBuilds = {},

    options = {},
}

ns.Packs = ns.Packs or {}
ns.Packs.PALADIN = pack
if type(ns.Register) == "function" then ns:Register("classPack", "PALADIN", pack) end
