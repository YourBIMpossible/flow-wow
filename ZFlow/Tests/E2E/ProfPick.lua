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
local MAGE = "Two profession slots are free. You wear cloth: Tailoring makes bags and cloth gear "
    .. "from the cloth you loot, and Enchanting turns the gear you do not need into enchants."
local HERB = "One profession slot is free. Alchemy goes with your Herbalism: it turns the herbs "
    .. "you gather into potions."

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
    t.eq(addon.problems:count(), 0)
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
    c.professions = function() local none; return none.read end
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

return tests
