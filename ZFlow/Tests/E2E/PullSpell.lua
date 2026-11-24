local _, ns = ...
-- Lead section 430 item 1 (zflow-btn-pull-spell): the spell on the key for
-- the fight, Flow's way. Flow (Modules/Rotation/Cast.lua C.FightLock and the
-- PLAYER_REGEN_DISABLED handler) never leaves the Attack spell on the key
-- for a fight where it would toggle the swing off, and locks the key to the
-- class pull spell instead. Z-Flow has no non-toggling start (Flow's
-- STARTATTACK binding is not copied: no binding is made), so the bound key
-- (RotationKey) and the visible Flow button never hold Attack: with an
-- enemy targeted they hold the spell for the fight, before the pull, so the
-- lock coming on early changes nothing. The rotation icon still shows the
-- advice. On the whole add-on loaded on a fake client, a Shaman.
--
-- What the fake client cannot express: the press, the swing, the order of
-- PLAYER_REGEN_DISABLED and the lock in game. Spell ids are made up. Not
-- tested in game.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local IDS = {
    ["Lightning Shield"] = 324, ["Lightning Bolt"] = 403, ["Flame Shock"] = 8050,
    ["Stormstrike"] = 17364, ["Attack"] = 6603,
}
local ATTACK_ID = 6603
local FLOW = ns.id.framePrefix .. "FlowButton"

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
    addon.settings:set(K.SETTING, true)
    c.advance(3, 5)
    return c, addon
end

local function pull(c)
    c.setTarget({ exists = true, hostile = true, dead = false })
    c.setTargetName("Training Dummy")
    c.advance(3, 5)
end

local function flowHeld(c)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == FLOW then
            local a = h.slots[1].attrs
            return a.spell or a.item
        end
    end
    return nil
end

local function keyAttrs(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h.attrs end
    end
    return {}
end

-- Every spell the key holds, on any modifier.
local function keySpells(c)
    local out = {}
    for key, value in pairs(keyAttrs(c)) do
        if type(key) == "string" and key:find("spell") and type(value) == "string" then out[value] = true end
    end
    return out
end

local function engaged(addon)
    local view = addon.rotationDriver.view()
    return type(view) == "table" and type(view.suggestion) == "table" and view.suggestion.engage == true
end

local function nothingWritten(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "no binding written") end
    t.eq(#c.secureMacros(), 0, "no macro made")
    t.ok(keyAttrs(c).type ~= "macro", "the key is never a macro")
end

tests["pull spell: an enemy targeted out of a fight: the key holds the fight spell, never Attack"] = function(t)
    local c, addon = start()
    pull(c)
    t.ok(engaged(addon), "the icon still advises starting the attack")
    t.eq(keySpells(c)["Attack"], nil, "Attack is not on the key")
    t.eq(keyAttrs(c).type, "spell", "the key holds a spell")
    t.eq(keyAttrs(c).spell, "Stormstrike", "the spell for the fight")
    nothingWritten(t, c)
end

tests["pull spell: an enemy targeted out of a fight: the Flow button holds the fight spell, never Attack"] = function(t)
    local c = start()
    pull(c)
    t.eq(flowHeld(c), "Stormstrike", "the Flow button holds the spell for the fight before the pull")
    nothingWritten(t, c)
end

tests["pull spell: the lock is on before the fight starts: key and button already hold the fight spell"] = function(t)
    local c = start()
    pull(c)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setLockdown(true)
    c.setCombat(true)
    c.advance(3, 5)
    t.eq(flowHeld(c), "Stormstrike", "the Flow button: the fight spell all fight")
    t.eq(keySpells(c)["Attack"], nil, "the key: no Attack a second press would toggle off")
    t.eq(keyAttrs(c).spell, "Stormstrike", "the key: the fight spell all fight")
    nothingWritten(t, c)
end

tests["pull spell: the swing stops in a fight: Attack never comes back onto key or button"] = function(t)
    local c = start()
    pull(c)
    c.setLockdown(false); c.setCurrentSpell(ATTACK_ID, true); c.setCombat(true); c.setLockdown(true)
    c.setCurrentSpell(ATTACK_ID, false); c.advance(3, 5)
    c.setLockdown(false); c.setCombat(false); c.advance(3, 5)
    t.ok(flowHeld(c) ~= "Attack", "out of the fight, the swing off: the Flow button is not Attack")
    t.eq(keySpells(c)["Attack"], nil, "nor the key")
end

return tests
