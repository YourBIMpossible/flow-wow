local _, ns = ...

-- Tests for ZFlow/Gear/Usable.lua (G12 from what the client reports), and
-- for Gear/Verdict.lua taking that answer ahead of the class pack's table.
--
-- `unmet` is the list of requirement lines the game itself marks as not met
-- on an item's tooltip, in the game's own words. client.gear does not give
-- it yet (a CLIENT NEED); the tests add it to the fake's answer by hand.

local U = ns.GearUsable
local tests = {}

local STA = "ITEM_MOD_STAMINA_SHORT"
local HELM = "item:1"

-- Usable.Check ---------------------------------------------------------------

tests["usable: nothing marked by the game is a yes"] = function(t)
    local a = U.Check({})
    t.eq(a.can, true)
    t.eq(a.why, "ok")
    t.eq(a.reason, U.REASON.ok)
    t.eq(a.source, "client")
end

tests["usable: what the game marks is a no, in the game's own words"] = function(t)
    local a = U.Check({ "Plate" })
    t.eq(a.can, false)
    t.eq(a.why, "client")
    t.eq(a.reason, U.REASON.unmet .. ": Plate")
    a = U.Check({ "Plate", "Requires Level 40" })
    t.eq(a.reason, U.REASON.unmet .. ": Plate; Requires Level 40")
    t.eq(a.source, "client")
end

tests["usable: the list not read is not known, never a yes"] = function(t)
    for _, unmet in ipairs({ false, "Plate", 0, true }) do
        local a = U.Check(unmet or nil)
        t.eq(a.can, nil, tostring(unmet))
        t.eq(a.why, "unknown")
        t.eq(a.reason, U.REASON.unread)
    end
end

tests["usable: more than three marks are counted, not all listed"] = function(t)
    local a = U.Check({ "One", "Two", "Three", "Four", "Five" })
    t.eq(a.can, false)
    t.eq(a.reason, U.REASON.unmet .. ": One; Two; Three and 2 more")
    t.eq(U.MAX, 3)
end

tests["usable: the same mark twice is said once"] = function(t)
    t.eq(U.Check({ "Plate", "Plate", "Requires Level 40" }).reason, U.REASON.unmet .. ": Plate; Requires Level 40")
end

tests["usable: colour codes are taken off the game's text, and spaces at the ends"] = function(t)
    local bar = string.char(124)
    local coloured = bar .. "cffff2020Plate" .. bar .. "r"
    t.eq(U.Clean(coloured), "Plate")
    t.eq(U.Clean("  Requires Level 40 "), "Requires Level 40")
    t.eq(U.Check({ coloured }).reason, U.REASON.unmet .. ": Plate")
end

tests["usable: a mark that cannot be shown is still a no"] = function(t)
    local bar = string.char(124)
    local odd = "Plate" .. bar .. "Hlink"
    t.eq(U.Clean(odd), nil, "a bar left in the text")
    t.eq(U.Clean("Pla" .. string.char(10) .. "te"), nil, "a line break")
    t.eq(U.Clean(""), nil)
    t.eq(U.Clean("   "), nil)
    t.eq(U.Clean(7), nil)
    local a = U.Check({ odd, 7, "" })
    t.eq(a.can, false, "the game did mark something")
    t.eq(a.why, "client")
    t.eq(a.reason, U.REASON.marked)
    a = U.Check({ odd, "Plate" })
    t.eq(a.reason, U.REASON.unmet .. ": Plate and 1 more")
end

-- Usable.Best ------------------------------------------------------------------

tests["usable: the client's answer goes ahead of the class table's; not read falls back to it"] = function(t)
    local pack = { can = false, why = "class", reason = "your class cannot use this kind of item", evidence = "first guess" }
    t.eq(U.Best(U.Check({}), pack).can, true, "the game says yes: yes")
    t.eq(U.Best(U.Check({}), pack).source, "client")
    t.eq(U.Best(U.Check({ "Plate" }), { can = true, why = "ok", reason = "you can use it" }).can, false,
        "the game says no: no")
    t.ok(U.Best(U.Check(nil), pack) == pack, "not read: the class table's answer, as it is")
    t.eq(U.Best(U.Check(nil), nil).can, nil, "neither: not known")
    t.eq(U.Best(nil, nil).can, nil)
    t.eq(U.Best(nil, nil).reason, U.REASON.unread)
end

-- Through Gear/Verdict.lua -----------------------------------------------------

local function pack()
    return {
        weights = { dps = { evidence = "first guess", values = { [STA] = 1 } } },
        proficiency = { evidence = "first guess", [4] = { [2] = true } },
    }
end

local function gear(more)
    local c = ns.make.fakeClient()
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
    c.setWorn(1, false)
    local g = c.gear(HELM)
    for key, value in pairs(more or {}) do g[key] = value end
    return g
end

tests["verdict G12: what the game marks goes on the line, and it is never an upgrade"] = function(t)
    local lines, detail = ns.GearVerdict.Lines(gear({ unmet = { "Plate", "Requires Level 40" } }),
        { pack = pack(), role = "dps", level = 10 })
    t.eq(lines, { { text = "Can't use: " .. U.REASON.unmet .. ": Plate; Requires Level 40", tone = "bad" } })
    t.eq(detail.use.source, "client")
    t.eq(detail.result.verdict, "upgrade", "the scorer would have called it one")
end

tests["verdict G12: the game marking nothing is a yes with no item type and no level read"] = function(t)
    local lines, detail = ns.GearVerdict.Lines(gear({ unmet = {} }), { pack = pack(), role = "dps" })
    t.eq(lines, { { text = "Upgrade for your head piece (+4, dps)", tone = "good" } })
    t.eq(detail.use.source, "client")
end

tests["verdict G12: the game's answer overrules the class table, both ways"] = function(t)
    local who = { pack = pack(), role = "dps", level = 10 }
    -- The table says plate (4/4) cannot be worn; the game marks nothing.
    local lines = ns.GearVerdict.Lines(gear({ unmet = {}, classId = 4, subclassId = 4, minLevel = 1 }), who)
    t.eq(lines[1].text, "Upgrade for your head piece (+4, dps)")
    -- The table says leather (4/2) can be worn; the game marks it.
    lines = ns.GearVerdict.Lines(gear({ unmet = { "Leather" }, classId = 4, subclassId = 2, minLevel = 1 }), who)
    t.eq(lines[1].text, "Can't use: " .. U.REASON.unmet .. ": Leather")
end

tests["verdict G12: with the game's marks not read, the class table still answers, with its label"] = function(t)
    local who = { pack = pack(), role = "dps", level = 10 }
    local lines, detail = ns.GearVerdict.Lines(gear({ classId = 4, subclassId = 4, minLevel = 1 }), who)
    t.eq(lines, { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } })
    t.eq(detail.use.source, nil, "not the client's answer")
    lines = ns.GearVerdict.Lines(gear(), who)
    t.eq(lines, { { text = "No verdict: " .. ns.GearCanUse.REASON.type, tone = "none" } }, "and neither read: not known")
end

tests["usable: no reason names the product, and nothing handed in is changed"] = function(t)
    local unmet = { "Plate", "Plate" }
    U.Check(unmet)
    t.eq(unmet, { "Plate", "Plate" })
    for _, text in pairs(U.REASON) do
        t.ok(type(text) == "string" and text ~= "")
        t.ok(not text:lower():find("flow", 1, true))
    end
end

return tests
