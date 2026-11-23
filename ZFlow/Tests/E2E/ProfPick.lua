local _, ns = ...
-- The profession picker (G17) end to end, on the whole add-on loaded on a
-- fake client. A character of level 3 or more with a free primary
-- profession slot gets one advisor prompt saying which profession to learn
-- and why, from its class and the professions it already has. Advice only:
-- nothing is trained. Per lead section 236: the professions not read and
-- then read, a profession learned (event) taking the advice away, a reload,
-- the read raising and then recovering, and the setting off. Not tested in
-- game.
local tests = {}

local ID = "aps.profPick"
local HINT = " Choices: " .. ns.id.slash .. " professions."
local MAGE = "Two profession slots are free. You wear cloth: Tailoring makes bags and cloth gear "
    .. "from the cloth you loot, and Enchanting turns the gear you do not need into enchants." .. HINT
local HERB = "One profession slot is free. Alchemy goes with your Herbalism: it turns the herbs "
    .. "you gather into potions." .. HINT

-- opts: class, level, professions (nil: not read), account, char.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass(opts.class or "MAGE")
    c.setLevel(opts.level or 10)
    c.setFaction("Alliance")
    c.setProfessions(opts.professions)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local advisor = addon.use("advisor")
    if type(advisor) ~= "table" or type(advisor.List) ~= "function" then return nil end
    for _, p in ipairs(advisor.List()) do
        if p.id == ID then return p end
    end
    return nil
end

local function text(addon)
    local p = prompt(addon)
    return p and p.text
end

tests["profession picker: no professions, a mage is told Tailoring and Enchanting"] = function(t)
    local _, addon = boot({ professions = {} })
    t.eq(text(addon), MAGE)
    -- Lead (section 274): the whole add-on lists problems of its own at boot on
    -- the fake client. The level-1 boot, where the picker is silent, is the
    -- baseline: this proves no extra problem compared with level 1, not none.
    local _, quiet = boot({ professions = {}, level = 1 })
    t.eq(text(quiet), nil, "below level 3: no advice")
    t.eq(addon.problems:count(), quiet.problems:count(), "the picker adds no problem")
end

tests["profession picker: one gathering profession, its craft is named"] = function(t)
    local _, addon = boot({ professions = { "Herbalism", "Cooking", "Swords" } })
    t.eq(text(addon), HERB)
end

tests["profession picker: two primaries, no advice"] = function(t)
    local _, addon = boot({ professions = { "Herbalism", "Alchemy" } })
    t.eq(prompt(addon), nil)
end

tests["profession picker: below level 3, no advice"] = function(t)
    local _, addon = boot({ level = 2, professions = {} })
    t.eq(prompt(addon), nil)
end

tests["profession picker: professions not read, then read"] = function(t)
    local c, addon = boot()
    t.eq(prompt(addon), nil, "not read: nothing guessed")
    c.setProfessions({})
    c.fire("SKILL_LINES_CHANGED")
    t.eq(text(addon), MAGE, "read: the advice")
end

tests["profession picker: a profession learned takes the advice away"] = function(t)
    local c, addon = boot({ professions = { "Herbalism" } })
    t.eq(text(addon), HERB)
    c.setProfessions({ "Herbalism", "Alchemy" })
    c.fire("SKILL_LINES_CHANGED")
    t.eq(prompt(addon), nil, "both slots used: gone")
end

tests["profession picker: a reload keeps the advice while the slot is free"] = function(t)
    local c, addon = boot({ professions = {} })
    t.eq(text(addon), MAGE)
    local _, addon2 = boot({ professions = {}, account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(text(addon2), MAGE, "said again after the reload")
end

tests["profession picker: the read raising, then recovering"] = function(t)
    local c, addon = boot({ professions = {} })
    local real = c.professions
    c.professions = function() error("professions read failed (test)") end
    c.fire("SKILL_LINES_CHANGED")
    t.eq(prompt(addon), nil, "the read raised: no advice")
    t.eq(addon:ModuleState("profPick"), "started", "the module stays on")
    c.professions = real
    c.fire("SKILL_LINES_CHANGED")
    t.eq(text(addon), MAGE, "recovered: the advice is back")
end

tests["profession picker: the setting off takes the advice away, on brings it back"] = function(t)
    local c, addon = boot({ professions = {} })
    t.eq(text(addon), MAGE)
    addon.settings:set("professions.picker", false)
    c.advance(5, 20)
    t.eq(prompt(addon), nil, "off: gone")
    addon.settings:set("professions.picker", true)
    c.advance(5, 20)
    t.eq(text(addon), MAGE, "on: back")
end

tests["profession picker: the setting row is on by default and filed under professions"] = function(t)
    local _, addon = boot()
    local row = addon.settings:row("professions.picker")
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "professions")
    t.eq(addon.settings:get("professions.picker"), true)
    local words = table.concat(row and row.synonyms or {}, " ")
    t.ok(words:find("profession", 1, true) ~= nil and words:find("choose", 1, true) ~= nil, "synonyms: " .. words)
end

-- The three choices Flow's card gave (lead section 274), as the word
-- "professions" on the slash command: later (Not now), choose (Choose
-- others) and route (Add to my route); reset undoes them.

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return table.concat(out, "\n")
end

local function reload(c, opts)
    opts.account = c.saved(ns.id.accountDB)
    opts.char = c.saved(ns.id.charDB)
    return boot(opts)
end

local function api(addon)
    local a = addon.use("profPick")
    if type(a) ~= "table" then return {} end
    return a
end

local function step(addon)
    local a = api(addon)
    if type(a.Step) ~= "function" then return nil end
    return a.Step()
end

local function skillOf(addon)
    local s = step(addon)
    return s and s.skill
end

local TAILOR = { roles = { trainer = true }, trains = { Tailoring = true }, factions = { Alliance = true },
                 map = 1453, x = 0.4, y = 0.6 }

tests["profession picker: later dismisses until the next level, and a reload keeps it"] = function(t)
    local c, addon = boot({ professions = {} })
    t.eq(text(addon), MAGE)
    local out = said(c, "professions later")
    t.ok(out:find("level 11", 1, true) ~= nil, "says when it comes back: " .. out)
    t.eq(prompt(addon), nil, "dismissed")
    local c2, addon2 = reload(c, { professions = {} })
    t.eq(prompt(addon2), nil, "still dismissed after the reload")
    c2.setLevel(11)
    c2.advance(5, 20)
    t.eq(text(addon2), MAGE, "back at the next level")
end

tests["profession picker: reset brings a dismissed prompt back"] = function(t)
    local c, addon = boot({ professions = {} })
    said(c, "professions later")
    t.eq(prompt(addon), nil)
    said(c, "professions reset")
    t.eq(text(addon), MAGE)
end

tests["profession picker: choose names the pair and the advice follows it, after a reload too"] = function(t)
    local c, addon = boot({ professions = {} })
    local out = said(c, "professions choose mining herbalism")
    t.ok(out:find("Mining and Herbalism", 1, true) ~= nil, "confirms the choice: " .. out)
    t.eq(text(addon), "Your choice: learn Mining and Herbalism." .. HINT)
    local c2, addon2 = reload(c, { professions = { "Mining" } })
    t.eq(text(addon2), "Your choice: learn Herbalism." .. HINT, "kept; Mining learned is left out")
    c2.setProfessions({ "Mining", "Herbalism" })
    c2.fire("SKILL_LINES_CHANGED")
    t.eq(prompt(addon2), nil, "both learned: no advice")
end

tests["profession picker: choose refuses a name that is no primary profession"] = function(t)
    local c, addon = boot({ professions = {} })
    local out = said(c, "professions choose cooking")
    t.ok(out:find("cooking", 1, true) ~= nil, "names it: " .. out)
    t.eq(text(addon), MAGE, "the advice is as before")
end

-- PP3-2: a name said twice counts once, wherever it repeats.
tests["profession picker: choose counts a repeated name once"] = function(t)
    local c, addon = boot({ professions = {} })
    local out = said(c, "professions choose mining mining mining")
    t.ok(out:find("your choice is saved: Mining.", 1, true) ~= nil, "one name, saved: " .. out)
    t.eq(text(addon), "Your choice: learn Mining." .. HINT)
    out = said(c, "professions choose mining herbalism mining")
    t.ok(out:find("Mining and Herbalism", 1, true) ~= nil, "a pair, saved: " .. out)
    t.eq(text(addon), "Your choice: learn Mining and Herbalism." .. HINT)
    -- PP3-2: a repeat that is not of the first name. The old check held each
    -- name up to the first only, so this was three names and the answer was
    -- "name one or two professions".
    out = said(c, "professions choose mining herbalism herbalism")
    t.ok(out:find("your choice is saved: Mining and Herbalism.", 1, true) ~= nil,
         "a later repeat counts once: " .. out)
end

-- PP3-1: as Flow did, "later" only quiets the prompt; a trainer step asked
-- for stays on the route (program-integ Modules/Professions.lua:349-353 sets
-- snoozeLevel only, and :441 reads it only for the reminder card).
tests["profession picker: later keeps a route step asked for"] = function(t)
    local c, addon = boot({ professions = {} })
    said(c, "professions route")
    said(c, "professions later")
    t.eq(prompt(addon), nil, "the prompt is quiet")
    t.eq(skillOf(addon), "Tailoring", "the route step stays")
end

tests["profession picker: route gives a words-only step, then a place once a trainer is learned"] = function(t)
    local c, addon = boot({ professions = {} })
    c.setPosition(1453, 0.5, 0.5)
    t.eq(step(addon), nil, "not asked for: no step")
    said(c, "professions route")
    local s = step(addon)
    t.eq(s and s.skill, "Tailoring")
    t.eq(s and s.place, nil, "no trainer saved: words only")
    t.eq(api(addon).Lines(), { "A Tailoring trainer in a capital city teaches it." })
    local db = c.saved(ns.id.accountDB)
    db.learned = db.learned or {}
    db.learned.places = db.learned.places or {}
    db.learned.places.npcs = { ["Lawrence Schneider"] = TAILOR }
    s = step(addon)
    t.eq(s and s.name, "Lawrence Schneider", "the trainer learned late is used")
    t.eq(s and s.place and s.place.map, 1453)
    local _, addon2 = reload(c, { professions = {} })
    t.eq(skillOf(addon2), "Tailoring", "the route choice is kept after a reload")
end

tests["profession picker: the route step follows the read, raising and recovering"] = function(t)
    local c, addon = boot({ professions = {} })
    said(c, "professions route")
    t.eq(skillOf(addon), "Tailoring")
    local real = c.professions
    c.professions = function() error("professions read failed (test)") end
    t.eq(step(addon), nil, "the read raised: no step")
    c.professions = real
    t.eq(skillOf(addon), "Tailoring", "recovered")
    c.setProfessions({ "Tailoring" })
    t.eq(skillOf(addon), "Enchanting", "Tailoring learned: the next one")
end

tests["profession picker: the word has its help line"] = function(t)
    local c = boot({ professions = {} })
    local out = said(c, "help professions")
    t.ok(out:find("later", 1, true) ~= nil and out:find("choose", 1, true) ~= nil
        and out:find("route", 1, true) ~= nil, "help: " .. out)
end

return tests
