local _, ns = ...
-- Section 197. The Priest rotation end to end, the same shape as
-- PaladinRotation.lua: the whole add-on loaded on a fake client, the
-- setting -> the client's reads -> the chooser -> the icon the player sees
-- and the line the diag word gives. Each test changes what the client
-- answers and looks at the icon and the words. Offline: the reads are the
-- fake client's, not the game's. Spell ids are plausible, not read here.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Shadow Word: Pain"] = 589,
    ["Mind Blast"] = 8092, ["Smite"] = 585, ["Shoot"] = 5019,
    ["Lesser Heal"] = 2050, ["Renew"] = 139,
}
local FORT = { ["Power Word: Fortitude"] = true }
local BUFFED = { ["Power Word: Fortitude"] = true, ["Inner Fire"] = true }
local PAIN = { ["Shadow Word: Pain"] = true }
local ENEMY = { exists = true, hostile = true, dead = false }
local RANGED = { "Shadow Word: Pain", "Mind Blast", "Smite", "Shoot" }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(10)
    if not opts.deadUnknown then c.setDead(false) end
    c.setCombat(false)
    c.setFormName(nil, true)
    for name, id in pairs(IDS) do
        if not (opts.unlearned and opts.unlearned[name]) then
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = true })
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

local function inRange(c, yes)
    for _, name in ipairs(RANGED) do c.setInRange(IDS[name], yes) end
end

-- A priest with both buffs up, an enemy targeted, every read given, and
-- Shadow Word: Pain not on it yet.
local function fighting(c)
    c.setPlayerBuffs(BUFFED); c.setTarget(ENEMY); c.setTargetDebuffs({}); c.setStealthed(false)
    inRange(c, true)
    c.setCurrentSpell(IDS["Shoot"], false); c.setCombat(true)
    c.advance(1, 5)
end

local function showing(icon, name) return icon.shown == true and icon.texture == "tex:" .. name end

tests["priest: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Power Word: Fortitude", "no buff up, out of a fight: Fortitude first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["priest: Fortitude, Inner Fire, then Pain, Mind Blast, Smite as the reads change"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Power Word: Fortitude")
    c.setPlayerBuffs(FORT); c.advance(1, 5)
    t.eq(icon.texture, "tex:Inner Fire", "Fortitude up: Inner Fire")
    c.setPlayerBuffs(BUFFED); c.setTarget(ENEMY); inRange(c, true)
    c.setCurrentSpell(IDS["Shoot"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Shadow Word: Pain", "an enemy, your Pain not on it")
    c.setTargetDebuffs(PAIN); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mind Blast", "Pain on the target: Mind Blast")
    t.ok(said(c):find("suggesting Mind Blast", 1, true), said(c))
    c.setSpellCooldown(IDS["Mind Blast"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Smite", "Mind Blast on cooldown: Smite")
    -- The wand already shooting: Smite is not asked for over it.
    c.setCurrentSpell(IDS["Shoot"], true); c.advance(1, 5)
    t.ok(not showing(icon, "Smite"), "wand shooting: not Smite, got " .. tostring(icon.texture))
    t.ok(not showing(icon, "Shoot"), "wand shooting: not Shoot again")
end

tests["priest: reads not given yet say what is missing, and show nothing that needs them"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.shown, true, "the read arrived: shown")
    t.eq(icon.texture, "tex:Power Word: Fortitude")
    -- Your debuffs on the target not read: Pain is passed by, and diag says why.
    c.setPlayerBuffs(BUFFED); c.setTarget(ENEMY); c.setTargetDebuffs(nil); inRange(c, true)
    c.setCurrentSpell(IDS["Shoot"], false); c.advance(1, 5)
    t.ok(not showing(icon, "Shadow Word: Pain"), "debuffs not read: no Pain")
    t.eq(icon.texture, "tex:Mind Blast")
    t.ok(said(c):find("your debuffs on the target", 1, true), "names the read: " .. said(c))
    -- Buffs that cannot be read: no buff is asked for.
    c.setTarget({ exists = false }); c.setPlayerBuffs(nil); c.advance(1, 5)
    t.ok(not showing(icon, "Power Word: Fortitude") and not showing(icon, "Inner Fire"),
        "buffs not read: no buff suggested")
end

tests["priest: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Power Word: Fortitude"] = true, ["Mind Blast"] = true } })
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.ok(not showing(icon, "Power Word: Fortitude"), "no Fortitude learned: not asked for")
    t.eq(icon.texture, "tex:Inner Fire")
    fighting(c); c.setTargetDebuffs(PAIN); c.advance(1, 5)
    t.ok(not showing(icon, "Mind Blast"), "Mind Blast not learned")
    t.eq(icon.texture, "tex:Smite")
end

tests["priest: cooldown is passed by and comes back; out of range is said"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c); c.setTargetDebuffs(PAIN); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mind Blast")
    c.setSpellCooldown(IDS["Mind Blast"], true); c.advance(1, 5)
    t.ok(not showing(icon, "Mind Blast"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Mind Blast"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mind Blast", "ready again")
    inRange(c, false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
end

tests["priest: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Shadow Word: Pain")
    local function attacking()
        for _, name in ipairs(RANGED) do if showing(icon, name) then return true end end
        return false
    end
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not attacking(), "dead target: no attack, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not attacking(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["priest: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.setTargetDebuffs({}); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Power Word: Fortitude")
end

-- Gear, through the same verdict the tooltip uses, with the Priest pack.
local INT = "ITEM_MOD_INTELLECT_SHORT"
local HELM = "item:1"
local function gear(more)
    local c = ns.make.fakeClient()
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [INT] = 4 } })
    c.setWorn(1, false)
    local g = c.gear(HELM)
    for key, value in pairs(more or {}) do g[key] = value end
    return g
end

tests["priest: gear the class cannot use is not offered; cloth it can use is scored"] = function(t)
    local who = { pack = ns.Packs.PRIEST, role = "dps", level = 10 }
    -- Plate (4/4) and a sword (2/7): not in the class table, the game's marks not read.
    for _, kind in ipairs({ { 4, 4 }, { 2, 7 } }) do
        local lines = ns.GearVerdict.Lines(gear({ classID = kind[1], subclassID = kind[2], minLevel = 1 }), who)
        t.eq(lines, { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } },
            "not offered: " .. kind[1] .. "/" .. kind[2])
    end
    -- Cloth (4/1), Intellect on it: in the table, scored with the dps weights.
    local lines, detail = ns.GearVerdict.Lines(gear({ classID = 4, subclassID = 1, minLevel = 1 }), who)
    t.eq(lines[1] and lines[1].tone, "good", "cloth is an upgrade: " .. tostring(lines[1] and lines[1].text))
    t.ok(tostring(lines[1] and lines[1].text):find("Upgrade for your head piece", 1, true), tostring(lines[1] and lines[1].text))
    t.eq(detail.result.verdict, "upgrade", "scored")
end

return tests
