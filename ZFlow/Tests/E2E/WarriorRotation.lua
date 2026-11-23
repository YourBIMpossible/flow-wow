local _, ns = ...
-- Lead section 197. The Warrior rotation end to end, on the whole add-on
-- loaded on a fake client: the setting -> the client's reads (the stance as
-- the form name) -> the chooser -> the icon the player sees and the line
-- the diag word gives. Plus gear: what a warrior cannot use is not offered,
-- what it can use is scored. Each test changes what the client answers and
-- looks at the icon and the words. Offline: the reads are the fake
-- client's, not the game's. The spell ids are made up for the test.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Battle Stance"] = 2457, ["Defensive Stance"] = 71, ["Battle Shout"] = 6673, ["Attack"] = 6603,
    ["Charge"] = 100, ["Rend"] = 772, ["Heroic Strike"] = 78, ["Execute"] = 5308,
    ["Overpower"] = 7384, ["Revenge"] = 6572, ["Sunder Armor"] = 7386,
}
-- The game says these can be used only after something happens (a dodge, a
-- block, the enemy nearly dead): they start as not usable.
local REACTIVE = { ["Execute"] = true, ["Overpower"] = true, ["Revenge"] = true }
-- The spells cast on the target: their range is read.
local AIMED = { "Attack", "Charge", "Rend", "Heroic Strike", "Execute", "Overpower", "Revenge", "Sunder Armor" }
local SHOUT = { ["Battle Shout"] = 100 }
local ENEMY = { exists = true, hostile = true, dead = false }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(10)
    if not opts.deadUnknown then c.setDead(false) end
    for name, id in pairs(IDS) do
        if not (opts.unlearned and opts.unlearned[name]) then
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = not REACTIVE[name] })
            c.setSpellCooldown(id, false)
        end
        if not (opts.noTexture and opts.noTexture[name]) then c.setSpellTexture(id, "tex:" .. name) end
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

local function on(c, addon, role)
    if role then addon.settings:set(D.ROLE, role) end
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

local function inRange(c, yes)
    for _, name in ipairs(AIMED) do c.setInRange(IDS[name], yes) end
end

-- A warrior in Battle Stance with the shout up, in a fight with an enemy
-- targeted, already swinging, Rend on it, Heroic Strike not queued, every
-- read given and everything in range.
local function fighting(c)
    c.setFormName("Battle Stance", true); c.setPlayerBuffs(SHOUT)
    c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(true)
    c.setTargetDebuffs({ Rend = 15 })
    c.setCurrentSpell(IDS["Attack"], true); c.setCurrentSpell(IDS["Heroic Strike"], false)
    inRange(c, true)
    c.advance(1, 5)
end

tests["warrior: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setFormName(nil, true); c.setPlayerBuffs({}); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Battle Stance", "in no stance: the stance first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["warrior: stance, shout, charge, attack, rend, then heroic strike"] = function(t)
    local c, addon, icon = start()
    c.setFormName(nil, true); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Battle Stance")
    c.setFormName("Battle Stance", true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Battle Shout", "in the stance: the shout")
    c.setPlayerBuffs(SHOUT); c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(false)
    inRange(c, true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Charge", "an enemy targeted, out of a fight: charge")
    c.setCombat(true); c.setCurrentSpell(IDS["Attack"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Attack", "in the fight, not swinging yet")
    c.setCurrentSpell(IDS["Attack"], true); c.setTargetDebuffs({}); c.advance(1, 5)
    t.eq(icon.texture, "tex:Rend", "swinging, no Rend on it")
    c.setTargetDebuffs({ Rend = 15 }); c.setCurrentSpell(IDS["Heroic Strike"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Heroic Strike", "Rend on, the next swing free")
    t.ok(said(c):find("suggesting Heroic Strike", 1, true), said(c))
    c.setCurrentSpell(IDS["Heroic Strike"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Heroic Strike"), "already queued: not asked again")
end

tests["warrior: Execute and Overpower only when the game says they can be used"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Heroic Strike", "neither usable: not shown")
    c.setSpell(IDS["Overpower"], { known = true, usable = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Overpower", "the game allows Overpower")
    c.setSpell(IDS["Execute"], { known = true, usable = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Execute", "the game allows Execute: before Overpower")
    c.setSpell(IDS["Execute"], { known = true }); c.setSpell(IDS["Overpower"], { known = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Heroic Strike", "usable not read: not a yes")
end

tests["warrior: a tank is asked for Defensive Stance, then Revenge, then Sunder Armor"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "tank"); fighting(c)
    t.eq(icon.texture, "tex:Defensive Stance", "tanking in Battle Stance: the tank stance")
    c.setFormName("Defensive Stance", true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sunder Armor", "Revenge not usable: sunder")
    c.setSpell(IDS["Revenge"], { known = true, usable = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Revenge", "the game allows Revenge")
    c.setSpell(IDS["Overpower"], { known = true, usable = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Revenge", "Overpower needs Battle Stance: not asked in Defensive")
end

tests["warrior: reads not given yet say what is missing, and show nothing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setFormName(nil, true); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.shown, true, "the read arrived: shown")
    t.eq(icon.texture, "tex:Battle Stance")
    -- The stance not read: no stance is asked for; the shout still is.
    c.setFormName(nil, false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Battle Shout", "stance not read: not asked to change it")
    -- Buffs that cannot be read either: nothing, and the words say which.
    c.setPlayerBuffs(nil); c.advance(1, 5)
    t.eq(icon.shown, false, "buffs not read: no buff suggested")
    local line = said(c)
    t.ok(line:find("which form you are in", 1, true), line)
    t.ok(line:find("your buffs", 1, true), line)
    -- Debuffs on the target not read: Rend is not asked for.
    fighting(c); c.setTargetDebuffs(nil); c.setCurrentSpell(IDS["Heroic Strike"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Rend"), "debuffs not read: no Rend")
end

tests["warrior: range not read is the reason given, not that nothing is out of range"] = function(t)
    local c, addon, icon = start()
    c.setFormName("Battle Stance", true); c.setPlayerBuffs(SHOUT); c.setTarget(ENEMY)
    c.setStealthed(false); c.setCombat(true); c.setTargetDebuffs({})
    c.setCurrentSpell(IDS["Attack"], true); on(c, addon)
    t.eq(icon.shown, false, "range not known: nothing suggested")
    local line = said(c)
    t.ok(line:find("not known whether it is in range", 1, true), line)
    t.ok(line:find("Rend", 1, true), "names the spell: " .. line)
    t.ok(not line:find("(nothing out of range)", 1, true), line)
    c.setInRange(IDS["Rend"], true); c.advance(1, 5)
    t.eq(icon.shown, true, "the range arrived")
    t.eq(icon.texture, "tex:Rend")
end

tests["warrior: Overpower on cooldown is passed by, and comes back when ready"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    c.setSpell(IDS["Overpower"], { known = true, usable = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Overpower")
    c.setSpellCooldown(IDS["Overpower"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Overpower"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Overpower"], false); c.advance(1, 5)
    t.eq(icon.shown, true, "ready again")
    t.eq(icon.texture, "tex:Overpower")
    -- Out of range: still the spell to get to, and the words say it is out of range.
    inRange(c, false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
end

tests["warrior: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Battle Shout"] = true, ["Rend"] = true, ["Charge"] = true } })
    c.setFormName("Battle Stance", true); c.setPlayerBuffs({}); on(c, addon)
    t.ok(not (icon.shown and icon.texture == "tex:Battle Shout"), "no shout learned: not asked for")
    c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(false); inRange(c, true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Charge"), "Charge not learned")
    fighting(c); c.setTargetDebuffs({}); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Rend"), "Rend not learned")
end

tests["warrior: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Heroic Strike")
    local attack = { ["tex:Heroic Strike"] = true, ["tex:Attack"] = true, ["tex:Rend"] = true, ["tex:Charge"] = true }
    local function attacking() return icon.shown and attack[icon.texture] == true end
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not attacking(), "dead target: no attack, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not attacking(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["warrior: no picture for the spell hides the icon, never a blank one"] = function(t)
    local c, addon, icon = start({ noTexture = { ["Battle Stance"] = true } })
    c.setFormName(nil, true); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(said(c):find("suggesting Battle Stance", 1, true), "still explained: " .. said(c))
end

tests["warrior: the switch and the role are kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon, "tank")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    t.eq(addon2.settings:get(D.ROLE), "tank", "the role kept")
    fighting(c2)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Defensive Stance")
end

-- Gear: the add-on's own client, with the item's class, subclass, needed
-- level and what the game marks on it added to the gear read.
local PLATE, WAND = "item:2", "item:7"

local function gearClient()
    local c = start()
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10 } })
    c.setItem(WAND, { kind = "INVTYPE_RANGEDRIGHT", stats = { ITEM_MOD_INTELLECT_SHORT = 5 } })
    c.setWorn(1, false)
    -- Plate helm: the game marks nothing. Wand: the marks not read.
    local types = { [PLATE] = { 4, 4, 1, {} }, [WAND] = { 2, 19, 1, nil } }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        local ty = types[link]
        if ty and type(g) == "table" then
            g.classID, g.subclassID, g.minLevel, g.unmet = ty[1], ty[2], ty[3], ty[4]
        end
        return g
    end
    return c
end

tests["warrior gear: a plate helm is scored, a wand is not offered"] = function(t)
    local c = gearClient()
    local lines = ns.GearTooltipModule.Lines(c, ns.Packs, PLATE)
    t.ok(type(lines) == "table" and #lines >= 1, "the helm has lines")
    for _, line in ipairs(lines or {}) do
        t.eq(line.tone, "good", line.text)
        t.ok(line.text:find("^Upgrade for your head piece %(%+") ~= nil, line.text)
    end
    t.eq(ns.GearTooltipModule.Lines(c, ns.Packs, WAND),
        { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } })
end

-- ------------------------------------- N58 (lead section 241): your stance

-- A stance you cast: the cast event, then a second. The stance row holds a
-- cast 6 s before it is kept (a stance swapped for one ability and back).
local function castId(c, name)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", IDS[name])
    c.advance(1, 5)
end

-- Past the row's 6 s window.
local function waitOut(c)
    c.advance(7, 14)
end

-- The stance kept for the role (dps unless named), or nil.
local function kept(c, key, role)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local own = type(state) == "table" and state.ownCasts or nil
    local mine = type(own) == "table" and own[role or "dps"] or nil
    return type(mine) == "table" and mine[key] or nil
end

-- The stance chosen with the word, or nil.
local function picked(c, key)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local choice = type(state) == "table" and state.ownChoice or nil
    return type(choice) == "table" and choice[key] or nil
end

-- The lines the word prints, as one.
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

-- Gap: before N58 the Warrior pack had no stance row, so a stance you cast
-- was never kept and no stance asked for was ever yours: the kept and
-- icon checks below are red on the old code.
tests["warrior N58: the stance you cast is kept after 6 s and asked for in no stance"] = function(t)
    local c, addon, icon = start()
    c.setFormName("Battle Stance", true); c.setPlayerBuffs({}); on(c, addon)
    castId(c, "Defensive Stance")
    t.eq(kept(c, "stance"), "Defensive Stance", "OC-2: held, and saved at once")
    waitOut(c)
    t.eq(kept(c, "stance"), "Defensive Stance", "past 6 s: kept for the role")
    c.setFormName(nil, true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Defensive Stance", "in no stance: the one you cast, not Battle Stance")
    c.setFormName("Battle Stance", true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Defensive Stance", "dps in a stance: not asked to change it, as before")
end

-- Lead section 248 OC-2 (LOW): a held cast was kept only at the next
-- chosen(), cast or fight end, so a reload inside the 6 s window dropped
-- it. Gap: on the old code the reload check below is red (nothing saved).
tests["warrior OC-2: a stance held over a reload inside the window is kept"] = function(t)
    local c, addon, icon = start()
    c.setFormName(nil, true); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Battle Stance", "nothing kept: Battle Stance")
    castId(c, "Defensive Stance")
    t.eq(icon.texture, "tex:Battle Stance", "inside the window: still the one before it")
    local c2, _, icon2 = reload(c)
    c2.setFormName(nil, true); c2.setPlayerBuffs({}); c2.advance(1, 5)
    t.eq(kept(c2, "stance"), "Defensive Stance", "after the reload: kept")
    t.eq(icon2.texture, "tex:Defensive Stance", "and asked for in no stance")
end

-- Gap: the 6 s window. Without it the Battle Stance cast would be kept at
-- once, replacing Defensive Stance; on the old code nothing is kept at all.
tests["warrior N58: a stance swapped for one ability and back inside 6 s is not kept"] = function(t)
    local c, addon = start()
    c.setFormName("Battle Stance", true); c.setPlayerBuffs({}); on(c, addon)
    castId(c, "Defensive Stance"); waitOut(c)
    t.eq(kept(c, "stance"), "Defensive Stance", "kept first")
    c.setFormName("Defensive Stance", true); c.advance(1, 5)
    castId(c, "Battle Stance")
    c.setFormName("Battle Stance", true); c.advance(1, 5)
    castId(c, "Defensive Stance")
    c.setFormName("Defensive Stance", true)
    waitOut(c)
    t.eq(kept(c, "stance"), "Defensive Stance", "the swap and back: the kept one stays")
    castId(c, "Battle Stance"); waitOut(c)
    t.eq(kept(c, "stance"), "Battle Stance", "a swap left in place: kept after the window")
end

tests["warrior N58: the stance word chooses one; auto clears it; a reload keeps it"] = function(t)
    local c, addon, icon = start()
    c.setFormName(nil, true); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Battle Stance", "nothing chosen: Battle Stance")
    local line = word(c, "stance defensive")
    t.ok(line:find("Defensive Stance", 1, true), line)
    t.eq(picked(c, "stance"), "Defensive Stance")
    t.eq(icon.texture, "tex:Defensive Stance", "the chosen stance")
    local c2, _, icon2 = reload(c)
    c2.setFormName(nil, true); c2.setPlayerBuffs({}); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Defensive Stance", "over a reload")
    line = word(c, "stance auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(picked(c, "stance"), nil, "auto forgets the choice")
    t.eq(icon.texture, "tex:Battle Stance", "auto: Battle Stance again")
end

tests["warrior N58: a tank's kept stance replaces Defensive Stance"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "tank"); fighting(c)
    c.setFormName("Defensive Stance", true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Defensive Stance", "in Defensive, nothing kept: no stance asked")
    castId(c, "Battle Stance")
    c.setFormName("Battle Stance", true)
    waitOut(c)
    t.eq(kept(c, "stance", "tank"), "Battle Stance", "kept for the tank role")
    t.eq(kept(c, "stance"), nil, "not for dps")
    t.ok(icon.texture ~= "tex:Defensive Stance", "in the kept one: Defensive not asked")
    c.setFormName("Defensive Stance", true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Battle Stance", "in Defensive: the kept one asked for")
end

tests["warrior N58: the spell name raising once: not kept; read again: kept"] = function(t)
    local c, addon = start()
    c.setFormName("Battle Stance", true); c.setPlayerBuffs({}); on(c, addon)
    local name = c.spellName
    c.spellName = function() error("made-up failure") end
    castId(c, "Defensive Stance"); waitOut(c)
    t.eq(kept(c, "stance"), nil, "the name could not be read: nothing kept")
    c.spellName = name
    castId(c, "Defensive Stance"); waitOut(c)
    t.eq(kept(c, "stance"), "Defensive Stance", "read again: kept")
end

return tests
