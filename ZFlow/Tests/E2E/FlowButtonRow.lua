local _, ns = ...
-- Lead section 409: the owner saw the Flow buttons row in game (build
-- ec94868b) as a grey "?" box, then two identical spell icons side by side,
-- with yellow bars beside two of them. On the whole add-on loaded on a fake
-- client, entered the way the player enters (boot, events, a pull):
--
--   1. The buff button with nothing to cast never shows the "?": dimmed
--      with the last buff's own picture, or nothing drawn when it never
--      held one. What a click casts is unchanged (nothing).
--   2. One picture for the next spell, on the Flow button: the rotation
--      icon stays on but draws nothing (faded) while the Flow button shows the same spell. It
--      shows only what the button does not: in a fight, the rotation's new
--      suggestion while the locked button keeps what it had.
--   3. The yellow bars are the move grips (UI/MoveHandle.lua). They are
--      drawn only while the mouse is over the grip or its button.
--   4. Each button carries a word under it: "Flow" and "Buffs".
--
-- What the fake client cannot express: the picture itself, the hover, the
-- click. Spell ids are made up; not tested in game.
local tests = {}

local FB = ns.FlowButton
local D = ns.RotationDriver
local FLOW = ns.id.framePrefix .. "FlowButton"
local SELF = ns.id.framePrefix .. "SelfButton"
local ICON = ns.id.framePrefix .. "RotationIcon"
local PRIEST = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Smite"] = 585,
}
local SHAMAN = {
    ["Lightning Shield"] = 324, ["Lightning Bolt"] = 403, ["Flame Shock"] = 8050,
    ["Stormstrike"] = 17364, ["Attack"] = 6603,
}

local function boot(c)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    c.advance(3, 5)
    return addon
end

local function spells(c, list)
    for name, id in pairs(list) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
        if type(c.setInRange) == "function" then c.setInRange(id, true) end
    end
end

local function priest(buffs)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false); c.setScreen(1000, 768)
    c.setPlayerBuffs(buffs or {})
    spells(c, PRIEST)
    return c, boot(c)
end

local function shaman()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("SHAMAN"); c.setFaction("Alliance"); c.setLevel(40)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false); c.setStealthed(false)
    c.setScreen(1000, 768)
    c.setPlayerBuffs({ ["Lightning Shield"] = 600 })
    spells(c, SHAMAN)
    c.setCurrentSpell(6603, false)
    c.setTarget({ exists = false })
    return c, boot(c)
end

local function rowOf(c, name)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == name then return h end
    end
    return nil
end

local function held(c, name)
    local h = rowOf(c, name)
    if not h then return nil end
    return h.slots[1].attrs.spell or h.slots[1].attrs.item
end

local function face(c, name)
    return (c.buttonFaces or {})[name .. "1"] or {}
end

local function icon(c)
    for _, h in ipairs(c.icons or {}) do
        if h.spec and h.spec.name == ICON then return h end
    end
    return {}
end

local function noMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

tests["flow row: one picture for the next spell, on the Flow button"] = function(t)
    local c = priest()
    t.eq(held(c, FLOW), "Power Word: Fortitude", "the Flow button holds the next spell")
    t.eq(rowOf(c, FLOW).slots[1].icon, "tex:Power Word: Fortitude", "with its picture")
    t.eq(face(c, FLOW).dimmed, nil, "not dimmed")
    t.ok(icon(c).spec ~= nil, "the rotation icon is made")
    t.eq(icon(c).faded, true, "the rotation icon draws nothing: it does not show the same picture beside it")
    noMacros(t, c)
end

tests["flow row: the buff button with nothing to cast shows no question mark"] = function(t)
    -- Never held a buff: nothing is drawn.
    local c0 = priest({ ["Power Word: Fortitude"] = 1800, ["Inner Fire"] = 600 })
    t.eq(held(c0, SELF), nil, "nothing to cast")
    t.eq(face(c0, SELF).dimmed, "gone", "never held a buff: nothing drawn, no grey box")
    t.eq(rowOf(c0, SELF).slots[1].attrs.type, nil, "a click casts nothing, as before")
    -- Held Inner Fire, then it went up: dimmed with its picture.
    local c = priest()
    t.eq(held(c, SELF), "Inner Fire", "the buff button holds the missing buff")
    t.eq(face(c, SELF).dimmed, nil, "not dimmed while it holds one")
    c.setPlayerBuffs({ ["Inner Fire"] = 600 }); c.advance(3, 5)
    t.eq(held(c, SELF), nil, "nothing to cast now")
    t.eq(rowOf(c, SELF).slots[1].attrs.type, nil, "a click casts nothing")
    t.eq(face(c, SELF).dimmed, "picture", "dimmed, no question mark")
    t.eq(rowOf(c, SELF).slots[1].icon, "tex:Inner Fire", "with the last buff's own picture")
    c.setPlayerBuffs({}); c.advance(3, 5)
    t.eq(held(c, SELF), "Inner Fire", "missing again: held")
    t.eq(face(c, SELF).dimmed, nil, "and bright")
    noMacros(t, c)
end

tests["flow row: the yellow bars are the move grips, drawn only on hover"] = function(t)
    local c = priest()
    for _, name in ipairs({ FLOW, SELF }) do
        local spec = (c.moveHandles or {})[name]
        t.ok(spec ~= nil, "a grip moves " .. name)
        t.eq(spec and spec.quiet, true, "its bar is not drawn until the mouse is over it")
        t.eq(type(spec and spec.onMoved), "function", "and it still moves the button")
    end
end

tests["flow row: each button carries a word, told apart without hovering"] = function(t)
    local c = priest()
    t.eq({ FB.FLOW_WORD, FB.SELF_WORD }, { "Flow", "Buffs" })
    t.eq(face(c, FLOW).label, "Flow", "the Flow button's word")
    t.eq(face(c, SELF).label, "Buffs", "the buff button's word")
end

tests["flow row: in a fight the rotation icon shows only what the locked button does not"] = function(t)
    local c = shaman()
    c.setTarget({ exists = true, hostile = true, dead = false }); c.setTargetName("Training Dummy")
    c.advance(3, 5)
    -- zflow-btn-pull-spell (lead section 430 item 1): the Flow button never
    -- holds Attack; before the pull it already holds the fight spell, and the
    -- rotation icon alone advises starting the attack.
    t.eq(held(c, FLOW), "Stormstrike", "before the pull: the fight spell on the Flow button")
    t.eq({ icon(c).shown, icon(c).faded }, { true, false }, "the icon shows Attack, which the button does not hold")
    t.eq(icon(c).texture, "tex:Attack")
    c.setLockdown(false); c.setCurrentSpell(6603, true); c.setCombat(true); c.setLockdown(true)
    c.advance(3, 5)
    t.eq(held(c, FLOW), "Stormstrike", "the fight spell, kept through the fight")
    t.eq(icon(c).faded, true, "the rotation suggests the same: no second picture")
    -- The swing stops: the rotation now suggests Attack; the locked button cannot change.
    c.setCurrentSpell(6603, false); c.advance(3, 5)
    t.eq(held(c, FLOW), "Stormstrike", "the click still casts what it held")
    t.eq({ icon(c).shown, icon(c).faded }, { true, false }, "the rotation icon shows the new suggestion the button cannot take")
    t.eq(icon(c).texture, "tex:Attack")
    c.setLockdown(false); c.setCombat(false); c.advance(3, 5)
    t.eq(held(c, FLOW), "Stormstrike", "after the fight the button still never takes Attack")
    t.eq({ icon(c).shown, icon(c).faded }, { true, false }, "the icon alone shows Attack")
    noMacros(t, c)
end

-- Lead section 415: the Flow button's own "?" (rotation off, or no
-- suggestion) never shows: it shows the last spell dimmed, or the plain
-- word "Flow" with no "?". The empty buff button takes no mouse; mouse
-- changes are made only while the lock reads a plain false.
local function question(c, name)
    local f = face(c, name)
    return f.empty == true and f.dimmed ~= "picture" and f.dimmed ~= "gone" and f.dimmed ~= "word"
end

tests["flow row: rotation off, the Flow button shows no question mark"] = function(t)
    local c, addon = priest()
    t.eq(question(c, FLOW), false, "on: no question mark")
    addon.settings:set(D.SETTING, false); c.advance(3, 5)
    t.eq(held(c, FLOW), nil, "off: the Flow button holds nothing")
    t.eq(question(c, FLOW), false, "off: no question mark")
    t.eq(face(c, FLOW).dimmed, "picture", "the last spell, dimmed")
    t.eq(rowOf(c, FLOW).slots[1].icon, "tex:Power Word: Fortitude", "its own picture")
    t.eq(rowOf(c, FLOW).slots[1].attrs.type, nil, "a click casts nothing")
    noMacros(t, c)
end

-- Never held a spell (the rotation never switched on): the same empty-hold
-- path the rotation takes when it has no suggestion yet.
tests["flow row: rotation never on, the Flow button shows its word, no question mark"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false); c.setScreen(1000, 768)
    spells(c, PRIEST)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN")
    addon.settings:set(D.SETTING, false)
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    t.ok(rowOf(c, FLOW) ~= nil, "the Flow button is made")
    t.eq(held(c, FLOW), nil, "holds nothing")
    t.eq(question(c, FLOW), false, "no question mark")
    t.eq(face(c, FLOW).dimmed, "word", "the plain word Flow, never held a spell")
    t.eq(face(c, FLOW).label, "Flow")
    noMacros(t, c)
end

tests["flow row: the empty buff button takes no mouse"] = function(t)
    local c = priest({ ["Power Word: Fortitude"] = 1800, ["Inner Fire"] = 600 })
    t.eq(held(c, SELF), nil, "nothing to cast")
    t.eq(face(c, SELF).mouse, false, "empty: takes no mouse")
    c.setPlayerBuffs({}); c.advance(3, 5)
    t.eq(held(c, SELF), "Inner Fire", "holds a buff")
    t.eq(face(c, SELF).mouse, true, "holding one: takes the mouse")
    -- In a fight the lock keeps it as it was; nothing is changed.
    c.setCombat(true); c.setLockdown(true)
    c.setPlayerBuffs({ ["Inner Fire"] = 600 }); c.advance(3, 5)
    t.eq(face(c, SELF).mouse, true, "in a fight: unchanged")
    t.eq(face(c, SELF).mouseInLock or 0, 0, "no mouse change made under the lock")
    c.setLockdown(false); c.setCombat(false); c.advance(3, 5)
    t.eq(held(c, SELF), nil, "after the fight: empty")
    t.eq(face(c, SELF).mouse, false, "and takes no mouse")
    t.eq(face(c, FLOW).mouse ~= false, true, "the Flow button holding a spell takes the mouse")
    noMacros(t, c)
end

return tests
