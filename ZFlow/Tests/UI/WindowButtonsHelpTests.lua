local _, ns = ...

-- Queue item A4 (S22): the button on the profession window and the one on
-- the bank window. The profession button opens the settings at its topic,
-- where the help for that window is. The bank button says "Bank list" and
-- brings the bank list back (owner, 2026-11-23: a button that said only the
-- add-on's name did not say what it was for). Fake client only: where the buttons
-- stand on the real windows was not looked at in game.

local W = ns.WindowButtons
local tests = {}

local function win(key)
    for _, w in ipairs(W.WINDOWS) do
        if w.key == key then return w end
    end
    return nil
end

local function buttonOn(c, frame)
    for _, h in ipairs(c.windowButtons or {}) do
        if h.frame == frame then return h end
    end
    return nil
end

-- A small kernel with the four rows, a stand-in settings panel and a
-- stand-in bank list (shown.bank counts its Show calls).
local function start(on, windows)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { settings = { buttons = on or {} } })
    for name, w in pairs(windows or { TradeSkillFrame = {}, BankFrame = {} }) do c.setWindow(name, w) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    for _, w in ipairs(W.WINDOWS) do
        k:Setting({ key = w.setting, scope = "account", type = "bool", default = false, label = w.label })
    end
    local shown = {}
    k:Module({ name = "settingsPanel", provides = { Show = function(topic, query)
        shown[#shown + 1] = { topic = topic, query = query }
    end } })
    k:Module({ name = "bankList", provides = { Show = function(...)
        shown.bank = (shown.bank or 0) + 1
        shown.bankArgs = select("#", ...)
        return true
    end } })
    local api = W.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, shown
end

tests["window help buttons: each opens a topic the settings have"] = function(t)
    for _, key in ipairs({ "profession" }) do
        local w = win(key)
        t.ok(w ~= nil, key .. ": listed")
        if w then
            t.eq(w.opens, ns.SettingsPanel.NAME, key .. ": the settings panel")
            t.eq(w.call, "Show", key .. ": shown at a topic")
            t.ok(ns.Settings.Topics.Find(w.args[1]) ~= nil, key .. ": a real topic")
            t.eq(#w.args, 1, key .. ": the topic and nothing else")
        end
    end
    t.eq(win("profession").args[1], "professions", "the profession topic")
end

tests["window help buttons: the bank row opens the bank list and says so"] = function(t)
    local w = win("bank")
    t.ok(w ~= nil, "listed")
    if not w then return end
    t.eq(w.opens, ns.BankList.NAME, "the bank list")
    t.eq(w.call, "Show")
    t.eq(w.args, nil, "nothing is passed")
    t.eq(w.text, "Bank list")
    t.eq(w.tipText, "Bank list: what to store and take out")
end

tests["window help buttons: the profession button opens the profession topic, once"] = function(t)
    local _, c, api, shown = start({ profession = true })
    local h = buttonOn(c, "TradeSkillFrame")
    t.ok(h ~= nil, "a button on the profession window")
    t.eq(buttonOn(c, "BankFrame"), nil, "none on the bank window")
    if not h then return end
    t.eq(h.spec.text, ns.id.title, "the add-on's name on it")
    t.ok(h.spec.tip:find("profession help", 1, true) ~= nil, "the tooltip says what it opens")
    h.click()
    t.eq(shown, { { topic = "professions" } }, "the profession topic, and no search")
    t.eq(api.state().profession, "shown")
end

-- Fails before the change: the button said only the add-on's name and its
-- tooltip "bag and bank help and settings", and it opened the settings.
tests["window help buttons: the bank button says Bank list and shows the bank list, once"] = function(t)
    local k, c, _, shown = start({ bank = true })
    local h = buttonOn(c, "BankFrame")
    t.ok(h ~= nil, "a button on the bank window")
    if not h then return end
    t.eq(h.spec.text, "Bank list", "what it does, on the button")
    t.eq(h.spec.tip, "Bank list: what to store and take out", "and in the tooltip")
    h.click()
    t.eq(shown.bank, 1, "the bank list is asked for once")
    t.eq(shown.bankArgs, 0, "with nothing passed")
    t.eq(#shown, 0, "the settings are not opened")
    t.eq(k.problems:count(), 0)
end

tests["window help buttons: a window not there at login gets its button when it opens"] = function(t)
    local _, c, api = start({ profession = true, bank = true }, {})
    t.eq(#c.windowButtons, 0, "no window, no button")
    t.eq(api.reasons().profession, "no window")
    c.setWindow("TradeSkillFrame", { shown = true })
    c.fire("TRADE_SKILL_SHOW")
    t.ok(buttonOn(c, "TradeSkillFrame") ~= nil, "made when the profession window opens")
    t.eq(buttonOn(c, "BankFrame"), nil, "the bank's still waits")
    c.setWindow("BankFrame", { shown = true })
    c.fire("BANKFRAME_OPENED")
    t.ok(buttonOn(c, "BankFrame") ~= nil, "made when the bank opens")
    t.eq(api.state().bank, "shown")
end

tests["window help buttons: a protected window gets none, and says why"] = function(t)
    local _, c, api = start({ profession = true }, { TradeSkillFrame = { protected = true } })
    t.eq(buttonOn(c, "TradeSkillFrame"), nil, "none")
    t.eq(api.reasons().profession, "its window is protected")
end

tests["window help buttons: turned off, the button goes; on again, it is back"] = function(t)
    local k, c, api = start({ bank = true })
    local h = buttonOn(c, "BankFrame")
    t.ok(h ~= nil, "made")
    if not h then return end
    k.settings:set("buttons.bank", false)
    t.eq(h.shown, false, "hidden")
    t.eq(api.state().bank, "off")
    k.settings:set("buttons.bank", true)
    t.eq(h.shown, true, "back")
end

-- ------------------------------------------------------------ whole add-on
tests["window help buttons: in the whole add-on both are on and open the real settings"] = function(t)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(addon.settings:get("buttons.profession"), true, "on by default")
    t.eq(addon.settings:get("buttons.bank"), true, "on by default")
    c.setWindow("TradeSkillFrame", { shown = true })
    c.fire("TRADE_SKILL_SHOW")
    c.setWindow("BankFrame", { shown = true })
    c.fire("BANKFRAME_OPENED")
    local before = #addon.problems:list()
    for frame, topic in pairs({ TradeSkillFrame = "professions" }) do
        local h = buttonOn(c, frame)
        t.ok(h ~= nil, frame .. ": its button")
        if h then
            h.click()
            t.eq(addon.store:get("account", ns.SettingsPage.TOPIC_PATH), topic, frame .. ": the settings stand at its topic")
        end
    end
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

return tests
