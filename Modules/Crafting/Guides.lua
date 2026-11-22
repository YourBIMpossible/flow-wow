-- Profession levelling data: what to make at each skill, what it takes, and
-- where those materials come from. The planner (SkillPlan.lua) works from
-- this plus what you have right now (skill, bags, quests, position) to put
-- gather / smelt / craft steps on the route.
--
-- There is no fixed path here: which recipe to make at each skill is worked
-- out by SkillPlan.lua (SP.Score) from the chance of a skill point, what the
-- materials cost and what's in your bags, over these recipes and the ones
-- your profession window showed (Recipes.lua). There are no colour
-- thresholds here: a recipe's colour (and so its chance of a skill point) is
-- only what the profession window reported at the skill Flow saw it at.
-- The skill a recipe is learned at isn't listed here either: Flow reads it
-- from the trainer's window (Trainer.lua) or the recipe item's tooltip, and
-- until then it is unknown (SkillPlan.lua: SP.LearnSkill).
-- Nor are node or smelting skills, how much a node gives, which mobs drop a
-- material or how often, or vendor prices: none of those were read from the
-- game by Flow, so they are unknown until it sees them (prices at a vendor,
-- drops in your own loot).
--
-- Extend by registering more:
--   ns:Register("profGuide", "<Profession>", {
--       kind = "craft" | "gather",
--       tool = itemID,                       -- needed in your bags (craft)
--       artisan = { Horde = "name", Alliance = "name" }, -- teaches Artisan (225 -> 300) instead of the city trainers
--       nodes = { { item = itemID } },       -- gathered for skill (Mining's veins); no skill listed
--       steps = { { recipe, item, mats = { [itemID] = n },
--                   faction = "Horde" | "Alliance",               -- only that side
--                   recipeItem = itemID,                          -- bought, not trained
--                   quest = { id, npc },                          -- the recipe is that quest's reward
--                   trainer = { Horde = "name", Alliance = "name" }, -- taught there, not by a city trainer
--                   tool = itemID,                                -- this recipe needs it in your bags (a rod, the Spanner)
--                   station = "anvil" | "forge" | "fire" | nil } } })
--   ns:Register("itemSource", itemID, {
--       name, gather = "<Profession>", objects = { objectIDs }, node = "name",
--       smelt = { from = itemID, n = count, spell = "Smelt X" },
--       looted = true,                      -- comes off mobs; which ones is unknown
--       drops = { "NPC name", ... },        -- (optional) mobs that drop it; none are listed here
--       fished = true, share = 0.7,         -- caught while levelling Fishing
--       made = "<Profession>",              -- you make it (another step's item)
--       vendor = true })                     -- bought (Questie lists the vendors)

local _, ns = ...

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local COPPER_VEIN  = { 1731, 2055, 3763, 103713 }
local TIN_VEIN     = { 1732, 2054, 3764, 103711 }
local IRON_VEIN    = { 1735 }
local MITHRIL_VEIN = { 2040 }
local THORIUM_VEIN = { 324, 175404 }

ns:Register("itemSource", 2770, { name = "Copper Ore", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein" })
ns:Register("itemSource", 2835, { name = "Rough Stone", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein" })
ns:Register("itemSource", 2840, { name = "Copper Bar", smelt = { from = 2770, n = 1, spell = "Smelt Copper" } })
ns:Register("itemSource", 2771, { name = "Tin Ore", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein" })
ns:Register("itemSource", 2836, { name = "Coarse Stone", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein" })
ns:Register("itemSource", 3576, { name = "Tin Bar", smelt = { from = 2771, n = 1, spell = "Smelt Tin" } })
ns:Register("itemSource", 2772, { name = "Iron Ore", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit" })
ns:Register("itemSource", 2838, { name = "Heavy Stone", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit" })
ns:Register("itemSource", 3575, { name = "Iron Bar", smelt = { from = 2772, n = 1, spell = "Smelt Iron" } })
ns:Register("itemSource", 3858, { name = "Mithril Ore", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit" })
ns:Register("itemSource", 7912, { name = "Solid Stone", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit" })
ns:Register("itemSource", 3860, { name = "Mithril Bar", smelt = { from = 3858, n = 1, spell = "Smelt Mithril" } })
ns:Register("itemSource", 12365, { name = "Dense Stone", gather = "Mining", objects = THORIUM_VEIN, node = "Thorium Vein" })
ns:Register("itemSource", 10620, { name = "Thorium Ore", gather = "Mining", objects = THORIUM_VEIN, node = "Thorium Vein" })
ns:Register("itemSource", 12359, { name = "Thorium Bar", smelt = { from = 10620, n = 1, spell = "Smelt Thorium" } })
-- Made by an earlier Blacksmithing step.
ns:Register("itemSource", 3486, { name = "Heavy Grinding Stone", made = "Blacksmithing" })

-- Looted from mobs. Which mobs, and how often, isn't listed: Flow has no
-- record of its own of who drops these, so the step says the source is
-- unknown. A `drops = { names }` list still works for an entry that has one,
-- and kills are then counted from your own loot (SkillPlan.lua: SP.RecordLoot).
ns:Register("itemSource", 2589, { name = "Linen Cloth", looted = true })
ns:Register("itemSource", 2672, { name = "Stringy Wolf Meat", looted = true })
ns:Register("itemSource", 769,  { name = "Chunk of Boar Meat", looted = true })
ns:Register("itemSource", 5467, { name = "Kodo Meat", looted = true })
ns:Register("itemSource", 5469, { name = "Strider Meat", looted = true })
ns:Register("itemSource", 5470, { name = "Thunder Lizard Tail", looted = true })
ns:Register("itemSource", 3173, { name = "Bear Meat", looted = true })
ns:Register("itemSource", 2674, { name = "Crawler Meat", looted = true })
ns:Register("itemSource", 2675, { name = "Crawler Claw", looted = true })
ns:Register("itemSource", 1015, { name = "Lean Wolf Flank", looted = true })
ns:Register("itemSource", 3685, { name = "Raptor Egg", looted = true })
ns:Register("itemSource", 12184, { name = "Raptor Flesh", looted = true })

-- Caught while levelling Fishing (share: roughly how many catches are this fish
-- in the water you fish at that skill). Counts against the meat Cooking would
-- otherwise farm.
ns:Register("itemSource", 6291, { name = "Raw Brilliant Smallfish", fished = true, share = 0.7 })
ns:Register("itemSource", 6289, { name = "Raw Longjaw Mud Snapper", fished = true, share = 0.6 })
ns:Register("itemSource", 6308, { name = "Raw Bristle Whisker Catfish", fished = true, share = 0.5 })
ns:Register("itemSource", 8365, { name = "Raw Mithril Head Trout", fished = true, share = 0.4 })
ns:Register("itemSource", 4603, { name = "Raw Spotted Yellowtail", fished = true, share = 0.5 })
ns:Register("itemSource", 13759, { name = "Raw Nightfin Snapper", fished = true, share = 0.4 })
ns:Register("itemSource", 13760, { name = "Raw Sunscale Salmon", fished = true, share = 0.4 })
ns:Register("itemSource", 13888, { name = "Darkclaw Lobster", fished = true, share = 0.3 })
ns:Register("itemSource", 13889, { name = "Raw Whitescale Salmon", fished = true, share = 0.4 })
ns:Register("itemSource", 13893, { name = "Large Raw Mightfish", fished = true, share = 0.3 })

-- Bought. No price is listed: Flow keeps the price a vendor's window showed
-- you (SkillPlan.lua: SP.Price), and until then the cost is unknown.
ns:Register("itemSource", 2678, { name = "Mild Spices", vendor = true })
ns:Register("itemSource", 2692, { name = "Hot Spices", vendor = true })
ns:Register("itemSource", 4536, { name = "Shiny Red Apple", vendor = true })
ns:Register("itemSource", 2665, { name = "Stormwind Seasoning Herbs", vendor = true })
ns:Register("itemSource", 2605, { name = "Green Dye", vendor = true })
ns:Register("itemSource", 3713, { name = "Soothing Spices", vendor = true })
ns:Register("itemSource", 159, { name = "Refreshing Spring Water", vendor = true })
-- Recipes and manuals.
-- Expert (150 -> 225) for these three comes from a book, not a trainer.
ns:Register("itemSource", 16072, { name = "Expert Cookbook", vendor = true })
ns:Register("itemSource", 16084, { name = "Expert First Aid - Under Wraps", vendor = true })
ns:Register("itemSource", 16083, { name = "Expert Fishing - The Bass and You", vendor = true })
ns:Register("itemSource", 6325, { name = "Recipe: Brilliant Smallfish", vendor = true })
ns:Register("itemSource", 6328, { name = "Recipe: Longjaw Mud Snapper", vendor = true })
ns:Register("itemSource", 6330, { name = "Recipe: Bristle Whisker Catfish", vendor = true })
ns:Register("itemSource", 17062, { name = "Recipe: Mithril Head Trout", vendor = true })
ns:Register("itemSource", 5484, { name = "Recipe: Roasted Kodo Meat", vendor = true })
ns:Register("itemSource", 5486, { name = "Recipe: Strider Stew", vendor = true })
ns:Register("itemSource", 5488, { name = "Recipe: Crispy Lizard Tail", vendor = true })
ns:Register("itemSource", 6892, { name = "Recipe: Smoked Bear Meat", vendor = true })
ns:Register("itemSource", 2698, { name = "Recipe: Cooked Crab Claw", vendor = true })
ns:Register("itemSource", 2701, { name = "Recipe: Seasoned Wolf Kabob", vendor = true })
ns:Register("itemSource", 3682, { name = "Recipe: Curiously Tasty Omelet", vendor = true })
ns:Register("itemSource", 12228, { name = "Recipe: Roast Raptor", vendor = true })
ns:Register("itemSource", 16112, { name = "Manual: Heavy Silk Bandage", vendor = true })
ns:Register("itemSource", 16113, { name = "Manual: Mageweave Bandage", vendor = true })
-- Tools.
ns:Register("itemSource", 5956, { name = "Blacksmith Hammer", vendor = true })
ns:Register("itemSource", 2901, { name = "Mining Pick", vendor = true })
ns:Register("itemSource", 6256, { name = "Fishing Pole", vendor = true })
ns:Register("itemSource", 6529, { name = "Shiny Bauble", vendor = true })   -- lure
ns:Register("itemSource", 4470, { name = "Simple Wood", vendor = true })      -- for Basic Campfire

-------------------------------------------------------------------------------
-- Professions
-------------------------------------------------------------------------------

ns:Register("profGuide", "Blacksmithing", {
    kind = "craft", tool = 5956,
    steps = {
        { recipe = "Rough Sharpening Stone", item = 2862, mats = { [2835] = 1 } },
        { recipe = "Rough Grinding Stone", item = 3470, mats = { [2835] = 2 } },
        { recipe = "Coarse Sharpening Stone", item = 2863, mats = { [2836] = 1 } },
        { recipe = "Coarse Grinding Stone", item = 3478, mats = { [2836] = 2 } },
        { recipe = "Runed Copper Belt", item = 2857, mats = { [2840] = 10 },
          station = "anvil" },
        { recipe = "Rough Bronze Leggings", item = 2865, mats = { [2841] = 6 },
          station = "anvil" },
        { recipe = "Heavy Grinding Stone", item = 3486, mats = { [2838] = 3 } },
        { recipe = "Green Iron Leggings", item = 3842,
          mats = { [3575] = 8, [3486] = 1, [2605] = 1 }, station = "anvil" },
        { recipe = "Green Iron Bracers", item = 3835,
          mats = { [3575] = 6, [2605] = 1 }, station = "anvil" },
        { recipe = "Solid Grinding Stone", item = 7966, mats = { [7912] = 4 } },
        { recipe = "Heavy Mithril Gauntlet", item = 7919,
          mats = { [3860] = 6, [4338] = 4 }, station = "anvil" },
        { recipe = "Mithril Coif", item = 7931,
          mats = { [3860] = 10, [4338] = 6 }, station = "anvil" },
        { recipe = "Dense Sharpening Stone", item = 12404, mats = { [12365] = 1 } },
        { recipe = "Heavy Mithril Boots", item = 7933,
          mats = { [3860] = 14, [4304] = 4 }, station = "anvil" },
    },
})

ns:Register("profGuide", "Mining", {
    kind = "gather", tool = 2901,
    -- Nodes raise Mining; smelting does too (craft-like steps below).
    nodes = {
        { item = 2770 },
        { item = 2771 },
        { item = 2772 },
        { item = 3858 },
        { item = 10620 },
    },
    steps = {
        { recipe = "Smelt Copper", item = 2840, mats = { [2770] = 1 }, station = "forge" },
        { recipe = "Smelt Tin", item = 3576, mats = { [2771] = 1 }, station = "forge" },
    },
})

-- From 240 the Triage doctors teach the bandages, not the city trainers.
local TRIAGE = { Horde = "Doctor Gregory Victor", Alliance = "Doctor Gustaf VanHowzen" }
ns:Register("profGuide", "First Aid", {
    kind = "craft",
    steps = {
        { recipe = "Linen Bandage", item = 1251, mats = { [2589] = 1 } },
        { recipe = "Heavy Linen Bandage", item = 2581, mats = { [2589] = 2 } },
        { recipe = "Wool Bandage", item = 3530, mats = { [2592] = 1 } },
        { recipe = "Heavy Wool Bandage", item = 3531, mats = { [2592] = 2 } },
        { recipe = "Silk Bandage", item = 6450, mats = { [4306] = 1 } },
        { recipe = "Heavy Silk Bandage", item = 6451, mats = { [4306] = 2 },
          recipeItem = 16112 },
        { recipe = "Mageweave Bandage", item = 8544, mats = { [4338] = 1 },
          recipeItem = 16113 },
        { recipe = "Heavy Mageweave Bandage", item = 8545, mats = { [4338] = 2 },
          trainer = TRIAGE },
        { recipe = "Runecloth Bandage", item = 14529, mats = { [14047] = 1 },
          trainer = TRIAGE },
        { recipe = "Heavy Runecloth Bandage", item = 14530, mats = { [14047] = 2 },
          trainer = TRIAGE },
    },
})

-- Some recipes and meats are one side's only (`faction`). Fish you catch
-- levels Cooking as well as meat, but Flow doesn't send you fishing for
-- Cooking: a fish recipe counts only when the fish is already in your bags.
ns:Register("profGuide", "Cooking", {
    kind = "craft",
    steps = {
        { recipe = "Charred Wolf Meat", item = 2679, mats = { [2672] = 1 },
          station = "fire" },
        { recipe = "Roasted Boar Meat", item = 2681, mats = { [769] = 1 },
          station = "fire" },
        { recipe = "Brilliant Smallfish", item = 6290, mats = { [6291] = 1 },
          station = "fire", recipeItem = 6325 },
        -- Horde.
        { recipe = "Roasted Kodo Meat", item = 5474, mats = { [5467] = 1, [2678] = 1 },
          station = "fire", recipeItem = 5484, faction = "Horde" },
        { recipe = "Strider Stew", item = 5477, mats = { [5469] = 1, [4536] = 1 },
          station = "fire", recipeItem = 5486, faction = "Horde" },
        { recipe = "Crispy Lizard Tail", item = 5479, mats = { [5470] = 1, [2692] = 1 },
          station = "fire", recipeItem = 5488, faction = "Horde" },
        -- Alliance.
        { recipe = "Smoked Bear Meat", item = 6890, mats = { [3173] = 1 },
          station = "fire", recipeItem = 6892, faction = "Alliance" },
        { recipe = "Crab Cake", item = 2683, mats = { [2674] = 1, [2678] = 1 },
          station = "fire", faction = "Alliance" },
        { recipe = "Cooked Crab Claw", item = 2682, mats = { [2675] = 1, [2678] = 1 },
          station = "fire", recipeItem = 2698, faction = "Alliance" },
        { recipe = "Seasoned Wolf Kabob", item = 1017, mats = { [1015] = 2, [2665] = 1 },
          station = "fire", recipeItem = 2701, faction = "Alliance" },
        -- Both.
        { recipe = "Curiously Tasty Omelet", item = 3665, mats = { [3685] = 1, [2692] = 1 },
          station = "fire", recipeItem = 3682 },
        { recipe = "Roast Raptor", item = 12210, mats = { [12184] = 1, [2692] = 1 },
          station = "fire", recipeItem = 12228 },
        -- Fish: candidates only while you carry the fish (SP.Candidates).
        { recipe = "Longjaw Mud Snapper", item = 4592, mats = { [6289] = 1 },
          station = "fire", recipeItem = 6328 },
        { recipe = "Bristle Whisker Catfish", item = 4593, mats = { [6308] = 1 },
          station = "fire", recipeItem = 6330 },
        { recipe = "Mithril Head Trout", item = 8364, mats = { [8365] = 1 },
          station = "fire", recipeItem = 17062 },
    },
})

ns:Register("profGuide", "Fishing", { kind = "gather", spots = true, tool = 6256, lure = 6529,
    -- Keep up with the water you'll fish in, not with crafting: starting-zone
    -- lakes need ~25 so fish don't get away, the next zones ~75, then ~150.
    pace = { { 1, 1 }, { 10, 25 }, { 20, 75 }, { 30, 150 }, { 40, 225 }, { 50, 300 } },
    tip = "Tip: a Shiny Bauble (+25 Fishing for 10 minutes) catches more while your skill is low. Flow's key puts it on your pole." })

ns:Register("profGuide", "Herbalism", { kind = "gather", spots = true })

-- Skinning has no nodes or spots: you skin the beasts you kill, and what you
-- can skin follows from the beast's level (SP.SkinSkill: the game's general
-- rule, which the corpse's own tooltip, "Requires Skinning N", confirms in
-- game). No mob or zone lists: the plan is the skill band for your level and
-- the beasts your quests bring you to. The knife is the one Disposition.lua
-- already knows (7005).
ns:Register("profGuide", "Skinning", { kind = "gather", skin = true, tool = 7005,
    tip = "Loot a beast first, then skin it: the game lets you skin only an empty corpse." })
