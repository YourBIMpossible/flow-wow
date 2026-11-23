local _, ns = ...
-- Lead section 197. The Mage rotation end to end, on the whole add-on
-- loaded on a fake client, the PaladinRotation.lua pattern: the setting ->
-- the client's reads -> the chooser -> the icon the player sees and the
-- line the diag word gives. Then gear: what a mage cannot use is not
-- offered, what it can is scored. Offline: the reads are the fake client's,
-- not the game's; the spell ids are made up.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Frost Armor"] = 9001, ["Arcane Intellect"] = 9002, ["Conjure Water"] = 9003, ["Conjure Food"] = 9004,
    ["Frostbolt"] = 9005, ["Fireball"] = 9006, ["Fire Blast"] = 9007, ["Shoot"] = 9008,
}
local ARMOR = { ["Frost Armor"] = true }
local BUFFED = { ["Frost Armor"] = true, ["Arcane Intellect"] = 900 }
local ENEMY = { exists = true, hostile = true, dead = false }
local WATER, FOOD = "Conjured Water", "Conjured Muffin"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("MAGE"); c.setFaction("Horde"); c.setLevel(10)
    if not opts.deadUnknown then c.setDead(false) end
    for name, id in pairs(IDS) do
        if not (opts.unlearned and opts.unlearned[name]) then
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = true })
            c.setSpellCooldown(id, false)
        end
        c.setSpellTexture(id, "tex:" .. name)
    end
    if not opts.noCounts then
        c.setItemCount(WATER, opts.water or 20)
        c.setItemCount(FOOD, opts.food or 20)
    end
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

-- Buffed, an enemy targeted and in range of every spell, in a fight.
local function fighting(c)
    c.setPlayerBuffs(BUFFED); c.setTarget(ENEMY); c.setStealthed(false)
    for _, name in ipairs({ "Frostbolt", "Fireball", "Fire Blast", "Shoot" }) do c.setInRange(IDS[name], true) end
    c.setCurrentSpell(IDS["Shoot"], false); c.setCombat(true)
    c.advance(1, 5)
end

tests["mage: the pack is registered and passes the contract"] = function(t)
    local ok, problems = ns.PackCheck(ns.Packs.MAGE)
    t.ok(ok, table.concat(problems or {}, "; "))
end

tests["mage: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Frost Armor", "no armor on: the armor first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["mage: armor, then intellect, then water and food when out, then the fight"] = function(t)
    local c, addon, icon = start({ water = 0, food = 0 })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Frost Armor")
    c.setPlayerBuffs(ARMOR); c.advance(1, 5)
    t.eq(icon.texture, "tex:Arcane Intellect", "armor up: the intellect")
    c.setPlayerBuffs(BUFFED); c.advance(1, 5)
    t.eq(icon.texture, "tex:Conjure Water", "no water in the bags")
    c.setItemCount(WATER, 20); c.advance(1, 5)
    t.eq(icon.texture, "tex:Conjure Food", "water made: the food")
    c.setItemCount(FOOD, 20); c.advance(1, 5)
    t.eq(icon.shown, false, "all done, no enemy: nothing")
    fighting(c)
    t.eq(icon.texture, "tex:Fire Blast", "in a fight: the instant first")
    t.ok(said(c):find("suggesting Fire Blast", 1, true), said(c))
    c.setSpellCooldown(IDS["Fire Blast"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Frostbolt", "Fire Blast on cooldown: Frostbolt")
end

tests["mage: no water asked for in a fight"] = function(t)
    local c, addon, icon = start({ water = 0 })
    on(c, addon); fighting(c)
    t.ok(not (icon.shown and icon.texture == "tex:Conjure Water"), "a fight: no conjuring")
end

tests["mage: reads not given say what is missing, and show nothing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Frost Armor", "the read arrived")
    c.setPlayerBuffs(nil); c.advance(1, 5)
    t.eq(icon.shown, false, "buffs not read: no buff suggested")
end

tests["mage: bag counts not read: no conjuring, and the diag word says so"] = function(t)
    local c, addon, icon = start({ noCounts = true })
    c.setPlayerBuffs(BUFFED); on(c, addon)
    t.ok(not (icon.shown and (icon.texture == "tex:Conjure Water" or icon.texture == "tex:Conjure Food")),
        "not known how many: not asked for")
    t.ok(said(c):find(ns.Diag.READ_WORDS.conjured, 1, true), said(c))
end

tests["mage: out of mana, the wand; a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Frostbolt"] = true } })
    on(c, addon); fighting(c)
    c.setSpellCooldown(IDS["Fire Blast"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Fireball", "no Frostbolt learned: Fireball")
    c.setSpell(IDS["Fireball"], { known = true, usable = false, noPower = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shoot", "no mana for it: the wand")
    c.setCurrentSpell(IDS["Shoot"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Shoot"), "already shooting: not pressed again")
end

tests["mage: cooldown and range"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    c.setSpellCooldown(IDS["Fire Blast"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Frostbolt")
    c.setInRange(IDS["Frostbolt"], false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
    c.setSpellCooldown(IDS["Fire Blast"], false); c.setInRange(IDS["Frostbolt"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Fire Blast", "ready again")
end

tests["mage: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    local function attacking()
        return icon.shown and (icon.texture == "tex:Fire Blast" or icon.texture == "tex:Frostbolt"
            or icon.texture == "tex:Shoot")
    end
    t.ok(attacking(), "attacking first")
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not attacking(), "dead target: no attack, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not attacking(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["mage: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Frost Armor")
end

-- Gear ------------------------------------------------------------------------

local CLOTH, PLATE = "item:9101", "item:9102"
local INT = "ITEM_MOD_INTELLECT_SHORT"

local function texts(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do out[#out + 1] = tostring(l.text) end
    return table.concat(out, " / ")
end

tests["mage gear: plate is not offered; cloth with intellect is scored"] = function(t)
    local c = start()
    -- Cloth: the game marks nothing unmet. Plate: the marks not read, so the
    -- pack's own table answers (its no still shows).
    c.setItem(CLOTH, { kind = "INVTYPE_CHEST", stats = { [INT] = 5 }, classID = 4, subclassID = 1, minLevel = 1,
        unmet = {} })
    c.setItem(PLATE, { kind = "INVTYPE_CHEST", stats = { [INT] = 50 }, classID = 4, subclassID = 4, minLevel = 1 })
    c.setWorn(5, false)
    local plate = texts(c.showItemTooltip(PLATE))
    t.ok(plate:find("Can't use", 1, true) ~= nil, "plate: can't use: " .. plate)
    t.ok(not plate:find("Upgrade", 1, true), "plate: no upgrade offered: " .. plate)
    local cloth = texts(c.showItemTooltip(CLOTH))
    t.ok(cloth:find("Upgrade", 1, true) ~= nil and cloth:find("dps", 1, true) ~= nil, "cloth: scored: " .. cloth)
end

return tests
