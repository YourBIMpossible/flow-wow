local _, ns = ...

-- Queue item A3 (G17/G18): a free primary profession slot is said inside
-- the docked profession panel: which profession to learn and why. Offline
-- only; every name here is made up or the game's own profession name, and
-- none of this was looked at in game.

local tests = {}

local function D() return ns.ProfDock end
local function PP() return ns.ProfPick end

local function keyed(view, key)
    for _, part in ipairs(view.children) do
        if part.key == key then return part end
    end
    return nil
end

tests["prof dock pick: one line per profession advised, with why"] = function(t)
    local advice = PP().Advice({}, "MAGE", 5)
    local rows = D().Pick(advice, function(name) return "A " .. name .. " trainer in a capital city teaches it." end)
    t.eq(#rows, 2, "two free slots: two lines")
    t.eq(rows[1].text, "Learn Tailoring", "the first")
    t.eq(rows[2].text, "Learn Enchanting", "the second")
    t.eq(rows[1].sub, D().PICK_WHY.Tailoring, "why, in a few words")
    t.ok(rows[1].icon ~= nil and rows[2].icon ~= nil, "each with a picture")
    t.ok(rows[1].tooltip:find(advice.text, 1, true) ~= nil, "the whole advice on hover")
    t.ok(rows[1].tooltip:find("A Tailoring trainer", 1, true) ~= nil, "and where it is taught")
end

tests["prof dock pick: one slot free names the partner of the one known"] = function(t)
    local rows = D().Pick(PP().Advice({ Mining = true, Cooking = true }, "WARRIOR", 10))
    t.eq(#rows, 1, "one line")
    t.eq(rows[1].text, "Learn Blacksmithing", "what goes with Mining")
    t.eq(rows[1].sub, D().PICK_WHY.Blacksmithing, "and why")
end

tests["prof dock pick: nothing to advise gives no lines"] = function(t)
    t.eq(#D().Pick(nil), 0, "no advice")
    t.eq(#D().Pick(PP().Advice({ Mining = true, Skinning = true }, "ROGUE", 10)), 0, "both slots used")
    t.eq(#D().Pick(PP().Advice({}, "ROGUE", 1)), 0, "too low a level")
    t.eq(#D().Pick({ wants = { 7, "" } }), 0, "not names")
end

tests["prof dock pick: every primary profession has a reason short enough for one line"] = function(t)
    for name in pairs(PP().PRIMARY) do
        local why = D().PICK_WHY[name]
        t.ok(type(why) == "string" and #why > 0 and #why <= 48, name .. ": a short reason")
        t.ok(type(D().PICK_ICON[name]) == "string", name .. ": a picture")
    end
end

tests["prof dock pick: the panel grows by the lines and shows them under their own heading"] = function(t)
    local rows = D().Pick(PP().Advice({}, "MAGE", 5))
    t.eq(D().Height({}, rows), D().BASE_HEIGHT + D().PICK_HEAD + 2 * D().PICK_ROW, "taller by two lines")
    t.eq(D().Height({}, {}), D().BASE_HEIGHT, "no lines: as before")
    t.eq(D().Height({}), D().BASE_HEIGHT, "not given: as before")
    local view = D().View({ prof = "Cooking", pick = rows })
    t.eq(keyed(view, "pickHead").text, "Free profession slot", "the heading")
    t.eq(keyed(view, "pick1").text, "Learn Tailoring", "the first line")
    t.eq(keyed(view, "pick2").sub, D().PICK_WHY.Enchanting, "the second line's reason")
    t.eq(keyed(view, "pick1").onClick, nil, "no click")
    t.eq(view.height, D().Height({}, rows), "the height follows")
    t.eq(keyed(D().View({ prof = "Cooking" }), "pickHead"), nil, "no advice: no heading")
    local plain = D().Plain({ pick = rows })
    t.ok(plain[#plain].text:find("Learn Enchanting", 1, true) ~= nil, "the plain panel says the same")
end

-- ------------------------------------------------------------------ module
local function has(t)
    if type(ns.offline) == "table" and type(ns.offline.addon) == "function" then return true end
    t.skip("no whole add-on offline")
    return false
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = { Cooking = { skill = 10, max = 75 } } } },
        state = { profPick = opts.state } })
    c.setScreen(1024, 768)
    c.setFrameRect("TradeSkillFrame", { l = 20, r = 404, b = 400, t = 760 })
    c.setClass(opts.class or "MAGE")
    c.setLevel(opts.level or 6)
    c.setProfessions(opts.known or { "Cooking" })
    c.setRecipes({ profession = 185, name = "Cooking", skill = 10, max = 75, recipes = {} })
    local addon = ns.offline.addon(c)
    -- Lead section 450: the dock is what stands when the profession path
    -- panel is turned off; with it on, the dock steps aside (Tests/E2E/ProfPathPanel.lua).
    addon.settings:set(ns.ProfPathPanel.SETTING, false)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return c, addon
end

local function texts(c)
    local w = c.kitWindows()[D().ID]
    if w == nil then return "" end
    local out = {}
    for _, part in ipairs(w.parts) do out[#out + 1] = tostring(part.text) end
    return table.concat(out, "\n")
end

tests["prof dock pick module: a new character sees what to learn in the panel"] = function(t)
    if not has(t) then return end
    local c = start()
    c.fire("TRADE_SKILL_SHOW")
    local said = texts(c)
    t.ok(said:find("Free profession slot", 1, true) ~= nil, said)
    t.ok(said:find("Learn Tailoring", 1, true) ~= nil, said)
    t.ok(said:find("Learn Enchanting", 1, true) ~= nil, said)
    t.eq(c.kitWindows()[D().ID].shown, true, "in the panel under the profession window")
end

tests["prof dock pick module: both slots used: nothing said"] = function(t)
    if not has(t) then return end
    local c = start({ known = { "Cooking", "Tailoring", "Enchanting" } })
    c.fire("TRADE_SKILL_SHOW")
    t.eq(texts(c):find("Free profession slot", 1, true), nil, "no heading")
    t.eq(texts(c):find("Learn Tailoring", 1, true), nil, "no lines")
end

tests["prof dock pick module: the picker's setting and its 'not now' are honoured"] = function(t)
    if not has(t) then return end
    local c, addon = start()
    addon.settings:set(PP().SETTING, false)
    c.fire("TRADE_SKILL_SHOW")
    t.eq(texts(c):find("Free profession slot", 1, true), nil, "setting off: nothing said")
    addon.settings:set(PP().SETTING, true)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.ok(texts(c):find("Free profession slot", 1, true) ~= nil, "on again: said")
    local c2 = start({ state = { snoozeLevel = 6 } })
    c2.fire("TRADE_SKILL_SHOW")
    t.eq(texts(c2):find("Free profession slot", 1, true), nil, "not now: nothing until the next level")
end

return tests
