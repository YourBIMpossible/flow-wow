local _, ns = ...
-- Talent points end to end (parity C-61, C-49), on the whole add-on loaded
-- on a fake client. At the talent level with points, chat says "talents
-- unlocked" once and the advisor has "Spend N talent point(s)" while out of
-- combat; at 0 points the prompt is gone. Level 9, or the points not read,
-- says nothing. Section 236: the read raising then recovering, and a
-- reload. Offline: the reads are the fake client ones. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local PROMPT = "aps.talents.spend"

-- opts.level, opts.points (nil: not read), opts.class, opts.char (a reload).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass(opts.class or "WARRIOR")
    c.setLevel(opts.level or 10)
    if type(c.setUnspentTalents) == "function" then c.setUnspentTalents(opts.points) end
    c.setCombat(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == PROMPT then return p.text end
    end
    return nil
end

local function unlockedSaid(c)
    local n = 0
    for i = 1, #c.printed do
        if tostring(c.printed[i]):lower():find("talents unlocked", 1, true) then n = n + 1 end
    end
    return n
end

local function points(c, n)
    c.setUnspentTalents(n)
    c.fire("CHARACTER_POINTS_CHANGED", 1)
    c.advance(1, 5)
end

tests["talents: reaching level 10 with 1 point says talents unlocked once and prompts Spend 1 talent point"] = function(t)
    local c, addon = start({ level = 9, points = 0 })
    t.eq(prompt(addon), nil, "level 9")
    c.setLevel(10); c.setUnspentTalents(1)
    c.fire("PLAYER_LEVEL_UP", 10)
    c.fire("CHARACTER_POINTS_CHANGED", 1)
    c.advance(1, 5)
    t.eq(unlockedSaid(c), 1, "said once")
    t.eq(prompt(addon), "Spend 1 talent point")
end

tests["talents: a login at level 12 with 3 points says talents unlocked once and prompts Spend 3 talent points"] = function(t)
    local c, addon = start({ level = 12, points = 3 })
    t.eq(unlockedSaid(c), 1)
    t.eq(prompt(addon), "Spend 3 talent points")
end

tests["talents: spending to 0 removes the prompt"] = function(t)
    local c, addon = start({ level = 11, points = 2 })
    t.eq(prompt(addon), "Spend 2 talent points")
    points(c, 1)
    t.eq(prompt(addon), "Spend 1 talent point")
    points(c, 0)
    t.eq(prompt(addon), nil)
end

tests["talents: in combat the prompt is gone, out of combat it is back"] = function(t)
    local c, addon = start({ level = 10, points = 1 })
    c.setCombat(true); c.advance(1, 5)
    t.eq(prompt(addon), nil, "in combat")
    c.setCombat(false); c.advance(1, 5)
    t.eq(prompt(addon), "Spend 1 talent point", "out of combat")
end

tests["talents: level 9 says nothing"] = function(t)
    local c, addon = start({ level = 9, points = 1 })
    t.eq(unlockedSaid(c), 0)
    t.eq(prompt(addon), nil)
end

tests["talents: points not read says nothing"] = function(t)
    local c, addon = start({ level = 20 })
    t.eq(unlockedSaid(c), 0)
    t.eq(prompt(addon), nil)
end

tests["talents 236: the read raising then recovering: nothing, then the prompt"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.setUnspentTalentsRaise) ~= "function" then t.ok(false, "c.setUnspentTalentsRaise"); return end
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE"); c.setLevel(15); c.setCombat(false)
    c.setUnspentTalents(4); c.setUnspentTalentsRaise(true)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    t.eq(prompt(addon), nil, "raising")
    t.eq(unlockedSaid(c), 0, "raising: nothing said")
    c.setUnspentTalentsRaise(false)
    c.fire("CHARACTER_POINTS_CHANGED", 1)
    c.advance(1, 5)
    t.eq(prompt(addon), "Spend 4 talent points", "recovered")
    t.eq(unlockedSaid(c), 1, "recovered: said once")
end

tests["talents 236: a reload does not say talents unlocked again"] = function(t)
    local c = start({ level = 12, points = 3 })
    t.eq(unlockedSaid(c), 1, "first login")
    local c2, addon2 = start({ level = 12, points = 3,
        account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(unlockedSaid(c2), 0, "after the reload")
    t.eq(prompt(addon2), "Spend 3 talent points", "the prompt is still there")
end

tests["talents: all nine classes get the prompt at level 10 with 1 point"] = function(t)
    for _, class in ipairs(CLASSES) do
        local _, addon = start({ class = class, level = 10, points = 1 })
        t.eq(prompt(addon), "Spend 1 talent point", class)
    end
end

return tests
