local _, ns = ...

-- The Paladin class pack (shape: ZFlow/Rotation/Pack.lua, same rows as
-- Classes/Druid.lua). Ported from Classes/Paladin/Rotation.lua, Data.lua and
-- Spells.lua on the zflow branch. Pure: every rule reads the snapshot it is
-- given (ZFlow/Rotation/Choose.lua lists the fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself. Every rule here
-- is for you or your own target: nothing heals, buffs, cleanses, shields or
-- revives another player.
--
-- Seal and blessing (CF-32, N12; lead sections 226 to 228). Rotation/
-- OwnCasts.lua keeps, from options.sticky below, what you cast yourself and
-- what you choose with the seal and blessing words; snapshot.chosen holds it
-- for the role you play. Each counts only while you know it.
--   Seal: one you cast this fight (sealFight); else the word's choice
--   (sealSet); else the one you last cast for this role (seal, saved over a
--   reload); else the role's: a tank who knows Seal of Fury gets Fury;
--   Command for a role that is not heal or tank, once known; a healer in a
--   group (snapshot.grouped) who knows Seal of Wisdom gets it; else
--   Righteousness.
--   Blessing (the long ones only; one cast on someone else does not count):
--   the word's choice (blessingSet); else the one you last cast on yourself
--   for this role (blessing); else the role's: healing Wisdom, tanking
--   Kings, once known; else Might; Kings when you know no Might.
--   A cast of the one picked at that moment is not kept (PC-1). Only the
--   one picked counts as up (PC-2): another blessing up, or in a fight
--   another seal up, counts as missing; a Greater blessing counts as its own.
-- Righteous Fury (CF-33c): for role tank only, out of a fight, when it is
-- not up or has under 30 s left. An aura (N13): only your own counts
-- (snapshot.ownBuffs, or the aura shown as your stance); another
-- paladin's does not.
--
-- Evidence. Nothing in this pack was read from the game by this file, and the
-- repository holds no list of client observations for the Paladin, so nothing
-- is marked "observed". Every spell name, trainer level, list order, timing
-- and stat weight is a "first guess" carried over from the old Paladin files,
-- whose commits name no source: each needs a check in the game client.
--
-- Not in this pack yet (tasks):
--   * blessings and cleansing for other players: group blessings, Cleanse
--     and Purify on anyone but yourself;
--   * Lay on Hands and Blessing of Protection;
--   * Holy Strike and Consecration (no row in the spell list);
--   * Judgment, Crusader Strike, Shield of the Righteous and Word of Glory
--     (named in the old lists, with no row in the old spell list);
--   * advice to use Divine Protection or Divine Shield (the chooser has no
--     step for it; both are on the Alt key row);
--   * a seal or blessing chosen on the settings page (the words choose one).

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
-- Read as off: true only when the current map was read and says false.
-- Not read (nil map or no answer for the spell) is not "off" (section 183).
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
-- Buffs read at all (an empty map is read: none up).
local function buffsRead(s) return type(s.buffs) == "table" end
-- A fight on, or not known (ns.Rotation.InFight); known to be out of one.
local function inFight(s) return ns.Rotation.InFight(s) end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
local function fight(s) return (s.hostile == true or inFight(s)) and true or false end

-- Is an aura of yours on? true, false, or nil when it cannot be told: the
-- form counts only as a yes (nil form is "no form" and "not known" alike),
-- and "no aura" needs your own buffs read (N13: another paladin's aura on
-- you is in s.buffs, not in s.ownBuffs).
local function hasAura(s)
    if AURAS[s.form or ""] then return true end
    if type(s.ownBuffs) ~= "table" then return nil end
    for name in pairs(s.ownBuffs) do
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

-- PC-2 (legacy isWanted): a buff on you is `want`, or its Greater form.
-- The longest time left on it: nil = not up; true = up, time not shown;
-- a number = seconds left.
local function leftOn(s, want)
    local best
    if type(want) ~= "string" then return nil end
    for name, left in pairs(s.buffs or {}) do
        if (name == want or name == "Greater " .. want) and left then
            if left == true or best == true then
                best = true
            elseif type(left) == "number" and (best == nil or left > best) then
                best = left
            end
        end
    end
    return best
end

-- A blessing is wanted out of a fight when `want` (the one picked when not
-- given) is not up on you, or has under 30 s left (PC-2, legacy
-- needBlessing): another blessing up counts as missing, so another
-- paladin's Kings does not hide your Might and a new choice applies at
-- once; a Greater blessing of the same name counts as up.
-- Not known whether a fight is on: not wanted. Buffs not read: not wanted.
function ns.PaladinWantsBlessing(s, want)
    if not outOfFight(s) or not buffsRead(s) then return false end
    local left = leftOn(s, want or ns.PaladinBlessing(s))
    if left == nil then return true end
    return type(left) == "number" and left < 30
end

-- A seal (PC-2, legacy wantSeal and needSeal): out of a fight, wanted only
-- when no seal at all is up. With a fight on or about to start (an enemy
-- targeted, or a fight on or not known), wanted when `want` (the one picked
-- when not given) is not up, so another seal counts as missing, or is
-- nearly out: 3 s in the fight, 8 s before the pull.
-- Buffs not read: not wanted (section 183).
function ns.PaladinWantsSeal(s, want)
    if not buffsRead(s) then return false end
    if not fight(s) then return longest(s, "Seal of ") == nil end
    local left = leftOn(s, want or ns.PaladinSeal(s))
    if left == nil then return true end
    if type(left) ~= "number" then return false end
    return left < (inFight(s) and 3 or 8)
end

local function sealUp(s) return buffsRead(s) and longest(s, "Seal of ") ~= nil end
local function wisdom(s) return s.role == "heal" and knows(s, "Blessing of Wisdom") end
local function command(s) return s.role ~= "heal" and s.role ~= "tank" and knows(s, "Seal of Command") end

-- Every seal, and the blessings kept on yourself (not Protection, Freedom
-- or Sacrifice: those are for a moment). One rule each, below.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Command", "Seal of Justice",
                "Seal of Light", "Seal of Wisdom", "Seal of Fury" }
local BLESSINGS = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation",
                    "Blessing of Light", "Blessing of Sanctuary" }
local function set(list)
    local out = {}
    for _, name in ipairs(list) do out[name] = true end
    return out
end
local IS_SEAL, IS_BLESSING = set(SEALS), set(BLESSINGS)
-- N58: the auras this pack can suggest (the ones in its spell list).
local AURA_NAMES = { "Devotion Aura", "Retribution Aura", "Concentration Aura" }
local IS_AURA = set(AURA_NAMES)
-- N58, B3: Oath of Light, a WoW: Forever paladin spell. PARTLY: not read
-- from a trainer, and what it does is not known (a first guess: a buff on
-- you). It is never the add-on's own pick: asked for only once you cast it
-- or choose it with the oath word.
local OATH_NAMES = { "Oath of Light" }
local IS_OATH = set(OATH_NAMES)

-- The first of snapshot.chosen[keys...] that is one of the list's and that
-- you know; nil when none is.
local function chosen(s, list, keys)
    if type(s.chosen) ~= "table" then return nil end
    for _, key in ipairs(keys) do
        local name = s.chosen[key]
        if type(name) == "string" and list[name] and knows(s, name) then return name end
    end
    return nil
end

-- The seal to keep up (CF-32, N12): this fight's cast, the word's choice,
-- the one cast for this role, each while known; else the role's.
local SEAL_KEYS = { "sealFight", "sealSet", "seal" }
function ns.PaladinSeal(s)
    local own = chosen(s, IS_SEAL, SEAL_KEYS)
    if own then return own end
    if s.role == "tank" and knows(s, "Seal of Fury") then return "Seal of Fury" end
    if command(s) then return "Seal of Command" end
    -- PC-3 (legacy roleSeal): healing in a group, read as yes.
    if s.role == "heal" and s.grouped == true and knows(s, "Seal of Wisdom") then return "Seal of Wisdom" end
    return "Seal of Righteousness"
end

-- N58: the aura to put up when none of yours is on: the one you cast or
-- chose, while known; else Devotion Aura. New: Flow had no aura choice.
function ns.PaladinAura(s)
    return ns.OwnCasts.Kept(s, IS_AURA, "aura") or "Devotion Aura"
end

-- N58, B3: the oath you cast or chose, while known; else none (auto).
-- New: Flow had no oath.
function ns.PaladinOath(s)
    return ns.OwnCasts.Kept(s, IS_OATH, "oath")
end

-- The blessing to keep up (N12): the word's choice, the one cast on
-- yourself for this role, each while known; else the role's.
local BLESSING_KEYS = { "blessingSet", "blessing" }
function ns.PaladinBlessing(s)
    local own = chosen(s, IS_BLESSING, BLESSING_KEYS)
    if own then return own end
    if wisdom(s) then return "Blessing of Wisdom" end
    if s.role == "tank" and knows(s, "Blessing of Kings") then return "Blessing of Kings" end
    if knows(s, "Blessing of Might") then return "Blessing of Might" end
    if knows(s, "Blessing of Kings") then return "Blessing of Kings" end
    return "Blessing of Might"
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local function auraRule(name)
    return { spell = name, kind = "buff", reason = "No aura is on",
             when = function(s) return hasAura(s) == false and ns.PaladinAura(s) == name end }
end

local buffs = {
    auraRule("Devotion Aura"), auraRule("Retribution Aura"), auraRule("Concentration Aura"),
    -- CF-33c: a tank only; out of a fight, buffs read, not up, or (PC-4,
    -- legacy needFury) under 30 s left.
    { spell = "Righteous Fury", kind = "buff", reason = "Tanking: Righteous Fury (threat)",
      when = function(s)
          if not (s.role == "tank" and outOfFight(s) and buffsRead(s)) then return false end
          local left = s.buffs["Righteous Fury"]
          return left == nil or (type(left) == "number" and left < 30)
      end },
    -- N58, B3 (PARTLY): your oath, out of a fight, buffs read and none
    -- named "Oath of" up. Read as a buff on you: a first guess. Capture
    -- fields oathSpell and oathAura (Core/Diag.lua) show it in game.
    { spell = "Oath of Light", kind = "buff", reason = "Your oath is not on (first guess: read as a buff on you)",
      when = function(s)
          return outOfFight(s) and buffsRead(s) and ns.PaladinOath(s) == "Oath of Light"
              and longest(s, "Oath of ") == nil
      end },
}
-- One rule per blessing and per seal; only the one picked can fire.
for _, name in ipairs(BLESSINGS) do
    buffs[#buffs + 1] = { spell = name, kind = "buff", reason = "Blessing missing or running out",
        when = function(s) return ns.PaladinBlessing(s) == name and ns.PaladinWantsBlessing(s, name) end }
end
for _, name in ipairs(SEALS) do
    buffs[#buffs + 1] = { spell = name, kind = "buff", reason = "Seal missing or running out",
        when = function(s) return ns.PaladinSeal(s) == name and ns.PaladinWantsSeal(s, name) end }
end
tag(buffs)

local melee = tag({
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and readOff(s, "Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile and readOff(s, "Auto Attack") end },
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
      when = inFight },
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
    -- CF-32: seals and blessings a rule can now suggest. No level: the old
    -- spell list's rows for them were guide-reported, so none is kept.
    ["Seal of Fury"]          = sp(nil, { "Tanking" }, nil, "the old rotation file's seal for a tank"),
    ["Blessing of Kings"]     = sp(nil, { "Survival" }, nil, "whether it is a talent was never checked in the game"),
    ["Blessing of Light"]     = sp(nil, { "Healing" }),
    ["Blessing of Sanctuary"] = sp(nil, { "Tanking" }, nil, "whether it is a talent was never checked in the game"),
    ["Attack"]                = sp(nil, { "DPS" }),
    ["Auto Attack"]           = sp(nil, { "DPS" }),
    ["Oath of Light"]         = sp(nil, { "Utility" }, nil,
        "N58, B3: WoW: Forever only; not read from a trainer; what it does is not known"),
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

    -- Your group's blessings, out of a fight: only shown (P-PARTY,
    -- Rotation/Group.lua; and on the tooltip, Rotation/GroupTip.lua);
    -- nothing is cast on anyone. One each (slot "blessing"), the first that
    -- fits: Kings for a tank; Might for melee; Wisdom for casters, healers
    -- and hunters; Kings for anyone else (Flow's Classes/Paladin/Rotation.lua
    -- 408-419). The greater blessings count. First guesses.
    groups = {
        { spell = "Blessing of Kings", aura = { "Blessing of Kings", "Greater Blessing of Kings" },
          who = { "tank" }, slot = "blessing", minutes = 5, rebuff = 30, evidence = GUESS },
        { spell = "Blessing of Might", aura = { "Blessing of Might", "Greater Blessing of Might" },
          who = { "melee", "tank" }, slot = "blessing", minutes = 5, rebuff = 30, evidence = GUESS },
        { spell = "Blessing of Wisdom", aura = { "Blessing of Wisdom", "Greater Blessing of Wisdom" },
          who = { "caster", "healer", "ranged" }, slot = "blessing", minutes = 5, rebuff = 30, evidence = GUESS },
        { spell = "Blessing of Kings", aura = { "Blessing of Kings", "Greater Blessing of Kings" },
          who = "all", slot = "blessing", minutes = 5, rebuff = 30, evidence = GUESS },
    },

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

    options = {
        -- Reads the rules lean on; one not given is named by diag (187).
        -- snapshot.chosen is not one: nil there is "nothing cast yet".
        reads = { "buffs", "ownBuffs" },
        -- CF-32, N12: your own casts kept by Rotation/OwnCasts.lua, by key:
        -- any seal; a blessing only when it is one kept on yourself, and
        -- only once it lands on you (onYou). word: the word that chooses
        -- one of `names`. pick (PC-1, legacy keptFromCast): the one the
        -- rotation would put up on that snapshot; a cast of it is not kept.
        -- N58: a seal cast in a fight is kept for that fight only, as Flow
        -- did; the aura you cast is kept for the role. B3: the oath you
        -- cast is kept for the role (PARTLY, see OATH_NAMES).
        sticky = {
            { prefix = "Seal of ", key = "seal", word = "seal", names = SEALS, fightOnly = true,
              pick = function(s) return ns.PaladinSeal(s) end },
            { prefix = "", only = IS_AURA, key = "aura", word = "aura", names = AURA_NAMES,
              pick = function(s) return ns.PaladinAura(s) end },
            { prefix = "", only = IS_OATH, key = "oath", word = "oath", names = OATH_NAMES,
              pick = function(s) return ns.PaladinOath(s) end },
            { prefix = "Blessing of ", key = "blessing", only = IS_BLESSING, onYou = true,
              word = "blessing", names = BLESSINGS,
              pick = function(s) return ns.PaladinBlessing(s) end },
        },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.PALADIN = pack
if type(ns.Register) == "function" then ns:Register("classPack", "PALADIN", pack) end
