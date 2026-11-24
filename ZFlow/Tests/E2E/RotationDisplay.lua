local _, ns = ...
-- FLOW-PARITY D-06, D-07, D-08: what the rotation shows besides its icon,
-- on the whole add-on loaded on a fake client, a Shaman with an enemy
-- targeted. Display only: none of these may change what any button holds.
--   barglow       the action bar button holding the suggested spell glows
--                 (Flow Modules/Rotation/Display.lua:2, :18, :151).
--   iconsweep     the icon shows the suggested spell's cooldown sweep and,
--                 while the swing is on, the swing badge (Display.lua:70,
--                 :80, :96, :355).
--   castedgedraw  while you cast, a bar fills along the bottom edge of the
--                 icon and of the self button (Flow 0.35.233
--                 Modules/Rotation/CastEdge.lua).
-- Spell ids are made up. Not tested in game.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Lightning Shield"] = 324, ["Lightning Bolt"] = 403, ["Flame Shock"] = 8050,
    ["Stormstrike"] = 17364, ["Attack"] = 6603,
}
local ATTACK_ID = 6603
local ICON = ns.id.framePrefix .. "RotationIcon"
local SELF = ns.id.framePrefix .. "SelfButton"
local FLOW = ns.id.framePrefix .. "FlowButton"
local ENEMY = { exists = true, hostile = true, dead = false }

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("SHAMAN"); c.setFaction("Alliance"); c.setLevel(40)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false); c.setStealthed(false)
    c.setScreen(1000, 768)
    c.setPlayerBuffs({ ["Lightning Shield"] = 600 })
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
        c.setInRange(id, true)
    end
    c.setCurrentSpell(ATTACK_ID, false)
    c.setTarget({ exists = false })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    c.advance(3, 5)
    c.setTarget(ENEMY)
    c.setTargetName("Training Dummy")
    c.advance(3, 5)
    return c, addon
end

local function icon(c)
    for _, h in ipairs(c.icons or {}) do
        if h.spec and h.spec.name == ICON then return h end
    end
    return nil
end

local function row(c, name)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == name then return h end
    end
    return nil
end

-- What every click row holds: display features must leave it as it was.
local function holds(c)
    local out = {}
    for _, h in ipairs(c.clickRows or {}) do
        for i, slot in ipairs(h.slots) do
            local a = {}
            for k, v in pairs(slot.attrs) do a[k] = v end
            out[h.spec.name .. i] = a
        end
    end
    return out
end

local function suggested(c)
    local h = icon(c)
    if not (h and h.shown and type(h.texture) == "string") then return nil end
    return (h.texture:gsub("^tex:", ""))
end

-- ---------------------------------------------------------------- D-06
tests["barglow D-06: the bar button holding the suggested spell glows; off clears it"] = function(t)
    local c, addon = start()
    local spell = suggested(c)
    t.ok(spell ~= nil, "a spell is suggested")
    t.eq(c.barGlowing, spell, "the glow is on the suggested spell's bar button")
    addon.settings:set(D.SETTING, false)
    c.advance(1, 3)
    t.eq(c.barGlowing, nil, "suggestions off: no glow")
end

tests["barglow D-06: the glow changes nothing any button casts"] = function(t)
    local c = start()
    local before = holds(c)
    t.ok(row(c, FLOW) ~= nil, "the Flow button is made")
    c.setBarGlowFails(true)
    c.advance(1, 3)
    t.eq(holds(c), before, "a failing glow leaves every button as it was")
end

-- ---------------------------------------------------------------- D-07
tests["iconsweep D-07: the icon draws the suggested spell's cooldown sweep"] = function(t)
    local c = start()
    local spell = suggested(c)
    t.ok(spell ~= nil, "a spell is suggested")
    local id = IDS[spell or ""]
    c.setSpellCooldownSpan(id, 7, 1.5)
    c.advance(0.5, 2)
    local h = icon(c)
    t.eq(h and h.sweep, { 7, 1.5 }, "the sweep is the spell's start and length")
    c.setSpellCooldownSpan(id, 0, 0)
    c.advance(0.5, 2)
    t.eq(h and h.sweep, { 0, 0 }, "ready: the sweep is cleared")
end

tests["iconsweep D-07: the swing badge shows while the swing is on"] = function(t)
    local c = start()
    local h = icon(c)
    t.eq(h and h.swinging, false, "no swing: no badge")
    local before = holds(c)
    c.setCurrentSpell(ATTACK_ID, true)
    c.advance(0.5, 2)
    t.eq(h and h.swinging, true, "swinging: the badge")
    c.setCurrentSpell(ATTACK_ID, false)
    c.advance(0.5, 2)
    t.eq(h and h.swinging, false, "the swing stops: no badge")
    t.eq(holds(c), before, "the badge changes nothing any button casts")
end

-- ---------------------------------------------------------------- D-08
tests["castedgedraw D-08: a cast fills the edge of the icon and the self button"] = function(t)
    local c, addon = start()
    t.eq(addon.problems:count(ns.CastEdge.NAME), 0, "the client has the cast read")
    local h, s = icon(c), row(c, SELF)
    t.ok(h ~= nil and s ~= nil, "the icon and the self button are made")
    if not (h and s) then return end
    local now = c.now() * 1000
    c.setCasting(now, now + 2000, false)
    c.advance(1, 1)
    t.eq(h.edgeShown, true, "the icon's edge is shown")
    t.ok(type(h.edgeValue) == "number" and math.abs(h.edgeValue - 0.5) < 1e-6, "half way: " .. tostring(h.edgeValue))
    t.eq(s.edgeShown, true, "the self button's edge is shown")
    t.ok(type(s.edgeValue) == "number" and math.abs(s.edgeValue - 0.5) < 1e-6, "self: " .. tostring(s.edgeValue))
    c.setCasting(nil)
    c.advance(0.1, 1)
    t.eq(h.edgeShown, false, "no cast: the icon's edge is hidden")
    t.eq(s.edgeShown, false, "no cast: the self button's edge is hidden")
end

tests["castedgedraw D-08: a channel drains"] = function(t)
    local c = start()
    local h = icon(c)
    local now = c.now() * 1000
    c.setCasting(now, now + 4000, true)
    c.advance(1, 1)
    t.ok(h and type(h.edgeValue) == "number" and math.abs(h.edgeValue - 0.75) < 1e-6, "a quarter through: 0.75")
end

return tests
