local _, ns = ...

-- The Mage class pack (shape: ZFlow/Rotation/Pack.lua, the rows of
-- Classes/Paladin.lua and Classes/Druid.lua). Lead section 197. Pure: every
-- rule reads the snapshot it is given (ZFlow/Rotation/Choose.lua lists the
-- fields) and nothing else.
--
-- Scope: damage on your own target and care for yourself: your armor, your
-- intellect, your own conjured food and water. Nothing here buffs, cleanses
-- or feeds another player.
--
-- Evidence. Nothing in this pack was read from the game, and the repository
-- holds no client observations for the Mage, so nothing is "observed". What
-- the class can equip is carried over from the old shared table
-- (Modules/Gear/Score.lua, CLASS_PROFICIENCY). Everything else (spell names,
-- trainer levels, list order, timings, conjured item names, stat weights,
-- the talent order) was written by Flow for this pack on 2026-11-23 and is
-- a "first guess": each needs a check in the game client. No guide,
-- database or other addon was used.
--
-- Shared pieces this pack uses: the snapshot's `conjured` read (bag counts
-- of the items options.conjure names; Rotation/Snapshot.lua R.Conjured).
--
-- Not in this pack yet (tasks):
--   * channelled spells (Arcane Missiles, Blizzard, Evocation): the snapshot
--     has no read of your own channel, so a suggestion could cut one short.
--     They stay in the spell list; the chooser does not suggest them;
--   * Frost Nova and Blink as steps: they answer an enemy next to you, and
--     the driver reads no such thing yet. Both are on the key rows;
--   * Polymorph and Counterspell on another enemy are shown only, never on
--     the key (lead section 242: the crowd-control and plate-cast steps of
--     Rotation/Choose.lua); both wait on the nameplate reads (P-READS);
--   * Amplify and Dampen Magic: asked for only once you cast or chose one
--     (MAGE-5, the magic row below); no default pick;
--   * Arcane Brilliance, and anything cast on another player (P-PARTY:
--     Arcane Intellect for your group is only shown, never cast).

local GUESS = "first guess"
local NOTE = "written by Flow for this pack, 2026-11-23; not read from the game"

local ARMORS = { "Mage Armor", "Ice Armor", "Frost Armor" }
-- N58 (lead section 241): the armors the armor word names.
local IS_ARMOR = {}
for _, name in ipairs(ARMORS) do IS_ARMOR[name] = true end
local WATER = { "Conjured Water", "Conjured Fresh Water", "Conjured Purified Water", "Conjured Spring Water",
    "Conjured Mineral Water", "Conjured Sparkling Water", "Conjured Crystal Water" }
local FOOD = { "Conjured Muffin", "Conjured Bread", "Conjured Rye", "Conjured Pumpernickel",
    "Conjured Sourdough", "Conjured Sweet Roll", "Conjured Cinnamon Roll" }
-- Fewer than this many in the bags: make more (out of a fight).
local LOW_STOCK = 4

local function knows(s, name)
    local r = s.spells and s.spells[name]
    return (r and r.known) and true or false
end
-- Read as off: true only when the current map was read and says false.
local function readOff(s, name) return type(s.current) == "table" and s.current[name] == false end
local function buffsRead(s) return type(s.buffs) == "table" end
local function outOfFight(s) return ns.Rotation.OutOfFight(s) end
local function inFight(s) return ns.Rotation.InFight(s) end

-- The armor to keep up: the best one known, by ARMORS order.
local function bestArmor(s)
    for _, name in ipairs(ARMORS) do
        if knows(s, name) then return name end
    end
    return nil
end

-- Is an armor up? nil when the buffs were not read.
local function armorUp(s)
    if not buffsRead(s) then return nil end
    for _, name in ipairs(ARMORS) do
        if s.buffs[name] then return true end
    end
    return false
end

-- Arcane Intellect is wanted out of a fight, with none up or under a minute left.
local function wantsIntellect(s)
    if not outOfFight(s) or not buffsRead(s) then return false end
    local left = s.buffs["Arcane Intellect"]
    if left == nil then return true end
    return type(left) == "number" and left < 60
end

-- N58 (lead section 241): the armor to keep up: the one you cast or chose,
-- while known; else the best one known, as before (nil when none is).
-- New: Flow had no armor choice.
function ns.MageArmor(s)
    local OC = ns.OwnCasts
    local kept = OC and OC.Kept(s, IS_ARMOR, "armor") or nil
    return kept or bestArmor(s)
end

-- MAGE-5 (P-SELFBUFF): Amplify or Dampen Magic, your own choice only (the
-- magic row of options.sticky): never asked for until cast or chosen.
local MAGICS = { "Amplify Magic", "Dampen Magic" }
local IS_MAGIC = { ["Amplify Magic"] = true, ["Dampen Magic"] = true }
local MAGIC_LEFT = 60
function ns.MageMagic(s)
    local OC = ns.OwnCasts
    if type(OC) ~= "table" then return nil end
    return OC.Kept(s, IS_MAGIC, "magic")
end
local function wantsMagic(s, name)
    if not outOfFight(s) or not buffsRead(s) or ns.MageMagic(s) ~= name then return false end
    local l = s.buffs[name]
    if l == nil then return true end
    return type(l) == "number" and l < MAGIC_LEFT
end

local function wantsArmor(s, name)
    return outOfFight(s) and ns.MageArmor(s) == name and armorUp(s) == false
end

-- Conjure more only on a count read out of a fight: not known is not "none".
local function lowStock(s, spell)
    local n = ns.Rotation.Conjured(s, spell)
    return outOfFight(s) and n ~= nil and n < LOW_STOCK
end

local function tag(list)
    for _, rule in ipairs(list) do
        if not rule.evidence then rule.evidence = GUESS end
    end
    return list
end

local buffs = tag({
    { spell = "Mage Armor", kind = "buff", reason = "No armor is on",
      when = function(s) return wantsArmor(s, "Mage Armor") end },
    { spell = "Ice Armor", kind = "buff", reason = "No armor is on",
      when = function(s) return wantsArmor(s, "Ice Armor") end },
    { spell = "Frost Armor", kind = "buff", reason = "No armor is on",
      when = function(s) return wantsArmor(s, "Frost Armor") end },
    { spell = "Arcane Intellect", kind = "buff", reason = "Arcane Intellect missing or running out",
      when = wantsIntellect },
    { spell = "Conjure Water", kind = "buff", reason = "Little conjured water left in your bags",
      when = function(s) return lowStock(s, "Conjure Water") end },
    { spell = "Conjure Food", kind = "buff", reason = "Little conjured food left in your bags",
      when = function(s) return lowStock(s, "Conjure Food") end },
    { spell = "Amplify Magic", kind = "buff", reason = "Amplify Magic, your choice, missing or running out",
      when = function(s) return wantsMagic(s, "Amplify Magic") end },
    { spell = "Dampen Magic", kind = "buff", reason = "Dampen Magic, your choice, missing or running out",
      when = function(s) return wantsMagic(s, "Dampen Magic") end },
})

local single = tag({
    { spell = "Fire Blast", target = true, reason = "Fire Blast is ready: instant damage",
      when = function(s) return s.hostile end },
    { spell = "Frostbolt", target = true, reason = "Frostbolt: damage, and it slows",
      when = function(s) return s.hostile end },
    { spell = "Fireball", target = true, reason = "No Frostbolt yet: Fireball",
      when = function(s) return s.hostile and not knows(s, "Frostbolt") end },
    -- The wand: last, when nothing above can be cast (no mana, all on
    -- cooldown). Never pressed while it shoots: that would stop it.
    { spell = "Shoot", target = true, reason = "Nothing else to cast: your wand",
      when = function(s) return s.hostile and readOff(s, "Shoot") end },
})

local aoe = tag({
    { spell = "Arcane Explosion", reason = "Several enemies", when = inFight },
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
    key = { "Frostbolt", "Fireball" },
    ctrl = { "Fire Blast", "Frost Nova" },
    shift = { "Frost Nova", "Blink" },
    alt = { "Blink", "Counterspell", "Mana Shield" },
    more = { "Counterspell", "Frost Nova", "Cone of Cold" },
}

-- Spells: the level is Flow's first guess at the trainer level, not read
-- from a WoW: Forever trainer. A row is a fact about the spell, not
-- advice: several rows are spells no rule here suggests.
local function sp(level, improves, needs, note)
    return { evidence = GUESS, level = level, improves = improves, needs = needs, note = note }
end
local spells = {
    ["Fireball"]            = sp(1,  { "DPS" }),
    ["Frost Armor"]         = sp(1,  { "Survival" }),
    ["Arcane Intellect"]    = sp(1,  { "Mana" }),
    ["Frostbolt"]           = sp(4,  { "DPS" }),
    ["Conjure Water"]       = sp(4,  { "Mana" }),
    ["Conjure Food"]        = sp(6,  { "Survival" }),
    ["Fire Blast"]          = sp(6,  { "DPS" }),
    ["Arcane Missiles"]     = sp(8,  { "DPS" }, nil, "channelled: not suggested (no channel read)"),
    ["Polymorph"]           = sp(8,  { "Control" }),
    ["Frost Nova"]          = sp(10, { "Control" }),
    ["Slow Fall"]           = sp(12, { "Utility" }),
    ["Dampen Magic"]        = sp(12, { "Utility" }),
    ["Arcane Explosion"]    = sp(14, { "DPS" }),
    ["Flamestrike"]         = sp(16, { "DPS" }),
    ["Remove Lesser Curse"] = sp(18, { "Utility" }),
    ["Amplify Magic"]       = sp(18, { "Utility" }),
    ["Blink"]               = sp(20, { "Survival" }),
    ["Blizzard"]            = sp(20, { "DPS" }, nil, "channelled: not suggested (no channel read)"),
    ["Evocation"]           = sp(20, { "Mana" }, nil, "channelled: not suggested (no channel read)"),
    ["Mana Shield"]         = sp(20, { "Survival" }),
    ["Fire Ward"]           = sp(20, { "Survival" }),
    ["Frost Ward"]          = sp(22, { "Survival" }),
    ["Scorch"]              = sp(22, { "DPS" }),
    ["Counterspell"]        = sp(24, { "Control" }),
    ["Cone of Cold"]        = sp(26, { "DPS" }),
    ["Ice Armor"]           = sp(30, { "Survival" }),
    ["Mage Armor"]          = sp(34, { "Mana" }),
    ["Shoot"]               = sp(nil, { "DPS" }, { "a wand" }),
}

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-23",
        method = "Written for this pack (lead section 197) on the Paladin and Druid pattern: damage on your own "
            .. "target and care for yourself only. What the class can equip is carried over from the old "
            .. "Modules/Gear/Score.lua; the list order is Flow's own (an instant when it is ready, the slowing "
            .. "bolt, the wand when nothing else can be cast; armor, intellect, then food and water out of a fight).",
        facts = "No value here was read from the game and none comes from a list of client observations (the "
            .. "repository has none for this class). Every value is marked first guess and needs a check in "
            .. "the game client. No guide, database or other addon used.",
    },

    -- One role: a mage deals damage. A mage has no heal or tank spec in this
    -- game, so there is no heal or tank row.
    roles = {
        dps = { name = "Frost", evidence = GUESS },
    },

    -- G31: the spec recommended while levelling alone, and why. Written for
    -- this pack in its own words from general knowledge of the class; nothing
    -- here was read from the game or taken from a guide.
    levelling = {
        role = "dps", evidence = GUESS,
        why = {
            "Slowing and rooting enemies keeps them away from you, so you take few hits.",
            "Fights are safe more than fast, and the water you conjure fills your mana between them.",
        },
    },

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS },
    },

    -- Buffs kept on yourself: recast with less than this many seconds left.
    maintain = {
        { spell = "Arcane Intellect", seconds = 60, evidence = GUESS },
        { spell = "Frost Armor", seconds = 30, evidence = GUESS },
    },

    lists = {
        default = join(buffs, single),
        aoe = join(buffs, aoe, single),
    },

    -- Arcane Intellect for those in your group who use mana, out of a
    -- fight: only shown (P-PARTY, Rotation/Group.lua; and on the tooltip);
    -- nothing is cast on anyone. Arcane Brilliance counts. First guesses.
    groups = {
        { spell = "Arcane Intellect", aura = { "Arcane Intellect", "Arcane Brilliance" },
          who = { "MAGE", "PRIEST", "WARLOCK", "SHAMAN", "DRUID", "PALADIN", "HUNTER" },
          minutes = 30, rebuff = 60, evidence = GUESS },
    },

    -- A mage has no heal of its own: the rows are empty, not unknown.
    heals = {
        self = {},
        hots = {},
        lingers = {},
        evidence = GUESS,
    },

    -- On your own target only, when it starts a cast.
    interrupts = {
        { spell = "Counterspell", evidence = GUESS },
    },

    -- Blink frees you from a root or a stun (first guess).
    breakers = {
        { spell = "Blink", types = { ROOT = true, STUN = true }, evidence = GUESS },
    },

    -- On yourself, out of a fight.
    dispels = {
        { spell = "Remove Lesser Curse", types = { Curse = true }, evidence = GUESS },
    },

    keys = { none = keys },

    -- Stat weights: relative numbers, score = sum(stat * weight). Flow's
    -- model: a mage's damage is its spells, so spell power and intellect
    -- (mana, spell crit) lead; hit and crit next; stamina to live; the
    -- wand's damage a little. Only a dps row: the class has no other role.
    weights = {
        dps = { evidence = GUESS, note = NOTE, values = {
            ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPELL_POWER_SHORT = 0.9, ITEM_MOD_HIT_RATING_SHORT = 0.8,
            ITEM_MOD_CRIT_RATING_SHORT = 0.7, ITEM_MOD_HASTE_RATING_SHORT = 0.5, ITEM_MOD_MASTERY_RATING_SHORT = 0.4,
            ITEM_MOD_VERSATILITY = 0.4, ITEM_MOD_SPIRIT_SHORT = 0.3, ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_MANA_REGENERATION_SHORT = 0.8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.5, RESISTANCE0_NAME = 0.02,
        } },
    },

    -- G15, lead section 280: the weapon speed each role likes, and why, for
    -- the speed line on a weapon's tooltip (Gear/WeaponSpeed.lua). "any":
    -- speed does not matter for the role. Not counted in the score.
    weaponSpeed = {
        evidence = GUESS,
        note = "written for lead section 280 from the game's rules as remembered; no outside source;"
            .. " not read from the game",
        dps = { prefer = "any", why = "spells do the damage, not the weapon's swing" },
    },

    -- What the class can equip, by item class and subclass ids, carried over
    -- from Modules/Gear/Score.lua. Armor (4): 0 misc, 1 cloth.
    -- Weapons (2): 7 one-handed swords, 10 staves, 15 daggers, 19 wands, 20 fishing poles.
    proficiency = {
        evidence = GUESS, note = "carried over from Modules/Gear/Score.lua CLASS_PROFICIENCY; authorship unrecorded",
        [4] = { [0] = true, [1] = true },
        [2] = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    },

    spells = spells,

    talentBuilds = {
        { name = "Frost levelling build", role = "dps", evidence = GUESS, note = NOTE,
          trees = { "Arcane", "Fire", "Frost" },
          order = {
              { "Improved Frostbolt", 5, why = "Frostbolt casts faster, the spell you cast most." },
              { "Elemental Precision", 3, why = "Fewer of your frost and fire spells are resisted." },
              { "Ice Shards", 5, why = "Frost spell crits hit harder." },
              { "Permafrost", 3, why = "Your chill effects last longer and slow more." },
              { "Piercing Ice", 3, why = "More damage from every frost spell." },
              { "Cold Snap", 1, why = "Resets your frost cooldowns when a pull goes wrong." },
              { "Frost Channeling", 3, why = "Frost spells cost less mana, so fewer drinking breaks." },
              { "Shatter", 5, why = "More crits on a frozen enemy, after Frost Nova." },
              { "Ice Block", 1, why = "Stops all damage for a few seconds to get out of trouble." },
              { "Improved Cone of Cold", 3, why = "More damage from Cone of Cold on enemies close in." },
              { "Winter's Chill", 5, why = "Your frost spells make the enemy easier to crit." },
              { "Ice Barrier", 1, why = "An absorb shield you can cast before a pull." },
          } },
    },

    options = {
        threatDrop = { none = "no mage spell drops threat at once; Ice Block stops damage, not threat" },
        -- N50 / GAP DRUID-2 (P-SELFBUFF): the known-spell tree. Talent spells,
        -- in order: the first you know names your tree (snapshot.tree,
        -- Rotation/Driver.lua). Which spell is a talent of which tree: a first
        -- guess from the 1.12 talent trees as remembered, not read from the game.
        trees = {
            { spell = "Arcane Power", tree = "Arcane", evidence = GUESS },
            { spell = "Ice Barrier", tree = "Frost", evidence = GUESS },
            { spell = "Combustion", tree = "Fire", evidence = GUESS },
            { spell = "Blast Wave", tree = "Fire", evidence = GUESS },
            { spell = "Presence of Mind", tree = "Arcane", evidence = GUESS },
            { spell = "Ice Block", tree = "Frost", evidence = GUESS },
            { spell = "Cold Snap", tree = "Frost", evidence = GUESS },
            { spell = "Pyroblast", tree = "Fire", evidence = GUESS },
        },
        -- Reads the rules lean on; one not given is named by diag (187).
        reads = { "buffs", "conjured" },
        -- Lead section 242: the crowd-control step holds a second beast or
        -- humanoid enemy, shown only. English creature type names; first
        -- guess, Needs game test.
        crowdControl = { { spell = "Polymorph", creatures = { beast = true, humanoid = true } } },
        -- What each conjuring spell makes, for the shared `conjured` read.
        conjure = {
            { spell = "Conjure Water", items = WATER },
            { spell = "Conjure Food", items = FOOD },
        },
        -- N58 (lead section 241): the armor you cast is the one asked for
        -- (OwnCasts.lua). No prefix: the row takes only the armors. word:
        -- the word that chooses one of `names`. pick (PC-1): the one asked
        -- for now; a cast of it is not kept.
        sticky = {
            { prefix = "", only = IS_ARMOR, key = "armor", word = "armor", names = ARMORS,
              pick = function(s) return ns.MageArmor(s) end },
            -- MAGE-5: Amplify or Dampen Magic. pick: the one asked for now.
            { prefix = "", only = IS_MAGIC, key = "magic", word = "magic", names = MAGICS,
              pick = function(s) return ns.MageMagic(s) end },
        },
    },
}

ns.Packs = ns.Packs or {}
ns.Packs.MAGE = pack
if type(ns.Register) == "function" then ns:Register("classPack", "MAGE", pack) end
