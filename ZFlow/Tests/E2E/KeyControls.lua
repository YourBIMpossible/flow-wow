local _, ns = ...
-- N41 (P-KEYS slice B): the key controls on the whole add-on, loaded on a
-- fake client: a paladin, the rotation and the key frame (the easy key)
-- switched on. Each control has a row on the Combat topic of the settings
-- window, with a group and words to find it by, and the rotation button
-- obeys it: Shift + key heals you, Alt + key holds the healthstone or
-- potion (N8), Ctrl + key heals a friend you target, and the key does
-- gathering (the gathering tracking step, P-GATHER). Off means that
-- modifier is not set. Per lead section 236: data arriving late, a reload,
-- and a read that fails then recovers. Made-up spell and item ids.
--
-- What the fake client cannot express: the press. The test sees the
-- attributes on the secure button, not the cast. Nothing is bound and no
-- macro is made (section 246). Not tested in game.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local SHIFT, ALT, CTRL, ACTIONS = "rotation.shiftHeal", "rotation.altItem", "rotation.ctrlFriend", "rotation.keyActions"
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local HEALS = { ["Flash of Light"] = { id = 19750, ms = 1500 }, ["Holy Light"] = { id = 635, ms = 2500 } }
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local STONE = 9201
local INFO = { [STONE] = { name = "Minor Healthstone", classID = 0, subclassID = 0, level = 10, minLevel = 0 } }
local MINERALS = "Find Minerals"

local function learn(c, name, id, ms)
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true, castMs = ms })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
end

-- opts.account / opts.char: saved tables (a reload). opts.noHeals: no heal
-- learned yet. opts.gather: Mining known with Find Minerals off.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false)
    for name, id in pairs(IDS) do learn(c, name, id) end
    if not opts.noHeals then
        for name, h in pairs(HEALS) do learn(c, name, h.id, h.ms) end
    end
    if opts.gather then
        learn(c, MINERALS, 9301)
        c.setProfessions({ "Mining" })
        c.setTracking(MINERALS, false)
    end
    c.setBagItems({ { item = STONE, count = 1 } })
    c.setItemInfo(INFO)
    c.setItemTexture(STONE, "tex:stone")
    c.setItemCooldown(STONE, 0)
    c.setPlayerBuffs(SEALED)
    c.setTarget({ exists = false })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
    return c, addon
end

-- One attribute on the rotation button.
local function attr(c, name)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h.attrs[name] end
    end
    return nil
end

local function friendTarget(c)
    c.setTarget({ exists = true, hostile = false, dead = false })
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
end

local function set(c, addon, key, value)
    addon.settings:set(key, value)
    c.advance(1, 5)
end

local function nothingWritten(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "no binding written") end
    if type(c.secureMacros) == "function" then t.eq(#c.secureMacros(), 0, "no macro made") end
end

local function rowOf(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["key controls: each control has a row on the Combat topic, with a group and words to find it by"] = function(t)
    local c, addon = start()
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
    for _, key in ipairs({ K.SETTING, SHIFT, ALT, CTRL, ACTIONS }) do
        t.ok(rowOf(c, key) ~= nil, "a row for " .. key .. " in the settings window")
        local row = addon.settings:row(key)
        t.ok(type(row) == "table" and type(row.group) == "string" and row.group:find("^combat") ~= nil,
            key .. " has a combat group")
        t.ok(type(row) == "table" and type(row.synonyms) == "table" and #row.synonyms > 0, key .. " has synonyms")
    end
    local easy = addon.settings:row(K.SETTING)
    local found = false
    for _, w in ipairs(type(easy) == "table" and easy.synonyms or {}) do
        if w == "easy key" then found = true end
    end
    t.ok(found, "the easy key is found by its old name")
    for _, key in ipairs({ SHIFT, ALT, CTRL, ACTIONS }) do
        t.eq(addon.settings:get(key), true, key .. " is on by default")
    end
end

tests["key controls: Shift + key heals you; off, Shift + key is not set"] = function(t)
    local c, addon = start()
    t.eq(attr(c, "*type-shift"), "spell")
    t.eq(attr(c, "*spell-shift"), "Flash of Light", "the fastest direct heal")
    t.eq(attr(c, "*unit-shift"), "player", "on you")
    set(c, addon, SHIFT, false)
    t.eq(attr(c, "*spell-shift"), nil, "off: nothing on Shift")
    t.eq(attr(c, "*type-shift"), nil)
    set(c, addon, SHIFT, true)
    t.eq(attr(c, "*spell-shift"), "Flash of Light", "on again")
    nothingWritten(t, c)
end

tests["key controls: Alt + key holds the healthstone; off, Alt + key is not set"] = function(t)
    local c, addon = start()
    t.eq(attr(c, "*type-alt"), "item")
    t.eq(attr(c, "*item-alt"), "item:" .. STONE)
    set(c, addon, ALT, false)
    t.eq(attr(c, "*item-alt"), nil, "off: no item on Alt")
    t.eq(attr(c, "*type-alt"), nil, "off: Alt not set")
    set(c, addon, ALT, true)
    t.eq(attr(c, "*item-alt"), "item:" .. STONE, "on again")
end

tests["key controls: Ctrl + key heals a friend you target; off, Ctrl + key is not set"] = function(t)
    local c, addon = start()
    local before = attr(c, "*spell-ctrl")
    t.ok(before ~= nil and before ~= "Flash of Light", "no friend targeted: the pack's spell, got " .. tostring(before))
    friendTarget(c); c.advance(1, 5)
    t.eq(attr(c, "*spell-ctrl"), "Flash of Light", "a friend targeted: your quick heal")
    t.eq(attr(c, "*unit-ctrl"), "target", "on the friend")
    set(c, addon, CTRL, false)
    t.eq(attr(c, "*spell-ctrl"), nil, "off: nothing on Ctrl")
    t.eq(attr(c, "*type-ctrl"), nil)
    nothingWritten(t, c)
end

tests["key controls: the key does gathering; off, the gathering step stays on the icon but off the key"] = function(t)
    local c, addon = start({ gather = true })
    local view = addon.rotationDriver.view()
    local s = type(view) == "table" and view.suggestion or nil
    t.eq(type(s) == "table" and s.spell, MINERALS, "the gathering step is suggested")
    t.eq(type(view) == "table" and type(view.attrs) == "table" and view.attrs.source, "suggestion", "on the key")
    set(c, addon, ACTIONS, false)
    view = addon.rotationDriver.view()
    s = type(view) == "table" and view.suggestion or nil
    t.eq(type(s) == "table" and s.spell, MINERALS, "off: still shown")
    t.eq(type(s) == "table" and s.keyOff, true, "off: marked as not on the key")
    t.ok(type(view) == "table" and type(view.attrs) == "table" and view.attrs.source ~= "suggestion", "off: not on the key")
end

tests["key controls: in a fight the key is not changed; it follows the row when the fight ends"] = function(t)
    local c, addon = start()
    c.setCombat(true); c.advance(1, 5)
    set(c, addon, SHIFT, false)
    t.eq(attr(c, "*spell-shift"), "Flash of Light", "in a fight: unchanged")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(1, 5)
    t.eq(attr(c, "*spell-shift"), nil, "after the fight: off")
end

tests["key controls: the rows are read back after a reload"] = function(t)
    local c, addon = start()
    set(c, addon, SHIFT, false)
    set(c, addon, CTRL, false)
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(SHIFT), false, "Shift read back")
    t.eq(addon2.settings:get(CTRL), false, "Ctrl read back")
    t.eq(attr(c2, "*spell-shift"), nil, "after the reload: nothing on Shift")
    t.eq(attr(c2, "*spell-ctrl"), nil, "after the reload: nothing on Ctrl")
    t.eq(attr(c2, "*item-alt"), "item:" .. STONE, "Alt still on")
    set(c2, addon2, SHIFT, true)
    t.eq(attr(c2, "*spell-shift"), "Flash of Light", "switched on again")
end

tests["key controls: a heal learned late goes on Shift + key"] = function(t)
    local c = start({ noHeals = true })
    t.eq(attr(c, "*spell-shift"), nil, "no heal known: nothing on Shift")
    for name, h in pairs(HEALS) do learn(c, name, h.id, h.ms) end
    c.fire("SPELLS_CHANGED"); c.advance(1, 5)
    t.eq(attr(c, "*spell-shift"), "Flash of Light", "learned late: on Shift")
end

tests["key controls: the friend read fails, then recovers"] = function(t)
    local c, addon = start()
    friendTarget(c)
    c.setUnitCareFails(true); c.advance(1, 5)
    local got = attr(c, "*spell-ctrl")
    t.ok(got ~= "Flash of Light", "friend not known: the pack's spell, got " .. tostring(got))
    t.ok(addon.rotationDriver.view() ~= nil and addon.rotationDriver.view().stale == nil, "the tick went on")
    c.setUnitCareFails(false); c.advance(1, 5)
    t.eq(attr(c, "*spell-ctrl"), "Flash of Light", "the read recovers: the heal on the friend")
    t.eq(attr(c, "*unit-ctrl"), "target")
end

return tests
