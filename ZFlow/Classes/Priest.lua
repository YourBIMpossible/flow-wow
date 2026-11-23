local _, ns = ...

-- The Priest class pack (shape: ZFlow/Rotation/Pack.lua, same rows as
-- Classes/Druid.lua and Classes/Paladin.lua). Pure: every rule reads the
-- snapshot it is given (ZFlow/Rotation/Choose.lua lists the fields) and
-- nothing else.
--
-- Scope: damage on your own target and care for yourself. Nothing here
-- heals, buffs, shields, cleanses or revives another player.
--
-- Section 197. The old code has no Priest class module, so the spell rows,
-- lists, keys, weights and roles below were written for this pack. From the
-- old shared tables on zflow it keeps: what the class can equip
-- (Modules/Gear/Score.lua), the resource (a Priest is not in the old no-mana
-- list, Modules/Rotation/BuffItems.lua), the kind of fighter, "caster"
-- (Modules/Rotation/Engine.lua), and the reagents kept in the bags
-- (Modules/Items/Disposition.lua).
--
-- Evidence. Nothing in this pack was read from the game, and the repository
-- holds no list of client observations for the Priest, so nothing is marked
-- "observed". Every spell name, trainer level, list order, time and stat
-- weight is a "first guess" written without a guide, a database or another
-- addon: each needs a check in the game client.
--
-- Not in this pack yet (tasks):
--   * Resurrection, and the heals, Fortitude, Shield and Dispel Magic on
--     anyone but yourself: needs a party member read and a chooser step for
--     other players (the pack holds nothing for them yet);
--   * Power Word: Shield in the list: the shield leaves Weakened Soul on you,
--     and no read gives your own debuffs by name, so "can it go on again"
--     cannot be told. It is on the Alt key row, for you to press;
--   * an aoe list: Holy Nova is a talent and hits only what is near you,
--     and no read says how many enemies are near;
--   * Smite or the wand chosen by mana: the client hides power amounts from
--     addon code (R.FROM_AMOUNT in Rotation/Snapshot.lua), so the list
--     cannot say "wand now to save mana". Smite comes before the wand, and
--     is not suggested while the wand is already shooting;
--   * Fade, Mind Soothe, Shackle Undead, Mind Control and Levitate: no step
--     of the chooser uses them yet (Fade is on the Alt key row);
--   * the food choice for a spirit healer: not carried over yet from the
--     old BuffItems.lua.

local GUESS = "first guess"
local OLD = "carried over from the old shared tables on zflow; authorship unrecorded"

local function knows(s, name) return ns.Rotation.Knows(s, name) end
-- Read as off: true only when the current map was read and says false.
-- Not read (nil map or no answer for the spell) is not "off" (section 183).
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
local function readOn(s, name) return type(s.current) == "table" and s.current[name] == true end
-- Buffs read at all (an empty map is read: none up).
local function buffsRead(s) return type(s.buffs) == "table" end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
local function shadow(s) return s.form == "Shadowform" end

-- The time left on a buff: nil = not up; true = up, time not shown; a number.
local function left(s, name)
    local v = s.buffs and s.buffs[name]
    if v == true or type(v) == "number" then return v end
    return nil
end

-- A buff of yours is wanted when the buffs were read and it is not up, or it
-- has fewer than `seconds` left. Not read: not wanted (section 183).
local function wants(s, name, seconds)
    if not buffsRead(s) then return false end
    local l = left(s, name)
    if l == nil then return true end
    return type(l) == "number" and l < seconds
end

-- Your own Shadow Word: Pain is on the target: true, false, or nil when your
-- debuffs on the target were not read.
local function painOn(s)
    if type(s.targetDebuffs) ~= "table" then return nil end
    return s.targetDebuffs["Shadow Word: Pain"] ~= nil and s.targetDebuffs["Shadow Word: Pain"] ~= false
end

-- Seconds left below which a buff is put up again (maintain rows below).
local FORT, INNER = 60, 30

-- Shadowform is wanted for a dps priest who knows it, with the form read and
-- not Shadowform. Form not read: not wanted (it cannot be told whether you
-- are in it).
local function wantsShadowform(s)
    return s.role == "dps" and knows(s, "Shadowform") and s.formKnown == true and not shadow(s)
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local buffs = tag({
    { spell = "Shadowform", kind = "buff", reason = "Damage role: Shadowform",
      when = function(s) return wantsShadowform(s) end },
    { spell = "Power Word: Fortitude", kind = "buff", reason = "Fortitude missing or running out",
      when = function(s) return outOfFight(s) and wants(s, "Power Word: Fortitude", FORT) end },
    { spell = "Inner Fire", kind = "buff", reason = "Inner Fire missing or running out",
      when = function(s)
          -- In a fight (or not known): only when it is not up at all.
          if outOfFight(s) then return wants(s, "Inner Fire", INNER) end
          return buffsRead(s) and left(s, "Inner Fire") == nil
      end },
})

local damage = tag({
    { spell = "Holy Fire", target = true, reason = "Open with Holy Fire",
      when = function(s) return s.hostile and outOfFight(s) and not shadow(s) end },
    { spell = "Shadow Word: Pain", target = true, reason = "Your Shadow Word: Pain is not on the target",
      when = function(s) return s.hostile and painOn(s) == false end },
    { spell = "Mind Blast", target = true, reason = "Mind Blast is ready",
      when = function(s) return s.hostile and true or false end },
    { spell = "Mind Flay", target = true, reason = "Mind Flay",
      when = function(s) return s.hostile and not readOn(s, "Shoot") end },
    { spell = "Smite", target = true, reason = "Smite",
      when = function(s) return s.hostile and not shadow(s) and not readOn(s, "Shoot") end },
    { spell = "Shoot", target = true, reason = "Start your wand",
      when = function(s) return s.hostile and readOff(s, "Shoot") end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key rows (what each modifier holds): no form, and Shadowform.
local casterKeys = {
    key = { "Smite", "Mind Blast", "Shadow Word: Pain" },
    ctrl = { "Shadow Word: Pain", "Holy Fire", "Mind Blast" },
    shift = { "Psychic Scream", "Silence" },
    alt = { "Power Word: Shield", "Fade", "Renew" },
    more = { "Flash Heal", "Lesser Heal", "Heal" },
}
local shadowKeys = {
    key = { "Mind Flay", "Mind Blast", "Shadow Word: Pain" },
    ctrl = { "Shadow Word: Pain", "Mind Blast" },
    shift = { "Psychic Scream", "Silence" },
    alt = { "Power Word: Shield", "Fade" },
    more = { "Mind Blast", "Shadow Word: Pain" },
}

-- Spells: the level is the trainer level as first guessed here (no source;
-- not read from a WoW: Forever trainer). No level: a talent, as first
-- guessed. A row is a fact about the spell, not advice.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Smite"]                 = sp(1,  { "DPS" }),
    ["Lesser Heal"]           = sp(1,  { "Healing" }),
    ["Power Word: Fortitude"] = sp(1,  { "Survival" }),
    ["Shadow Word: Pain"]     = sp(4,  { "DPS" }),
    ["Power Word: Shield"]    = sp(6,  { "Survival" }),
    ["Renew"]                 = sp(8,  { "Healing" }),
    ["Fade"]                  = sp(8,  { "Survival" }),
    ["Mind Blast"]            = sp(10, { "DPS" }),
    ["Inner Fire"]            = sp(12, { "Survival" }),
    ["Psychic Scream"]        = sp(14, { "Control" }),
    ["Cure Disease"]          = sp(14, { "Utility" }),
    ["Heal"]                  = sp(16, { "Healing" }),
    ["Dispel Magic"]          = sp(18, { "Utility" }),
    ["Flash Heal"]            = sp(20, { "Healing" }),
    ["Holy Fire"]             = sp(20, { "DPS" }),
    ["Abolish Disease"]       = sp(32, { "Utility" }),
    ["Greater Heal"]          = sp(40, { "Healing" }),
    ["Mind Flay"]             = sp(nil, { "DPS" }, nil, "a Shadow talent"),
    ["Silence"]               = sp(nil, { "Control" }, nil, "a Shadow talent"),
    ["Shadowform"]            = sp(nil, { "DPS" }, nil, "a Shadow talent"),
    ["Shoot"]                 = sp(nil, { "DPS" }, nil, "needs a wand in the ranged slot"),
}

local function weights(values)
    return { evidence = GUESS, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-22",
        method = "Section 197: spell rows, lists, keys, weights and roles written for this pack as first guesses, "
            .. "without a guide, database or other addon; what the class can equip, the resource, the kind and "
            .. "the reagents kept from the old shared tables on the zflow branch (Modules/Gear/Score.lua, "
            .. "Modules/Rotation/BuffItems.lua, Modules/Rotation/Engine.lua, Modules/Items/Disposition.lua).",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. Nothing copied from proprietary data.",
    },

    roles = {
        dps  = { name = "Shadow", evidence = GUESS },
        heal = { name = "Holy", evidence = GUESS },
    },

    resources = {
        { name = "Mana", forms = { "none", "Shadowform" }, evidence = GUESS, note = OLD },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Power Word: Fortitude", seconds = FORT, evidence = GUESS },
        { spell = "Inner Fire", seconds = INNER, evidence = GUESS },
    },

    -- No aoe list yet: see "Not in this pack yet" above.
    lists = {
        default = join(buffs, damage),
    },

    -- Does not apply: nothing is cast on the group.
    groups = {},

    heals = {
        self = { "Flash Heal", "Lesser Heal", "Heal", "Greater Heal", "Renew" },
        hots = { "Renew" },
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only. Psychic Scream reaches only what is near you.
    interrupts = {
        { spell = "Silence", evidence = GUESS },
        { spell = "Psychic Scream", near = true, evidence = GUESS },
    },

    -- Does not apply: as first guessed, a priest has no spell that frees it
    -- from being held.
    breakers = {},

    -- On yourself, out of a fight.
    dispels = {
        { spell = "Dispel Magic", types = { Magic = true }, evidence = GUESS },
        { spell = "Abolish Disease", types = { Disease = true }, evidence = GUESS },
        { spell = "Cure Disease", types = { Disease = true }, evidence = GUESS },
    },

    keys = { none = casterKeys, Shadowform = shadowKeys },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_POWER_SHORT = 0.9, ITEM_MOD_SPIRIT_SHORT = 0.6,
            ITEM_MOD_STAMINA_SHORT = 0.4, ITEM_MOD_HIT_RATING_SHORT = 0.8, ITEM_MOD_CRIT_RATING_SHORT = 0.5,
            ITEM_MOD_HASTE_RATING_SHORT = 0.6, ITEM_MOD_MANA_REGENERATION_SHORT = 1.0,
            ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.0, RESISTANCE0_NAME = 0.03,
        }),
        heal = weights({
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9, ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5, ITEM_MOD_SPIRIT_SHORT = 0.7, ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.5, ITEM_MOD_HASTE_RATING_SHORT = 0.6, RESISTANCE0_NAME = 0.03,
        }),
    },

    -- What the class can equip, by item class and subclass ids, as the old
    -- table gave them. Armor (4): 0, 1. Weapons (2): 4, 10, 15, 19, 20.
    proficiency = {
        evidence = GUESS, note = OLD,
        [4] = { [0] = true, [1] = true },
        [2] = { [4] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    },

    spells = spells,

    -- Does not apply: no talent plan is written; the rotation plays the role
    -- you choose and reads no talent.
    talentBuilds = {},

    options = {
        -- N58 (lead section 241): no own-choice row: Priest has no aura,
        -- stance, form or armor choice in this rotation.
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "buffs", "targetDebuffs", "formKnown" },
    },

    -- Beyond the sixteen rows, from the old shared tables.
    kind = { name = "caster", evidence = GUESS, note = OLD },
    reagents = {
        { item = "Light Feather", evidence = GUESS, note = OLD },
        { item = "Holy Candle", evidence = GUESS, note = OLD },
        { item = "Sacred Candle", evidence = GUESS, note = OLD },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.PRIEST = pack
if type(ns.Register) == "function" then ns:Register("classPack", "PRIEST", pack) end
