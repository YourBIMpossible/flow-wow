local _, ns = ...

-- The Shaman class pack (shape: ZFlow/Rotation/Pack.lua, same rows as
-- Classes/Druid.lua, Classes/Paladin.lua and Classes/Priest.lua). Pure: every
-- rule reads the snapshot it is given (ZFlow/Rotation/Choose.lua lists the
-- fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself. Nothing here
-- heals, buffs, cleanses or revives another player.
--
-- Section 197. The old code has no Shaman class module, so the spell rows,
-- lists, keys, weights and roles below were written for this pack. From the
-- old shared tables on zflow it keeps: what the class can equip
-- (Modules/Gear/Score.lua), the resource (a Shaman is not in the old no-mana
-- list, Modules/Rotation/BuffItems.lua), the kind of fighter, "caster"
-- (Modules/Rotation/Engine.lua), the stats its food may give
-- (BuffItems.lua) and the reagent kept in the bags
-- (Modules/Items/Disposition.lua).
--
-- Evidence. Nothing in this pack was read from the game, and the repository
-- holds no list of client observations for the Shaman, so nothing is marked
-- "observed". Every spell name, trainer level, list order, time and stat
-- weight is a "first guess" written without a guide, a database or another
-- addon: each needs a check in the game client.
--
-- Not in this pack yet (tasks):
--   * SHAMAN-1 (P-KEYS slice A) holds Ancestral Spirit and the heals for
--     another player in `care`, on the care key only (Rotation/CareKeys.lua);
--     Chain Heal and the totems for a party are not in it;
--   * Frostbrand Weapon in the list: a slowing imbue for the moment, not
--     one to keep up. Windfury, Flametongue and Rockbiter are in the list
--     (P-SELFBUFF, read against your weapon enchant) and on the Alt key row;
--   * totems in the list: no read says which totem is down or how far it is,
--     and most totems reach the group. Searing, Stoneskin and Earthbind are
--     on the key rows, for you to press;
--   * Lightning Bolt as a filler in a fight, and Lightning Bolt or the swing
--     chosen by mana: the client hides power amounts from addon code
--     (R.FROM_AMOUNT in Rotation/Snapshot.lua). Lightning Bolt opens a pull;
--     in a fight the list is the swing and the shocks;
--   * an aoe list: Chain Lightning and Fire Nova Totem, as no read counts the
--     enemies near you;
--   * Purge on the target: no read gives the target's buffs (on the Ctrl key
--     row);
--   * Ghost Wolf: travel, no step of the chooser uses it (on the Shift key
--     row).

local GUESS = "first guess"
local OLD = "carried over from the old shared tables on zflow; authorship unrecorded"

-- Read as off: true only when the current map was read and says false.
-- Not read (nil map or no answer for the spell) is not "off" (section 183).
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
-- Lead section 340: not swinging, by the driver's swing read (s.attacking,
-- Rotation/Driver.lua attackingOf, over Auto Attack and Attack). Where that
-- read was not made, either name read as off. One row for both names: the
-- button casts the swing as "Attack" (Rotation/Cast.lua C.ATTACK_SPELL).
local function swingOff(s)
    if s.attacking ~= nil then return s.attacking == false end
    return readOff(s, "Attack") or readOff(s, "Auto Attack")
end
-- Buffs read at all (an empty map is read: none up).
local function buffsRead(s) return type(s.buffs) == "table" end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
-- Ghost Wolf shown as the form: nothing is cast from it. A form not read
-- counts as no form (the same as Classes/Paladin.lua).
local function wolf(s) return s.form == "Ghost Wolf" end

-- The time left on a buff: nil = not up; true = up, time not shown; a number.
local function left(s, name)
    local v = s.buffs and s.buffs[name]
    if v == true or type(v) == "number" then return v end
    return nil
end

-- Your own Flame Shock is on the target: true, false, or nil when your
-- debuffs on the target were not read.
local function flameOn(s)
    if type(s.targetDebuffs) ~= "table" then return nil end
    return s.targetDebuffs["Flame Shock"] ~= nil and s.targetDebuffs["Flame Shock"] ~= false
end

-- Seconds left below which Lightning Shield is put up again out of a fight.
local SHIELD = 30

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local buffs = tag({
    { spell = "Lightning Shield", kind = "buff", reason = "Lightning Shield missing or running out",
      when = function(s)
          if wolf(s) or not buffsRead(s) then return false end
          local l = left(s, "Lightning Shield")
          if l == nil then return true end
          -- In a fight (or not known): only when it is not up at all.
          return outOfFight(s) and type(l) == "number" and l < SHIELD
      end },
})

-- P-SELFBUFF: the imbue on your main hand (snapshot.weaponEnchant, from
-- client.weaponEnchant). Asked for when the main hand is read bare, or out
-- of a fight with less than IMBUE seconds left. Not read, or the main hand
-- not known: not asked. One rule per imbue; the chooser takes the first
-- you know, in this order (a first guess: the strongest first).
local IMBUE = 60
local function imbueDue(s)
    if wolf(s) or type(s.weaponEnchant) ~= "table" then return false end
    local main = s.weaponEnchant.main
    if main == false then return true end
    if type(main) ~= "number" then return false end
    return outOfFight(s) and main < IMBUE
end
local function imbueRule(name)
    return { spell = name, kind = "buff", reason = "No imbue on your main hand, or running out: " .. name,
             when = imbueDue }
end
buffs[#buffs + 1] = imbueRule("Windfury Weapon")
buffs[#buffs + 1] = imbueRule("Flametongue Weapon")
buffs[#buffs + 1] = imbueRule("Rockbiter Weapon")
tag(buffs)

local damage = tag({
    { spell = "Lightning Bolt", target = true, reason = "Open with Lightning Bolt",
      when = function(s) return s.hostile and outOfFight(s) and not wolf(s) end },
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(s) return s.hostile == true and swingOff(s) end },
    { spell = "Stormstrike", target = true, reason = "Stormstrike is ready",
      when = function(s) return s.hostile and not wolf(s) end },
    { spell = "Flame Shock", target = true, reason = "Your Flame Shock is not on the target",
      when = function(s) return s.hostile and not wolf(s) and flameOn(s) == false end },
    { spell = "Earth Shock", target = true, reason = "Earth Shock is ready",
      when = function(s) return s.hostile and not wolf(s) end },
})

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- The key row (what each modifier holds). Ghost Wolf has no row: nothing is
-- cast from it.
local keys = {
    key = { "Stormstrike", "Earth Shock", "Lightning Bolt" },
    ctrl = { "Flame Shock", "Frost Shock", "Purge" },
    shift = { "Earthbind Totem", "Ghost Wolf", "Searing Totem" },
    alt = { "Rockbiter Weapon", "Flametongue Weapon", "Windfury Weapon" },
    more = { "Healing Wave", "Lesser Healing Wave", "Stoneskin Totem" },
}

-- Spells: the level is the trainer level as first guessed here (no source;
-- not read from a WoW: Forever trainer). No level: a talent, or the swing,
-- as first guessed. A row is a fact about the spell, not advice: several
-- rows are spells no rule here suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Lightning Bolt"]      = sp(1,  { "DPS" }),
    ["Healing Wave"]        = sp(1,  { "Healing" }),
    -- SHAMAN-1: on a dead friend, out of a fight only (the care key).
    ["Ancestral Spirit"]    = sp(12, { "Utility" }),
    ["Rockbiter Weapon"]    = sp(1,  { "DPS" }, nil, "a weapon imbue; the weapon enchant read shows it"),
    ["Earth Shock"]         = sp(4,  { "DPS", "Control" }),
    ["Stoneskin Totem"]     = sp(4,  { "Survival" }, nil, "a totem; no read shows it"),
    ["Earthbind Totem"]     = sp(6,  { "Control" }, nil, "a totem; no read shows it"),
    ["Lightning Shield"]    = sp(8,  { "Survival" }),
    ["Flame Shock"]         = sp(10, { "DPS" }),
    ["Flametongue Weapon"]  = sp(10, { "DPS" }, nil, "a weapon imbue; the weapon enchant read shows it"),
    ["Searing Totem"]       = sp(10, { "DPS" }, nil, "a totem; no read shows it"),
    ["Purge"]               = sp(12, { "Utility" }),
    ["Cure Poison"]         = sp(16, { "Utility" }),
    ["Ghost Wolf"]          = sp(20, { "Utility" }, nil, "a form for travel"),
    ["Frost Shock"]         = sp(20, { "DPS", "Control" }),
    ["Lesser Healing Wave"] = sp(20, { "Healing" }),
    ["Cure Disease"]        = sp(22, { "Utility" }),
    ["Windfury Weapon"]     = sp(30, { "DPS" }, nil, "a weapon imbue; the weapon enchant read shows it"),
    ["Stormstrike"]         = sp(nil, { "DPS" }, nil, "an Enhancement talent"),
    ["Attack"]              = sp(nil, { "DPS" }, nil, "the swing; the client names it Attack or Auto Attack"),
    ["Auto Attack"]         = sp(nil, { "DPS" }, nil, "the swing; the client names it Attack or Auto Attack"),
}

local function weights(values)
    return { evidence = GUESS, values = values }
end

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-22",
        method = "Section 197: spell rows, lists, keys, weights and roles written for this pack as first guesses, "
            .. "without a guide, database or other addon; what the class can equip, the resource, the kind, the "
            .. "food stats and the reagent kept from the old shared tables on the zflow branch "
            .. "(Modules/Gear/Score.lua, Modules/Rotation/BuffItems.lua, Modules/Rotation/Engine.lua, "
            .. "Modules/Items/Disposition.lua); mail from level 40 (section 205, D3: a level in place of true).",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. Nothing copied from proprietary data.",
    },

    roles = {
        dps  = { name = "Enhancement", evidence = GUESS },
        heal = { name = "Restoration", evidence = GUESS },
    },

    -- G31: the spec recommended while levelling alone, and why. Written for
    -- this pack in its own words from general knowledge of the class; nothing
    -- here was read from the game or taken from a guide.
    levelling = {
        role = "dps", evidence = GUESS,
        why = {
            "Weapon hits with a weapon enchant on, and a shock now and then, kill at a steady pace for little mana.",
            "You can still heal yourself between fights, and heal a dungeon at your level without healing talents.",
        },
    },

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS, note = OLD },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Lightning Shield", seconds = SHIELD, evidence = GUESS },
    },

    -- No aoe list yet: see "Not in this pack yet" above.
    lists = {
        default = join(buffs, damage),
    },

    -- Does not apply: nothing is cast on the group (totems are keys only).
    groups = {},
    groupsNone = "A shaman's group help is its totems, keys only; Water Walking and Water Breathing are only for the moment they are needed.",

    heals = {
        self = { "Lesser Healing Wave", "Healing Wave" },
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only.
    interrupts = {
        { spell = "Earth Shock", evidence = GUESS },
    },

    -- Does not apply: as first guessed, a shaman has no spell that frees
    -- itself from being held (Tremor Totem is a totem, with no read).
    breakers = {},

    -- On yourself, out of a fight.
    dispels = {
        { spell = "Cure Poison", types = { Poison = true }, evidence = GUESS },
        { spell = "Cure Disease", types = { Disease = true }, evidence = GUESS },
    },

    -- SHAMAN-1 (P-KEYS slice A): for another player, on the care key only
    -- (Rotation/CareKeys.lua, R.FriendHeal). The cures are the dispels above.
    care = {
        friend = { "Lesser Healing Wave", "Healing Wave" },
        revive = "Ancestral Spirit",
        evidence = GUESS,
    },

    keys = { none = keys },

    -- Stat weights per role: relative numbers, score = sum(stat * weight).
    weights = {
        dps = weights({
            ITEM_MOD_STRENGTH_SHORT = 1.0, ITEM_MOD_AGILITY_SHORT = 0.7, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_INTELLECT_SHORT = 0.3, ITEM_MOD_SPIRIT_SHORT = 0.1, ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 0.9, ITEM_MOD_HASTE_RATING_SHORT = 0.6,
            ITEM_MOD_SPELL_POWER_SHORT = 0.2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0, RESISTANCE0_NAME = 0.07,
        }),
        heal = weights({
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9, ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5, ITEM_MOD_SPIRIT_SHORT = 0.4, ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.6, ITEM_MOD_HASTE_RATING_SHORT = 0.7, RESISTANCE0_NAME = 0.07,
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
                why = "Windfury Weapon and Stormstrike hit for weapon damage, so a slow weapon makes each extra"
                    .. " swing bigger" },
        heal = { prefer = "any", why = "healing spells do not use the weapon's swing" },
    },

    -- What the class can equip, by item class and subclass ids, as the old
    -- table gave them. Armor (4): 0, 1, 2, 3 mail from level 40 (section
    -- 205, D3: a level in place of true), 6, 9. Weapons (2): 0, 1, 4, 5,
    -- 10, 13, 15, 20.
    proficiency = {
        evidence = GUESS, note = OLD,
        [4] = { [0] = true, [1] = true, [2] = true, [3] = 40, [6] = true, [9] = true },
        [2] = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true, [20] = true },
    },

    spells = spells,

    -- Does not apply: no talent plan is written; the rotation plays the role
    -- you choose and reads no talent.
    talentBuilds = {
        { name = "Enhancement levelling build", role = "dps", evidence = GUESS, note = "written for this pack on 2026-11-23 from general knowledge of the class; not read from the game",
          trees = { "Elemental", "Enhancement", "Restoration" },
          order = {
              { "Ancestral Knowledge", 5, why = "More mana, so longer between drinking breaks." },
              { "Thundering Strikes", 5, why = "More critical hits with your weapon." },
              { "Two-Handed Axes and Maces", 1, why = "Lets you wield a two-handed axe or mace." },
              { "Improved Ghost Wolf", 2, why = "Ghost Wolf comes faster, so less time walking between pulls." },
              { "Enhancing Totems", 2, why = "Your strength and agility totems give more." },
              { "Flurry", 5, why = "After a critical hit, your next few swings come faster." },
              { "Elemental Weapons", 3, why = "Your Rockbiter and Windfury weapon enchants are stronger." },
              { "Parry", 1, why = "You can parry, so you take less damage while you fight." },
              { "Toughness", 1, why = "More armor from your items." },
              { "Weapon Mastery", 5, why = "More damage with every weapon." },
              { "Stormstrike", 1, why = "A strike that hits twice and makes your next nature spells hit harder." },
          },
        },
    },

    options = {
        crowdControl = { none = "no shaman spell in this client holds a second enemy" },
        threatDrop = { none = "no shaman spell in this client drops threat" },
        -- N50 / GAP DRUID-2 (P-SELFBUFF): the known-spell tree. Talent spells,
        -- in order: the first you know names your tree (snapshot.tree,
        -- Rotation/Driver.lua). Which spell is a talent of which tree: a first
        -- guess from the 1.12 talent trees as remembered, not read from the game.
        trees = {
            { spell = "Mana Tide Totem", tree = "Restoration", evidence = GUESS },
            { spell = "Stormstrike", tree = "Enhancement", evidence = GUESS },
            { spell = "Elemental Mastery", tree = "Elemental", evidence = GUESS },
            { spell = "Nature's Swiftness", tree = "Restoration", evidence = GUESS },
        },
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "buffs", "targetDebuffs" },
        -- N58 (lead section 241): no own-choice row yet. The imbue steps
        -- (P-SELFBUFF) ask for the first imbue you know; the one you cast is
        -- not kept. The row (prefix "", key "imbue", word "imbue") is the
        -- next N58 step. Totems: none is suggested.
        -- P-SELFBUFF: the self-buff rows (Tests/Rotation/SelfBuffRows.lua).
        selfBuffs = {
            rows = { "Lightning Shield", "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon" },
            none = {
                { what = "Frostbrand Weapon", why = "a slowing imbue for the moment, not one to keep up" },
                { what = "Water Shield", why = "not a spell of this client's shaman (first guess)" },
            },
            waits = {},
        },
    },

    -- Beyond the sixteen rows, from the old shared tables.
    kind = { name = "caster", evidence = GUESS, note = OLD },
    foodStats = { evidence = GUESS, note = OLD, Strength = true, Agility = true },
    reagents = {
        { item = "Ankh", evidence = GUESS, note = OLD },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.SHAMAN = pack
if type(ns.Register) == "function" then ns:Register("classPack", "SHAMAN", pack) end
