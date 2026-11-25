local _, ns = ...

-- Riding trainer and mount vendor names by race: approximate, from Flow.
-- Source: Flow's Modules/Nav/Mounts.lua lines 31-38, Flow commit a529eea,
-- copied as Flow has it (the race tokens, the trainer, the vendor and
-- Flow's word for the mount). Nothing is added, corrected or extended.
-- Brought in by the owner's ruling, lead section 602: the one table of
-- riding names Z-Flow carries. NAMES ONLY: no place, level or price is in
-- this file. A place comes only from the player's own Questie at run time
-- (Nav/RidingStep.lua, through Nav/ProfStep.lua N.ProfPlace), and a price
-- only from the trainer window the player opened.
--
-- Flow reads the race as a token (the second answer of UnitRace). Z-Flow's
-- client gives only the race number (client.raceId(), the third answer),
-- so RACE below maps the game's race numbers to Flow's tokens for the
-- eight races Flow lists. That map is Z-Flow's own, not Flow's; a number
-- not in it has no name, and the riding step stays as it was.
--
--   N.RidingNames.mount = { [race token] = { trainer, vendor, what } }
--   N.RidingNames.RACE  = { [race number] = race token }
-- When this file loads, each trainer's name is given to N.ProfPlace.Want,
-- so the one pass over Questie's NPCs keeps that NPC's places. The vendors
-- are not asked for: nothing reads them yet.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local R = {}
N.RidingNames = R

R.mount = {
    Human    = { trainer = "Randal Hunter",       vendor = "Katie Hunter",        what = "a horse" },
    Dwarf    = { trainer = "Ultham Ironhorn",     vendor = "Veron Amberstill",    what = "a ram" },
    NightElf = { trainer = "Jartsam",             vendor = "Lelanai",             what = "a nightsaber" },
    Gnome    = { trainer = "Binjy Featherwhistle", vendor = "Milli Featherwhistle", what = "a mechanostrider" },
    Orc      = { trainer = "Kildar",              vendor = "Ogunaro Wolfrunner",  what = "a wolf" },
    Troll    = { trainer = "Xar'Ti",              vendor = "Zjolnir",             what = "a raptor" },
    Tauren   = { trainer = "Kar Stormsinger",     vendor = "Harb Clawhoof",       what = "a kodo" },
    Scourge  = { trainer = "Velma Warnam",        vendor = "Zachariah Post",      what = "a skeletal horse" },
}

R.RACE = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf",
           [5] = "Scourge", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }

local PP = N.ProfPlace
if type(PP) == "table" and type(PP.Want) == "function" then
    for _, row in pairs(R.mount) do PP.Want(row.trainer) end
end
