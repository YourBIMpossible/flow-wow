local _, ns = ...

-- Weapon master names: approximate, from Flow.
-- Source: Flow's Modules/Gear/WeaponSkills.lua lines 25-33, Flow commit
-- a529eea, copied as Flow has it (the names and the item subclass numbers
-- of the weapon kinds each teaches; Flow's own note on it: "classic data,
-- approximate"). Nothing is added, corrected or extended here.
-- Brought in by the owner's ruling, lead section 602: the one table of
-- weapon masters Z-Flow carries. NAMES ONLY: no place is in this file. A
-- place comes only from the player's own Questie at run time, or from a
-- weapon master the player visited (Nav/WeaponMasterStep.lua, through
-- Nav/ProfStep.lua N.ProfPlace). The city after each line is Flow's own
-- comment, not read by anything.
-- Item subclasses: 0 Axes, 1 Two-Handed Axes, 2 Bows, 3 Guns, 4 Maces,
-- 5 Two-Handed Maces, 6 Polearms, 7 Swords, 8 Two-Handed Swords, 10 Staves,
-- 13 Fist Weapons, 15 Daggers, 16 Thrown, 18 Crossbows, 19 Wands.
--
--   N.WeaponMasterNames = { [NPC name] = { skills = { [subclass] = true } } }
ns.Nav = ns.Nav or {}
local N = ns.Nav

local function teaches(...)
    local t = {}
    for _, s in ipairs({ ... }) do t[s] = true end
    return t
end

N.WeaponMasterNames = {
    -- Alliance
    ["Woo Ping"] = { skills = teaches(6, 7, 8, 10, 15, 18) },          -- Stormwind
    ["Buliwyf Stonehand"] = { skills = teaches(0, 1, 3, 4, 5, 13) },   -- Ironforge
    ["Bixi Wobblebonk"] = { skills = teaches(15, 16, 18) },            -- Ironforge
    ["Ilyenia Moonfire"] = { skills = teaches(2, 10, 13, 15) },        -- Darnassus
    -- Horde
    ["Hanashi"] = { skills = teaches(0, 1, 2, 10, 16) },               -- Orgrimmar
    ["Sayoc"] = { skills = teaches(0, 1, 2, 13, 15, 16) },             -- Orgrimmar
    ["Ansekhwa"] = { skills = teaches(3, 4, 5, 10) },                  -- Thunder Bluff
    ["Archibald"] = { skills = teaches(6, 7, 8, 15, 18) },             -- Undercity
}
