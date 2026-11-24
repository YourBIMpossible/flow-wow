local _, ns = ...
-- N1, N2, N20 and N5 (P-KEYS slice D): what the rotation key does out of a
-- fight, on the whole add-on loaded on a fake client: a paladin, the
-- rotation and the key frame (the easy key) switched on. Out of a fight,
-- with nothing stronger to suggest, the key equips your fishing pole and
-- casts Fishing (weapons back first with an enemy targeted), skins or
-- gathers a looted corpse, opens the right profession by a station it has
-- learned, and equips a better item from your bags. Each has a row on the
-- Combat topic, with a group and words to find it by. Per lead section 236:
-- data arriving late, a reload, and a read that fails then recovers.
-- Made-up spell and item ids and places.
--
-- What the fake client cannot express: the press. The test sees the
-- attributes on the secure button, not the cast or the equip. Nothing is
-- bound and no macro is made (section 246). Not tested in game.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local FISHING, CORPSE, STATION, UPGRADE = "rotation.fishing", "rotation.corpseKey", "rotation.stationKey", "rotation.upgradeKey"
local ACTIONS = "rotation.keyActions"
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local POLE, MAIN, OFF, ORE = 6256, 2488, 2129, 2770
local function link(id) return "item:" .. id end
local INFO = {
    [POLE] = { name = "Fishing Pole", classID = 2, subclassID = 20, level = 1, minLevel = 0 },
    [MAIN] = { name = "Sword", classID = 2, subclassID = 7, level = 10, minLevel = 5 },
    [OFF] = { name = "Shield", classID = 4, subclassID = 6, level = 10, minLevel = 5 },
}
local HEAD, BETTER = "item:4320", "item:4321"
local STR = "ITEM_MOD_STRENGTH_SHORT"
local FB = ns.FlowButton
local FLOW = ns.id.framePrefix .. "FlowButton"

local function tip(c, name)
    if type(c.hoverTipText) ~= "function" then return nil end
    return c.hoverTipText(name .. "1")
end

local function learn(c, name, id)
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
end

-- opts.account / opts.char: saved tables (a reload). opts.noPoleInfo: the
-- pole's item data not arrived yet.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false)
    for name, id in pairs(IDS) do learn(c, name, id) end
    c.setBagItems({ { item = POLE, count = 1 } })
    local info = {}
    for id, row in pairs(INFO) do
        if not (opts.noPoleInfo and id == POLE) then info[id] = row end
    end
    c.setItemInfo(info)
    c.setWorn(16, link(MAIN)); c.setWorn(17, link(OFF))
    c.setPlayerBuffs(SEALED)
    c.setTarget({ exists = false })
    c.setPosition(1411, 0.2, 0.2)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
    return c, addon
end

local function attr(c, name)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h.attrs[name] end
    end
    return nil
end

local function set(c, addon, key, value)
    addon.settings:set(key, value)
    c.advance(1, 5)
end

local function suggested(addon)
    local view = addon.rotationDriver.view()
    if type(view) ~= "table" then return nil end
    return view.suggestion
end

local function nothingWritten(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "no binding written") end
    if type(c.secureMacros) == "function" then t.eq(#c.secureMacros(), 0, "no macro made") end
    t.ok(attr(c, "type") ~= "macro", "never a macro")
end

local function rowOf(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

-- The pole put on (as the press would): main hand the pole, off hand empty,
-- the weapons in the bags.
local function poleOn(c)
    c.setWorn(16, link(POLE)); c.setWorn(17, false); c.setFishingPole(true)
    c.setBagItems({ { item = MAIN, count = 1 }, { item = OFF, count = 1 } })
    c.advance(1, 5)
end

tests["key actions: each action has a row on the Combat topic, with a group and words to find it by"] = function(t)
    local c, addon = start()
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
    for _, key in ipairs({ FISHING, CORPSE, STATION, UPGRADE }) do
        t.ok(rowOf(c, key) ~= nil, "a row for " .. key .. " in the settings window")
        local row = addon.settings:row(key)
        t.ok(type(row) == "table" and type(row.group) == "string" and row.group:find("^combat") ~= nil,
            key .. " has a combat group")
        t.ok(type(row) == "table" and type(row.synonyms) == "table" and #row.synonyms > 0, key .. " has synonyms")
    end
    t.eq(addon.settings:get(FISHING), false, "fishing is off until you switch it on")
    for _, key in ipairs({ CORPSE, STATION, UPGRADE }) do t.eq(addon.settings:get(key), true, key .. " is on") end
end

tests["key actions: fishing on: pole from the bags, then Fishing, then weapons back with an enemy targeted"] = function(t)
    local c, addon = start()
    t.ok(attr(c, "item") ~= link(POLE), "fishing off: no pole on the key")
    set(c, addon, FISHING, true)
    t.eq(attr(c, "type"), "item")
    t.eq(attr(c, "item"), link(POLE), "the pole from the bags")
    learn(c, "Fishing", 7620)
    poleOn(c)
    t.eq(attr(c, "type"), "spell")
    t.eq(attr(c, "spell"), "Fishing")
    t.eq(attr(c, "unit"), "player")
    c.setTarget({ exists = true, hostile = true, dead = false }); c.advance(1, 5)
    t.eq(attr(c, "type"), "item")
    t.eq(attr(c, "item"), link(MAIN), "weapons back first")
    nothingWritten(t, c)
end

tests["key actions: a fish on the line is shown, never put on the key"] = function(t)
    local c, addon = start()
    set(c, addon, FISHING, true)
    learn(c, "Fishing", 7620)
    poleOn(c)
    c.setChannel({ name = "Fishing", endsAt = 30 }); c.advance(1, 5)
    local s = suggested(addon)
    t.eq(type(s) == "table" and s.look, true, "shown")
    t.ok(attr(c, "spell") ~= "Fishing", "the key does not cast again")
end

tests["key actions: the weapons are read back after a reload"] = function(t)
    local c, addon = start()
    set(c, addon, FISHING, true)
    learn(c, "Fishing", 7620)
    poleOn(c)
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    learn(c2, "Fishing", 7620)
    poleOn(c2)
    c2.setWorn(16, link(POLE))
    c2.setTarget({ exists = true, hostile = true, dead = false }); c2.advance(1, 5)
    t.eq(attr(c2, "item"), link(MAIN), "the main hand remembered through the reload")
end

tests["key actions: the pole's item data arriving late"] = function(t)
    local c, addon = start({ noPoleInfo = true })
    set(c, addon, FISHING, true)
    t.ok(attr(c, "item") ~= link(POLE), "not known as a pole yet")
    local info = {}
    for id, row in pairs(INFO) do info[id] = row end
    c.setItemInfo(info)
    c.fire("GET_ITEM_INFO_RECEIVED"); c.advance(1, 5)
    t.eq(attr(c, "item"), link(POLE), "known now")
end

local function skinner(c)
    c.setProfessions({ "Skinning" })
    learn(c, "Skinning", 8613)
    c.setTarget({ exists = true, hostile = true, dead = true })
end

tests["key actions: a looted skinnable corpse: the key skins it; with loot on it, only shown"] = function(t)
    local c, addon = start()
    skinner(c)
    c.setTargetCorpse({ exists = true, dead = true, player = false, lootable = true, needs = "Skinning" })
    c.advance(1, 5)
    local s = suggested(addon)
    t.eq(type(s) == "table" and s.look, true, "loot it first: shown")
    t.ok(attr(c, "spell") ~= "Skinning")
    c.setTargetCorpse({ exists = true, dead = true, player = false, lootable = false, needs = "Skinning" })
    c.advance(1, 5)
    t.eq(attr(c, "type"), "spell")
    t.eq(attr(c, "spell"), "Skinning")
    t.eq(attr(c, "unit"), "target")
    set(c, addon, CORPSE, false)
    t.ok(attr(c, "spell") ~= "Skinning", "row off: not on the key")
    nothingWritten(t, c)
end

tests["key actions: the corpse read fails, then recovers"] = function(t)
    local c, addon = start()
    skinner(c)
    c.setTargetCorpse({ exists = true, dead = true, player = false, lootable = false, needs = "Skinning" })
    c.setTargetCorpseFails(true); c.advance(1, 5)
    t.ok(attr(c, "spell") ~= "Skinning", "not known: not on the key")
    t.ok(addon.rotationDriver.view() ~= nil and addon.rotationDriver.view().stale == nil, "the tick went on")
    c.setTargetCorpseFails(false); c.advance(1, 5)
    t.eq(attr(c, "spell"), "Skinning", "recovered")
end

local function smith(c)
    c.setProfessions({ "Mining", "Blacksmithing" })
    learn(c, "Smelting", 2656)
    learn(c, "Blacksmithing", 2018)
end

-- The forge learned: the profession window opened by it, the tool met.
local function learnForge(c)
    c.setPosition(1411, 0.5, 0.5)
    c.setTradeSkillRows({ name = "Blacksmithing", rows = { { index = 1, name = "Rough Sharpening Stone" } } })
    c.setTradeSkillTools(1, { { name = "Blacksmith Forge", has = true } })
    c.fire("TRADE_SKILL_SHOW"); c.advance(1, 5)
    c.setTradeSkillRows(nil)
    c.setTradeSkillTools(1, nil)
end

tests["key actions: by a forge with ore, one press opens Smelting; far from it, nothing"] = function(t)
    local c = start()
    smith(c)
    learnForge(c)
    c.setItemCount(ORE, 3); c.advance(1, 5)
    t.eq(attr(c, "type"), "spell")
    t.eq(attr(c, "spell"), "Smelting")
    c.setPosition(1411, 0.8, 0.8); c.advance(1, 5)
    t.ok(attr(c, "spell") ~= "Smelting", "far away")
    c.setPosition(1411, 0.5, 0.5); c.setItemCount(ORE, 0); c.advance(1, 5)
    t.eq(attr(c, "spell"), "Blacksmithing", "no ore: Blacksmithing")
    c.setTradeSkillRows({ name = "Blacksmithing", rows = {} }); c.advance(1, 5)
    t.ok(attr(c, "spell") ~= "Blacksmithing", "open already: the craft bar makes the count")
    nothingWritten(t, c)
end

tests["key actions: learned stations are kept in the add-on's saved settings through a reload"] = function(t)
    local c = start()
    smith(c)
    learnForge(c)
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    smith(c2)
    c2.setPosition(1411, 0.5, 0.5); c2.setItemCount(ORE, 3); c2.advance(1, 5)
    t.eq(attr(c2, "spell"), "Smelting", "the forge remembered")
end

tests["key actions: the station row off: nothing is learned"] = function(t)
    local c, addon = start()
    smith(c)
    set(c, addon, STATION, false)
    learnForge(c)
    set(c, addon, STATION, true)
    c.setItemCount(ORE, 3); c.advance(1, 5)
    t.ok(attr(c, "spell") ~= "Smelting", "no forge learned")
end

local function gear(c)
    c.setItem(HEAD, { kind = "INVTYPE_HEAD", stats = { [STR] = 4 }, unmet = {} })
    c.setItem(BETTER, { kind = "INVTYPE_HEAD", stats = { [STR] = 9 }, unmet = {} })
    c.setWorn(1, HEAD)
    c.setBagItems({ { item = BETTER, count = 1 } })
end

tests["key actions: a better item in the bags: the key equips it, out of a fight only"] = function(t)
    local c, addon = start()
    gear(c); c.advance(1, 5)
    t.eq(attr(c, "type"), "item")
    t.eq(attr(c, "item"), "item:4321")
    set(c, addon, UPGRADE, false)
    t.ok(attr(c, "item") ~= "item:4321", "row off")
    set(c, addon, UPGRADE, true)
    t.eq(attr(c, "item"), "item:4321", "on again")
    c.setCombat(true); c.advance(1, 5)
    local s = suggested(addon)
    t.ok(not (type(s) == "table" and s.itemId == 4321), "in a fight: not suggested")
    nothingWritten(t, c)
end

-- Section 448 (F5): the Flow button holds the same key (FB.SETTING is
-- K.SETTING), so the same equip-upgrade item that reaches the RotationKey
-- button also reaches it; its tooltip must read the item's name, not the
-- raw secure-attribute text the button is actually set with ("item:4321").
tests["key actions: a better item in the bags: the Flow button's tooltip names it, not the raw item text"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no FlowButton module"); return end
    local c, addon = start()
    gear(c)
    local info = {}
    for id, row in pairs(INFO) do info[id] = row end
    info[4321] = { name = "Reinforced Circlet" }
    c.setItemInfo(info); c.advance(1, 5)
    t.eq(attr(c, "item"), "item:4321", "the key still casts by the raw item text")
    local line = tip(c, FLOW)
    t.ok(type(line) == "string" and line:find("Reinforced Circlet", 1, true) ~= nil,
        "the tooltip names the item: " .. tostring(line))
    t.ok(type(line) == "string" and line:find("item:4321", 1, true) == nil,
        "never the raw item text: " .. tostring(line))
end

-- Section 454: the item's name not loaded yet: a plain line, never the token.
tests["key actions: the Flow button's item name not loaded yet: a plain line, not the raw item text"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no FlowButton module"); return end
    local c = start()
    gear(c)
    local info = {}
    for id, row in pairs(INFO) do info[id] = row end
    info[4321] = { name = "" }
    c.setItemInfo(info); c.advance(1, 5)
    t.eq(attr(c, "item"), "item:4321", "the key still casts by the raw item text")
    local line = tip(c, FLOW)
    t.ok(type(line) == "string" and line:find(FB.ITEM_PENDING or "Item not loaded yet.", 1, true) ~= nil,
        "the tooltip says the item is not loaded yet: " .. tostring(line))
    t.ok(type(line) == "string" and line:find("item:4321", 1, true) == nil,
        "never the raw item text: " .. tostring(line))
end

tests["key actions: the key's actions row off: none of these is put on the key"] = function(t)
    local c, addon = start()
    gear(c)
    set(c, addon, ACTIONS, false)
    t.ok(attr(c, "item") ~= "item:4321", "off")
    set(c, addon, ACTIONS, true)
    t.eq(attr(c, "item"), "item:4321", "on")
end

return tests
