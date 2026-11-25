local _, ns = ...
-- Lead section 408: the four faults the owner saw in the Advice window, on
-- the whole add-on loaded on a fake client.
--   1. the title stood twice: in the title bar and as a line under it
--   2. the one line was cut with "..."
--   3. the window was far taller than its one line
--   4. nothing said what to do next
-- Offline: the window is the fake client's record of the kit window, and
-- its wrapping is the fake's count of letters, not the game's fonts. Not
-- tested in game.
local tests = {}

local SIZE = ns.Kit.look.size
local TITLE = ns.id.title .. ": Advice"
local LONG_A, LONG_B = "Test trouble in the deep mine", "Test stalkers in the old keep"

local function row(id, title, complete)
    return { id = id, title = title, complete = complete == true, objectives = {} }
end

-- A made-up Questie: who takes each quest (opts.who: { [quest id] = name }).
local function questie(who)
    local db = {}
    function db.GetQuest(id)
        if who[id] == nil then return { ObjectiveData = {} } end
        return { ObjectiveData = {}, Finisher = { Type = "monster", Id = 9000 + id } }
    end
    function db.GetNPC(id) return { name = who[id - 9000], spawns = {} } end
    function db.GetObject() return nil end
    function db.GetItem() return nil end
    return db
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE")
    c.setLevel(20)
    c.setQuestLog(opts.log or {})
    if opts.who then c.setQuestieModule("QuestieDB", questie(opts.who)) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function window(c) return c.kitWindows().Advisor end

local function lineParts(w)
    local out = {}
    for _, p in ipairs(w and w.parts or {}) do
        if p.kind == "line" then out[#out + 1] = p end
    end
    return out
end

local function handIn(w)
    for _, p in ipairs(lineParts(w)) do
        if type(p.text) == "string" and p.text:find("Ready to hand in", 1, true) then return p end
    end
    return nil
end

-- The height a window of that many text rows has: the title bar, the
-- padding above and below, and the rows.
local function fitted(rows)
    return SIZE.title + 2 * SIZE.pad + rows * SIZE.lineHeight
end

tests["advice window: the title stands once, in the title bar only"] = function(t)
    local c = start({ log = { row(1, LONG_A, true) } })
    local w = window(c)
    t.ok(type(w) == "table" and w.shown == true, "the window is shown")
    if type(w) ~= "table" then return end
    t.eq(w.title, TITLE, "the title bar")
    for _, p in ipairs(w.parts) do
        t.ok(p.kind ~= "header", "no header part under the title bar")
        t.ok(p.text ~= TITLE, "no part repeats the title")
    end
end

tests["advice window: the hand-in line is whole and wraps; no quest name is cut"] = function(t)
    local c = start({ log = { row(1, LONG_A, true), row(2, LONG_B, true) } })
    local p = handIn(window(c))
    t.ok(p ~= nil, "the hand-in line is in the window")
    if p == nil then return end
    t.ok(p.text:find(LONG_A, 1, true) ~= nil and p.text:find(LONG_B, 1, true) ~= nil, "both names whole: " .. p.text)
    t.eq(p.wrap, true, "the line wraps instead of being cut")
    t.ok(type(p.rows) == "number" and p.rows >= 2, "longer than one row, so drawn on more")
end

tests["advice window: the window is as tall as its lines"] = function(t)
    local c, addon = start({ log = { row(1, "Test wolves", true) }, who = { [1] = "Test Keeper" } })
    local w = window(c)
    if type(w) ~= "table" then t.ok(false, "no window") return end
    -- Lead section 564 R8: the first time it shows, a row under the title
    -- says what the panel is (a section part); it counts one row, for as
    -- long as it is there.
    local function rowsOf(win)
        local n = 0
        for _, p in ipairs(lineParts(win)) do n = n + (p.rows or 1) end
        for _, p in ipairs(win.parts) do
            if p.kind == "section" then n = n + 1 end
        end
        return n
    end
    local rows = rowsOf(w)
    t.eq(#lineParts(w), 1, "one line")
    t.eq(w.height, fitted(rows), "one line: no empty space under it")
    addon.advisor.Add("test.other", "Repair your gear.", 0)
    local two = window(c)
    local rows2 = rowsOf(two)
    t.eq(rows2, rows + 1)
    t.eq(two.height, fitted(rows2), "it grows with a second line")
    addon.advisor.Remove("test.other")
    t.eq(window(c).height, fitted(rows), "and shrinks back")
end

tests["advice window: the hand-in line says who to see, where Questie knows"] = function(t)
    local c = start({ log = { row(1, "Test wolves", true) }, who = { [1] = "Test Keeper" } })
    local p = handIn(window(c))
    t.eq(p and p.text, "Ready to hand in: Test wolves. Go see Test Keeper.")
    local c2 = start({ log = { row(1, "Test wolves", true), row(2, "Test boars", true), row(3, "Test bears") },
        who = { [1] = "Test Keeper", [2] = "Test Smith" } })
    local p2 = handIn(window(c2))
    t.eq(p2 and p2.text, "Ready to hand in: Test wolves (see Test Keeper), Test boars (see Test Smith).")
end

tests["advice window: who is not known: the line still says what to look for"] = function(t)
    local LOOK = " Look for the yellow ? over who takes it."
    local c = start({ log = { row(1, "Test wolves", true) } })
    local p = handIn(window(c))
    t.eq(p and p.text, "Ready to hand in: Test wolves." .. LOOK, "no Questie")
    local c2 = start({ log = { row(1, "Test wolves", true), row(2, "Test boars", true) }, who = { [1] = "Test Keeper" } })
    local p2 = handIn(window(c2))
    t.eq(p2 and p2.text, "Ready to hand in: Test wolves (see Test Keeper), Test boars." .. LOOK, "one of two known")
end

tests["advice window: nothing in it can be pressed, and nothing is handed in"] = function(t)
    local c = start({ log = { row(1, "Test wolves", true) }, who = { [1] = "Test Keeper" } })
    for _, p in ipairs(window(c).parts) do
        t.ok(c.kitClick("Advisor", p.path) ~= true, "a part took a click")
    end
end

return tests
