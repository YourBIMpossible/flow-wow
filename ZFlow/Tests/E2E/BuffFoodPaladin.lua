local _, ns = ...
-- Lead section 236 (on section 235 item 4): Well Fed food on the whole
-- add-on, loaded on a fake client, entered the way the player gets there:
-- a paladin out of a fight, buffs up, no target, the rotation switched on.
-- The icon and the diag word show the best Well Fed food for the role, the
-- fishing food only with a fishing pole equipped. Cases: data arriving late
-- and in parts, a reload (the food setting read back), and a read that fails
-- then recovers. Made-up items and tooltip lines; not tested in game.
--
-- Late data: the fake fires GET_ITEM_INFO_RECEIVED as the game does when
-- item data arrives (lead section 238); the driver drops what it kept on
-- that event, and an answer read in part was not kept anyway.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }

local STRF, STAF, LURE = 9005, 9006, 9007
local LINES = {
    [STRF] = { "Strength Stew", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Strength for 15 min." },
    [STAF] = { "Stamina Stew", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Stamina for 15 min." },
    [LURE] = { "Angler Bites", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Fishing skill for 15 min." },
}
local INFO = {
    [STRF] = { name = "Strength Stew", classID = 0, subclassID = 5 },
    [STAF] = { name = "Stamina Stew", classID = 0, subclassID = 5 },
    [LURE] = { name = "Angler Bites", classID = 0, subclassID = 5 },
}
local TEX = { [STRF] = "tex:Strength Stew", [STAF] = "tex:Stamina Stew", [LURE] = "tex:Angler Bites" }

-- opts.account / opts.char: saved tables (a reload); opts.lines false: no
-- tooltip lines read yet; opts.info: the item info the client gives.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setBagItems({ { item = STAF, count = 2 }, { item = STRF, count = 2 }, { item = LURE, count = 2 } })
    c.setItemInfo(opts.info or INFO)
    if opts.lines ~= false then
        for id, lines in pairs(LINES) do c.setItemLines(id, lines) end
    end
    for id, tex in pairs(TEX) do c.setItemTexture(id, tex) end
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
    local ok, why = addon.settings:set(D.SETTING, true)
    c.advance(1, 5)
    return ok, why
end

-- The rotation lines the diag word prints now.
local function said(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("rotation:", 1, true) then out[#out + 1] = line end
    end
    return table.concat(out, " / ")
end

-- A food on the icon now (any of the three).
local function foodShown(icon)
    return icon.shown == true and (icon.texture == TEX[STRF] or icon.texture == TEX[STAF]
        or icon.texture == TEX[LURE])
end

tests["paladin food: the best Well Fed food for a dps, the fishing food with a pole"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    on(c, addon)
    t.eq(icon.shown, true, "buffs up, no target, out of a fight: the food")
    t.eq(icon.texture, "tex:Strength Stew", "a dps paladin values Strength over Stamina")
    t.ok(said(c):find("suggesting Strength Stew", 1, true), said(c))
    c.setFishingPole(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Angler Bites", "a fishing pole equipped: the fishing food")
    c.setFishingPole(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Strength Stew", "the pole put away: the fight food again")
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Might"] = 200,
        ["Seal of Righteousness"] = 25, [ns.BuffFood.WELL_FED] = true })
    c.advance(1, 5)
    t.ok(not foodShown(icon), "Well Fed on: no food")
end

tests["paladin food: item data arriving late and in parts"] = function(t)
    local c, addon, icon = start({ info = {}, lines = false })
    on(c, addon)
    t.ok(not foodShown(icon), "nothing read yet: no food")
    -- Part of it: the Stamina Stew read, the Strength Stew not yet.
    c.setItemInfo({ [STAF] = INFO[STAF] }); c.setItemLines(STAF, LINES[STAF]); c.advance(1, 5)
    t.eq(icon.texture, "tex:Stamina Stew", "the one food read")
    -- The rest arrives with no bag change.
    c.setItemInfo(INFO)
    for id, lines in pairs(LINES) do c.setItemLines(id, lines) end
    c.fire("GET_ITEM_INFO_RECEIVED")
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Strength Stew", "the late food is read: the better one")
end

tests["paladin food: the food setting is read back after a reload"] = function(t)
    local c, addon, icon = start()
    on(c, addon)
    t.eq(icon.texture, "tex:Strength Stew")
    addon.settings:set(D.FOOD, false); c.advance(1, 5)
    t.ok(not foodShown(icon), "switched off: no food")
    local c2, addon2, icon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.advance(1, 5)
    t.eq(addon2.settings:get(D.FOOD), false, "the setting read back")
    t.eq(addon2.settings:get(D.SETTING), true, "the rotation still on")
    t.ok(not foodShown(icon2), "after the reload: still no food")
    addon2.settings:set(D.FOOD, true); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Strength Stew", "switched on again: the food")
end

tests["paladin food: a read that fails, then recovers"] = function(t)
    local c, addon, icon = start()
    local lines = c.itemLines
    c.itemLines = function() error("tooltip read failed") end
    on(c, addon)
    t.ok(not foodShown(icon), "lines not read: no food")
    c.itemLines = lines; c.advance(1, 5)
    t.eq(icon.texture, "tex:Strength Stew", "the read recovers: the food")
    -- The pole read fails: not known, so no fishing food.
    c.fishingPole = function() error("pole read failed") end
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Strength Stew", "pole not known: the fight food")
    c.fishingPole = function() return true end
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Angler Bites", "the pole read recovers: the fishing food")
end

return tests
