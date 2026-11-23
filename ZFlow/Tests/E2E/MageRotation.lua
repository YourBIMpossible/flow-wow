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
    -- One spell out of range is passed by for the next one in range (lead
    -- fix at the merge: the test asked for "out of range" here; White ran it).
    c.setInRange(IDS["Frostbolt"], false); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Frostbolt"), "out of range: not shown")
    -- Every attack out of range: the words say so.
    for _, name in ipairs({ "Fireball", "Fire Blast", "Shoot" }) do c.setInRange(IDS[name], false) end
    c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
    for _, name in ipairs({ "Frostbolt", "Fireball", "Fire Blast", "Shoot" }) do c.setInRange(IDS[name], true) end
    c.setSpellCooldown(IDS["Fire Blast"], false); c.advance(1, 5)
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

-- ------------------------------------- N58 (lead section 241): your choice

-- The better armors; ids made up.
local ARMOR_IDS = { ["Ice Armor"] = 9020, ["Mage Armor"] = 9021 }

local function learn(c, name)
    local id = ARMOR_IDS[name]
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
end

-- Your own cast went off, then a frame or so.
local function cast(c, name)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", IDS[name] or ARMOR_IDS[name])
    c.advance(1, 5)
end

-- The armor kept for the role (none chosen: dps), or nil.
local function kept(c, key, role)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local own = type(state) == "table" and state.ownCasts or nil
    local mine = type(own) == "table" and own[role or "dps"] or nil
    return type(mine) == "table" and mine[key] or nil
end

-- The armor chosen with the word, or nil.
local function picked(c, key)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local choice = type(state) == "table" and state.ownChoice or nil
    return type(choice) == "table" and choice[key] or nil
end

-- The lines a slash word prints, as one.
local function word(c, text)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, " / ")
end

local function reload(c)
    return start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
end

local NO_ARMOR = { ["Arcane Intellect"] = 900 }

tests["mage N58: the armor you cast is the one asked for, over a reload"] = function(t)
    local c, addon, icon = start()
    learn(c, "Ice Armor")
    c.setPlayerBuffs(NO_ARMOR); on(c, addon)
    t.eq(icon.texture, "tex:Ice Armor", "none cast: the best known, as before")
    cast(c, "Ice Armor")
    t.eq(kept(c, "armor"), nil, "the one asked for: not kept (PC-1)")
    cast(c, "Frost Armor")
    t.eq(kept(c, "armor"), "Frost Armor", "kept for the role")
    t.eq(icon.texture, "tex:Frost Armor", "no armor on: the one you cast")
    c.setPlayerBuffs(BUFFED); c.advance(1, 5)
    t.eq(icon.shown, false, "your armor up: nothing asked for")
    c.setPlayerBuffs(NO_ARMOR); c.setTarget(ENEMY); c.setCombat(true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Frost Armor"), "in a fight: no armor, as before")
    local c2, _, icon2 = reload(c)
    learn(c2, "Ice Armor")
    c2.setPlayerBuffs(NO_ARMOR); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Frost Armor", "over a reload")
end

tests["mage N58: the armor word chooses one; one not known holds the usual; auto"] = function(t)
    local c, addon, icon = start()
    learn(c, "Ice Armor")
    c.setPlayerBuffs(NO_ARMOR); on(c, addon)
    local line = word(c, "armor frost")
    t.ok(line:find("Frost Armor", 1, true), line)
    t.eq(picked(c, "armor"), "Frost Armor")
    t.eq(icon.texture, "tex:Frost Armor", "the chosen armor")
    line = word(c, "armor mage")
    t.ok(line:find("Mage Armor", 1, true), line)
    t.eq(picked(c, "armor"), "Mage Armor")
    t.eq(icon.texture, "tex:Ice Armor", "Mage Armor not known: the best known holds")
    learn(c, "Mage Armor"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mage Armor", "learned: the chosen armor")
    local c2, _, icon2 = reload(c)
    learn(c2, "Ice Armor"); learn(c2, "Mage Armor")
    c2.setPlayerBuffs(NO_ARMOR); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Mage Armor", "the word's choice over a reload")
    word(c, "armor frost")
    line = word(c, "armor auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(picked(c, "armor"), nil, "auto clears the choice")
    t.eq(icon.texture, "tex:Mage Armor", "auto: the best known")
end

tests["mage N58: a read that fails keeps nothing and clears nothing; read again, fine"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(NO_ARMOR); on(c, addon)
    learn(c, "Ice Armor"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Ice Armor")
    local nameRead = c.spellName
    c.spellName = function() error("made-up failure") end
    cast(c, "Frost Armor")
    t.eq(kept(c, "armor"), nil, "the spell name not read: nothing kept")
    c.spellName = nameRead; c.advance(1, 5)
    cast(c, "Frost Armor")
    t.eq(kept(c, "armor"), "Frost Armor", "read again: kept")
    local buffsRead = c.playerBuffs
    c.playerBuffs = function() error("made-up failure") end
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Frost Armor"), "your buffs not read: no armor asked for")
    c.playerBuffs = buffsRead; c.advance(1, 5)
    t.eq(icon.texture, "tex:Frost Armor", "read again: the kept armor")
    t.eq(kept(c, "armor"), "Frost Armor", "the failed read did not clear it")
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

-- ----------------------------- MAGE-5 (P-SELFBUFF, section 236): magic
-- Amplify or Dampen Magic: off until you cast or choose one; then kept up
-- out of a fight, over a reload. Ids made up.
local MAGIC_IDS = { ["Amplify Magic"] = 9030, ["Dampen Magic"] = 9031 }
local ALL_UP = { ["Frost Armor"] = true, ["Arcane Intellect"] = 900 }

local function learnMagic(c)
    for name, id in pairs(MAGIC_IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
end

tests["mage MAGE-5: Amplify Magic: off until cast, then kept up, over a reload"] = function(t)
    local c, addon, icon = start()
    learnMagic(c)
    c.setPlayerBuffs(ALL_UP); on(c, addon)
    t.eq(icon.shown, false, "known, never cast: nothing asked for")
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", MAGIC_IDS["Amplify Magic"]); c.advance(1, 5)
    t.eq(kept(c, "magic"), "Amplify Magic", "kept for the role")
    t.eq(icon.texture, "tex:Amplify Magic", "it ran out: asked for")
    c.setPlayerBuffs({ ["Frost Armor"] = true, ["Arcane Intellect"] = 900, ["Amplify Magic"] = 500 }); c.advance(1, 5)
    t.eq(icon.shown, false, "up: nothing asked for")
    local c2, _, icon2 = reload(c)
    learnMagic(c2)
    c2.setPlayerBuffs(ALL_UP); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Amplify Magic", "over a reload")
    word(c2, "magic dampen")
    t.eq(icon2.texture, "tex:Dampen Magic", "the word chooses Dampen")
end

return tests
