local _, ns = ...
-- Lead section 340: the owner saw these in game. The Flow button stuck on
-- "Attack" in a fight, and three buttons that looked the same. On the whole
-- add-on loaded on a fake client, a Shaman with an enemy targeted.
--
--   1. The Shaman pack has one Attack row, driven by the swing read
--      (Rotation/Driver.lua attackingOf), not two rows for two names.
--   2. The Flow button holds Attack before a pull. PLAYER_REGEN_DISABLED is
--      handled before the lock is on (first guess, not seen in game): the
--      Flow button takes the spell for the fight then, never Attack, which a
--      second click would toggle off. In the fight the button cannot change;
--      its tooltip says what the click casts and that it changes after.
--   3. Three buttons, each saying what it is: the rotation icon shows the
--      next spell and casts nothing, the Flow button casts, the buff button
--      casts self buffs. The buff button stands apart by default. The
--      rotation icon is not shown beside the Flow button holding the same
--      spell.
--
-- What the fake client cannot express: the click, the swing, the order of
-- PLAYER_REGEN_DISABLED and the lock in game. Spell ids are made up.
local tests = {}

local FB = ns.FlowButton
local D = ns.RotationDriver
local IDS = {
    ["Lightning Shield"] = 324, ["Lightning Bolt"] = 403, ["Flame Shock"] = 8050,
    ["Stormstrike"] = 17364, ["Attack"] = 6603,
}
local ATTACK_ID = 6603
local FLOW = ns.id.framePrefix .. "FlowButton"
local SELF = ns.id.framePrefix .. "SelfButton"
local ICON = ns.id.framePrefix .. "RotationIcon"
local ENEMY = { exists = true, hostile = true, dead = false }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
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
    return c, addon
end

local function rowOf(c, name)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == name then return h end
    end
    return nil
end

local function held(c)
    local h = rowOf(c, FLOW)
    if not h then return nil end
    local a = h.slots[1].attrs
    return a.spell or a.item
end

local function icon(c)
    for _, h in ipairs(c.icons or {}) do
        if h.spec and h.spec.name == ICON then return h end
    end
    return nil
end

local function tip(c, frame)
    if type(c.hoverTipText) ~= "function" then return nil end
    return c.hoverTipText(frame)
end

local function pull(c)
    c.setTarget(ENEMY)
    c.setTargetName("Training Dummy")
    c.advance(3, 5)
end

-- The press on Attack: the swing goes on and the fight starts; the lock
-- comes on after PLAYER_REGEN_DISABLED is handled.
local function fightStarts(c)
    c.setLockdown(false)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setCombat(true)
    c.setLockdown(true)
end

local function noMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

local function attackRows()
    local pack = ns.Packs.SHAMAN
    local out = {}
    for _, list in pairs(type(pack) == "table" and pack.lists or {}) do
        for _, rule in ipairs(list) do
            if type(rule) == "table" and (rule.spell == "Attack" or rule.spell == "Auto Attack") then out[#out + 1] = rule end
        end
    end
    return out
end

tests["flow fight: the Shaman pack has one Attack row, driven by the swing read"] = function(t)
    local rows = attackRows()
    t.eq(#rows, 1, "one Attack row, not one per name")
    local r = rows[1]
    if not r then return end
    t.eq(r.spell, "Attack", "the name the button casts")
    t.ok(r.when({ hostile = true, attacking = false }) == true, "not swinging: start it")
    t.ok(not r.when({ hostile = true, attacking = true, current = { Attack = false } }), "the swing read says swinging: not again")
    t.ok(not r.when({ hostile = false, attacking = false }), "no enemy: no swing")
end

tests["flow fight: Attack on the Flow button, the fight starts before the lock: the fight spell"] = function(t)
    local c = start()
    pull(c)
    t.eq(held(c), "Attack", "before the pull the Flow button holds Attack")
    fightStarts(c)
    t.eq(held(c), "Stormstrike", "set as the fight starts, before the lock: the fight spell")
    c.advance(3, 5)
    t.eq(held(c), "Stormstrike", "kept through the fight")
    t.ok(held(c) ~= "Attack", "never Attack a second click would toggle off")
    noMacros(t, c)
end

tests["flow fight: the lock is on before the fight starts: Attack stays, the tooltip says so"] = function(t)
    local c = start()
    pull(c)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setLockdown(true)
    c.setCombat(true)
    c.advance(3, 5)
    t.eq(held(c), "Attack", "the lock was on: nothing could be set")
    local line = tip(c, FLOW .. "1") or ""
    t.ok(line:find("Attack", 1, true) ~= nil and line:find("after the fight", 1, true) ~= nil,
        "the tooltip says the click casts Attack and that it changes after the fight: " .. line)
    noMacros(t, c)
end

tests["flow fight: in a fight the Flow tooltip says what the click casts, not the new suggestion"] = function(t)
    local c = start()
    pull(c)
    fightStarts(c)
    -- The swing stops: the rotation now suggests Attack; the button cannot change.
    c.setCurrentSpell(ATTACK_ID, false); c.advance(3, 5)
    t.eq(held(c), "Stormstrike", "the button keeps what it had")
    local line = tip(c, FLOW .. "1") or ""
    t.ok(line:find("Casts Stormstrike", 1, true) ~= nil, "says what the click casts: " .. line)
    t.ok(line:find("Attack", 1, true) ~= nil and line:find("after the fight", 1, true) ~= nil,
        "names the suggestion and when the button changes: " .. line)
    c.setLockdown(false); c.setCombat(false); c.advance(3, 5)
    t.ok((tip(c, FLOW .. "1") or ""):find("after the fight", 1, true) == nil, "out of the fight: the plain line")
end

tests["flow fight: each of the three buttons says what it is"] = function(t)
    local c = start()
    pull(c)
    local flow = tip(c, FLOW .. "1") or ""
    t.ok(flow:find("^Flow button") ~= nil, "the Flow button names itself: " .. flow)
    t.ok(flow:find("click", 1, true) ~= nil, "and says a click casts: " .. flow)
    local self = tip(c, SELF .. "1") or ""
    t.ok(self:find("^Buff button") ~= nil, "the buff button names itself: " .. self)
    t.ok(self:find("self buff", 1, true) ~= nil, "and says it is for self buffs: " .. self)
    local shown = tip(c, ICON) or ""
    t.ok(shown:find("^Rotation icon") ~= nil, "the rotation icon names itself: " .. shown)
    t.ok(shown:find("casts nothing", 1, true) ~= nil, "and says it only shows: " .. shown)
end

tests["flow fight: the buff button stands apart from the Flow button by default"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(FB.DOCK), false, "not docked by default")
    t.eq(addon.settings:row(FB.DOCK).default, false, "the row's default")
    local f, s = rowOf(c, FLOW), rowOf(c, SELF)
    if not (f and s) then t.ok(false, "both buttons made"); return end
    t.eq(s.point, FB.SELF_DEFAULT_POINT, "its own default place")
    local dx = math.abs(s.point[3] - f.point[3])
    local dy = math.abs(s.point[4] - f.point[4])
    t.ok(dx >= FB.SIZE + FB.DOCK_GAP or dy >= FB.SIZE + FB.DOCK_GAP, "apart from the Flow button, not touching it")
    addon.settings:set(FB.DOCK, true); c.advance(3, 5)
    local p = FB.DEFAULT_POINT
    t.eq(s.point, { p[1], p[2], p[3], p[4] - 26 - FB.DOCK_GAP - 26 }, "docked on: under the Flow button")
end

tests["flow fight: the rotation icon is not shown beside the Flow button holding the same spell"] = function(t)
    local c = start()
    pull(c)
    local h = icon(c)
    if not h then t.ok(false, "the rotation icon"); return end
    t.eq(held(c), "Attack")
    t.eq(h.shown, false, "the same spell as the Flow button: the icon is hidden")
    fightStarts(c)
    c.setCurrentSpell(ATTACK_ID, false); c.advance(3, 5)
    t.eq(held(c), "Stormstrike")
    t.eq(h.shown, true, "the suggestion differs from what the click casts: the icon shows it")
    t.eq(h.texture, "tex:Attack")
end

return tests
