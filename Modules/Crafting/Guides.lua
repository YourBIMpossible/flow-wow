-- Profession levelling data: what to make at each skill, what it takes, and
-- where those materials come from. The planner (SkillPlan.lua) works from
-- this plus what you have right now (skill, bags, quests, position) to put
-- gather / smelt / craft stops on the route.
--
-- `use` is the path the public levelling guides take: at each skill, which
-- recipe they make. The planner sticks to it, so it never grinds a recipe on
-- to grey once the guides have moved on. Skill colours (learn / yellow /
-- green / grey) are approximate, from the same guides and the Classic Era
-- client data; what the profession window shows in game (Recipes.lua) wins
-- whenever Flow has seen it. Recipes only a quest teaches are left out.
--
-- Extend by registering more:
--   ns:Register("profGuide", "<Profession>", {
--       kind = "craft" | "gather",
--       tool = itemID,                       -- needed in your bags (craft)
--       steps = { { recipe, item, learn, yellow, green, grey, mats = { [itemID] = n },
--                   use = { from, to } | { { from, to }, ... },   -- the guides' path
--                   faction = "Horde" | "Alliance",               -- only that side
--                   recipeItem = itemID,                          -- bought, not trained
--                   station = "anvil" | "forge" | "fire" | nil } } })
--   ns:Register("itemSource", itemID, {
--       name, gather = "<Profession>", objects = { objectIDs }, skill = n, yield = per node,
--       smelt = { from = itemID, n = count, skill = n, spell = "Smelt X" },
--       drops = { "NPC name", ... },        -- mobs that drop it
--       fished = true, share = 0.7,         -- caught while levelling Fishing
--       rate = 0.35,                        -- rough chance per kill (Flow learns yours as you loot)
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

ns:Register("itemSource", 2770, { name = "Copper Ore", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 2 })
ns:Register("itemSource", 2835, { name = "Rough Stone", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 0.8 })
ns:Register("itemSource", 2840, { name = "Copper Bar", smelt = { from = 2770, n = 1, skill = 1, spell = "Smelt Copper" } })
ns:Register("itemSource", 2771, { name = "Tin Ore", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 2 })
ns:Register("itemSource", 2836, { name = "Coarse Stone", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 0.8 })
ns:Register("itemSource", 3576, { name = "Tin Bar", smelt = { from = 2771, n = 1, skill = 65, spell = "Smelt Tin" } })
ns:Register("itemSource", 2772, { name = "Iron Ore", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 2 })
ns:Register("itemSource", 2838, { name = "Heavy Stone", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 0.8 })
ns:Register("itemSource", 3575, { name = "Iron Bar", smelt = { from = 2772, n = 1, skill = 125, spell = "Smelt Iron" } })
ns:Register("itemSource", 3858, { name = "Mithril Ore", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit", skill = 175, yield = 2 })
ns:Register("itemSource", 7912, { name = "Solid Stone", gather = "Mining", objects = MITHRIL_VEIN, node = "Mithril Deposit", skill = 175, yield = 0.8 })
ns:Register("itemSource", 3860, { name = "Mithril Bar", smelt = { from = 3858, n = 1, skill = 175, spell = "Smelt Mithril" } })
ns:Register("itemSource", 12365, { name = "Dense Stone", gather = "Mining", objects = THORIUM_VEIN, node = "Thorium Vein", skill = 230, yield = 0.8 })
-- Made by an earlier Blacksmithing step.
ns:Register("itemSource", 3486, { name = "Heavy Grinding Stone", made = "Blacksmithing" })

-- Mob drops (names are looked up in Questie; only spawns on your map are used).
-- Rates are rough guesses until Flow has seen your own loot.
ns:Register("itemSource", 2589, { name = "Linen Cloth", drops = {
    "Defias Thug", "Defias Cutpurse", "Defias Bandit", "Defias Rogue Wizard", "Defias Smuggler",
    "Kobold Vermin", "Kobold Worker", "Kobold Laborer", "Kobold Tunneler", "Riverpaw Gnoll", "Riverpaw Runt",
    "Murloc Streamrunner", "Murloc Forager" } })
ns:Register("itemSource", 2672, { name = "Stringy Wolf Meat", rate = 0.35, drops = { "Young Wolf", "Timber Wolf", "Prowler", "Gray Forest Wolf" } })
ns:Register("itemSource", 769,  { name = "Chunk of Boar Meat", rate = 0.45, drops = { "Stonetusk Boar", "Rockhide Boar", "Small Crag Boar" } })
-- Horde cooking meats (the Barrens).
ns:Register("itemSource", 5467, { name = "Kodo Meat", rate = 0.5, drops = { "Barrens Kodo", "Greater Barrens Kodo" } })
ns:Register("itemSource", 5469, { name = "Strider Meat", rate = 0.5, drops = {
    "Plainstrider", "Adult Plainstrider", "Elder Plainstrider", "Fleeting Plainstrider", "Ornery Plainstrider" } })
ns:Register("itemSource", 5470, { name = "Thunder Lizard Tail", rate = 0.5, drops = { "Thunder Lizard", "Lightning Hide", "Thunderhead", "Stormsnout" } })
-- Alliance cooking meats.
ns:Register("itemSource", 3173, { name = "Bear Meat", rate = 0.4, drops = {
    "Young Forest Bear", "Black Bear", "Elder Black Bear", "Grizzled Black Bear", "Thistle Bear",
    "Ferocious Grizzled Bear", "Giant Grizzled Bear" } })
local CRAWLERS = { "Sand Crawler", "Shore Crawler", "Pygmy Tide Crawler", "Tide Crawler", "Encrusted Tide Crawler" }
ns:Register("itemSource", 2674, { name = "Crawler Meat", rate = 0.35, drops = CRAWLERS })
ns:Register("itemSource", 2675, { name = "Crawler Claw", rate = 0.35, drops = CRAWLERS })
ns:Register("itemSource", 1015, { name = "Lean Wolf Flank", rate = 0.35, drops = { "Coyote", "Coyote Packleader", "Starving Dire Wolf", "Rabid Dire Wolf" } })
-- Both sides.
ns:Register("itemSource", 3685, { name = "Raptor Egg", rate = 0.3, drops = {
    "Mottled Raptor", "Mottled Screecher", "Mottled Scytheclaw", "Highland Raptor", "Highland Thrasher", "Highland Strider" } })
ns:Register("itemSource", 12184, { name = "Raptor Flesh", rate = 0.4, drops = { "Jungle Stalker", "Lashtail Raptor", "Highland Fleshstalker", "Highland Thrasher" } })

-- Caught while levelling Fishing (share: roughly how many catches are this fish
-- in the water you fish at that skill). Counts against the meat Cooking would
-- otherwise farm.
ns:Register("itemSource", 6291, { name = "Raw Brilliant Smallfish", fished = true, share = 0.7 })
ns:Register("itemSource", 6289, { name = "Raw Longjaw Mud Snapper", fished = true, share = 0.6 })
ns:Register("itemSource", 6308, { name = "Raw Bristle Whisker Catfish", fished = true, share = 0.5 })
ns:Register("itemSource", 8365, { name = "Raw Mithril Head Trout", fished = true, share = 0.4 })

-- Bought. price: copper, approximate; replaced by the real price once you've
-- seen it at a vendor.
ns:Register("itemSource", 2678, { name = "Mild Spices", vendor = true, price = 10 })
ns:Register("itemSource", 2692, { name = "Hot Spices", vendor = true, price = 40 })
ns:Register("itemSource", 4536, { name = "Shiny Red Apple", vendor = true, price = 25 })
ns:Register("itemSource", 2665, { name = "Stormwind Seasoning Herbs", vendor = true, price = 20 })
ns:Register("itemSource", 2605, { name = "Green Dye", vendor = true, price = 100 })
-- Recipes and manuals.
ns:Register("itemSource", 6325, { name = "Recipe: Brilliant Smallfish", vendor = true, price = 40 })
ns:Register("itemSource", 6328, { name = "Recipe: Longjaw Mud Snapper", vendor = true, price = 400 })
ns:Register("itemSource", 6330, { name = "Recipe: Bristle Whisker Catfish", vendor = true, price = 1200 })
ns:Register("itemSource", 17062, { name = "Recipe: Mithril Head Trout", vendor = true, price = 2200 })
ns:Register("itemSource", 5484, { name = "Recipe: Roasted Kodo Meat", vendor = true, price = 240 })
ns:Register("itemSource", 5486, { name = "Recipe: Strider Stew", vendor = true, price = 440 })
ns:Register("itemSource", 5488, { name = "Recipe: Crispy Lizard Tail", vendor = true, price = 400 })
ns:Register("itemSource", 6892, { name = "Recipe: Smoked Bear Meat", vendor = true, price = 250 })
ns:Register("itemSource", 2698, { name = "Recipe: Cooked Crab Claw", vendor = true, price = 400 })
ns:Register("itemSource", 2701, { name = "Recipe: Seasoned Wolf Kabob", vendor = true, price = 1600 })
ns:Register("itemSource", 3682, { name = "Recipe: Curiously Tasty Omelet", vendor = true, price = 1600 })
ns:Register("itemSource", 12228, { name = "Recipe: Roast Raptor", vendor = true, price = 5000 })
ns:Register("itemSource", 16112, { name = "Manual: Heavy Silk Bandage", vendor = true, price = 2200 })
ns:Register("itemSource", 16113, { name = "Manual: Mageweave Bandage", vendor = true, price = 5000 })
-- Tools.
ns:Register("itemSource", 5956, { name = "Blacksmith Hammer", vendor = true, price = 18 })
ns:Register("itemSource", 2901, { name = "Mining Pick", vendor = true, price = 16 })
ns:Register("itemSource", 6256, { name = "Fishing Pole", vendor = true, price = 23 })
ns:Register("itemSource", 6529, { name = "Shiny Bauble", vendor = true, price = 100 })   -- lure: +25 Fishing
ns:Register("itemSource", 4470, { name = "Simple Wood", vendor = true, price = 38 })      -- for Basic Campfire

-------------------------------------------------------------------------------
-- Professions
-------------------------------------------------------------------------------

-- Gaps the guides fill with plans from quests (Imperial Plate, 270+) are
-- left to "whatever still gives skill".
ns:Register("profGuide", "Blacksmithing", {
    kind = "craft", tool = 5956,
    steps = {
        { recipe = "Rough Sharpening Stone", item = 2862, learn = 1, yellow = 15, green = 35, grey = 55, mats = { [2835] = 1 }, use = { 1, 30 } },
        { recipe = "Rough Grinding Stone", item = 3470, learn = 25, yellow = 45, green = 65, grey = 85, mats = { [2835] = 2 }, use = { 30, 65 } },
        { recipe = "Coarse Sharpening Stone", item = 2863, learn = 65, yellow = 65, green = 72, grey = 80, mats = { [2836] = 1 }, use = { 65, 75 } },
        { recipe = "Coarse Grinding Stone", item = 3478, learn = 75, yellow = 75, green = 87, grey = 100, mats = { [2836] = 2 }, use = { 75, 90 } },
        { recipe = "Runed Copper Belt", item = 2857, learn = 70, yellow = 110, green = 130, grey = 150, mats = { [2840] = 10 },
          station = "anvil", use = { 90, 110 } },
        { recipe = "Rough Bronze Leggings", item = 2865, learn = 105, yellow = 145, green = 160, grey = 175, mats = { [2841] = 6 },
          station = "anvil", use = { { 110, 125 }, { 140, 160 } } },
        { recipe = "Heavy Grinding Stone", item = 3486, learn = 125, yellow = 125, green = 137, grey = 150, mats = { [2838] = 3 }, use = { 125, 140 } },
        { recipe = "Green Iron Leggings", item = 3842, learn = 155, yellow = 180, green = 192, grey = 205,
          mats = { [3575] = 8, [3486] = 1, [2605] = 1 }, station = "anvil", use = { 160, 165 } },
        { recipe = "Green Iron Bracers", item = 3835, learn = 165, yellow = 190, green = 202, grey = 215,
          mats = { [3575] = 6, [2605] = 1 }, station = "anvil", use = { 165, 200 } },
        { recipe = "Solid Grinding Stone", item = 7966, learn = 200, yellow = 200, green = 205, grey = 210, mats = { [7912] = 4 }, use = { 200, 210 } },
        { recipe = "Heavy Mithril Gauntlet", item = 7919, learn = 205, yellow = 225, green = 235, grey = 245,
          mats = { [3860] = 6, [4338] = 4 }, station = "anvil", use = { 210, 230 } },
        { recipe = "Mithril Coif", item = 7931, learn = 230, yellow = 250, green = 260, grey = 270,
          mats = { [3860] = 10, [4338] = 6 }, station = "anvil", use = { 230, 250 } },
        { recipe = "Dense Sharpening Stone", item = 12404, learn = 250, yellow = 255, green = 257, grey = 260, mats = { [12365] = 1 }, use = { 250, 260 } },
        { recipe = "Heavy Mithril Boots", item = 7933, learn = 235, yellow = 255, green = 265, grey = 275,
          mats = { [3860] = 14, [4304] = 4 }, station = "anvil", use = { 260, 270 } },
    },
})

ns:Register("profGuide", "Mining", {
    kind = "gather", tool = 2901,
    -- Nodes raise Mining; smelting does too (craft-like steps below).
    nodes = {
        { item = 2770, learn = 1, yellow = 25, green = 50, grey = 100 },
        { item = 2771, learn = 65, yellow = 90, green = 115, grey = 165 },
        { item = 2772, learn = 125, yellow = 150, green = 175, grey = 225 },
    },
    steps = {
        { recipe = "Smelt Copper", item = 2840, learn = 1, yellow = 25, green = 47, grey = 70, mats = { [2770] = 1 }, station = "forge" },
        { recipe = "Smelt Tin", item = 3576, learn = 65, yellow = 65, green = 70, grey = 75, mats = { [2771] = 1 }, station = "forge" },
    },
})

ns:Register("profGuide", "First Aid", {
    kind = "craft",
    steps = {
        { recipe = "Linen Bandage", item = 1251, learn = 1, yellow = 30, green = 45, grey = 60, mats = { [2589] = 1 }, use = { 1, 40 } },
        { recipe = "Heavy Linen Bandage", item = 2581, learn = 40, yellow = 50, green = 75, grey = 100, mats = { [2589] = 2 }, use = { 40, 80 } },
        { recipe = "Wool Bandage", item = 3530, learn = 80, yellow = 80, green = 115, grey = 150, mats = { [2592] = 1 }, use = { 80, 115 } },
        { recipe = "Heavy Wool Bandage", item = 3531, learn = 115, yellow = 115, green = 150, grey = 185, mats = { [2592] = 2 }, use = { 115, 150 } },
        { recipe = "Silk Bandage", item = 6450, learn = 150, yellow = 150, green = 180, grey = 210, mats = { [4306] = 1 }, use = { 150, 180 } },
        { recipe = "Heavy Silk Bandage", item = 6451, learn = 180, yellow = 180, green = 210, grey = 240, mats = { [4306] = 2 },
          recipeItem = 16112, use = { 180, 210 } },
        { recipe = "Mageweave Bandage", item = 8544, learn = 210, yellow = 210, green = 240, grey = 270, mats = { [4338] = 1 },
          recipeItem = 16113, use = { 210, 240 } },
        { recipe = "Heavy Mageweave Bandage", item = 8545, learn = 240, yellow = 240, green = 270, grey = 300, mats = { [4338] = 2 }, use = { 240, 260 } },
        { recipe = "Runecloth Bandage", item = 14529, learn = 260, yellow = 260, green = 290, grey = 320, mats = { [14047] = 1 }, use = { 260, 290 } },
        { recipe = "Heavy Runecloth Bandage", item = 14530, learn = 290, yellow = 290, green = 320, grey = 350, mats = { [14047] = 2 }, use = { 290, 300 } },
    },
})

-- One path per side from 40 to 130 (the recipes and meats differ), then the
-- same for both. Fish from your Fishing stops levels Cooking as well as the
-- meat it matches (same colours), so the fish recipes have no path of their
-- own: they stand in for meat you'd otherwise farm. Past 225 the guides use
-- meats Flow has no drop data for yet.
ns:Register("profGuide", "Cooking", {
    kind = "craft",
    steps = {
        { recipe = "Charred Wolf Meat", item = 2679, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [2672] = 1 },
          station = "fire", use = { 1, 40 } },
        { recipe = "Roasted Boar Meat", item = 2681, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [769] = 1 },
          station = "fire", use = { 1, 40 } },
        { recipe = "Brilliant Smallfish", item = 6290, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [6291] = 1 },
          station = "fire", recipeItem = 6325, use = { 1, 40 } },
        -- Horde.
        { recipe = "Roasted Kodo Meat", item = 5474, learn = 35, yellow = 75, green = 95, grey = 115, mats = { [5467] = 1, [2678] = 1 },
          station = "fire", recipeItem = 5484, faction = "Horde", use = { 40, 50 } },
        { recipe = "Strider Stew", item = 5477, learn = 50, yellow = 90, green = 110, grey = 130, mats = { [5469] = 1, [4536] = 1 },
          station = "fire", recipeItem = 5486, faction = "Horde", use = { 50, 100 } },
        { recipe = "Crispy Lizard Tail", item = 5479, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [5470] = 1, [2692] = 1 },
          station = "fire", recipeItem = 5488, faction = "Horde", use = { 100, 130 } },
        -- Alliance.
        { recipe = "Smoked Bear Meat", item = 6890, learn = 40, yellow = 80, green = 100, grey = 120, mats = { [3173] = 1 },
          station = "fire", recipeItem = 6892, faction = "Alliance", use = { 40, 75 } },
        { recipe = "Crab Cake", item = 2683, learn = 75, yellow = 115, green = 135, grey = 155, mats = { [2674] = 1, [2678] = 1 },
          station = "fire", faction = "Alliance", use = { 75, 85 } },
        { recipe = "Cooked Crab Claw", item = 2682, learn = 85, yellow = 125, green = 145, grey = 165, mats = { [2675] = 1, [2678] = 1 },
          station = "fire", recipeItem = 2698, faction = "Alliance", use = { 85, 100 } },
        { recipe = "Seasoned Wolf Kabob", item = 1017, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [1015] = 2, [2665] = 1 },
          station = "fire", recipeItem = 2701, faction = "Alliance", use = { 100, 130 } },
        -- Both.
        { recipe = "Curiously Tasty Omelet", item = 3665, learn = 130, yellow = 170, green = 190, grey = 210, mats = { [3685] = 1, [2692] = 1 },
          station = "fire", recipeItem = 3682, use = { 130, 175 } },
        { recipe = "Roast Raptor", item = 12210, learn = 175, yellow = 215, green = 235, grey = 255, mats = { [12184] = 1, [2692] = 1 },
          station = "fire", recipeItem = 12228, use = { 175, 225 } },
        -- Fish (no path of their own, see above).
        { recipe = "Longjaw Mud Snapper", item = 4592, learn = 50, yellow = 90, green = 110, grey = 130, mats = { [6289] = 1 },
          station = "fire", recipeItem = 6328 },
        { recipe = "Bristle Whisker Catfish", item = 4593, learn = 100, yellow = 140, green = 160, grey = 180, mats = { [6308] = 1 },
          station = "fire", recipeItem = 6330 },
        { recipe = "Mithril Head Trout", item = 8364, learn = 175, yellow = 215, green = 235, grey = 255, mats = { [8365] = 1 },
          station = "fire", recipeItem = 17062 },
    },
})

ns:Register("profGuide", "Fishing", { kind = "gather", spots = true, tool = 6256, lure = 6529,
    -- Keep up with the water you'll fish in, not with crafting: starting-zone
    -- lakes need ~25 so fish don't get away, the next zones ~75, then ~150.
    pace = { { 1, 1 }, { 10, 25 }, { 20, 75 }, { 30, 150 }, { 40, 225 }, { 50, 300 } },
    tip = "Tip: a Shiny Bauble (+25 Fishing for 10 minutes) catches more while your skill is low. Flow's key puts it on your pole." })

ns:Register("profGuide", "Herbalism", { kind = "gather", spots = true })
