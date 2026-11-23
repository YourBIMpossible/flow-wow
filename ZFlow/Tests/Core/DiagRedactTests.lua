-- F-021: the saved diag snapshot carries no character or realm name in
-- its timing by default. Fake client only.
local _, ns = ...

local function saved()
    local c = ns.make.fakeClient({ env = {
        UnitName = function() return "Secretname" end,
        GetRealmName = function() return "Secretrealm" end,
        UnitFullName = function() return "Secretname", "Secretrealm" end,
    } })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("VARIABLES_LOADED")
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c.saved(ns.id.accountDB).diag
end

return {
    ["F-021: the saved snapshot timing names neither the character nor the realm"] = function(t)
        local d = saved()
        t.ok(type(d.snaps) == "table" and type(d.snaps[1]) == "table", "a snapshot was saved")
        t.eq(d.snaps[1].timing.character, nil)
        t.eq(d.snaps[1].timing.realm, nil)
        t.eq(d.snaps[1].timing.start, 1, "the start count is still saved")
    end,
}
