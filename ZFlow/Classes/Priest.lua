local _, ns = ...

-- The Priest class pack (shape: ZFlow/Rotation/Pack.lua, same rows as
-- Classes/Druid.lua and Classes/Paladin.lua). Pure data.
--
-- The old code has no Priest class module: no rotation, no spell list, no
-- key rows, no stat weights, no talent plan. This pack holds only what the
-- old shared tables say about a Priest, and leaves the rest empty. An empty
-- row means "not known yet", never "the class has none": with this pack the
-- chooser suggests nothing and the key plan binds nothing.
--
-- Ported:
--   * what the class can equip (Modules/Gear/Score.lua, G.CLASS_PROFICIENCY);
--   * the resource: a Priest is not in the old no-mana list
--     (Modules/Rotation/BuffItems.lua), so it is treated as a mana user;
--   * the kind of fighter, "caster" (Modules/Rotation/Engine.lua);
--   * the spell reagents kept in the bags (Modules/Items/Disposition.lua).
--
-- Not ported, on purpose:
--   * Resurrection (Modules/Rotation/Actions.lua): it is cast on another
--     player, and a pack holds nothing for other players;
--   * the food choice for a spirit healer (BuffItems.lua): it reads a role,
--     and this pack names no roles.
--
-- Evidence. Nothing here was read from the game by this file, and the old
-- tables name no source: every value is a "first guess".

local GUESS = "first guess"
local OLD = "carried over from the old shared tables on zflow; authorship unrecorded"

local pack = {
    provenance = {
        author = "Flow",
        date = "2026-11-21",
        method = "Ported from the Priest entries of the old shared tables on the zflow branch "
            .. "(Modules/Gear/Score.lua, Modules/Rotation/BuffItems.lua, Modules/Rotation/Engine.lua, "
            .. "Modules/Items/Disposition.lua). The old code has no Priest class module, so no rotation, "
            .. "spell, key, weight or talent row exists to port. Nothing added from outside the repository.",
        facts = "No value here was read from the game by this file and none comes from a list of client "
            .. "observations (the repository has none for this class). Every value is marked first guess and "
            .. "needs a check in the game client. No guide, database or other addon used.",
    },

    -- Not known: the old code names no Priest specialisation.
    roles = {},

    resources = {
        { name = "Mana", forms = { "none" }, evidence = GUESS, note = OLD },
    },

    maintain = {},

    -- Not known: no list to port. The chooser suggests nothing.
    lists = { default = {} },

    groups = {},

    heals = { self = {} },

    interrupts = {},
    breakers = {},
    dispels = {},

    -- Not known: no key rows to port. The key plan binds nothing.
    keys = {},

    weights = {},

    -- What the class can equip, by item class and subclass ids, as the old
    -- table gave them. Armor (4): 0, 1. Weapons (2): 4, 10, 15, 19, 20.
    proficiency = {
        evidence = GUESS, note = OLD,
        [4] = { [0] = true, [1] = true },
        [2] = { [4] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    },

    spells = {},

    talentBuilds = {},

    options = {},

    -- Beyond the sixteen rows, from the old shared tables.
    kind = { name = "caster", evidence = GUESS, note = OLD },
    reagents = {
        { item = "Light Feather", evidence = GUESS, note = OLD },
        { item = "Holy Candle", evidence = GUESS, note = OLD },
        { item = "Sacred Candle", evidence = GUESS, note = OLD },
    },

    -- What nobody has written down yet for this class.
    unknown = { "roles", "maintain", "lists", "heals", "interrupts", "breakers", "dispels", "keys", "weights",
                "spells", "talentBuilds" },
}

ns.Packs = ns.Packs or {}
ns.Packs.PRIEST = pack
if type(ns.Register) == "function" then ns:Register("classPack", "PRIEST", pack) end
