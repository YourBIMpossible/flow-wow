local _, ns = ...
-- F-20 (lead sections 788, 790): "Tooltips where WoW shows them", as Flow's
-- switch (Modules/Settings.lua:743; Core.lua:317-318 ns.TipsAtGameSpot,
-- :335-340 ns.Tip: GameTooltip_SetDefaultAnchor when on). On by default,
-- as Flow (section 563). A setting row in the windows group, a pure answer
-- for where a tooltip goes, and the answer handed to the client
-- (client.setTipSpot, a CLIENT NEED: Core/Client.lua's SetOwner calls ask
-- it). Fake client; not tested in game. Fails before: no UI/TipSpot.lua.
local tests = {}

local function TS() return ns.TipSpot end

tests["tip spot: the pure answer"] = function(t)
    t.eq(type(TS()), "table", "loaded")
    if type(TS()) ~= "table" then return end
    t.eq(TS().Where(true, "ANCHOR_RIGHT"), TS().GAME, "on: the game's own spot")
    t.eq(TS().Where(false, "ANCHOR_RIGHT"), "ANCHOR_RIGHT", "off: beside the frame, as asked")
    t.eq(TS().Where(nil, "ANCHOR_LEFT"), TS().GAME, "not known: the default, the game's spot")
    t.eq(TS().Where(false, "ANCHOR_NONE"), "ANCHOR_NONE", "a tooltip placed by hand stays")
    t.eq(TS().Where(true, "ANCHOR_NONE"), "ANCHOR_NONE", "even when on")
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    TS().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

tests["tip spot: the row, on by default, and the client asks the setting"] = function(t)
    if type(TS()) ~= "table" then return t.ok(false, "not loaded") end
    local k, c = start()
    local row = k.settings:row(TS().SETTING)
    t.ok(row ~= nil, "a row")
    t.eq(row and row.group, "general.windows", "where a player looks for what is on the screen")
    t.eq(k.settings:get(TS().SETTING), true, "on by default, as Flow")
    t.eq(type(c.tipSpot), "function", "the fake keeps the answer")
    if type(c.tipSpot) ~= "function" then return end
    t.eq(c.tipSpot("ANCHOR_RIGHT"), TS().GAME)
    k.settings:set(TS().SETTING, false)
    t.eq(c.tipSpot("ANCHOR_RIGHT"), "ANCHOR_RIGHT", "off: beside the frame")
end

return tests
