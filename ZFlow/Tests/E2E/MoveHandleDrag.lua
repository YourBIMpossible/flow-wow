local _, ns = ...
-- The move handle (S29, UI/MoveHandle.lua) on the whole add-on loaded on a
-- fake client, a priest with the click slots on, through its real entry:
-- the grip's drag (c.dragHandle stands in for the drag on screen). What
-- the player sees: the row where it was let go, kept on the screen, and in
-- the same place after a reload. The place is kept only in the add-on's own
-- saved data (the account table), never in the character table. Unknown
-- data: a screen size that is not known, and a drop point that is not a
-- point. Nothing is bound and no macro type set. Not tested in game.
local tests = {}

local S = ns.ClickSlots
local D = ns.RotationDriver
local IDS = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Smite"] = 585,
}
local NAME = ns.id.framePrefix .. "ClickSlots"

local function start(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, char or {})
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 600)
    c.setPlayerBuffs({})
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(S.SETTING, true)
    c.advance(3, 5)
    return c, addon
end

local function slotRow(c)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == NAME then return h end
    end
    return nil
end

-- Somewhere in tbl, a point table equal to p.
local function holds(tbl, p, seen)
    if type(tbl) ~= "table" then return false end
    seen = seen or {}
    if seen[tbl] then return false end
    seen[tbl] = true
    if tbl[1] == p[1] and tbl[2] == p[2] and tbl[3] == p[3] and tbl[4] == p[4] then return true end
    for _, v in pairs(tbl) do
        if holds(v, p, seen) then return true end
    end
    return false
end

local function noBindsNoMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

tests["move handle: a drag past the screen edge keeps the row on screen, saved only in the add-on's account data"] = function(t)
    local c = start()
    local h = slotRow(c)
    t.ok(h ~= nil, "the row was made")
    if not h then return end
    t.ok(c.moveHandles[NAME] ~= nil, "the grip is on the row")
    t.eq(c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", -50, 2000 }), true, "the grip moved")
    local kept = { "BOTTOMLEFT", "BOTTOMLEFT", 0, 600 - S.SIZE }
    t.eq(h.point, kept, "clamped to the top left corner")
    t.ok(holds(c.saved(ns.id.accountDB), kept), "the place is in the add-on's account data")
    t.ok(not holds(c.saved(ns.id.charDB), kept), "and not in the character data")

    local c2 = start(c.saved(ns.id.accountDB), c.saved(ns.id.charDB))
    local h2 = slotRow(c2)
    t.ok(h2 ~= nil, "the row made again after a reload")
    if h2 then t.eq(h2.point, kept, "where it was left") end
    noBindsNoMacros(t, c2)
end

tests["move handle: unknown data: no screen size, and a drop that is not a point"] = function(t)
    local c, addon = start()
    local h = slotRow(c)
    if not h then t.ok(false, "no row") return end
    c.setScreen(nil)
    local far = { "BOTTOMLEFT", "BOTTOMLEFT", 1500, 900 }
    t.eq(c.dragHandle(NAME, far), true)
    t.eq(h.point, far, "screen not known: kept where let go, not clamped to a guess")
    local saved = addon.settings:get(S.LAYOUT)
    t.eq(type(saved) == "table" and saved.point, far, "and kept")

    c.setScreen(1000, 600)
    t.eq(c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", "far", 10 }), true, "the grip let go")
    t.eq(h.point, far, "a drop with no number: the row stays")
    c.dragHandle(NAME, { "MIDDLE", "BOTTOMLEFT", 10, 10 })
    t.eq(h.point, far, "a drop on an anchor that does not exist: the row stays")
    c.dragHandle(NAME, "not a point")
    t.eq(h.point, far, "a drop that is no table: the row stays")
    saved = addon.settings:get(S.LAYOUT)
    t.eq(type(saved) == "table" and saved.point, far, "nothing else was saved")
    noBindsNoMacros(t, c)
end

return tests
