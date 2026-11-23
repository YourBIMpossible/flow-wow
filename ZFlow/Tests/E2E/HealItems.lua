local _, ns = ...
-- N8 (lead section 238): healthstone, then healing potion, on the whole
-- add-on, loaded on a fake client: a paladin, the rotation and the key
-- frame switched on. Out of a fight the best healing item goes on Alt +
-- the rotation key; in a fight with the low-health warning on, the icon
-- shows the healthstone, the potion while the stone cools down. Cases:
-- item data arriving late (GET_ITEM_INFO_RECEIVED), a reload (the setting
-- read back), and a read that fails then recovers. Made-up items; not
-- tested in game.
--
-- What the fake client cannot express: the press itself. A secure button
-- acts only on a hardware click; the test sees the attributes set on it
-- ("*type-alt", "*item-alt"), not the item used. Section 246 (N63-E): the
-- item type ("*item-alt" = "item:ID"), never a macro. N8 stays PARTLY
-- until seen in the client.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }

local STONE, POT = 9201, 9202
local INFO = {
    [STONE] = { name = "Minor Healthstone", classID = 0, subclassID = 0, level = 10, minLevel = 0 },
    [POT] = { name = "Minor Healing Potion", classID = 0, subclassID = 1, level = 5, minLevel = 1 },
}
local TEX = { [STONE] = "tex:Minor Healthstone", [POT] = "tex:Minor Healing Potion" }

-- opts.account / opts.char: saved tables (a reload); opts.info: the item
-- info the client gives.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setBagItems({ { item = STONE, count = 1 }, { item = POT, count = 3 } })
    c.setItemInfo(opts.info or INFO)
    for id, tex in pairs(TEX) do c.setItemTexture(id, tex) end
    c.setItemCooldown(STONE, 0); c.setItemCooldown(POT, 0)
    c.setPlayerBuffs(SEALED)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    return c, addon, icon
end

local function on(c, addon)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
end

-- What Alt + the rotation key holds: the item id, or nil.
local function onAlt(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then
            local m = h.attrs["*item-alt"]
            if h.attrs["*type-alt"] == "item" and type(m) == "string" then
                return tonumber(m:match("^item:(%d+)$"))
            end
            return nil
        end
    end
    return nil
end

local function fight(c, low)
    c.setCombat(true); c.setLowHealth(low); c.advance(1, 5)
end

local function itemShown(icon)
    return icon.shown == true and (icon.texture == TEX[STONE] or icon.texture == TEX[POT])
end

tests["paladin heal items: the stone on Alt, then the stone, then the potion in a fight"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    on(c, addon)
    t.eq(onAlt(c), STONE, "out of a fight: the stone on Alt + the key")
    t.ok(not itemShown(icon), "out of a fight: no item offered")
    fight(c, false)
    t.ok(not itemShown(icon), "in a fight, no warning: no item")
    c.setLowHealth(true); c.advance(1, 5)
    t.eq(icon.texture, TEX[STONE], "low health: the stone")
    c.setItemCooldown(STONE, 120); c.advance(1, 5)
    t.eq(icon.texture, TEX[POT], "the stone cooling down: the potion")
    c.setItemCooldown(POT, 60); c.advance(1, 5)
    t.ok(not itemShown(icon), "both cooling down: no item")
    t.eq(onAlt(c), STONE, "in a fight the key is not changed")
end

tests["paladin heal items: item data arriving late"] = function(t)
    local c, addon, icon = start({ info = {} })
    on(c, addon)
    t.eq(onAlt(c), nil, "nothing read yet: nothing on Alt")
    c.setItemInfo({ [POT] = INFO[POT] }); c.fire("GET_ITEM_INFO_RECEIVED"); c.advance(1, 5)
    t.eq(onAlt(c), POT, "the potion read: the potion on Alt")
    c.setItemInfo(INFO); c.fire("GET_ITEM_INFO_RECEIVED"); c.advance(1, 5)
    t.eq(onAlt(c), STONE, "the stone read late: the stone on Alt")
    fight(c, true)
    t.eq(icon.texture, TEX[STONE], "in the fight: the stone")
end

tests["paladin heal items: the setting is read back after a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    addon.settings:set(D.HEAL, false); c.advance(1, 5)
    t.eq(onAlt(c), nil, "switched off: nothing on Alt")
    local c2, addon2, icon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.advance(1, 5)
    t.eq(addon2.settings:get(D.HEAL), false, "the setting read back")
    fight(c2, true)
    t.ok(not itemShown(icon2), "after the reload, low health: no item")
    c2.setCombat(false); c2.setLowHealth(false)
    addon2.settings:set(D.HEAL, true); c2.advance(1, 5)
    t.eq(onAlt(c2), STONE, "switched on again: the stone on Alt")
    fight(c2, true)
    t.eq(icon2.texture, TEX[STONE], "and offered in the fight")
end

tests["paladin heal items: a read that fails, then recovers"] = function(t)
    local c, addon, icon = start()
    on(c, addon)
    local low, cd = c.lowHealth, c.itemCooldown
    c.lowHealth = function() error("warning read failed") end
    fight(c, true)
    t.ok(not itemShown(icon), "the warning not known: no item")
    c.lowHealth = low; c.advance(1, 5)
    t.eq(icon.texture, TEX[STONE], "the read recovers: the stone")
    c.itemCooldown = function() error("cooldown read failed") end
    c.advance(1, 5)
    t.ok(not itemShown(icon), "cooldowns not known: no item")
    c.itemCooldown = cd; c.advance(1, 5)
    t.eq(icon.texture, TEX[STONE], "the cooldown read recovers: the stone")
end

return tests
