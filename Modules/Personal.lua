-- Personal copy only: the owner's own choices, laid over the main project in
-- ONE file so the rest stays main's code and merges stay clean.
--
-- 1. Flow stops nagging about two things, unless you turn them back on:
--   * "Equip <item> from your bags" (Flow Improvements list) and the easy-button
--     step "Equip <item> (upgrade +n)"
--   * "Put <spell> on your action bars" (Flow Improvements list)
--   Kept: gear marks on bag items, tooltip verdicts, quest-reward arrows, the
--   new-spell card. They only show something when you look.
--     /flow gearadvice on|off     (off by default)
--     /flow baradvice on|off      (off by default)
-- 2. On unless you turn them off (main: off unless ticked): the buff button
--    and the faint profession arrow. Only a setting never touched is filled in.

local _, ns = ...

local function on(key) return ns.db and ns.db[key] == true end

-- Silences a registered advisor's check() unless the setting is on.
local function quiet(advisorKey, setting)
    local advisor = ns:Get("advisor", advisorKey)
    if not (advisor and advisor.check) then return end
    local original = advisor.check
    advisor.check = function()
        if not on(setting) then return {} end
        return original()
    end
end

quiet("gear", "gearAdvice")
quiet("bars", "barAdvice")

local action = ns:Get("action", "gear:upgrade")
if action and action.get then
    local original = action.get
    action.get = function(ctx)
        if not on("gearAdvice") then return nil end
        return original(ctx)
    end
end

local function toggle(setting, what)
    return function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then ns.db[setting] = (arg == "on") end
        ns:Print(what .. ": " .. (on(setting) and "on" or "off"))
    end
end

ns.commands.gearadvice = toggle("gearAdvice", "equip suggestions (improvements list and easy button), /flow gearadvice on|off")
ns.commands.baradvice = toggle("barAdvice", "put-it-on-your-bars suggestions (improvements list), /flow baradvice on|off")

-- Defaults: fill in only what was never set, so a choice you made stays.
local function defaults()
    if type(ns.db) ~= "table" then return end
    ns.db.buffButton = ns.db.buffButton or {}
    if ns.db.buffButton.enabled == nil then ns.db.buffButton.enabled = true end
    if type(ns.db.nav) == "table" and ns.db.nav.profArrow == nil then ns.db.nav.profArrow = true end
end
ns.PersonalDefaults = defaults
ns:On("PLAYER_LOGIN", defaults)

ns:Register("test", "personal: equip and action-bar nags are quiet unless switched on", function(t)
    local g, b = ns.db.gearAdvice, ns.db.barAdvice
    ns.db.gearAdvice, ns.db.barAdvice = false, false
    local gear, bars, step = ns:Get("advisor", "gear"), ns:Get("advisor", "bars"), ns:Get("action", "gear:upgrade")
    if step and step.get then t:eq(step.get({}), nil, "no equip step on the easy button") end
    if gear and gear.check then t:eq(#gear.check(), 0, "no equip line in the improvements list") end
    if bars and bars.check then t:eq(#bars.check(), 0, "no 'put it on your bars' line") end
    ns.db.gearAdvice, ns.db.barAdvice = g, b
end)

ns:Register("test", "personal: buff button and profession arrow are on unless you turned them off", function(t)
    local bb, arrow = ns.db.buffButton, ns.db.nav and ns.db.nav.profArrow
    ns.db.buffButton = { enabled = false }
    if ns.db.nav then ns.db.nav.profArrow = false end
    defaults()
    t:eq(ns.db.buffButton.enabled, false, "buff button you turned off stays off")
    if ns.db.nav then t:eq(ns.db.nav.profArrow, false, "profession arrow you turned off stays off") end
    ns.db.buffButton = {}
    if ns.db.nav then ns.db.nav.profArrow = nil end
    defaults()
    t:eq(ns.db.buffButton.enabled, true, "buff button never set: on")
    if ns.db.nav then t:eq(ns.db.nav.profArrow, true, "profession arrow never set: on") end
    ns.db.buffButton = bb
    if ns.db.nav then ns.db.nav.profArrow = arrow end
end)
