local _, ns = ...

-- The Rogue class pack (lead section 197; shape: ZFlow/Rotation/Pack.lua,
-- same rows as Classes/Paladin.lua, Classes/Druid.lua and the Warrior pack).
-- Pure: every rule reads the snapshot it is given (ZFlow/Rotation/Choose.lua
-- lists the fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself. Nothing here is
-- cast on another player. A pack suggests; it never casts.
--
-- Stealth is read as its own yes or no (s.stealthed): true, false, or nil
-- when not read. Not read is neither: no Stealth, no swing, no strike, no
-- opener waits on it. Stealth is not a shapeshift form here, so the stealth
-- key row has no form (ZFlow/Rotation/KeyPlan.lua: "[stealth] 9", any form;
-- needs game test). Energy is not read as an amount: the game marks a
-- strike not usable when there is too little (needs game test). Combo points
-- are a hidden amount (R.FROM_AMOUNT in Rotation/Snapshot.lua): a finisher
-- waits for s.finisherReady, which no reader builds yet, so no finisher is
-- suggested until one does.
--
-- Evidence. Nothing in this pack was read from the game by this file, and the
-- repository holds no list of client observations for the Rogue, so nothing
-- is marked "observed". Every spell name, trainer level, list order, timing
-- and stat weight is a "first guess" written for section 197 with no
-- outside source: each needs a check in the game client.
--
-- Not built, on purpose:
--   * poisons (putting one on a weapon is the use of an item; no poison row);
--   * the finisher read (combo points; see above);
--   * a talent order (talentBuilds is empty: one written from memory would be
--     guide-shaped, and no capture backs one);
--   * Vanish and Blind as breakers (breakers is empty: whether the control
--     read names the effect type is not known);
--   * a tank role (the class has none).

local GUESS = "first guess"
local NOTE = "written for lead section 197; no outside source; needs a check in the game client"

-- Read as off: true only when the current map was read and says false.
-- Not read (nil map or no answer for the spell) is not "off" (section 183).
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
local function inFight(s) return ns.Rotation.InFight(s) end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
local function stealthed(s) return s.stealthed == true end
-- Read as not stealthed. A stealth nobody read (nil) is neither.
local function unstealthed(s) return s.stealthed == false end
-- Combo points are a hidden amount: a finisher waits for the reader's say-so.
local function finisher(s) return s.finisherReady == true end
-- A buff on yourself missing or nearly out. Buffs not read: not wanted.
local function needBuff(s, name, secs)
    if type(s.buffs) ~= "table" then return false end
    local left = s.buffs[name]
    if left == nil then return true end
    return type(left) == "number" and left < secs
end
-- The game did not say no. Ambush needs a dagger in hand: the game's usable
-- answer says so (needs game test); not read is not a no.
local function notRefused(s, name)
    local r = s.spells and s.spells[name]
    return not (r and r.usable == false)
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local survive = tag({
    { spell = "Evasion", kind = "buff", reason = "The game warns of low health: Evasion",
      when = function(s) return inFight(s) and s.lowHealth == true end },
})

local stealth = tag({
    { spell = "Stealth", kind = "buff", reason = "An enemy, out of a fight: Stealth first",
      when = function(s) return outOfFight(s) and s.hostile == true and unstealthed(s) end },
})

-- From stealth: the opener.
local opener = tag({
    { spell = "Ambush", target = true, reason = "Stealthed: open with Ambush",
      when = function(s) return s.hostile == true and stealthed(s) and notRefused(s, "Ambush") end },
    { spell = "Garrote", target = true, reason = "Stealthed: open with Garrote",
      when = function(s) return s.hostile == true and stealthed(s) end },
    { spell = "Cheap Shot", target = true, reason = "Stealthed: open with Cheap Shot",
      when = function(s) return s.hostile == true and stealthed(s) end },
})

local swing = tag({
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile == true and unstealthed(s) and readOff(s, "Attack") end },
})

local finish = tag({
    { spell = "Slice and Dice", kind = "buff", reason = "A finisher due, Slice and Dice off or running out",
      when = function(s)
          return s.hostile == true and unstealthed(s) and finisher(s) and needBuff(s, "Slice and Dice", 3)
      end },
    { spell = "Eviscerate", target = true, reason = "A finisher due: Eviscerate",
      when = function(s) return s.hostile == true and unstealthed(s) and finisher(s) end },
})

local build = tag({
    { spell = "Sinister Strike", target = true, reason = "Build: Sinister Strike",
      when = function(s) return s.hostile == true and unstealthed(s) end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key rows: out of stealth, and stealthed (no form: any form).
local noneKeys = {
    key = { "Sinister Strike" },
    ctrl = { "Eviscerate", "Slice and Dice" },
    shift = { "Slice and Dice", "Gouge" },
    alt = { "Kick", "Gouge" },
    more = { "Evasion", "Sprint", "Stealth" },
}
local stealthKeys = {
    key = { "Ambush", "Garrote", "Cheap Shot", "Sinister Strike" },
    ctrl = { "Cheap Shot", "Garrote" },
    shift = { "Sap", "Distract" },
    alt = { "Garrote", "Cheap Shot" },
    more = { "Sprint", "Vanish" },
}

-- Spells: the level is a first guess at the trainer level. A row is a fact
-- about the spell, not advice: several rows are spells no rule suggests.
local function sp(level, improves, note)
    return { evidence = GUESS, level = level, improves = improves, note = note }
end
local spells = {
    ["Attack"]          = sp(1,  { "DPS" }),
    ["Stealth"]         = sp(1,  { "DPS" }),
    ["Sinister Strike"] = sp(1,  { "DPS" }),
    ["Eviscerate"]      = sp(1,  { "DPS" }, "a finisher"),
    ["Backstab"]        = sp(4,  { "DPS" }, "from behind, a dagger in hand"),
    ["Gouge"]           = sp(6,  { "Control" }),
    ["Evasion"]         = sp(8,  { "Survival" }),
    ["Sap"]             = sp(10, { "Control" }, "from stealth, out of a fight"),
    ["Slice and Dice"]  = sp(10, { "DPS" }, "a finisher"),
    ["Sprint"]          = sp(10, { "Survival" }),
    ["Kick"]            = sp(12, { "Control" }),
    ["Garrote"]         = sp(14, { "DPS" }, "from stealth"),
    ["Ambush"]          = sp(18, { "DPS" }, "from stealth, a dagger in hand"),
    ["Distract"]        = sp(22, { "Control" }),
    ["Vanish"]          = sp(22, { "Survival" }),
    ["Cheap Shot"]      = sp(26, { "Control" }, "from stealth"),
}

local function weights(values)
    return { evidence = GUESS, note = NOTE, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-22",
        method = "Written for lead section 197 on the shape of Classes/Paladin.lua, Classes/Druid.lua and the "
            .. "Warrior pack, through the shared chooser, key plan, gear weights and trainer list only. Client "
            .. "reads are snapshot fields; nothing added from outside the repository.",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. No guide, database or other addon used.",
    },

    -- No tank role: the class has none.
    roles = {
        dps = { name = "Combat / Assassination / Subtlety", evidence = GUESS },
    },

    resources = {
        { name = "Energy", forms = { "none" }, evidence = GUESS },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    -- Slice and Dice is a finisher: it also waits for finisherReady.
    maintain = {
        { spell = "Slice and Dice", seconds = 3, evidence = GUESS },
    },

    -- One list: no spell of the class hits several enemies at this stage
    -- (Blade Flurry is a talent; not built), so there is no aoe list.
    lists = {
        default = join(survive, stealth, opener, swing, finish, build),
    },

    -- Nothing is cast on the group.
    groups = {},

    -- No heal of its own (Evasion is in the list, on the game's warning).
    heals = {
        self = {},
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only.
    interrupts = {
        { spell = "Kick", evidence = GUESS },
    },

    -- Not built: see the header (Vanish, Blind).
    breakers = {},

    -- The class removes nothing.
    dispels = {},

    keys = {
        none = noneKeys,
        stealth = stealthKeys,
    },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_AGILITY_SHORT = 1.0, ITEM_MOD_STRENGTH_SHORT = 0.5, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.9,
            ITEM_MOD_HASTE_RATING_SHORT = 0.7, ITEM_MOD_MASTERY_RATING_SHORT = 0.6, ITEM_MOD_VERSATILITY = 0.6,
            ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0, RESISTANCE0_NAME = 0.05,
        }),
    },

    -- What the class can equip, by item class and subclass ids.
    -- Armor (4): 0 misc, 1 cloth, 2 leather.
    -- Weapons (2): 2 bow, 3 gun, 4 one-handed mace, 7 one-handed sword,
    -- 13 fist, 15 dagger, 16 thrown, 18 crossbow, 20 fishing pole.
    proficiency = {
        evidence = GUESS, note = NOTE,
        [4] = { [0] = true, [1] = true, [2] = true },
        [2] = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true,
                [18] = true, [20] = true },
    },

    spells = spells,

    -- Not authored: see the header.
    talentBuilds = {},

    options = {
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "stealthed", "buffs", "targetDebuffs" },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.ROGUE = pack
if type(ns.Register) == "function" then ns:Register("classPack", "ROGUE", pack) end
