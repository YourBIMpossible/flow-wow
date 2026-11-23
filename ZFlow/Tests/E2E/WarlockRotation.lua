local _, ns = ...
-- Lead sections 197 and 206. The Warlock rotation end to end, the shape of
-- PaladinRotation.lua and HunterRotation.lua: the whole add-on loaded on a
-- fake client, the setting -> the client's reads (the pet's among them,
-- the accepted pet contract) -> the chooser -> the icon the player sees and
-- the line the diag word gives; then the gear line on an item's tooltip.
-- Offline: the reads are the fake client's, not the game's. Spell ids are
-- made up.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Demon Skin"] = 9201, ["Summon Imp"] = 9202, ["Summon Voidwalker"] = 9203, ["Curse of Agony"] = 9204,
    ["Corruption"] = 9205, ["Immolate"] = 9206, ["Shadow Bolt"] = 9207, ["Shoot"] = 9208,
}
local TARGETED = { "Curse of Agony", "Corruption", "Immolate", "Shadow Bolt", "Shoot" }
local SKIN = { ["Demon Skin"] = true }
local DOTTED = { ["Curse of Agony"] = true, ["Corruption"] = true, ["Immolate"] = true }
local VOID = { exists = true, dead = false, inCombat = false, family = "Voidwalker" }
local ENEMY = { exists = true, hostile = true, dead = false }
local INT = "ITEM_MOD_INTELLECT_SHORT"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("WARLOCK"); c.setFaction("Horde"); c.setLevel(opts.level or 12)
    if not opts.deadUnknown then c.setDead(false) end
    for name, id in pairs(IDS) do
        if not (opts.unlearned and opts.unlearned[name]) then
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = true })
            c.setSpellCooldown(id, false)
        end
        c.setSpellTexture(id, "tex:" .. name)
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

-- Out of a fight, armor up, no target; the pet as given.
local function idle(c, pet)
    c.setPlayerBuffs(SKIN); c.setPet(pet); c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(1, 5)
end

-- In a fight on an enemy in range of every spell, the debuffs as given.
local function fighting(c, debuffs)
    c.setPlayerBuffs(SKIN); c.setPet(VOID); c.setTarget(ENEMY); c.setTargetDebuffs(debuffs or {})
    for _, name in ipairs(TARGETED) do c.setInRange(IDS[name], true) end
    c.setCurrentSpell(IDS["Shoot"], false); c.setCombat(true)
    c.advance(1, 5)
end

tests["warlock: the pack is registered and passes the contract"] = function(t)
    local ok, problems = ns.PackCheck(ns.Packs.WARLOCK)
    t.ok(ok, table.concat(problems or {}, "; "))
end

tests["warlock: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setPet(VOID); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Demon Skin", "no armor on: the armor first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["warlock: armor, then the curse, corruption, immolate, the bolt, the wand"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setPet(VOID); on(c, addon)
    t.eq(icon.texture, "tex:Demon Skin")
    idle(c, VOID)
    t.eq(icon.shown, false, "armor up, pet out, no enemy: nothing")
    fighting(c, {})
    t.eq(icon.texture, "tex:Curse of Agony", "nothing on the target: the curse first")
    c.setTargetDebuffs({ ["Curse of Agony"] = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Corruption")
    c.setTargetDebuffs({ ["Curse of Agony"] = true, ["Corruption"] = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Immolate")
    c.setTargetDebuffs(DOTTED); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shadow Bolt", "all three on: the bolt")
    t.ok(said(c):find("suggesting Shadow Bolt", 1, true), said(c))
    c.setSpell(IDS["Shadow Bolt"], { known = true, usable = false, noPower = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shoot", "no mana for the bolt: the wand")
    c.setCurrentSpell(IDS["Shoot"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Shoot"), "already shooting: not pressed again")
end

tests["warlock: no pet out asks to summon the voidwalker, a dead one too, out of a fight only"] = function(t)
    local c, addon, icon = start()
    on(c, addon); idle(c, { exists = false })
    t.eq(icon.texture, "tex:Summon Voidwalker", "no pet: summon it")
    c.setPet({ exists = true, dead = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Summon Voidwalker", "a dead pet: summon again")
    c.setPet({ exists = false }); c.setCombat(true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Summon Voidwalker"), "in a fight: no summoning")
end

tests["warlock: with no voidwalker learned, the imp"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Summon Voidwalker"] = true } })
    on(c, addon); idle(c, { exists = false })
    t.eq(icon.texture, "tex:Summon Imp")
end

tests["warlock: the pet not read: nothing about it, and the diag names the read"] = function(t)
    local c, addon, icon = start()
    on(c, addon); idle(c, nil)
    t.eq(icon.shown, false, "pet not read: nothing asked for")
    local line = said(c)
    t.ok(line:find("your pet", 1, true), line)
    c.setPet({ exists = false }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Summon Voidwalker", "read now, and none out")
end

tests["warlock: target debuffs not read: no curse or corruption asked for"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c, {})
    c.setTargetDebuffs(nil); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shadow Bolt", "not known what is on it: the bolt, not a dot")
    t.ok(said(c):find("your debuffs on the target", 1, true), said(c))
end

tests["warlock: reads not given say what is missing, and show nothing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); c.setPet(VOID); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Demon Skin", "the read arrived")
    c.setPlayerBuffs(nil); c.advance(1, 5)
    t.eq(icon.shown, false, "buffs not read: no armor suggested")
end

tests["warlock: cooldown and range"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c, DOTTED)
    t.eq(icon.texture, "tex:Shadow Bolt")
    c.setInRange(IDS["Shadow Bolt"], false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
    c.setInRange(IDS["Shadow Bolt"], true); c.setSpellCooldown(IDS["Shadow Bolt"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Shadow Bolt"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Shadow Bolt"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shadow Bolt", "ready again")
end

tests["warlock: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Curse of Agony"] = true } })
    on(c, addon); fighting(c, {})
    t.eq(icon.texture, "tex:Corruption", "no curse learned: corruption first")
end

tests["warlock: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c, DOTTED)
    local function attacking()
        return icon.shown and (icon.texture == "tex:Shadow Bolt" or icon.texture == "tex:Shoot"
            or icon.texture == "tex:Corruption" or icon.texture == "tex:Immolate" or icon.texture == "tex:Curse of Agony")
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

tests["warlock: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.setPet(VOID); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Demon Skin")
end

-- Gear ------------------------------------------------------------------------

local VERDICT = { "Can't use: ", "No verdict: ", "Upgrade for ", "Same as ", "Not an upgrade for " }
local function texts(added)
    local out = {}
    for i = 1, #added do
        local text = tostring(added[i].text)
        for _, head in ipairs(VERDICT) do
            if text:sub(1, #head) == head then
                out[#out + 1] = text
                break
            end
        end
    end
    return out
end

tests["warlock gear: plate refused, cloth with intellect scored"] = function(t)
    local c = start()
    c.setWorn(5, false)
    c.setItem("item:plate", { kind = "INVTYPE_CHEST", stats = { [INT] = 10 }, classID = 4, subclassID = 4, minLevel = 10 })
    c.setItem("item:cloth", { kind = "INVTYPE_CHEST", stats = { [INT] = 5 }, classID = 4, subclassID = 1,
        minLevel = 10, unmet = {} })
    t.eq(texts(c.showItemTooltip("item:plate")),
        { "Can't use: your class cannot use this kind of item (first guess)" }, "plate: never")
    local cloth = texts(c.showItemTooltip("item:cloth"))
    t.eq(#cloth, 1)
    t.ok(cloth[1] ~= nil and cloth[1]:find("Upgrade for your chest", 1, true) == 1 and cloth[1]:find("dps", 1, true),
        "cloth: scored: " .. tostring(cloth[1]))
end

return tests
