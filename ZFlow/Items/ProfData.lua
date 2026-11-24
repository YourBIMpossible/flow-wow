local _, ns = ...

-- ProfData (lead section 449, P-PATH-1): the factual rows the profession
-- path (Items/ProfPath.lua) reads. Every row is a first guess, from Flow,
-- needs a game check: ported from Flow's Modules/Crafting/Guides.lua and
-- GuidesCrafting.lua (commit e4c52c99), with Flow's guide path ("use") left
-- out. The path picks its own recipe at each skill from these facts.
--
--   ProfData.PROFS[profession] = {
--       kind = "craft" | "gather", tool = itemID,
--       nodes = { { item, learn, yellow, green, grey } },          -- Mining
--       steps = { { recipe, item, learn, yellow, green, grey,
--                   mats = { [itemID] = n }, recipeItem = itemID,
--                   trainer = { Horde = "name", Alliance = "name" },
--                   station = "anvil" | "forge" | "fire", tool = itemID,
--                   faction = "Horde" | "Alliance" } } }
--   ProfData.SOURCES[itemID] = { name, gather = "<Profession>", objects,
--       node, skill, yield, smelt = { from, n, skill, spell },
--       drops = { "NPC name" }, rate, fished, share, made = "<Profession>",
--       vendor = true, price = copper (approximate) }
--   ProfData.ShippedRows() -> { [profession] = { { name, skill } } }, the
--       shape of RecipeFacts.SHIPPED (not plugged in here).
--
-- Colours the player saw in game (Items/RecipeColours.lua) win over the
-- learn / yellow / green / grey numbers here. Not tested in game.
local ProfData = {}
ns.ProfData = ProfData

ProfData.NOTE = "first guess, from Flow, needs a game check"

local S = {}
local P = {}
ProfData.SOURCES = S
ProfData.PROFS = P

local COPPER_VEIN  = { 1731, 2055, 3763, 103713 }
local TIN_VEIN     = { 1732, 2054, 3764, 103711 }
local IRON_VEIN    = { 1735 }
local MITHRIL_VEIN = { 2040 }
local THORIUM_VEIN = { 324, 175404 }

S[2770] = { name = "Copper Ore", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 2 }
S[2835] = { name = "Rough Stone", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 0.8 }
S[2840] = { name = "Copper Bar", smelt = { from = 2770, n = 1, skill = 1, spell = "Smelt Copper" } }
S[2771] = { name = "Tin Ore", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 2 }
S[2836] = { name = "Coarse Stone", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 0.8 }
S[3576] = { name = "Tin Bar", smelt = { from = 2771, n = 1, skill = 65, spell = "Smelt Tin" } }
S[2772] = { name = "Iron Ore", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 2 }
S[2838] = { name = "Heavy Stone", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 0.8 }
S[3575] = { name = "Iron Bar", smelt = { from = 2772, n = 1, skill = 125, spell = "Smelt Iron" } }
S[3858] = { name = "Mithril Ore", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit", skill = 175, yield = 2 }
S[7912] = { name = "Solid Stone", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit", skill = 175, yield = 0.8 }
S[3860] = { name = "Mithril Bar", smelt = { from = 3858, n = 1, skill = 175, spell = "Smelt Mithril" } }
S[12365] = { name = "Dense Stone", gather = "Mining", objects = THORIUM_VEIN, node = "Thorium Vein", skill = 245, yield = 0.8 }
S[10620] = { name = "Thorium Ore", gather = "Mining", objects = THORIUM_VEIN, node = "Thorium Vein", skill = 245, yield = 2 }
S[12359] = { name = "Thorium Bar", smelt = { from = 10620, n = 1, skill = 250, spell = "Smelt Thorium" } }
S[3486] = { name = "Heavy Grinding Stone", made = "Blacksmithing" }
S[2589] = { name = "Linen Cloth", drops = {
    "Defias Thug", "Defias Cutpurse", "Defias Bandit", "Defias Rogue Wizard", "Defias Smuggler",
    "Kobold Vermin", "Kobold Worker", "Kobold Laborer", "Kobold Tunneler", "Riverpaw Gnoll", "Riverpaw Runt",
    "Murloc Streamrunner", "Murloc Forager" } }
S[2672] = { name = "Stringy Wolf Meat", rate = 0.35, drops = { "Young Wolf", "Timber Wolf", "Prowler", "Gray Forest Wolf" } }
S[769] = { name = "Chunk of Boar Meat", rate = 0.45, drops = { "Stonetusk Boar", "Rockhide Boar", "Small Crag Boar" } }
S[5467] = { name = "Kodo Meat", rate = 0.5, drops = { "Barrens Kodo", "Greater Barrens Kodo" } }
S[5469] = { name = "Strider Meat", rate = 0.5, drops = {
    "Plainstrider", "Adult Plainstrider", "Elder Plainstrider", "Fleeting Plainstrider", "Ornery Plainstrider" } }
S[5470] = { name = "Thunder Lizard Tail", rate = 0.5, drops = { "Thunder Lizard", "Lightning Hide", "Thunderhead", "Stormsnout" } }
S[3173] = { name = "Bear Meat", rate = 0.4, drops = {
    "Young Forest Bear", "Black Bear", "Elder Black Bear", "Grizzled Black Bear", "Thistle Bear",
    "Ferocious Grizzled Bear", "Giant Grizzled Bear" } }
local CRAWLERS = { "Sand Crawler", "Shore Crawler", "Pygmy Tide Crawler", "Tide Crawler", "Encrusted Tide Crawler" }
S[2674] = { name = "Crawler Meat", rate = 0.35, drops = CRAWLERS }
S[2675] = { name = "Crawler Claw", rate = 0.35, drops = CRAWLERS }
S[1015] = { name = "Lean Wolf Flank", rate = 0.35, drops = { "Coyote", "Coyote Packleader", "Starving Dire Wolf", "Rabid Dire Wolf" } }
S[3685] = { name = "Raptor Egg", rate = 0.3, drops = {
    "Mottled Raptor", "Mottled Screecher", "Mottled Scytheclaw", "Highland Raptor", "Highland Thrasher", "Highland Strider" } }
S[12184] = { name = "Raptor Flesh", rate = 0.4, drops = { "Jungle Stalker", "Lashtail Raptor", "Highland Fleshstalker", "Highland Thrasher" } }
S[6291] = { name = "Raw Brilliant Smallfish", fished = true, share = 0.7 }
S[6289] = { name = "Raw Longjaw Mud Snapper", fished = true, share = 0.6 }
S[6308] = { name = "Raw Bristle Whisker Catfish", fished = true, share = 0.5 }
S[8365] = { name = "Raw Mithril Head Trout", fished = true, share = 0.4 }
S[4603] = { name = "Raw Spotted Yellowtail", fished = true, share = 0.5 }
S[13759] = { name = "Raw Nightfin Snapper", fished = true, share = 0.4 }
S[13760] = { name = "Raw Sunscale Salmon", fished = true, share = 0.4 }
S[13888] = { name = "Darkclaw Lobster", fished = true, share = 0.3 }
S[13889] = { name = "Raw Whitescale Salmon", fished = true, share = 0.4 }
S[13893] = { name = "Large Raw Mightfish", fished = true, share = 0.3 }
S[2678] = { name = "Mild Spices", vendor = true, price = 10 }
S[2692] = { name = "Hot Spices", vendor = true, price = 40 }
S[4536] = { name = "Shiny Red Apple", vendor = true, price = 25 }
S[2665] = { name = "Stormwind Seasoning Herbs", vendor = true, price = 20 }
S[2605] = { name = "Green Dye", vendor = true, price = 100 }
S[3713] = { name = "Soothing Spices", vendor = true, price = 160 }
S[159] = { name = "Refreshing Spring Water", vendor = true, price = 25 }
S[16072] = { name = "Expert Cookbook", vendor = true, price = 10000 }
S[16084] = { name = "Expert First Aid - Under Wraps", vendor = true, price = 10000 }
S[16083] = { name = "Expert Fishing - The Bass and You", vendor = true, price = 10000 }
S[6325] = { name = "Recipe: Brilliant Smallfish", vendor = true, price = 40 }
S[6328] = { name = "Recipe: Longjaw Mud Snapper", vendor = true, price = 400 }
S[6330] = { name = "Recipe: Bristle Whisker Catfish", vendor = true, price = 1200 }
S[17062] = { name = "Recipe: Mithril Head Trout", vendor = true, price = 2200 }
S[5484] = { name = "Recipe: Roasted Kodo Meat", vendor = true, price = 240 }
S[5486] = { name = "Recipe: Strider Stew", vendor = true, price = 440 }
S[5488] = { name = "Recipe: Crispy Lizard Tail", vendor = true, price = 400 }
S[6892] = { name = "Recipe: Smoked Bear Meat", vendor = true, price = 250 }
S[2698] = { name = "Recipe: Cooked Crab Claw", vendor = true, price = 400 }
S[2701] = { name = "Recipe: Seasoned Wolf Kabob", vendor = true, price = 1600 }
S[3682] = { name = "Recipe: Curiously Tasty Omelet", vendor = true, price = 1600 }
S[12228] = { name = "Recipe: Roast Raptor", vendor = true, price = 5000 }
S[16110] = { name = "Recipe: Monster Omelet", vendor = true, price = 12000 }
S[18046] = { name = "Recipe: Tender Wolf Steak", vendor = true, price = 12000 }
S[13939] = { name = "Recipe: Spotted Yellowtail", vendor = true, price = 16000 }
S[13945] = { name = "Recipe: Nightfin Soup", vendor = true, price = 20000 }
S[13946] = { name = "Recipe: Poached Sunscale Salmon", vendor = true, price = 20000 }
S[13947] = { name = "Recipe: Lobster Stew", vendor = true, price = 20000 }
S[13948] = { name = "Recipe: Mightfish Steak", vendor = true, price = 20000 }
S[13949] = { name = "Recipe: Baked Salmon", vendor = true, price = 20000 }
S[16112] = { name = "Manual: Heavy Silk Bandage", vendor = true, price = 2200 }
S[16113] = { name = "Manual: Mageweave Bandage", vendor = true, price = 5000 }
S[5956] = { name = "Blacksmith Hammer", vendor = true, price = 18 }
S[2901] = { name = "Mining Pick", vendor = true, price = 16 }
S[6256] = { name = "Fishing Pole", vendor = true, price = 23 }
S[6529] = { name = "Shiny Bauble", vendor = true, price = 100 }
S[4470] = { name = "Simple Wood", vendor = true, price = 38 }
P["Blacksmithing"] = {
    kind = "craft", tool = 5956,
    steps = {
        { recipe = "Rough Sharpening Stone", item = 2862, learn = 1, yellow = 15, green = 35, grey = 55, mats = { [2835] = 1 } },
        { recipe = "Rough Grinding Stone", item = 3470, learn = 25, yellow = 45, green = 65, grey = 85, mats = { [2835] = 2 } },
        { recipe = "Coarse Sharpening Stone", item = 2863, learn = 65, yellow = 65, green = 72, grey = 80, mats = { [2836] = 1 } },
        { recipe = "Coarse Grinding Stone", item = 3478, learn = 75, yellow = 75, green = 87, grey = 100, mats = { [2836] = 2 } },
        { recipe = "Runed Copper Belt", item = 2857, learn = 70, yellow = 110, green = 130, grey = 150, mats = { [2840] = 10 },
          station = "anvil" },
        { recipe = "Rough Bronze Leggings", item = 2865, learn = 105, yellow = 145, green = 160, grey = 175, mats = { [2841] = 6 },
          station = "anvil" },
        { recipe = "Heavy Grinding Stone", item = 3486, learn = 125, yellow = 125, green = 137, grey = 150, mats = { [2838] = 3 } },
        { recipe = "Green Iron Leggings", item = 3842, learn = 155, yellow = 180, green = 192, grey = 205,
          mats = { [3575] = 8, [3486] = 1, [2605] = 1 }, station = "anvil" },
        { recipe = "Green Iron Bracers", item = 3835, learn = 165, yellow = 190, green = 202, grey = 215,
          mats = { [3575] = 6, [2605] = 1 }, station = "anvil" },
        { recipe = "Solid Grinding Stone", item = 7966, learn = 200, yellow = 200, green = 205, grey = 210, mats = { [7912] = 4 } },
        { recipe = "Heavy Mithril Gauntlet", item = 7919, learn = 205, yellow = 225, green = 235, grey = 245,
          mats = { [3860] = 6, [4338] = 4 }, station = "anvil" },
        { recipe = "Mithril Coif", item = 7931, learn = 230, yellow = 250, green = 260, grey = 270,
          mats = { [3860] = 10, [4338] = 6 }, station = "anvil" },
        { recipe = "Dense Sharpening Stone", item = 12404, learn = 250, yellow = 255, green = 257, grey = 260, mats = { [12365] = 1 } },
        { recipe = "Heavy Mithril Boots", item = 7933, learn = 235, yellow = 255, green = 265, grey = 275,
          mats = { [3860] = 14, [4304] = 4 }, station = "anvil" },
        { recipe = "Imperial Plate Belt", item = 12424, learn = 265, yellow = 285, green = 292, grey = 300,
          mats = { [12359] = 22, [8170] = 6, [7909] = 1 }, station = "anvil", recipeItem = 12688 },
        { recipe = "Imperial Plate Bracers", item = 12425, learn = 270, yellow = 290, green = 295, grey = 300,
          mats = { [12359] = 20, [7910] = 1 }, station = "anvil", recipeItem = 12690 },
        { recipe = "Imperial Plate Boots", item = 12426, learn = 295, yellow = 300, green = 300, grey = 300,
          mats = { [12359] = 34, [7910] = 1, [7909] = 1 }, station = "anvil", recipeItem = 12700 },
    },
}
P["Mining"] = {
    kind = "gather", tool = 2901,
    nodes = {
        { item = 2770, learn = 1, yellow = 25, green = 50, grey = 100 },
        { item = 2771, learn = 65, yellow = 90, green = 115, grey = 165 },
        { item = 2772, learn = 125, yellow = 150, green = 175, grey = 225 },
        { item = 3858, learn = 175, yellow = 200, green = 225, grey = 275 },
        { item = 10620, learn = 245, yellow = 270, green = 295, grey = 345 },
    },
    steps = {
        { recipe = "Smelt Copper", item = 2840, learn = 1, yellow = 25, green = 47, grey = 70, mats = { [2770] = 1 }, station = "forge" },
        { recipe = "Smelt Tin", item = 3576, learn = 65, yellow = 65, green = 70, grey = 75, mats = { [2771] = 1 }, station = "forge" },
    },
}
local TRIAGE = { Horde = "Doctor Gregory Victor", Alliance = "Doctor Gustaf VanHowzen" }
P["First Aid"] = {
    kind = "craft",
    steps = {
        { recipe = "Linen Bandage", item = 1251, learn = 1, yellow = 30, green = 45, grey = 60, mats = { [2589] = 1 } },
        { recipe = "Heavy Linen Bandage", item = 2581, learn = 40, yellow = 50, green = 75, grey = 100, mats = { [2589] = 2 } },
        { recipe = "Wool Bandage", item = 3530, learn = 80, yellow = 80, green = 115, grey = 150, mats = { [2592] = 1 } },
        { recipe = "Heavy Wool Bandage", item = 3531, learn = 115, yellow = 115, green = 150, grey = 185, mats = { [2592] = 2 } },
        { recipe = "Silk Bandage", item = 6450, learn = 150, yellow = 150, green = 180, grey = 210, mats = { [4306] = 1 } },
        { recipe = "Heavy Silk Bandage", item = 6451, learn = 180, yellow = 180, green = 210, grey = 240, mats = { [4306] = 2 },
          recipeItem = 16112 },
        { recipe = "Mageweave Bandage", item = 8544, learn = 210, yellow = 210, green = 240, grey = 270, mats = { [4338] = 1 },
          recipeItem = 16113 },
        { recipe = "Heavy Mageweave Bandage", item = 8545, learn = 240, yellow = 240, green = 270, grey = 300, mats = { [4338] = 2 },
          trainer = TRIAGE },
        { recipe = "Runecloth Bandage", item = 14529, learn = 260, yellow = 260, green = 290, grey = 320, mats = { [14047] = 1 },
          trainer = TRIAGE },
        { recipe = "Heavy Runecloth Bandage", item = 14530, learn = 290, yellow = 290, green = 320, grey = 350, mats = { [14047] = 2 },
          trainer = TRIAGE },
    },
}
P["Cooking"] = {
    kind = "craft",
    steps = {
        { recipe = "Charred Wolf Meat", item = 2679, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [2672] = 1 },
          station = "fire" },
        { recipe = "Roasted Boar Meat", item = 2681, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [769] = 1 },
          station = "fire" },
        { recipe = "Brilliant Smallfish", item = 6290, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [6291] = 1 },
          station = "fire", recipeItem = 6325 },
        { recipe = "Roasted Kodo Meat", item = 5474, learn = 35, yellow = 75, green = 95, grey = 115, mats = { [5467] = 1, [2678] = 1 },
          station = "fire", recipeItem = 5484, faction = "Horde" },
        { recipe = "Strider Stew", item = 5477, learn = 50, yellow = 90, green = 110, grey = 130, mats = { [5469] = 1, [4536] = 1 },
          station = "fire", recipeItem = 5486, faction = "Horde" },
        { recipe = "Crispy Lizard Tail", item = 5479, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [5470] = 1, [2692] = 1 },
          station = "fire", recipeItem = 5488, faction = "Horde" },
        { recipe = "Smoked Bear Meat", item = 6890, learn = 40, yellow = 80, green = 100, grey = 120, mats = { [3173] = 1 },
          station = "fire", recipeItem = 6892, faction = "Alliance" },
        { recipe = "Crab Cake", item = 2683, learn = 75, yellow = 115, green = 135, grey = 155, mats = { [2674] = 1, [2678] = 1 },
          station = "fire", faction = "Alliance" },
        { recipe = "Cooked Crab Claw", item = 2682, learn = 85, yellow = 125, green = 145, grey = 165, mats = { [2675] = 1, [2678] = 1 },
          station = "fire", recipeItem = 2698, faction = "Alliance" },
        { recipe = "Seasoned Wolf Kabob", item = 1017, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [1015] = 2, [2665] = 1 },
          station = "fire", recipeItem = 2701, faction = "Alliance" },
        { recipe = "Curiously Tasty Omelet", item = 3665, learn = 130, yellow = 170, green = 190, grey = 210, mats = { [3685] = 1, [2692] = 1 },
          station = "fire", recipeItem = 3682 },
        { recipe = "Roast Raptor", item = 12210, learn = 175, yellow = 215, green = 235, grey = 255, mats = { [12184] = 1, [2692] = 1 },
          station = "fire", recipeItem = 12228 },
        { recipe = "Monster Omelet", item = 12218, learn = 225, yellow = 250, green = 262, grey = 275, mats = { [12207] = 1, [3713] = 2 },
          station = "fire", recipeItem = 16110 },
        { recipe = "Tender Wolf Steak", item = 18045, learn = 225, yellow = 250, green = 262, grey = 275, mats = { [12208] = 1, [3713] = 1 },
          station = "fire", recipeItem = 18046 },
        { recipe = "Spotted Yellowtail", item = 6887, learn = 225, yellow = 250, green = 262, grey = 275, mats = { [4603] = 1 },
          station = "fire", recipeItem = 13939 },
        { recipe = "Nightfin Soup", item = 13931, learn = 250, yellow = 275, green = 285, grey = 295, mats = { [13759] = 1, [159] = 1 },
          station = "fire", recipeItem = 13945 },
        { recipe = "Poached Sunscale Salmon", item = 13932, learn = 250, yellow = 275, green = 285, grey = 295, mats = { [13760] = 1 },
          station = "fire", recipeItem = 13946 },
        { recipe = "Mightfish Steak", item = 13934, learn = 275, yellow = 300, green = 300, grey = 300, mats = { [13893] = 1, [2692] = 1, [3713] = 1 },
          station = "fire", recipeItem = 13948 },
        { recipe = "Lobster Stew", item = 13933, learn = 275, yellow = 300, green = 300, grey = 300, mats = { [13888] = 1, [159] = 1 },
          station = "fire", recipeItem = 13947 },
        { recipe = "Baked Salmon", item = 13935, learn = 275, yellow = 300, green = 300, grey = 300, mats = { [13889] = 1, [3713] = 1 },
          station = "fire", recipeItem = 13949 },
        { recipe = "Longjaw Mud Snapper", item = 4592, learn = 50, yellow = 90, green = 110, grey = 130, mats = { [6289] = 1 },
          station = "fire", recipeItem = 6328 },
        { recipe = "Bristle Whisker Catfish", item = 4593, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [6308] = 1 },
          station = "fire", recipeItem = 6330 },
        { recipe = "Mithril Head Trout", item = 8364, learn = 175, yellow = 215, green = 235, grey = 255, mats = { [8365] = 1 },
          station = "fire", recipeItem = 17062 },
    },
}
P["Fishing"] = { kind = "gather", tool = 6256 }
P["Herbalism"] = { kind = "gather" }
S[2447] = { name = "Peacebloom", gather = "Herbalism", objects = { 1618, 3724 }, node = "Peacebloom", skill = 1, yield = 1.5 }
S[765] = { name = "Silverleaf", gather = "Herbalism", objects = { 1617, 3725 }, node = "Silverleaf", skill = 1, yield = 1.5 }
S[785] = { name = "Mageroyal", gather = "Herbalism", objects = { 1620, 3727 }, node = "Mageroyal", skill = 50, yield = 1.5 }
S[2450] = { name = "Briarthorn", gather = "Herbalism", objects = { 1621, 3729 }, node = "Briarthorn", skill = 70, yield = 1.5 }
S[3820] = { name = "Stranglekelp", gather = "Herbalism", objects = { 2045 }, node = "Stranglekelp", skill = 85, yield = 1.5 }
S[2453] = { name = "Bruiseweed", gather = "Herbalism", objects = { 1622, 3730 }, node = "Bruiseweed", skill = 100, yield = 1.5 }
S[3355] = { name = "Wild Steelbloom", gather = "Herbalism", objects = { 1623 }, node = "Wild Steelbloom", skill = 115, yield = 1.5 }
S[3356] = { name = "Kingsblood", gather = "Herbalism", objects = { 1624 }, node = "Kingsblood", skill = 125, yield = 1.5 }
S[3357] = { name = "Liferoot", gather = "Herbalism", objects = { 2041 }, node = "Liferoot", skill = 150, yield = 1.5 }
S[3821] = { name = "Goldthorn", gather = "Herbalism", objects = { 2046 }, node = "Goldthorn", skill = 170, yield = 1.5 }
S[3358] = { name = "Khadgar's Whisker", gather = "Herbalism", objects = { 2043 }, node = "Khadgar's Whisker", skill = 185, yield = 1.5 }
S[8831] = { name = "Purple Lotus", gather = "Herbalism", objects = { 142140 }, node = "Purple Lotus", skill = 210, yield = 1.5 }
S[8836] = { name = "Arthas' Tears", gather = "Herbalism", objects = { 142141 }, node = "Arthas' Tears", skill = 220, yield = 1.5 }
S[8838] = { name = "Sungrass", gather = "Herbalism", objects = { 142142 }, node = "Sungrass", skill = 230, yield = 1.5 }
S[8839] = { name = "Blindweed", gather = "Herbalism", objects = { 142143 }, node = "Blindweed", skill = 235, yield = 1.5 }
S[13464] = { name = "Golden Sansam", gather = "Herbalism", objects = { 176583 }, node = "Golden Sansam", skill = 260, yield = 1.5 }
S[13465] = { name = "Mountain Silversage", gather = "Herbalism", objects = { 176586 }, node = "Mountain Silversage", skill = 280, yield = 1.5 }
S[2775] = { name = "Silver Ore", gather = "Mining", objects = { 1733, 105569 }, node = "Silver Vein", skill = 75, yield = 2 }
S[2842] = { name = "Silver Bar", smelt = { from = 2775, n = 1, skill = 75, spell = "Smelt Silver" } }
S[2320] = { name = "Coarse Thread", vendor = true, price = 10 }
S[2321] = { name = "Fine Thread", vendor = true, price = 100 }
S[2324] = { name = "Bleach", vendor = true, price = 25 }
S[2604] = { name = "Red Dye", vendor = true, price = 50 }
S[4291] = { name = "Silken Thread", vendor = true, price = 500 }
S[6260] = { name = "Blue Dye", vendor = true, price = 50 }
S[6261] = { name = "Orange Dye", vendor = true, price = 1000 }
S[8343] = { name = "Heavy Silken Thread", vendor = true, price = 2000 }
S[14341] = { name = "Rune Thread", vendor = true, price = 5000 }
S[4289] = { name = "Salt", vendor = true, price = 50 }
S[4340] = { name = "Gray Dye", vendor = true, price = 350 }
S[2325] = { name = "Black Dye", vendor = true, price = 1000 }
S[3371] = { name = "Empty Vial", vendor = true, price = 20 }
S[3372] = { name = "Leaded Vial", vendor = true, price = 200 }
S[8925] = { name = "Crystal Vial", vendor = true, price = 2500 }
S[6217] = { name = "Copper Rod", vendor = true, price = 124 }
S[2880] = { name = "Weak Flux", vendor = true, price = 100 }
S[14481] = { name = "Pattern: Runecloth Gloves", vendor = true, price = 16000 }
S[15725] = { name = "Pattern: Wicked Leather Gauntlets", vendor = true, price = 12000 }
S[15756] = { name = "Pattern: Runic Leather Headband", vendor = true, price = 22000 }
S[13477] = { name = "Recipe: Superior Mana Potion", vendor = true, price = 12000 }
S[13480] = { name = "Recipe: Major Healing Potion", vendor = true, price = 15000 }
S[11039] = { name = "Formula: Enchant Cloak - Minor Agility", vendor = true, price = 800 }
S[11101] = { name = "Formula: Enchant Bracer - Lesser Strength", vendor = true, price = 2500 }
S[20754] = { name = "Formula: Lesser Mana Oil", vendor = true, price = 10000 }
S[16217] = { name = "Formula: Enchant Shield - Greater Stamina", vendor = true, price = 12000 }
S[16224] = { name = "Formula: Enchant Cloak - Superior Defense", vendor = true, price = 20000 }
S[16042] = { name = "Schematic: Thorium Widget", vendor = true, price = 12000 }
S[16047] = { name = "Schematic: Thorium Tube", vendor = true, price = 16000 }
S[2996] = { name = "Bolt of Linen Cloth", made = "Tailoring" }
S[2997] = { name = "Bolt of Woolen Cloth", made = "Tailoring" }
S[4305] = { name = "Bolt of Silk Cloth", made = "Tailoring" }
S[4339] = { name = "Bolt of Mageweave", made = "Tailoring" }
S[14048] = { name = "Bolt of Runecloth", made = "Tailoring" }
S[4233] = { name = "Cured Medium Hide", made = "Leatherworking" }
S[4236] = { name = "Cured Heavy Hide", made = "Leatherworking" }
S[4246] = { name = "Fine Leather Belt", made = "Leatherworking" }
S[118] = { name = "Minor Healing Potion", made = "Alchemy" }
S[4357] = { name = "Rough Blasting Powder", made = "Engineering" }
S[4359] = { name = "Handful of Copper Bolts", made = "Engineering" }
S[4364] = { name = "Coarse Blasting Powder", made = "Engineering" }
S[4371] = { name = "Bronze Tube", made = "Engineering" }
S[4375] = { name = "Whirring Bronze Gizmo", made = "Engineering" }
S[4377] = { name = "Heavy Blasting Powder", made = "Engineering" }
S[4382] = { name = "Bronze Framework", made = "Engineering" }
S[10505] = { name = "Solid Blasting Powder", made = "Engineering" }
S[10560] = { name = "Unstable Trigger", made = "Engineering" }
S[10561] = { name = "Mithril Casing", made = "Engineering" }
S[6338] = { name = "Silver Rod" }
S[11128] = { name = "Golden Rod" }
S[11144] = { name = "Truesilver Rod" }
S[6218] = { name = "Runed Copper Rod" }
S[6339] = { name = "Runed Silver Rod" }
S[11130] = { name = "Runed Golden Rod" }
S[11145] = { name = "Runed Truesilver Rod" }
S[16207] = { name = "Runed Arcanite Rod" }
S[10498] = { name = "Gyromatic Micro-Adjustor" }
P["Tailoring"] = {
    kind = "craft",
    steps = {
        { recipe = "Bolt of Linen Cloth", item = 2996, learn = 1, yellow = 25, green = 37, grey = 50, mats = { [2589] = 2 } },
        { recipe = "Linen Belt", item = 7026, learn = 15, yellow = 50, green = 67, grey = 85, mats = { [2996] = 1, [2320] = 1 } },
        { recipe = "Reinforced Linen Cape", item = 2580, learn = 60, yellow = 85, green = 102, grey = 120, mats = { [2996] = 2, [2320] = 3 } },
        { recipe = "Bolt of Woolen Cloth", item = 2997, learn = 75, yellow = 90, green = 97, grey = 105, mats = { [2592] = 3 } },
        { recipe = "Simple Kilt", item = 10047, learn = 75, yellow = 100, green = 117, grey = 135, mats = { [2996] = 4, [2321] = 1 } },
        { recipe = "Double-stitched Woolen Shoulders", item = 4314, learn = 110, yellow = 135, green = 152, grey = 170,
          mats = { [2997] = 3, [2321] = 2 } },
        { recipe = "Bolt of Silk Cloth", item = 4305, learn = 125, yellow = 135, green = 140, grey = 145, mats = { [4306] = 4 } },
        { recipe = "Azure Silk Hood", item = 7048, learn = 145, yellow = 155, green = 160, grey = 165, mats = { [4305] = 2, [6260] = 2, [2321] = 1 } },
        { recipe = "Silk Headband", item = 7050, learn = 160, yellow = 170, green = 175, grey = 180, mats = { [4305] = 3, [2321] = 2 } },
        { recipe = "Formal White Shirt", item = 4334, learn = 170, yellow = 180, green = 185, grey = 190,
          mats = { [4305] = 3, [2324] = 2, [2321] = 1 } },
        { recipe = "Bolt of Mageweave", item = 4339, learn = 175, yellow = 180, green = 182, grey = 185, mats = { [4338] = 5 } },
        { recipe = "Crimson Silk Vest", item = 7058, learn = 185, yellow = 205, green = 215, grey = 225,
          mats = { [4305] = 4, [2604] = 2, [2321] = 2 } },
        { recipe = "Crimson Silk Pantaloons", item = 7062, learn = 195, yellow = 215, green = 225, grey = 235,
          mats = { [4305] = 4, [2604] = 2, [4291] = 2 } },
        { recipe = "Orange Mageweave Shirt", item = 10056, learn = 215, yellow = 220, green = 225, grey = 230,
          mats = { [4339] = 1, [6261] = 1, [8343] = 1 } },
        { recipe = "Black Mageweave Gloves", item = 10003, learn = 215, yellow = 230, green = 245, grey = 260, mats = { [4339] = 2, [8343] = 2 } },
        { recipe = "Black Mageweave Headband", item = 10024, learn = 230, yellow = 245, green = 260, grey = 275, mats = { [4339] = 3, [8343] = 2 } },
        { recipe = "Bolt of Runecloth", item = 14048, learn = 250, yellow = 255, green = 257, grey = 260, mats = { [14047] = 5 } },
        { recipe = "Runecloth Belt", item = 13856, learn = 255, yellow = 270, green = 285, grey = 300, mats = { [14048] = 3, [14341] = 1 } },
        { recipe = "Runecloth Gloves", item = 13863, learn = 275, yellow = 290, green = 305, grey = 320,
          mats = { [14048] = 4, [8170] = 4, [14341] = 1 }, recipeItem = 14481 },
    },
}
P["Leatherworking"] = {
    kind = "craft",
    steps = {
        { recipe = "Light Leather", item = 2318, learn = 1, yellow = 20, green = 30, grey = 40, mats = { [2934] = 3 } },
        { recipe = "Light Armor Kit", item = 2304, learn = 1, yellow = 30, green = 45, grey = 60, mats = { [2318] = 1 } },
        { recipe = "Cured Light Hide", item = 4231, learn = 35, yellow = 55, green = 65, grey = 75, mats = { [783] = 1, [4289] = 1 } },
        { recipe = "Embossed Leather Gloves", item = 4239, learn = 55, yellow = 85, green = 100, grey = 115, mats = { [2318] = 3, [2320] = 2 } },
        { recipe = "Fine Leather Belt", item = 4246, learn = 80, yellow = 110, green = 125, grey = 140, mats = { [2318] = 6, [2320] = 2 } },
        { recipe = "Cured Medium Hide", item = 4233, learn = 100, yellow = 115, green = 122, grey = 130, mats = { [4232] = 1, [4289] = 1 } },
        { recipe = "Dark Leather Boots", item = 2315, learn = 100, yellow = 125, green = 137, grey = 150,
          mats = { [2319] = 4, [2321] = 2, [4340] = 1 } },
        { recipe = "Dark Leather Belt", item = 4249, learn = 125, yellow = 150, green = 162, grey = 175,
          mats = { [4246] = 1, [4233] = 1, [2321] = 2, [4340] = 1 } },
        { recipe = "Heavy Leather", item = 4234, learn = 150, yellow = 150, green = 155, grey = 160, mats = { [2319] = 5 } },
        { recipe = "Cured Heavy Hide", item = 4236, learn = 150, yellow = 160, green = 165, grey = 170, mats = { [4235] = 1, [4289] = 3 } },
        { recipe = "Heavy Armor Kit", item = 4265, learn = 150, yellow = 170, green = 180, grey = 190, mats = { [4234] = 5, [2321] = 1 } },
        { recipe = "Barbaric Shoulders", item = 5964, learn = 175, yellow = 195, green = 205, grey = 215,
          mats = { [4234] = 8, [4236] = 1, [2321] = 2 } },
        { recipe = "Guardian Gloves", item = 5966, learn = 190, yellow = 210, green = 220, grey = 230,
          mats = { [4234] = 4, [4236] = 1, [4291] = 1 } },
        { recipe = "Thick Armor Kit", item = 8173, learn = 200, yellow = 220, green = 230, grey = 240, mats = { [4304] = 5, [4291] = 1 } },
        { recipe = "Nightscape Headband", item = 8176, learn = 205, yellow = 225, green = 235, grey = 245, mats = { [4304] = 5, [4291] = 2 } },
        { recipe = "Nightscape Pants", item = 8193, learn = 230, yellow = 250, green = 260, grey = 270, mats = { [4304] = 14, [4291] = 4 } },
        { recipe = "Rugged Armor Kit", item = 15564, learn = 250, yellow = 250, green = 260, grey = 270, mats = { [8170] = 5 } },
        { recipe = "Wicked Leather Gauntlets", item = 15083, learn = 260, yellow = 280, green = 290, grey = 300,
          mats = { [8170] = 8, [2325] = 1, [14341] = 1 }, recipeItem = 15725 },
        { recipe = "Runic Leather Headband", item = 15094, learn = 290, yellow = 310, green = 320, grey = 330,
          mats = { [8170] = 14, [14047] = 10, [14341] = 1 }, recipeItem = 15756 },
    },
}
P["Alchemy"] = {
    kind = "craft",
    steps = {
        { recipe = "Minor Healing Potion", item = 118, learn = 1, yellow = 55, green = 75, grey = 95, mats = { [2447] = 1, [765] = 1, [3371] = 1 } },
        { recipe = "Lesser Healing Potion", item = 858, learn = 55, yellow = 85, green = 105, grey = 125, mats = { [118] = 1, [2450] = 1 } },
        { recipe = "Healing Potion", item = 929, learn = 110, yellow = 135, green = 155, grey = 175, mats = { [2453] = 1, [2450] = 1, [3372] = 1 } },
        { recipe = "Lesser Mana Potion", item = 3385, learn = 120, yellow = 145, green = 165, grey = 185, mats = { [785] = 1, [3820] = 1, [3371] = 1 } },
        { recipe = "Greater Healing Potion", item = 1710, learn = 155, yellow = 175, green = 195, grey = 215, mats = { [3357] = 1, [3356] = 1, [3372] = 1 } },
        { recipe = "Elixir of Agility", item = 8949, learn = 185, yellow = 205, green = 225, grey = 245, mats = { [3820] = 1, [3821] = 1, [3372] = 1 } },
        { recipe = "Elixir of Greater Defense", item = 8951, learn = 195, yellow = 215, green = 235, grey = 255, mats = { [3355] = 1, [3821] = 1, [3372] = 1 } },
        { recipe = "Superior Healing Potion", item = 3928, learn = 215, yellow = 230, green = 250, grey = 270, mats = { [8838] = 1, [3358] = 1, [8925] = 1 } },
        { recipe = "Elixir of Detect Undead", item = 9154, learn = 230, yellow = 245, green = 265, grey = 285, mats = { [8836] = 1, [8925] = 1 } },
        { recipe = "Elixir of Greater Agility", item = 9187, learn = 240, yellow = 255, green = 275, grey = 295, mats = { [8838] = 1, [3821] = 1, [8925] = 1 } },
        { recipe = "Superior Mana Potion", item = 13443, learn = 260, yellow = 275, green = 295, grey = 315,
          mats = { [8838] = 2, [8839] = 2, [8925] = 1 }, recipeItem = 13477 },
        { recipe = "Major Healing Potion", item = 13446, learn = 275, yellow = 290, green = 310, grey = 330,
          mats = { [13464] = 2, [13465] = 1, [8925] = 1 }, recipeItem = 13480 },
    },
}
P["Enchanting"] = {
    kind = "craft",
    steps = {
        { recipe = "Runed Copper Rod", item = 6218, learn = 1, yellow = 5, green = 7, grey = 10, mats = { [6217] = 1, [10940] = 1, [10938] = 1 } },
        { recipe = "Enchant Bracer - Minor Health", learn = 1, yellow = 70, green = 90, grey = 110, mats = { [10940] = 1 }, tool = 6218 },
        { recipe = "Enchant Bracer - Minor Stamina", learn = 50, yellow = 100, green = 120, grey = 140, mats = { [10940] = 3 }, tool = 6218 },
        { recipe = "Runed Silver Rod", item = 6339, learn = 100, yellow = 130, green = 150, grey = 170,
          mats = { [6338] = 1, [10940] = 6, [10939] = 3, [1210] = 1 } },
        { recipe = "Greater Magic Wand", item = 11288, learn = 70, yellow = 110, green = 130, grey = 150, mats = { [4470] = 1, [10939] = 1 }, tool = 6218 },
        { recipe = "Enchant Cloak - Minor Agility", learn = 110, yellow = 135, green = 155, grey = 175, mats = { [10998] = 1 }, recipeItem = 11039, tool = 6339 },
        { recipe = "Enchant Bracer - Lesser Stamina", learn = 130, yellow = 155, green = 175, grey = 195, mats = { [11083] = 2 }, tool = 6339 },
        { recipe = "Runed Golden Rod", item = 11130, learn = 150, yellow = 175, green = 195, grey = 215,
          mats = { [11128] = 1, [5500] = 1, [11082] = 2, [11083] = 2 } },
        { recipe = "Enchant Bracer - Lesser Strength", learn = 140, yellow = 165, green = 185, grey = 205, mats = { [11083] = 2 }, recipeItem = 11101, tool = 6339 },
        { recipe = "Enchant Bracer - Strength", learn = 180, yellow = 200, green = 220, grey = 240, mats = { [11137] = 1 }, tool = 11130 },
        { recipe = "Runed Truesilver Rod", item = 11145, learn = 200, yellow = 220, green = 240, grey = 260,
          mats = { [11144] = 1, [7971] = 1, [11135] = 2, [11137] = 2 } },
        { recipe = "Enchant Cloak - Greater Defense", learn = 205, yellow = 225, green = 245, grey = 265, mats = { [11137] = 3 }, tool = 11145 },
        { recipe = "Enchant Gloves - Agility", learn = 210, yellow = 230, green = 250, grey = 270, mats = { [11174] = 1, [11137] = 1 }, tool = 11145 },
        { recipe = "Enchant Boots - Stamina", learn = 215, yellow = 235, green = 255, grey = 275, mats = { [11137] = 5 }, tool = 11145 },
        { recipe = "Enchant Chest - Superior Health", learn = 220, yellow = 240, green = 260, grey = 280, mats = { [11137] = 6 }, tool = 11145 },
        { recipe = "Lesser Mana Oil", item = 20747, learn = 250, yellow = 260, green = 270, grey = 280,
          mats = { [11176] = 3, [8831] = 2, [8925] = 1 }, recipeItem = 20754, tool = 11145 },
        { recipe = "Enchant Shield - Greater Stamina", learn = 265, yellow = 285, green = 305, grey = 325, mats = { [11176] = 10 }, recipeItem = 16217, tool = 11145 },
        { recipe = "Enchant Cloak - Superior Defense", learn = 285, yellow = 305, green = 325, grey = 345, mats = { [16204] = 8 }, recipeItem = 16224, tool = 11145 },
    },
}
P["Engineering"] = {
    kind = "craft", tool = 5956,
    steps = {
        { recipe = "Rough Blasting Powder", item = 4357, learn = 1, yellow = 20, green = 30, grey = 40, mats = { [2835] = 1 } },
        { recipe = "Handful of Copper Bolts", item = 4359, learn = 30, yellow = 45, green = 52, grey = 60, mats = { [2840] = 1 }, station = "anvil" },
        { recipe = "Arclight Spanner", item = 6219, learn = 50, yellow = 70, green = 80, grey = 90, mats = { [2840] = 6 }, station = "anvil" },
        { recipe = "Rough Copper Bomb", item = 4360, learn = 30, yellow = 60, green = 75, grey = 90,
          mats = { [2840] = 1, [4359] = 1, [4357] = 2, [2589] = 1 }, station = "anvil" },
        { recipe = "Coarse Blasting Powder", item = 4364, learn = 75, yellow = 85, green = 90, grey = 95, mats = { [2836] = 1 } },
        { recipe = "Coarse Dynamite", item = 4365, learn = 75, yellow = 90, green = 97, grey = 105, mats = { [4364] = 3, [2589] = 1 } },
        { recipe = "Silver Contact", item = 4404, learn = 90, yellow = 110, green = 125, grey = 140, mats = { [2842] = 1 } },
        { recipe = "Bronze Tube", item = 4371, learn = 105, yellow = 105, green = 130, grey = 155, mats = { [2841] = 2, [2880] = 1 }, station = "anvil" },
        { recipe = "Standard Scope", item = 4406, learn = 110, yellow = 135, green = 147, grey = 160, mats = { [4371] = 1, [1206] = 1 }, tool = 6219 },
        { recipe = "Heavy Blasting Powder", item = 4377, learn = 125, yellow = 125, green = 135, grey = 145, mats = { [2838] = 1 } },
        { recipe = "Whirring Bronze Gizmo", item = 4375, learn = 125, yellow = 125, green = 150, grey = 175, mats = { [2841] = 2, [2592] = 1 }, station = "anvil", tool = 6219 },
        { recipe = "Bronze Framework", item = 4382, learn = 145, yellow = 145, green = 170, grey = 195, mats = { [2841] = 2, [2319] = 1, [2592] = 1 } },
        { recipe = "Explosive Sheep", item = 4384, learn = 150, yellow = 175, green = 187, grey = 200,
          mats = { [4382] = 1, [4375] = 1, [4377] = 2, [2592] = 2 }, station = "anvil", tool = 6219 },
        { recipe = "Gyromatic Micro-Adjustor", item = 10498, learn = 175, yellow = 175, green = 195, grey = 215, mats = { [3859] = 4 }, station = "anvil" },
        { recipe = "Solid Blasting Powder", item = 10505, learn = 175, yellow = 175, green = 185, grey = 195, mats = { [7912] = 2 } },
        { recipe = "Mithril Tube", item = 10559, learn = 195, yellow = 195, green = 215, grey = 235, mats = { [3860] = 3 }, station = "anvil" },
        { recipe = "Unstable Trigger", item = 10560, learn = 200, yellow = 200, green = 220, grey = 240,
          mats = { [3860] = 1, [4338] = 1, [10505] = 1 }, station = "anvil", tool = 6219 },
        { recipe = "Mithril Casing", item = 10561, learn = 215, yellow = 215, green = 235, grey = 255, mats = { [3860] = 3 }, station = "anvil", tool = 6219 },
        { recipe = "Hi-Explosive Bomb", item = 10562, learn = 235, yellow = 235, green = 255, grey = 275,
          mats = { [10561] = 2, [10560] = 1, [10505] = 2 }, station = "anvil", tool = 6219 },
        { recipe = "Dense Blasting Powder", item = 15992, learn = 250, yellow = 250, green = 255, grey = 260, mats = { [12365] = 2 } },
        { recipe = "Thorium Widget", item = 15994, learn = 260, yellow = 280, green = 290, grey = 300, mats = { [12359] = 3, [14047] = 1 }, recipeItem = 16042, station = "anvil", tool = 6219 },
        { recipe = "Thorium Tube", item = 16000, learn = 275, yellow = 295, green = 305, grey = 315, mats = { [12359] = 6 }, recipeItem = 16047, station = "anvil", tool = 6219 },
    },
}

function ProfData.ShippedRows()
    local out = {}
    for prof, g in pairs(P) do
        local rows = {}
        for _, r in ipairs(type(g.steps) == "table" and g.steps or {}) do
            if type(r.recipe) == "string" and type(r.learn) == "number" then
                rows[#rows + 1] = { name = r.recipe, skill = r.learn }
            end
        end
        if #rows > 0 then out[prof] = rows end
    end
    return out
end
