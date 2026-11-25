local _, ns = ...

-- Parity row A2-12 (lead section 794): a quest step with no place (words
-- only) also says which creatures dropped what it needs (UI/Arrow.lua
-- Arrow.DropWords, through Nav/DropLines.lua). A stand-in lines module is put
-- on ns.Nav for each test and the one there before is put back. The pure
-- part only: the hook in the arrow's source reads the store and the item
-- names, which these tests do not drive. Not tested in game.

local tests = {}

local function withLines(standIn, fn)
    local saved = ns.Nav.DropLines
    ns.Nav.DropLines = standIn
    local ok, err = pcall(fn)
    ns.Nav.DropLines = saved
    if not ok then error(err, 0) end
end

-- Answers one line per creature in the book that dropped the item asked for.
local function fakeLines()
    local L = { asked = {} }
    function L.Rows(book, itemName, nameOf)
        L.asked[#L.asked + 1] = itemName
        local out = {}
        for _, e in pairs(book) do
            if nameOf(e.item) == itemName then out[#out + 1] = { name = e.name } end
        end
        return out
    end
    function L.Lines(rows)
        local out = {}
        for i, r in ipairs(rows) do out[i] = r.name .. " drops it" end
        return out
    end
    return L
end

local BOOK = { [1] = { name = "Wolf", item = 5 } }
local function nameOf(key) if key == 5 then return "Stringy Wolf Meat" end return nil end
local function worded()
    return { quest = 33, objective = 1, label = "Wolves", detail = "Stringy Wolf Meat: 0/6", still = true,
             lines = { "Wolves", "Stringy Wolf Meat: 0/6", "No place known." } }
end

tests["drop words: a words-only step gets the drop lines after its own"] = function(t)
    local L = fakeLines()
    withLines(L, function()
        local step = worded()
        local out = ns.Arrow.DropWords(step, BOOK, nameOf)
        t.eq(L.asked, { "Stringy Wolf Meat" }, "the objective's item")
        t.eq(out.lines, { "Wolves", "Stringy Wolf Meat: 0/6", "No place known.", "Wolf drops it" })
        t.eq(#step.lines, 3, "the step handed in is not changed")
    end)
end

tests["drop words: a step with a place, a why line or no module is as before"] = function(t)
    withLines(fakeLines(), function()
        local placed = worded()
        placed.place = { map = 1, x = 0.5, y = 0.5 }
        t.ok(ns.Arrow.DropWords(placed, BOOK, nameOf) == placed, "a step with a place")
        local why = { still = true, lines = { "no directions" }, why = true }
        t.ok(ns.Arrow.DropWords(why, BOOK, nameOf) == why, "the why line has no quest")
        local none = worded()
        t.ok(ns.Arrow.DropWords(none, {}, nameOf) == none, "nothing recorded: no lines")
    end)
    withLines(nil, function()
        local step = worded()
        t.ok(ns.Arrow.DropWords(step, BOOK, nameOf) == step, "no lines module")
    end)
end

tests["drop words: a lines module that fails leaves the step as it was"] = function(t)
    local broken = fakeLines()
    function broken.Rows() error("lines broke") end
    withLines(broken, function()
        local step = worded()
        t.ok(ns.Arrow.DropWords(step, BOOK, nameOf) == step)
    end)
end

return tests
