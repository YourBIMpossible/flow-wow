local _, ns = ...
-- Parity row A1-28, the data half (lead section 794): hide a quest step,
-- list the hidden ones and unhide them, as Flow's Modules/Nav/Nav.lua
-- (N:Hide and N:Unhide :1308-1318, the route leaving hidden steps out :628,
-- "Unhide all steps (N)" in its menu). Saved per character as Z-Flow's own
-- data; nothing in the game changes. The arrow's "Hide this step" click and
-- the route's filter are in held files (UI/Arrow.lua, Nav/TripRoute.lua): a
-- LEAD NEED. Made-up steps. Not tested in game. Fails before: no file.
local tests = {}

local function HS() return ns.Nav and ns.Nav.HiddenSteps end

local function store()
    local data = {}
    return { data = data,
        get = function(_, scope, path) return data[scope .. "|" .. path] end,
        set = function(_, scope, path, v) data[scope .. "|" .. path] = v return true end }
end

tests["hidden steps: a quest step's key, by quest and objective or turn-in"] = function(t)
    t.eq(type(HS()), "table", "loaded")
    if type(HS()) ~= "table" then return end
    t.eq(HS().KeyOf({ quest = 7, objective = 2 }), "q:7:2")
    t.eq(HS().KeyOf({ quest = 7, turnIn = true }), "q:7:in")
    t.eq(HS().KeyOf({ quest = 7 }), "q:7:in", "no objective: the hand-in")
    t.eq(HS().KeyOf({ label = "Sell" }), nil, "not a quest step")
end

tests["hidden steps: hide, list, unhide one, unhide all"] = function(t)
    if type(HS()) ~= "table" then return t.ok(false, "not loaded") end
    local s = store()
    t.eq(HS().Hide(s, "q:7:2", "Wolves"), true)
    t.eq(HS().Hide(s, "q:9:in", "Hand in Rats"), true)
    t.eq(HS().List(s), { { key = "q:9:in", label = "Hand in Rats" }, { key = "q:7:2", label = "Wolves" } },
        "by label")
    t.eq(HS().IsHidden(s, "q:7:2"), true)
    t.eq(HS().Unhide(s, "q:7:2"), true)
    t.eq(HS().IsHidden(s, "q:7:2"), false)
    t.eq(HS().Unhide(s, "q:7:2"), false, "not hidden: nothing to do")
    HS().Hide(s, "q:1:1", "A")
    t.eq(HS().UnhideAll(s), 2, "how many came back")
    t.eq(HS().List(s), {})
    t.eq(HS().Hide(s, nil, "x"), false)
end

tests["hidden steps: the route without the hidden ones"] = function(t)
    if type(HS()) ~= "table" then return t.ok(false, "not loaded") end
    local s = store()
    HS().Hide(s, "q:7:2", "Wolves")
    local steps = { { quest = 7, objective = 2, label = "Wolves" }, { quest = 7, objective = 3, label = "Boars" },
                    { label = "Sell" } }
    local kept = HS().Filter(steps, s)
    t.eq(#kept, 2)
    t.eq({ kept[1].label, kept[2].label }, { "Boars", "Sell" })
    t.eq(#HS().Filter(steps, nil), 3, "no store: as given")
end

tests["hidden steps: the word lists and unhides"] = function(t)
    if type(HS()) ~= "table" then return t.ok(false, "not loaded") end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    HS().Hide(addon.store, "q:7:2", "Wolves")
    local function said(rest)
        local from = #c.printed
        c.slashes[ns.id.slash](HS().WORD .. rest)
        local out = {}
        for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
        return table.concat(out, " / ")
    end
    t.ok(said(""):find("1. Wolves", 1, true) ~= nil, "listed")
    said(" show 1")
    t.eq(HS().IsHidden(addon.store, "q:7:2"), false, "show 1 brings it back")
    HS().Hide(addon.store, "q:7:2", "Wolves")
    said(" show all")
    t.eq(HS().List(addon.store), {}, "show all")
    t.ok(said(""):find(HS().NONE, 1, true) ~= nil, "none hidden says so")
end

return tests
