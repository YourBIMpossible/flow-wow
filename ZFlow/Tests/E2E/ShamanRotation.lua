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

-- Section 212 (S-02): what is in reach is every target rule of the pack's
-- list, not a list kept by hand here. A spell added to IDS later is then put
-- out of range with the rest. keep, when given, is left as it is.
local function reach()
    local out = {}
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        if rule.target and IDS[rule.spell] then out[#out + 1] = rule.spell end
    end
    return out
end

local function inRange(c, yes, keep)
    for _, name in ipairs(reach()) do
        if name ~= keep then c.setInRange(IDS[name], yes) end
    end
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

tests["shaman: on by default (lead section 294); switched off nothing shows; on again, the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.setTargetDebuffs({}); c.advance(1, 5)
    t.eq(addon.settings:get(D.SETTING), true, "on by default (lead section 294)")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off: nothing shown")
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
    -- One attack left in range: it is suggested, and the words do not say
    -- out of range (section 208 mistake 1). This is what the check below
    -- would see if reach() missed a learned attack.
    inRange(c, false, "Earth Shock"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Earth Shock", "the one left in range")
    t.ok(not said(c):find("out of range", 1, true), "not told out of range: " .. said(c))
    inRange(c, false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
    -- Section 220 (Zen's section 218 read): a spell really passed by for
    -- range. None of your debuffs on the target, so Flame Shock is wanted
    -- and, in range, shown before Earth Shock. Read out of range, it is
    -- passed by: Earth Shock (in range) is shown and nothing says out of range.
    c.setTargetDebuffs({}); inRange(c, true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Flame Shock", "Flame Shock wanted and in range: shown first")
    c.setInRange(IDS["Flame Shock"], false); c.advance(1, 5)
    t.ok(not showing(icon, "Flame Shock"), "Flame Shock out of range: not shown")
    t.eq(icon.texture, "tex:Earth Shock", "the next spell in range is shown")
    t.ok(not said(c):find("out of range", 1, true), "not told out of range: " .. said(c))
end

-- Section 220 (Zen's section 218 read): the pack's target rules, written out
-- here by hand, in list order, so a change to the pack is seen. A rule
-- added or a `target = true` dropped in Classes/Shaman.lua makes this differ;
-- the writer then decides whether the spell joins IDS (and so reach()).
local TARGET_RULES = { "Lightning Bolt", "Attack", "Auto Attack", "Stormstrike", "Flame Shock", "Earth Shock" }
-- The target rules this file does not teach (not in IDS, so never learned
-- and never shown here). Any other target rule must be in reach().
local NOT_TAUGHT = { ["Auto Attack"] = true, ["Stormstrike"] = true }

tests["shaman: every learned target rule is put out of range by the test"] = function(t)
    local targets = {}
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        if rule.target then targets[#targets + 1] = rule.spell end
    end
    t.eq(targets, TARGET_RULES, "the pack's target rules, as written out here")
    -- MyBuddy SN-2: no hand-kept list of what is in reach. Every target rule
    -- of the pack is in reach unless it is named below as not taught here;
    -- reach() leaves a spell out only when IDS lacks it, so a later target
    -- rule whose spell is not in IDS fails here instead of being skipped.
    local inReach = {}
    for _, name in ipairs(reach()) do inReach[name] = true end
    for _, name in ipairs(targets) do
        if NOT_TAUGHT[name] then
            t.ok(IDS[name] == nil and not inReach[name], "not taught here, so not in reach: " .. name)
        else
            t.ok(inReach[name], "in reach: " .. name)
        end
    end
end

-- Section 212 (S-03): Flame Shock on the target counts only when it is
-- yours. The pack reads s.targetDebuffs as it is given; the client fills it
-- with the filter "HARMFUL|PLAYER" (Core/Client.lua c.targetDebuffs), so
-- another player's Flame Shock never reaches the rule. This pins both ends.
local function flameRule()
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        if rule.spell == "Flame Shock" then return rule end
    end
end

local function targetEnv(theirs, mine)
    local env = { GetTime = function() return 100 end }
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if unit ~= "target" then return nil end
            local rows = {}
            if theirs and filter == "HARMFUL" then rows[#rows + 1] = { name = "Flame Shock", expirationTime = 110 } end
            if mine and (filter == "HARMFUL" or filter == "HARMFUL|PLAYER") then
                rows[#rows + 1] = { name = "Flame Shock", expirationTime = 112 }
            end
            return rows[i]
        end,
    }
    return env
end

tests["shaman: another player's Flame Shock does not hide yours"] = function(t)
    local rule = flameRule()
    t.ok(rule ~= nil, "a Flame Shock rule")
    if not rule then return end
    local theirs = ns.make.client(targetEnv(true, false)).targetDebuffs()
    t.eq(theirs, {}, "the read leaves out a Flame Shock that is not yours")
    t.eq(rule.when({ hostile = true, targetDebuffs = theirs }), true, "yours is not on it: suggested")
    local mine = ns.make.client(targetEnv(true, true)).targetDebuffs()
    t.eq(mine, { ["Flame Shock"] = 12 }, "yours is read")
    t.eq(rule.when({ hostile = true, targetDebuffs = mine }), false, "yours is on it: not suggested")
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

-- Section 205: mail (4/3) from level 40, as the Hunter pack has it.
tests["shaman gear: mail is refused below level 40 and scored from 40"] = function(t)
    local mail = { unmet = {}, classID = 4, subclassID = 3, minLevel = 30 }
    -- Below 40 with the game's own marks not read, the class table's no is
    -- shown (lead fix at the merge: with unmet = {} the game says it can be
    -- worn, and the game's answer outranks the table; White ran it).
    local unread = { classID = 4, subclassID = 3, minLevel = 30 }
    for _, level in ipairs({ 10, 39 }) do
        local who = { pack = ns.Packs.SHAMAN, role = "dps", level = level }
        t.eq(ns.GearVerdict.Lines(gear(unread), who),
            { { text = "Can't use: your class can use this kind from level 40 (first guess)", tone = "bad" } },
            "mail at " .. level .. ": not yet")
    end
    for _, level in ipairs({ 40, 41 }) do
        local who = { pack = ns.Packs.SHAMAN, role = "dps", level = level }
        local lines, detail = ns.GearVerdict.Lines(gear(mail), who)
        t.eq(lines[1] and lines[1].tone, "good", "mail at " .. level .. ": " .. tostring(lines[1] and lines[1].text))
        t.ok(tostring(lines[1] and lines[1].text):find("Upgrade for your head piece", 1, true),
            tostring(lines[1] and lines[1].text))
        t.eq(detail.result.verdict, "upgrade", "mail at " .. level .. ": scored")
    end
    -- At 40 with the game's own marks not read: no verdict, never an upgrade.
    local who = { pack = ns.Packs.SHAMAN, role = "dps", level = 40 }
    local lines = ns.GearVerdict.Lines(gear({ classID = 4, subclassID = 3, minLevel = 30 }), who)
    t.eq(lines[1] and lines[1].text, "No verdict: " .. ns.GearUsable.REASON.unconfirmed, "marks not read")
end

tests["shaman pack: mail is the one armor kind with a level"] = function(t)
    local armor = ns.Packs.SHAMAN.proficiency[4]
    t.eq(armor[3], 40, "mail from 40")
    for _, kind in ipairs({ 0, 1, 2, 6, 9 }) do t.eq(armor[kind], true, "armor kind " .. kind) end
    t.eq(armor[4], nil, "no plate")
end

-- ---------------------- P-SELFBUFF: the imbue on your main hand (section 236)
-- The fake's weaponEnchant read -> snapshot.weaponEnchant -> the pack's
-- imbue step -> the icon. Spell id plausible, not read here.
local ROCKBITER = 8017

local function imbueReady(opts)
    local c, addon, icon = start(opts)
    c.setSpellId("Rockbiter Weapon", ROCKBITER); c.setSpell(ROCKBITER, { known = true, usable = true })
    c.setSpellCooldown(ROCKBITER, false); c.setSpellTexture(ROCKBITER, "tex:Rockbiter Weapon")
    c.setPlayerBuffs(SHIELDED); c.setTargetDebuffs({})
    on(c, addon)
    return c, addon, icon
end

tests["shaman P-SELFBUFF: the read comes late; a bare main hand asks for the imbue, one on clears it"] = function(t)
    local c, _, icon = imbueReady()
    t.ok(not showing(icon, "Rockbiter Weapon"), "the enchant not read yet: no imbue")
    c.setWeaponEnchant({ main = { has = false } }); c.advance(1, 5)
    t.ok(showing(icon, "Rockbiter Weapon"), "read late, bare: Rockbiter Weapon")
    c.setWeaponEnchant({ main = { has = true, left = 1500 } }); c.advance(1, 5)
    t.ok(not showing(icon, "Rockbiter Weapon"), "on for 25 minutes: cleared")
    c.setWeaponEnchant({ main = { has = true, left = 20 } }); c.advance(1, 5)
    t.ok(showing(icon, "Rockbiter Weapon"), "20 seconds left out of a fight: asked again")
end

tests["shaman P-SELFBUFF: the enchant read raising, then answering"] = function(t)
    local c, addon, icon = imbueReady()
    local before = #addon.problems:list()
    c.setWeaponEnchant({ main = { has = false } })
    c.setWeaponEnchantFails(true); c.advance(1, 5)
    t.ok(not showing(icon, "Rockbiter Weapon"), "the read raised: not known, no imbue")
    t.eq(#addon.problems:list(), before, "no new problem: the raise is caught")
    c.setWeaponEnchantFails(false); c.advance(1, 5)
    t.ok(showing(icon, "Rockbiter Weapon"), "the read answers again: bare, the imbue")
end

tests["shaman P-SELFBUFF: over a reload the imbue is asked for again from the read"] = function(t)
    local c = imbueReady()
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, _, icon2 = imbueReady({ account = account, char = char })
    t.ok(not showing(icon2, "Rockbiter Weapon"), "after the reload, not read yet: no imbue")
    c2.setWeaponEnchant({ main = { has = false } }); c2.advance(1, 5)
    t.ok(showing(icon2, "Rockbiter Weapon"), "read bare after the reload: the imbue")
end

return tests
