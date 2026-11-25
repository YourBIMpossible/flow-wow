local _, ns = ...
-- E-45 (lead section 660), end to end on the whole add-on loaded on a fake
-- client: the loot window closes with junk still in it, and the player is told
-- how many grey items were left, once per session. The read is
-- client.onLootLeft (CLIENT NEED, stubbed in the fake). Flow research:
-- Modules/Items/LootFilter.lua:176 (the told-once line). Made-up items.
-- Not tested in game.
--
-- Fails before the change: the fake has no c.fireLootLeft, and nothing says it.
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c
end

local function said(c, part)
    local n = 0
    for _, p in ipairs(c.printed) do
        if ns.ItemPresent.Plain(p):find(part, 1, true) then n = n + 1 end
    end
    return n
end

local LEFT = {
    { item = "item:97", count = 3, quality = 0 },
    { item = "item:98", count = 1, quality = 0 },
    { item = "item:2318", count = 2, quality = 1 },
}

tests["loot left: junk left in the loot window is told, once"] = function(t)
    local c = boot()
    t.eq(type(c.fireLootLeft), "function", "the fake has the loot-left read")
    if type(c.fireLootLeft) ~= "function" then return end
    c.fireLootLeft(LEFT)
    c.advance(0.1, 2)
    t.eq(said(c, "left 2 grey items in the loot window."), 1, "the player is told")
    c.fireLootLeft(LEFT)
    c.advance(0.1, 2)
    t.eq(said(c, "grey item"), 1, "told once per session")
end

tests["loot left: nothing grey left, nothing said"] = function(t)
    local c = boot()
    if type(c.fireLootLeft) ~= "function" then t.ok(false, "no c.fireLootLeft") return end
    c.fireLootLeft({ { item = "item:2318", count = 2, quality = 1 } })
    c.fireLootLeft({})
    c.advance(0.1, 2)
    t.eq(said(c, "grey item"), 0)
end

return tests
