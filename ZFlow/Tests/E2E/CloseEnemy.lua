local _, ns = ...
-- Section 401 (mage-3 HOLD): the whole add-on on a fake client, a mage in a
-- fight. The close-enemy reads (client.targetClose, client.hitOnYouAge) go
-- through the rotation driver into the Frost Nova rule. Made-up spell ids.
-- Offline test; the real reads Need game test.
local tests = {}

local D = ns.RotationDriver
local SPELLS = { ["Frost Armor"] = 9001, ["Arcane Intellect"] = 9002, ["Frostbolt"] = 9005,
    ["Fireball"] = 9006, ["Frost Nova"] = 9012 }

local function start(close, age)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("MAGE"); c.setFaction("Alliance"); c.setLevel(30); c.setDead(false)
    local buffs = {}
    for name, id in pairs(SPELLS) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name); c.setInRange(id, true)
        buffs[name] = 1800
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    c.setPlayerBuffs(buffs); c.setTarget({ exists = true, hostile = true, dead = false })
    c.setTargetClose(close); c.setHitOnYouAge(age)
    c.setCombat(true)
    c.advance(2, 10)
    return c, addon
end

local function spell(addon)
    local use = addon.use(D.NAME)
    local v = type(use) == "table" and use.View() or nil
    local s = type(v) == "table" and v.suggestion or nil
    return type(s) == "table" and s.spell or nil
end

local NEXT = { near = true, noMana = true, onYou = true }

tests["close enemy e2e: mage, a melee enemy next to you hit you just now: Frost Nova"] = function(t)
    local _, addon = start(NEXT, 0.5)
    t.eq(spell(addon), "Frost Nova")
end

tests["close enemy e2e: mage, the same enemy not near: no Frost Nova"] = function(t)
    local _, addon = start({ near = false, noMana = true, onYou = true }, 0.5)
    t.ok(spell(addon) ~= "Frost Nova", tostring(spell(addon)))
end

tests["close enemy e2e: mage, no hit seen or an old hit: no Frost Nova"] = function(t)
    local _, a1 = start(NEXT, false)
    t.ok(spell(a1) ~= "Frost Nova", tostring(spell(a1)))
    local _, a2 = start(NEXT, D.HIT_WINDOW + 5)
    t.ok(spell(a2) ~= "Frost Nova", tostring(spell(a2)))
end

tests["close enemy e2e: mage, the reads not known: no Frost Nova, a suggestion still"] = function(t)
    local _, addon = start(nil, nil)
    local s = spell(addon)
    t.ok(s ~= nil, "a suggestion")
    t.ok(s ~= "Frost Nova", tostring(s))
end

return tests
