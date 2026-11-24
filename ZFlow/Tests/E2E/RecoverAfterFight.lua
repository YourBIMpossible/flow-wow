local _, ns = ...
-- D-14: bandage or food after a fight, on the whole add-on, loaded on a
-- fake client: a paladin, buffs up, the rotation and the key frame on, a
-- bandage and bread in the bags. Hurt in a fight (the low-health warning),
-- then out of it: the bandage on the rotation key (the item type), and
-- with Recently Bandaged on you the bread. Made-up items and tooltip
-- lines; not tested in game. The fake cannot press the key: the test sees
-- the attributes set on it, not the item used.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }

local LINEN, BREAD = 9401, 9402
local INFO = {
    [LINEN] = { name = "Linen Bandage", classID = 0, subclassID = 7, level = 1, minLevel = 0 },
    [BREAD] = { name = "Tough Hunk of Bread", classID = 0, subclassID = 5, level = 5, minLevel = 1 },
}
local LINES = { [BREAD] = { "Tough Hunk of Bread", "Use: Restores 61 health over 18 sec." } }

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setBagItems({ { item = LINEN, count = 5 }, { item = BREAD, count = 4 } })
    c.setItemInfo(INFO)
    for id, l in pairs(LINES) do c.setItemLines(id, l) end
    c.setItemTexture(LINEN, "tex:Linen Bandage"); c.setItemTexture(BREAD, "tex:Bread")
    c.setPlayerBuffs(SEALED); c.setPlayerDebuffs({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
    return c, addon
end

-- The item id on the rotation key itself (no modifier), or nil.
local function onKey(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then
            for attr, v in pairs(h.attrs) do
                if not tostring(attr):find("-", 1, true) and type(v) == "string" then
                    local id = tonumber(v:match("^item:(%d+)$"))
                    if id then return id end
                end
            end
            return nil
        end
    end
    return nil
end

local function keyAttr(c, name)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h.attrs[name] end
    end
    return nil
end

tests["recover after a fight: the bandage on the key, then food when bandaged"] = function(t)
    local c = start()
    t.eq(onKey(c), nil, "not hurt: no bandage or food on the key")
    c.setCombat(true); c.setLowHealth(true); c.advance(3, 10)
    c.setCombat(false); c.setLowHealth(false); c.advance(1, 5)
    t.eq(onKey(c), LINEN, "hurt after the fight: the bandage on the key")
    t.eq(keyAttr(c, "unit"), "player", "the bandage on you")
    c.setPlayerDebuffs({ ["Recently Bandaged"] = true }); c.advance(1, 5)
    t.eq(onKey(c), BREAD, "Recently Bandaged: the bread on the key")
    c.setMounted(true); c.advance(1, 5)
    t.eq(onKey(c), nil, "mounted: nothing")
end

return tests
