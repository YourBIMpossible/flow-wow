-- Buttons and Flow windows (lead section 387 R3), end to end on the whole
-- add-on loaded on a fake client: right-click the arrow, Show, then a row.
-- The world map button hides and comes back; the Dungeon Quests window
-- opens and closes. Not tested in game.
local _, ns = ...
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, 1436); c.setPosition(1436, 0.5, 0.5)
    c.setWindow("WorldMapFrame", {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(0.1, 2)
    return c, addon
end

local function mapButton(c)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == "WorldMapFrame" then return h end
    end
    return nil
end

local function into(t, q, level)
    q.click("right")
    t.eq(q.enter("show"), true, "Show opens its level")
    t.eq(q.enter(level), true, level .. " opens under Show")
end

tests["menu windows: Buttons turns the world map button off and on again"] = function(t)
    local c, addon = boot()
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if not q then return end
    local h = mapButton(c)
    t.eq(h ~= nil and h.shown, true, "on at first")
    into(t, q, "buttons")
    t.eq(q.pickRow("buttons.worldMap"), true, "the world map button row")
    c.advance(0.1, 2)
    t.eq(addon.settings:get("buttons.worldMap"), false)
    t.eq(h ~= nil and h.shown, false, "hidden")
    t.ok(type(q.menuItems) == "table", "the Buttons level stays open")
    t.eq(q.pickRow("buttons.worldMap"), true)
    c.advance(0.1, 2)
    t.eq(addon.settings:get("buttons.worldMap"), true)
    t.eq(h ~= nil and h.shown, true, "shown again")
    t.eq(addon.problems:count(), 0)
end

tests["menu windows: Flow windows opens the Dungeon Quests window, then closes it"] = function(t)
    local c, addon = boot()
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if not q then return end
    into(t, q, "windows")
    t.eq(q.pickRow("windows.dungeonWindow"), true, "the Dungeon quests row")
    c.advance(1, 10)
    local rec = c.kitWindows()["dungeons"]
    t.eq(rec ~= nil and rec.shown, true, "open")
    into(t, q, "windows")
    t.eq(q.pickRow("windows.dungeonWindow"), true)
    c.advance(0.1, 2)
    t.eq(rec ~= nil and rec.shown, false, "closed: the row toggles")
    t.eq(addon.problems:count(), 0)
end

return tests
