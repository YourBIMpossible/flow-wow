local _, ns = ...

-- Tests for UI/MinimapBezel.lua (slice 6, §8.2): the thin-line
-- border on the minimap, OFF by default (the lead's §913 ruling),
-- on draws it with the kit theme's edge colour and off restores
-- the stock Blizzard border. The setting row, then the module
-- over the fake client's recorded bezel handle. Not tested in
-- game.

local tests = {}

local function BZ() return ns.MinimapBezel end

tests["minimap bezel: the row is an account bool, off by default"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    local row = addon.settings:row(BZ().SETTING)
    t.ok(type(row) == "table", "the row is there")
    t.eq(row and row.scope, "account")
    t.eq(row and row.type, "bool")
    t.eq(row and row.default, false)
    t.eq(row and row.group, "travel.map")
end

tests["minimap bezel: the border follows the setting"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = BZ().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    api.Refresh()
    t.eq(c.bezelSets[1] and c.bezelSets[1].on, false, "off by default: the stock border stays")
    t.eq(api.Applied(), false)
    t.eq(c.bezelSets[1] and c.bezelSets[1].colour, { r = 0.4, g = 0.4, b = 0.4, a = 1 },
        "the strip colour is the kit theme's edge colour")
    k.settings:set("nav.minimapBezel", true)
    api.Refresh()
    t.eq(c.bezelSets[1].on, true, "on: the thin line is drawn")
    t.eq(api.Applied(), true)
    k.settings:set("nav.minimapBezel", false)
    api.Refresh()
    t.eq(c.bezelSets[1].on, false, "off again: the stock border is back")
    t.eq(api.Applied(), false)
end

return tests
