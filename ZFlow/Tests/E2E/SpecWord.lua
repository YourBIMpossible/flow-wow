local _, ns = ...
-- G31, the parts that do not wait for probe ZP2, on the whole add-on loaded
-- on a fake client with the real class packs, through the real entry
-- points (the slash command, the PLAYER_LEVEL_UP event, the item tooltip):
--   * the spec word: the levelling spec the class's pack recommends and
--     why, then the role you chose;
--   * the line said when you reach the level talents open at;
--   * the role you chose driving the tooltip's verdict line.
-- Lead section 280: every one of the nine classes has a recommendation.
-- Lead section 236: the class read late, the class read raising then
-- recovering, a reload, the role setting changed. Nothing here reads
-- talents; unspent points wait for ZP2. Offline: the fake client's reads,
-- not the game's. Made-up items. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ROLE_WORDS = { dps = "damage", heal = "healing", tank = "tanking" }
local STR = "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG = "item:4301", "item:4302"

-- opts: class, level, role (spec.role saved), account, char (saved tables).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = opts.char or {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass(opts.class or "WARRIOR"); c.setFaction("Alliance"); c.setLevel(opts.level or 9); c.setDead(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function line(text) return ns.id.title .. ": " .. text end

local function problemCount(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

-- The first line the word must print for a class, from the pack itself.
local function firstLine(addon, class)
    local pack = addon.Packs[class]
    local role = pack.levelling.role
    return line("recommended levelling spec: " .. pack.roles[role].name .. " (" .. ROLE_WORDS[role] .. ").")
end

-- --------------------------------------------------------- all nine classes
tests["spec e2e: every class pack has a levelling recommendation (section 280)"] = function(t)
    local missing = {}
    for _, class in ipairs(CLASSES) do
        local pack, lv
        if type(ns.Packs) == "table" then pack = ns.Packs[class] end
        if type(pack) == "table" then lv = pack.levelling end
        if type(lv) ~= "table" then
            missing[#missing + 1] = class
        else
            t.ok(type(pack.roles[lv.role]) == "table", class .. ": the role is one the pack names")
            t.ok(type(pack.roles[lv.role].name) == "string", class .. ": that role has a name")
            t.ok(type(lv.why) == "table" and #lv.why >= 1, class .. ": at least one reason")
            t.eq(lv.evidence, "first guess", class .. ": not read from the game, so a first guess")
        end
    end
    t.eq(table.concat(missing, ", "), "", "classes with no levelling recommendation")
end

for _, class in ipairs(CLASSES) do
    tests["spec e2e: " .. class .. " - the word names the spec, every reason, then your role"] = function(t)
        local c, addon = boot({ class = class })
        local pack = addon.Packs[class]
        t.ok(type(pack) == "table" and type(pack.levelling) == "table", class .. ": a levelling row")
        if type(pack) ~= "table" or type(pack.levelling) ~= "table" then return end
        local problems = problemCount(addon)
        local out = said(c, "spec")
        t.eq(out[1], firstLine(addon, class))
        for i, why in ipairs(pack.levelling.why) do t.eq(out[1 + i], line(why), class .. ": reason " .. i) end
        t.eq(#out, #pack.levelling.why + 3, class .. ": the spec, the reasons, your role, where it comes from")
        t.ok(out[#out - 1]:find("no role chosen", 1, true) ~= nil, class .. ": none chosen: " .. tostring(out[#out - 1]))
        t.ok(out[#out]:find("the default", 1, true) ~= nil, class .. ": no talents read: " .. tostring(out[#out]))
        t.eq(problemCount(addon), problems, class .. ": the word records no problem")
    end
end

-- ------------------------------------------------------------------ the word
tests["spec e2e: the word has a line of help"] = function(t)
    local c, addon = boot()
    t.eq(type(addon.diag.help.spec), "string")
    t.eq(said(c, "help spec"), { line(ns.id.slash .. " spec - " .. tostring(addon.diag.help.spec)) })
end

tests["spec e2e: nothing is said at login"] = function(t)
    local c = boot()
    local hits = {}
    for _, text in ipairs(c.printed) do
        local s = tostring(text)
        if s:find("levelling spec", 1, true) or s:find("talents unlocked", 1, true) then hits[#hits + 1] = s end
    end
    t.eq(hits, {}, "nothing of the spec or talents is said at login")
end

tests["spec e2e: the role setting changed - the last line follows it"] = function(t)
    local c, addon = boot({ class = "WARRIOR" })
    t.ok(#said(c, "spec") >= 4, "the spec, a reason, your role, where it comes from")
    said(c, "role dps")
    local out = said(c, "spec")
    t.eq(out[#out - 1], line("your role is set to damage (" .. addon.Packs.WARRIOR.roles.dps.name
        .. "), the recommended one."))
    t.eq(addon.settings:set("spec.role", "tank"), true)
    out = said(c, "spec")
    t.ok(out[#out - 1]:find("tanking (" .. addon.Packs.WARRIOR.roles.tank.name .. ")", 1, true) ~= nil,
        "tank: " .. tostring(out[#out - 1]))
    t.ok(out[#out - 1]:find("yours to choose", 1, true) ~= nil, "never a fault: " .. tostring(out[#out - 1]))
    t.ok(out[#out]:find("your role setting", 1, true) ~= nil, "from your setting: " .. tostring(out[#out]))
    t.eq(out[1], firstLine(addon, "WARRIOR"), "the recommendation does not move with your role")
end

tests["spec e2e: a role the class has no part for"] = function(t)
    local c = boot({ class = "MAGE", role = "heal" })
    local out = said(c, "spec")
    t.ok(out[#out - 1]:find("no healing part", 1, true) ~= nil, tostring(out[#out - 1]))
end

tests["spec e2e: a reload keeps the role the word names"] = function(t)
    local c = boot({ class = "PALADIN" })
    said(c, "role tank")
    local before = said(c, "spec")
    local again = boot({ class = "PALADIN", account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(said(again, "spec"), before, "the same lines after the reload")
    t.ok(before[#before]:find("tanking", 1, true) ~= nil, tostring(before[#before]))
end

-- ------------------------------------------------- late and unavailable reads
tests["spec e2e: the class read late - said in words, then the lines once it is read"] = function(t)
    local c, addon = boot({ class = "DRUID" })
    local problems = problemCount(addon)
    c.setClass(nil)
    local out = said(c, "spec")
    t.eq(#out, 1)
    t.ok(out[1]:find("class is not known yet", 1, true) ~= nil, tostring(out[1]))
    c.setClass("DRUID")
    t.eq(said(c, "spec")[1], firstLine(addon, "DRUID"))
    t.eq(problemCount(addon), problems, "a class not read yet is not a problem")
end

tests["spec e2e: the class read raising, then recovering"] = function(t)
    local c, addon = boot({ class = "SHAMAN" })
    local real = c.class
    c.class = function() error("class read failed (test)") end
    local out = said(c, "spec")
    t.eq(#out, 1, "one line, no Lua error: " .. table.concat(out, " | "))
    t.ok(out[1]:find("class is not known yet", 1, true) ~= nil, tostring(out[1]))
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP", 10)
    local unlocked, notKnown = 0, 0
    for i = before + 1, #c.printed do
        local text = tostring(c.printed[i])
        if text:find("talents unlocked", 1, true) then unlocked = unlocked + 1 end
        if text:find("class is not known yet", 1, true) then notKnown = notKnown + 1 end
    end
    t.eq(unlocked, 1, "the level line is still said while the read raises")
    t.eq(notKnown, 1, "and the class is said to be not known, once")
    c.class = real
    t.eq(said(c, "spec")[1], firstLine(addon, "SHAMAN"))
end

-- ------------------------------------------------------------ the level line
tests["spec e2e: reaching level 10 says talents unlocked, then the spec lines"] = function(t)
    local c, addon = boot({ class = "PRIEST", level = 9 })
    local want = said(c, "spec")
    local problems = problemCount(addon)
    local before = #c.printed
    c.setLevel(10)
    c.fire("PLAYER_LEVEL_UP", 10)
    local out = {}
    for i = before + 1, #c.printed do
        local text = tostring(c.printed[i])
        if text:find("talents unlocked", 1, true) or text:find("levelling spec", 1, true) then out[#out + 1] = text end
    end
    t.eq(#out, 2, "the level line and the spec line: " .. table.concat(out, " | "))
    t.ok(out[1]:find("talents unlocked", 1, true) ~= nil, "the level line first")
    t.eq(out[2], want[1])
    t.eq(problemCount(addon), problems, "the level line records no problem")
end

tests["spec e2e: other levels say nothing of talents"] = function(t)
    local c = boot({ class = "PRIEST", level = 8 })
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP", 9)
    c.fire("PLAYER_LEVEL_UP", 11)
    c.fire("PLAYER_LEVEL_UP", 20)
    local hits = {}
    for i = before + 1, #c.printed do
        local s = tostring(c.printed[i])
        if s:find("talents unlocked", 1, true) then hits[#hits + 1] = s end
    end
    t.eq(hits, {}, "levels 9, 11 and 20 say nothing of talents")
end

-- A reload at level 10 is a login, not a level-up: the line is not said again.
tests["spec e2e: a reload at level 10 does not say talents unlocked again"] = function(t)
    local c = boot({ class = "ROGUE", level = 9 })
    c.setLevel(10)
    c.fire("PLAYER_LEVEL_UP", 10)
    local again = boot({ class = "ROGUE", level = 10, account = c.saved(ns.id.accountDB),
                         char = c.saved(ns.id.charDB) })
    local hits = {}
    for _, text in ipairs(again.printed) do
        local s = tostring(text)
        if s:find("talents unlocked", 1, true) then hits[#hits + 1] = s end
    end
    t.eq(hits, {}, "the reload at 10 does not say talents unlocked")
end

-- --------------------------------------------------- the role and the tooltip
-- Warrior weights (ZFlow/Classes/Warrior.lua): dps Strength 1.0, Stamina
-- 0.35; tank Stamina 1.0, Strength 0.6. The worn helm has 2 Strength (2 and
-- 1.2), the new one 10 (10 and 6).
local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function gearUp(c)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setWorn(1, WORN)
end

local function hover(c, link)
    local out = {}
    for _, a in ipairs(c.showItemTooltip(link)) do out[#out + 1] = a.text end
    return out
end

local function at(list, text)
    for i = 1, #list do
        if list[i] == text then return i end
    end
    return nil
end

local DPS, TANK = "Upgrade for your head piece (+8, dps)", "Upgrade for your head piece (+4.8, tank)"

tests["spec e2e: no role chosen - the tooltip has a verdict for every role"] = function(t)
    local c = boot({ class = "WARRIOR", level = 10 })
    gearUp(c)
    local lines = hover(c, STRONG)
    t.ok(at(lines, DPS) ~= nil and at(lines, TANK) ~= nil, table.concat(lines, " | "))
end

tests["spec e2e: the role word drives the tooltip verdict, and none brings every role back"] = function(t)
    local c = boot({ class = "WARRIOR", level = 10 })
    gearUp(c)
    said(c, "role tank")
    local lines = hover(c, STRONG)
    t.eq(lines[1], TANK)
    t.eq(at(lines, DPS), nil, "no verdict for a role not chosen: " .. table.concat(lines, " | "))
    said(c, "role dps")
    lines = hover(c, STRONG)
    t.eq(lines[1], DPS)
    t.eq(at(lines, TANK), nil, "no verdict for a role not chosen: " .. table.concat(lines, " | "))
    said(c, "role none")
    lines = hover(c, STRONG)
    t.ok(at(lines, DPS) ~= nil and at(lines, TANK) ~= nil, "none: " .. table.concat(lines, " | "))
end

tests["spec e2e: a role the pack has no weights for - the tooltip keeps every role"] = function(t)
    local c = boot({ class = "WARRIOR", level = 10, role = "heal" })
    gearUp(c)
    local lines = hover(c, STRONG)
    t.ok(at(lines, DPS) ~= nil and at(lines, TANK) ~= nil, table.concat(lines, " | "))
end

tests["spec e2e: a reload keeps the chosen role's verdict alone"] = function(t)
    local c = boot({ class = "WARRIOR", level = 10 })
    said(c, "role tank")
    local again = boot({ class = "WARRIOR", level = 10, account = c.saved(ns.id.accountDB),
                         char = c.saved(ns.id.charDB) })
    gearUp(again)
    local lines = hover(again, STRONG)
    t.eq(lines[1], TANK)
    t.eq(at(lines, DPS), nil, table.concat(lines, " | "))
end

tests["spec e2e: item data late - the chosen role's verdict once it is read"] = function(t)
    local c = boot({ class = "WARRIOR", level = 10, role = "tank" })
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItem(WORN, helm({ [STR] = 2 }))
    c.setWorn(1, WORN)
    t.eq(at(hover(c, STRONG), TANK), nil, "nothing while the item is not loaded")
    c.setItem(STRONG, helm({ [STR] = 10 }))
    local lines = hover(c, STRONG)
    t.eq(lines[1], TANK)
    t.eq(at(lines, DPS), nil, table.concat(lines, " | "))
end

return tests
