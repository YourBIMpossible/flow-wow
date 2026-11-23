local _, ns = ...
-- Section 197. The Shaman rotation end to end, the same shape as
-- PaladinRotation.lua: the whole add-on loaded on a fake client, the
-- setting -> the client's reads -> the chooser -> the icon the player sees
-- and the line the diag word gives. Each test changes what the client
-- answers and looks at the icon and the words. Offline: the reads are the
-- fake client's, not the game's. Spell ids are plausible, not read here.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Lightning Shield"] = 324, ["Lightning Bolt"] = 403, ["Flame Shock"] = 8050,
    ["Earth Shock"] = 8042, ["Attack"] = 6603, ["Healing Wave"] = 331,
}
local SHIELDED = { ["Lightning Shield"] = true }
local FLAME = { ["Flame Shock"] = true }
local ENEMY = { exists = true, hostile = true, dead = false }
local REACH = { "Lightning Bolt", "Flame Shock", "Earth Shock", "Attack" }
local ATTACKS = { "Lightning Bolt", "Flame Shock", "Earth Shock", "Attack" }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("SHAMAN"); c.setFaction("Alliance"); c.setLevel(10)
    if not opts.deadUnknown then c.setDead(false) end
    c.setCombat(false)
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
    for _, name in ipairs(REACH) do c.setInRange(IDS[name], yes) end
end

-- A shaman with Lightning Shield up, an enemy targeted, every read given,
-- in a fight, the swing not started, and Flame Shock not on it yet.
local function fighting(c)
    c.setPlayerBuffs(SHIELDED); c.setTarget(ENEMY); c.setTargetDebuffs({}); c.setStealthed(false)
    inRange(c, true)
    c.setCurrentSpell(IDS["Attack"], false); c.setCombat(true)
    c.advance(1, 5)
end

local function showing(icon, name) return icon.shown == true and icon.texture == "tex:" .. name end

tests["shaman: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Lightning Shield", "no shield up: Lightning Shield first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["shaman: shield, Lightning Bolt to open, then the swing, Flame Shock, Earth Shock"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Lightning Shield")
    -- Out of a fight, the swing already on (so the shared engage step has
    -- nothing to start): the pack opens with Lightning Bolt.
    c.setPlayerBuffs(SHIELDED); c.setTarget(ENEMY); inRange(c, true)
    c.setCurrentSpell(IDS["Attack"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Lightning Bolt", "an enemy, out of a fight: open with Lightning Bolt")
    c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Flame Shock", "in the fight, swinging, your Flame Shock not on it")
    t.ok(not showing(icon, "Lightning Bolt"), "no Lightning Bolt in the fight")
    c.setTargetDebuffs(FLAME); c.advance(1, 5)
    t.eq(icon.texture, "tex:Earth Shock", "Flame Shock on the target: Earth Shock")
    t.ok(said(c):find("suggesting Earth Shock", 1, true), said(c))
    c.setCurrentSpell(IDS["Attack"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Attack", "in the fight, the swing stopped: Attack first")
end

tests["shaman: reads not given yet say what is missing, and show nothing that needs them"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.shown, true, "the read arrived: shown")
    t.eq(icon.texture, "tex:Lightning Shield")
    -- Your debuffs on the target not read: Flame Shock is passed by, and diag says why.
    fighting(c); c.setCurrentSpell(IDS["Attack"], true); c.setTargetDebuffs(nil); c.advance(1, 5)
    t.ok(not showing(icon, "Flame Shock"), "debuffs not read: no Flame Shock")
    t.eq(icon.texture, "tex:Earth Shock")
    t.ok(said(c):find("your debuffs on the target", 1, true), "names the read: " .. said(c))
    -- Buffs that cannot be read: the shield is not asked for.
    c.setTarget({ exists = false }); c.setCombat(false); c.setPlayerBuffs(nil); c.advance(1, 5)
    t.ok(not showing(icon, "Lightning Shield"), "buffs not read: no shield suggested")
end

tests["shaman: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Lightning Shield"] = true, ["Flame Shock"] = true } })
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); on(c, addon)
    t.ok(not showing(icon, "Lightning Shield"), "no shield learned: not asked for")
    fighting(c); c.setCurrentSpell(IDS["Attack"], true); c.advance(1, 5)
    t.ok(not showing(icon, "Flame Shock"), "Flame Shock not learned")
    t.eq(icon.texture, "tex:Earth Shock")
end

tests["shaman: cooldown is passed by and comes back; out of range is said"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c); c.setCurrentSpell(IDS["Attack"], true); c.setTargetDebuffs(FLAME)
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Earth Shock")
    c.setSpellCooldown(IDS["Earth Shock"], true); c.advance(1, 5)
    t.ok(not showing(icon, "Earth Shock"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Earth Shock"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Earth Shock", "ready again")
    inRange(c, false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
end

tests["shaman: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Attack")
    local function attacking()
        for _, name in ipairs(ATTACKS) do if showing(icon, name) then return true end end
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

tests["shaman: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.setTargetDebuffs({}); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Lightning Shield")
end

-- Gear, through the same verdict the tooltip uses, with the Shaman pack.
local STR = "ITEM_MOD_STRENGTH_SHORT"
local HELM = "item:1"
local function gear(more)
    local c = ns.make.fakeClient()
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STR] = 4 } })
    c.setWorn(1, false)
    local g = c.gear(HELM)
    for key, value in pairs(more or {}) do g[key] = value end
    return g
end

tests["shaman: gear the class cannot use is not offered; leather it can use is scored"] = function(t)
    local who = { pack = ns.Packs.SHAMAN, role = "dps", level = 10 }
    -- Plate (4/4) and a sword (2/7): not in the class table, the game's marks not read.
    for _, kind in ipairs({ { 4, 4 }, { 2, 7 } }) do
        local lines = ns.GearVerdict.Lines(gear({ classID = kind[1], subclassID = kind[2], minLevel = 1 }), who)
        t.eq(lines, { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } },
            "not offered: " .. kind[1] .. "/" .. kind[2])
    end
    -- Leather (4/2), Strength on it, the game marking nothing unmet: scored with the dps weights.
    local lines, detail = ns.GearVerdict.Lines(gear({ unmet = {}, classID = 4, subclassID = 2, minLevel = 1 }), who)
    t.eq(lines[1] and lines[1].tone, "good", "leather is an upgrade: " .. tostring(lines[1] and lines[1].text))
    t.ok(tostring(lines[1] and lines[1].text):find("Upgrade for your head piece", 1, true), tostring(lines[1] and lines[1].text))
    t.eq(detail.result.verdict, "upgrade", "scored")
end

return tests
