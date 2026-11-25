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
--      rotation icon and the Flow button do not stand side by side by
--      default.
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

-- Lead section 348: Druid and Paladin fold the same way. Each distinct
-- Attack rule is counted once (a rule shared by several lists is one rule).
local function distinctAttackRows(class)
    local pack, seen, out = ns.Packs[class], {}, {}
    for _, list in pairs(type(pack) == "table" and pack.lists or {}) do
        for _, rule in ipairs(list) do
            if type(rule) == "table" and (rule.spell == "Attack" or rule.spell == "Auto Attack") and not seen[rule] then
                seen[rule] = true
                out[#out + 1] = rule
            end
        end
    end
    return out
end

tests["flow fight: Druid and Paladin have one Attack row per place, on the swing read"] = function(t)
    for class, want in pairs({ DRUID = 2, PALADIN = 1 }) do
        local rows = distinctAttackRows(class)
        t.eq(#rows, want, class .. ": one Attack row per place, not one per name")
        for _, r in ipairs(rows) do
            t.eq(r.spell, "Attack", class .. ": the name the button casts")
            t.ok(not r.when({ hostile = true, attacking = true, current = { Attack = false, ["Auto Attack"] = false } }),
                class .. ": the swing read says swinging: not again")
        end
    end
    local p = distinctAttackRows("PALADIN")[1]
    if p then t.ok(p.when({ hostile = true, attacking = false }) == true, "PALADIN: not swinging: start it") end
end

tests["flow fight: Attack on the Flow button, the fight starts before the lock: the fight spell"] = function(t)
    local c = start()
    pull(c)
    t.eq(held(c), "Stormstrike", "zflow-btn-pull-spell: before the pull the Flow button already holds the fight spell")
    fightStarts(c)
    t.eq(held(c), "Stormstrike", "set as the fight starts, before the lock: the fight spell")
    c.advance(3, 5)
    t.eq(held(c), "Stormstrike", "kept through the fight")
    t.ok(held(c) ~= "Attack", "never Attack a second click would toggle off")
    noMacros(t, c)
end

tests["flow fight: the lock is on before the fight starts: the fight spell was already set"] = function(t)
    local c = start()
    pull(c)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setLockdown(true)
    c.setCombat(true)
    c.advance(3, 5)
    t.eq(held(c), "Stormstrike", "zflow-btn-pull-spell: set before the pull, so the lock changes nothing")
    local line = tip(c, FLOW .. "1") or ""
    t.ok(line:find("Casts Stormstrike", 1, true) ~= nil, "the tooltip says the click casts the fight spell: " .. line)
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

-- Recovery R1 (lead section 564): one buffButton.dock default, docked, as
-- legacy Flow has it (BuffButton.lua BB.DockWanted: docked unless taken
-- off), the same in the three files that name it.
tests["flow fight: one dock default, the same in the three files"] = function(t)
    local _, addon = start()
    t.eq(addon.settings:row(FB.DOCK).default, true, "the settings row (Rotation/FlowButton.lua)")
    local model = nil
    for _, row in ipairs(ns.Settings.Model.ROWS) do
        if row.key == FB.DOCK then model = row.default end
    end
    t.eq(model, true, "the settings model (Settings/Model.lua)")
    t.eq(ns.Import.Stored.BuffButtonSettings({}).dock, true, "the import's reading (Import/Stored.lua)")
end

tests["flow fight: the buff button is docked under the Flow button by default"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(FB.DOCK), true, "docked by default")
    local s = rowOf(c, SELF)
    if not s then t.ok(false, "the buff button made"); return end
    local p = FB.DEFAULT_POINT
    local under = { p[1], p[2], p[3], p[4] - 26 - FB.DOCK_GAP - 26 }
    t.eq(s.point, under, "under the Flow button")
    local c2 = start({ account = { settings = { buffButton = { dock = true } } } })
    s = rowOf(c2, SELF)
    if not s then t.ok(false, "the buff button, docked"); return end
    t.eq(s.point, under, "docked saved on: the same place")
end

-- A saved choice is never overwritten by the new default.
tests["flow fight: a saved dock choice or a saved place keeps the buff button apart"] = function(t)
    -- Saved off: apart, at its own default place.
    local c, addon = start({ account = { settings = { buffButton = { dock = false } } } })
    t.eq(addon.settings:get(FB.DOCK), false, "the saved choice is read")
    local f, s = rowOf(c, FLOW), rowOf(c, SELF)
    if not (f and s) then t.ok(false, "both buttons made"); return end
    t.eq(s.point, FB.SELF_DEFAULT_POINT, "its own default place")
    local dx = math.abs(s.point[3] - f.point[3])
    local dy = math.abs(s.point[4] - f.point[4])
    t.ok(dx >= FB.SIZE + FB.DOCK_GAP or dy >= FB.SIZE + FB.DOCK_GAP, "apart from the Flow button, not touching it")
    -- A place saved while the default was "apart" (the player dragged it;
    -- no dock value was written then): it stays at that place.
    local place = { "CENTER", "CENTER", 200, 100 }
    local account = { layout = { buffButton = { frame = { place[1], place[2], place[3], place[4] } } } }
    local c2 = start({ account = account })
    s = rowOf(c2, SELF)
    if not s then t.ok(false, "the buff button, with a saved place"); return end
    t.eq(s.point, place, "where the player left it, not under the Flow button")
    local saved = c2.saved(ns.id.accountDB)
    t.eq(type(saved.settings) == "table" and type(saved.settings.buffButton) == "table"
        and saved.settings.buffButton.dock or nil, nil, "and nothing was written for it")
    -- Saved on wins over a saved place.
    account = { layout = { buffButton = { frame = { place[1], place[2], place[3], place[4] } } },
                settings = { buffButton = { dock = true } } }
    local c3 = start({ account = account })
    s = rowOf(c3, SELF)
    if not s then t.ok(false, "the buff button, docked with a saved place"); return end
    local p = FB.DEFAULT_POINT
    t.eq(s.point, { p[1], p[2], p[3], p[4] - 26 - FB.DOCK_GAP - 26 }, "saved on: under the Flow button")
end

tests["flow fight: the rotation icon and the Flow button do not stand side by side"] = function(t)
    local c = start()
    pull(c)
    local h, f = icon(c), rowOf(c, FLOW)
    if not (h and f) then t.ok(false, "the rotation icon and the Flow button"); return end
    t.eq(held(c), "Stormstrike")
    t.eq(h.shown, true, "the icon shows the next spell")
    local gap = math.abs(h.point[4] - f.point[4]) - (ns.RotationIcon.SIZE + FB.SIZE) / 2
    t.ok(gap >= FB.SIZE, "a full button apart, not touching: " .. gap)
end

-- Parity row D-03 (lead section 712), as Flow's Modules/Rotation/Cast.lua
-- (:232-236 assistantSpell, :1048-1050 at the pull): where the client has
-- the game's one-button assistant (C_AssistedCombat.GetActionSpell, on
-- warcraft.wiki.gg for the forever flavour from 1.60.1), the key and the
-- Flow button hold its spell for the fight instead of the pack's fight
-- spell. Only a plain spell name counts. Fails before: never read.
tests["flow fight: the game's one-button assistant spell is held for the fight when the client has one"] = function(t)
    local c = start()
    c.setAssistantSpell("Single-Button Assistant")
    pull(c)
    t.eq(held(c), "Single-Button Assistant", "the assistant's spell, before the pull")
    fightStarts(c)
    c.advance(3, 5)
    t.eq(held(c), "Single-Button Assistant", "kept through the fight")
    noMacros(t, c)
end

tests["flow fight: no assistant, or an answer that is no plain name, keeps the pack's fight spell"] = function(t)
    for _, answer in ipairs({ false, "", 42 }) do
        local c = start()
        if answer ~= false then c.setAssistantSpell(answer) end
        pull(c)
        t.eq(held(c), "Stormstrike", "the pack's fight spell: " .. tostring(answer))
    end
    local c = start()
    c.assistantSpell = function() error("the client refused") end
    pull(c)
    t.eq(held(c), "Stormstrike", "a read that raises")
end

tests["flow fight: the assistant read, pure"] = function(t)
    local D = ns.RotationDriver
    t.eq(D.Assistant({ assistantSpell = function() return "Single-Button Assistant" end }), "Single-Button Assistant")
    t.eq(D.Assistant({ assistantSpell = function() return nil end }), nil)
    t.eq(D.Assistant({ assistantSpell = function() return "" end }), nil)
    t.eq(D.Assistant({}), nil, "no such read")
    t.eq(D.Assistant(nil), nil)
end

return tests
