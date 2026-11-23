local _, ns = ...
-- The setting rows whose features left them "the lead's to add" (lead
-- section 187). Until this file, none of these keys was a kernel row: the
-- settings page and /zflow set refused them ("no setting is called ..."),
-- and each feature read nil and stayed at its built-in default, so the
-- player could not switch it. Types and defaults are the features' own
-- (each file's "Setting:" note) and, where it holds the key, the settings
-- model's (Settings/Model.lua). Scope: char where the feature says so,
-- else account. A key some module already declares is not declared again.
-- group: the row's topic and section in Settings/Topics.lua; synonyms: more
-- words the settings search finds it by.
--
-- ui.intro and buttons.* are declared by their own modules (Intro,
-- WindowButtons), later in the load.
--
-- Not here on purpose: sell.*, auction.chartClick and buffButton.* are in
-- the model for the Flow import only; no Z-Flow feature reads them yet, so
-- no switch is shown that would do nothing.

local R = {}
ns.Settings = ns.Settings or {}
ns.Settings.Rows = R

R.ROWS = {
    { key = "quest.arrow", scope = "account", type = "bool", default = true, group = "travel.arrow",
      synonyms = { "arrow", "waypoint", "quest", "pointer", "direction" },
      label = "Point the quest arrow at my quests",
      help = "With no waypoint of your own, the quest arrow points at the next place for the quests in your log." },
    { key = "nav.flightPaths", scope = "account", type = "bool", default = true, group = "travel.flights",
      synonyms = { "flight", "taxi", "gryphon", "wind rider", "fly" },
      label = "Learn flight paths and use them on the way",
      help = "Keeps the flight paths your own flight maps show and offers a flight as a step when it is quicker." },
    { key = "nav.crossings", scope = "account", type = "bool", default = true, group = "travel.flights",
      synonyms = { "boat", "zeppelin", "ship", "continent", "crossing" },
      label = "Use boats and zeppelins on the way",
      help = "For a place on another continent, the arrow points at the boarding place of a boat or zeppelin you have taken twice. Your trips are still noted when this is off." },
    { key = "nav.zoneFirst", scope = "account", type = "bool", default = true, group = "travel.route",
      synonyms = { "route", "order", "zone", "quest" },
      label = "Finish quests in this zone first",
      help = "On, what is left near you on this map comes first. Off, the quest arrow follows your quest log order, even when that leads away." },
    { key = "vendor.list", scope = "account", type = "bool", default = true, group = "bags",
      synonyms = { "sell", "vendor", "junk", "merchant", "grey" },
      label = "Show the sell list at a merchant",
      help = "A list of what you might sell, beside the merchant window. Look only: nothing is sold." },
    { key = "repair.warnBelow", scope = "account", type = "number", default = 0.20, min = 0, max = 1, group = "bags",
      synonyms = { "repair", "durability", "broken", "armor" },
      label = "Warn when gear is below this share",
      help = "The repair warning shows when your most worn item is below this share of its durability (0 to 1)." },
    { key = "bank.list", scope = "account", type = "bool", default = true, group = "bags",
      synonyms = { "bank", "banker", "deposit", "store" },
      label = "Show the bank list at the bank",
      help = "A list of what could go to the bank, beside the bank window. Look only: nothing is moved." },
    { key = "loot.junkNote", scope = "account", type = "bool", default = true, group = "gear.loot",
      synonyms = { "grey", "loot", "vendor trash", "note" },
      label = "Note grey loot",
      help = "A short note in chat when you loot a grey item." },
    { key = "loot.record", scope = "account", type = "bool", default = true, group = "gear.loot",
      synonyms = { "drops", "loot", "record", "count" },
      label = "Record what my loot windows show",
      help = "Keeps what your own loot windows showed, for drop counts. Nothing is looted for you." },
    { key = "advisor.panel", scope = "char", type = "bool", default = true, group = "general.windows",
      synonyms = { "advice", "advisor", "tips", "prompts" },
      label = "Show the advisor panel",
      help = "Off hides the panel at once; its prompts are kept and show again when it is back on." },
}

-- Declares each row on kernel k that k does not hold yet. Returns how many.
function R.Declare(k)
    local n = 0
    if type(k) ~= "table" or type(k.Setting) ~= "function" or type(k.settings) ~= "table" then return n end
    for _, row in ipairs(R.ROWS) do
        if k.settings:row(row.key) == nil then
            local copy = {}
            for f, v in pairs(row) do copy[f] = v end
            if k:Setting(copy) then n = n + 1 end
        end
    end
    return n
end

R.Declare(ns)
