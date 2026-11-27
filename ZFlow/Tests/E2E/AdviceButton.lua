local _, ns = ...
-- G32 end to end: the whole add-on on a fake client. The minimap button's
-- right-click menu has an advice row, with the number of prompts; choosing
-- it opens the advice window, which says "No advice right now." when there
-- is none. "/zflow advice" does the same. With the panel setting off the
-- row still opens nothing and the reason is said in chat. Look only:
-- nothing is cast, used or moved. Fake client button, not the game frame.
-- Not tested in game.
--
-- Red before the code: the menu has no advice row and the slash command
-- has no advice word.
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setMinimap({ size = 140 })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function button(c) return type(c.minimapButtons) == "table" and c.minimapButtons[1] or nil end

local function row(items, key)
    for _, item in ipairs(items or {}) do
        if item.key == key then return item end
    end
    return nil
end

local function window(c) return c.kitWindows()[ns.Advisor.KIT_ID] end

local function lines(c)
    local out = {}
    for _, p in ipairs(window(c) and window(c).parts or {}) do
        if p.kind == "line" or p.kind == "card" or p.kind == "fadedLine" then out[#out + 1] = p.text end
    end
    return out
end

local function said(c, text)
    for _, line in ipairs(c.printed) do
        if type(line) == "string" and line:find(text, 1, true) then return true end
    end
    return false
end

tests["advice button: the minimap menu has an advice row with the prompt count"] = function(t)
    local c, addon = boot()
    local n = #addon.use("advisor").List()
    local b = button(c)
    b.click("right")
    local r = row(b.menuItems, "advice")
    t.ok(r ~= nil, "the advice row is there")
    local want = n > 0 and ns.MinimapButton.MENU_ADVICE_N:format(n) or ns.MinimapButton.MENU_ADVICE
    t.eq(r and r.text, want)
    t.ok(row(b.menuItems, "settings") ~= nil, "the settings row is still there")
end

tests["advice button: choosing the row opens the advice window"] = function(t)
    local c, addon = boot()
    local advisor = addon.use("advisor")
    for _, p in ipairs(advisor.List()) do advisor.Remove(p.id) end
    local b = button(c)
    b.click("right")
    b.choose("advice")
    t.eq(b.menuItems, nil, "the menu closed")
    t.eq(window(c) and window(c).shown, true, "the advice window is shown")
    t.eq(lines(c), { ns.Advisor.NONE }, "no advice: says so")
end

tests["advice button: a prompt is counted in the row and shown in the window"] = function(t)
    local c, addon = boot()
    local advisor = addon.use("advisor")
    for _, p in ipairs(advisor.List()) do advisor.Remove(p.id) end
    advisor.Add("e2e.test", "Repair at the next vendor.", 10)
    c.kitClose(ns.Advisor.KIT_ID)
    local b = button(c)
    b.click("right")
    t.eq(row(b.menuItems, "advice").text, ns.MinimapButton.MENU_ADVICE_N:format(1))
    b.choose("advice")
    t.eq(window(c).shown, true)
    t.eq(lines(c), { "Repair at the next vendor." })
end

tests["advice button: the panel setting off, the row says why in chat and opens nothing"] = function(t)
    local c, addon = boot()
    addon.settings:set(ns.Advisor.SETTING, false)
    local b = button(c)
    b.click("right")
    b.choose("advice")
    local w = window(c)
    t.ok(w == nil or w.shown ~= true, "nothing shown")
    t.ok(said(c, ns.Advisor.OFF), "the reason is said")
end

tests["advice button: /zflow advice opens the window"] = function(t)
    local c, addon = boot()
    local advisor = addon.use("advisor")
    for _, p in ipairs(advisor.List()) do advisor.Remove(p.id) end
    c.slashes[ns.id.slash]("advice")
    t.eq(window(c) and window(c).shown, true)
    t.eq(lines(c), { ns.Advisor.NONE })
end

return tests
