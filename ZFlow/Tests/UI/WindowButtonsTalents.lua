local _, ns = ...

-- F-29 (lead section 817): the talent window gets its button too, as
-- Flow's "Flow Talents" tab on the game's talent window (Modules/
-- GameButtons.lua:222-238 at b657e6e5). A click opens this add-on's talents
-- window (UI/TalentsWindow.lua, C-62 know-4). Which frame is the talent
-- window depends on the client, so the button goes on the first of
-- W.TALENT_FRAMES the client says is there, inside its talents part when it
-- has one. The talent window loads late (on first open), so the button is
-- asked again when an add-on loads. Fake client; not tested in game.

local W = ns.WindowButtons
local tests = {}

local function win(key)
    for _, w in ipairs(W.WINDOWS) do
        if w.key == key then return w end
    end
    return nil
end

local function start(windows)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { settings = { buttons = { talents = true } } })
    for name, w in pairs(windows or {}) do c.setWindow(name, w) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    for _, w in ipairs(W.WINDOWS) do
        k:Setting({ key = w.setting, scope = "account", type = "bool", default = false, label = w.label })
    end
    local opened = 0
    k:Module({ name = "talentsWindow", provides = { Open = function() opened = opened + 1 return true end } })
    local api = W.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, api, function() return opened end
end

local function buttonOn(c, frame)
    for _, h in ipairs(c.windowButtons or {}) do
        if h.frame == frame then return h end
    end
    return nil
end

tests["window buttons F-29: the talent window has its own row and opens the talents window"] = function(t)
    local w = win("talents")
    t.ok(w ~= nil, "a talents entry")
    if not w then return end
    t.eq(w.setting, "buttons.talents")
    t.eq(w.opens, "talentsWindow")
    t.eq(w.call, "Open")
    t.eq(w.frames, W.TALENT_FRAMES)
    t.eq(W.TALENT_FRAMES[1], "PlayerSpellsFrame")
end

tests["window buttons F-29: a click on the talent window button opens the talents window"] = function(t)
    if not win("talents") then return t.ok(false, "no talents entry") end
    local c, api, opened = start({ PlayerSpellsFrame = {} })
    local h = buttonOn(c, "PlayerSpellsFrame")
    t.ok(h ~= nil, "a button on the talent window")
    if not h then return end
    h.click()
    t.eq(opened(), 1, "the talents window, once")
    t.eq(api.state().talents, "shown")
end

tests["window buttons F-29: another client's talent frame is used when the first is not there"] = function(t)
    if not win("talents") then return t.ok(false, "no talents entry") end
    local c = start({ PlayerTalentFrame = {} })
    t.ok(buttonOn(c, "PlayerTalentFrame") ~= nil, "on the frame the client has")
    t.eq(buttonOn(c, "PlayerSpellsFrame"), nil)
end

tests["window buttons F-29: a talent window that loads late gets its button when it loads"] = function(t)
    if not win("talents") then return t.ok(false, "no talents entry") end
    local c, api = start({})
    t.eq(api.state().talents, "not made")
    c.setWindow("PlayerSpellsFrame", {})
    c.fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    t.ok(buttonOn(c, "PlayerSpellsFrame") ~= nil, "made once the talent window is there")
    t.eq(api.state().talents, "shown")
end

return tests
