local _, ns = ...
-- Lead section 187. The Druid rotation end to end, the same shape as
-- PaladinRotation.lua: the whole add-on loaded on a fake client, the
-- setting -> the client's reads -> the chooser -> the icon the player sees
-- and the line the diag word gives. Each test changes what the client
-- answers and looks at the icon and the words. Offline: the reads are the
-- fake client's, not the game's. Spell ids are plausible, not read here.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Mark of the Wild"] = 1126, ["Thorns"] = 467, ["Cat Form"] = 768, ["Prowl"] = 5215,
    ["Claw"] = 1082, ["Rake"] = 1822, ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603,
}
local BUFFED = { ["Mark of the Wild"] = true, ["Thorns"] = true }
local ENEMY = { exists = true, hostile = true, dead = false }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("DRUID"); c.setFaction("Alliance"); c.setLevel(20)
    if not opts.deadUnknown then c.setDead(false) end
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
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

-- A caster druid: no form, read as no form, out of a fight.
local function caster(c, buffs)
    c.setFormName(nil, true); c.setPlayerBuffs(buffs); c.setCombat(false)
    c.advance(1, 5)
end

-- A cat in a fight: an enemy targeted, swinging, every read given, both
-- melee spells read as in range.
local function clawing(c, debuffs)
    c.setFormName("Cat Form"); c.setPlayerBuffs(BUFFED); c.setTargetDebuffs(debuffs)
    c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(true)
    c.setCurrentSpell(IDS["Attack"], true)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Rake"], true); c.setInRange(IDS["Claw"], true)
    c.advance(1, 5)
end

tests["druid: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    caster(c, {})
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Mark of the Wild", "no buff on: the mark first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["druid: form known as none: the mark, then thorns"] = function(t)
    local c, addon, icon = start()
    caster(c, {}); on(c, addon)
    t.eq(icon.texture, "tex:Mark of the Wild")
    t.ok(said(c):find("suggesting Mark of the Wild", 1, true), said(c))
    c.setPlayerBuffs({ ["Mark of the Wild"] = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Thorns", "the mark is up: thorns next")
end

-- Defect (187): the form not read left the druid told only "nothing out of
-- range" or "no enemy targeted"; the read that was missing was never named.
tests["druid: form not known: nothing is suggested and the diag names the missing read"] = function(t)
    local c, addon, icon = start()
    c.setFormName(nil); c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false, "form not read: no caster buff asked for")
    local line = said(c)
    t.ok(line:find("not read: which form you are in", 1, true), line)
    c.setFormName(nil, true); c.advance(1, 5)
    t.eq(icon.shown, true, "the form arrived")
    t.eq(icon.texture, "tex:Mark of the Wild")
    t.ok(not said(c):find("which form you are in", 1, true), "read now: not named: " .. said(c))
end

-- Defect (187): buffs not read hid every buff and the diag said nothing.
tests["druid: buffs not read: no buff is asked for and the diag says why"] = function(t)
    local c, addon, icon = start()
    caster(c, nil); on(c, addon)
    t.eq(icon.shown, false, "buffs not read: no mark")
    t.ok(said(c):find("not read: your buffs", 1, true), said(c))
    c.setPlayerBuffs({}); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mark of the Wild", "read and none: the mark")
end

tests["druid: a damage druid with an enemy targeted is asked for Cat Form, then Prowl"] = function(t)
    local c, addon, icon = start()
    caster(c, BUFFED); c.setTarget(ENEMY); on(c, addon, "dps")
    t.eq(icon.texture, "tex:Cat Form", "no form, an enemy, damage: the form")
    c.setFormName("Cat Form"); c.setStealthed(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Prowl", "a cat out of a fight, not in stealth: prowl")
    c.setStealthed(true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Prowl"), "in stealth: prowl not asked again")
end

-- Defect (187): the target's debuffs were never read, so Rake (and Rip,
-- Moonfire, Demoralizing Roar) never fired: missing on the target needs
-- that read.
tests["druid: rake when the bleed is missing, claw when it is on, and the read named when not given"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "dps"); clawing(c, {})
    t.eq(icon.texture, "tex:Rake", "no bleed on the target: rake")
    c.setTargetDebuffs({ Rake = 9 }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Claw", "the bleed is on: claw")
    c.setTargetDebuffs(nil); c.advance(1, 5)
    t.eq(icon.texture, "tex:Claw", "not read: rake passed by")
    t.ok(said(c):find("rotation: not read: your debuffs on the target; spells that need them are passed by.",
        1, true), said(c))
end

tests["druid: rake on cooldown is passed by, and comes back when ready"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "dps"); clawing(c, {})
    t.eq(icon.texture, "tex:Rake")
    c.setSpellCooldown(IDS["Rake"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Claw", "rake on cooldown: claw")
    c.setSpellCooldown(IDS["Rake"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Rake", "ready again")
end

-- Open question (187): the icon showed an out of range spell (farOpener)
-- with no mark. It is now drawn marked out of range.
tests["druid: out of range: the spell to get to is shown marked, and the words say so"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "dps"); clawing(c, {})
    t.ok(icon.marked == nil, "in range: no mark")
    c.setInRange(IDS["Rake"], false); c.setInRange(IDS["Claw"], false); c.advance(1, 5)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Rake")
    t.eq(icon.marked, "far", "out of range: marked")
    t.ok(said(c):find("out of range: move closer", 1, true), said(c))
    c.setInRange(IDS["Rake"], true); c.setInRange(IDS["Claw"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Rake")
    t.ok(icon.marked == nil, "back in range: the mark is gone")
end

tests["druid: you dying hides the icon and says so"] = function(t)
    local c, addon, icon = start()
    on(c, addon, "dps"); clawing(c, {})
    t.eq(icon.shown, true)
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(icon.marked == nil, "no mark left behind")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["druid: no picture for the spell hides the icon, never a blank one"] = function(t)
    local c, addon, icon = start({ noTexture = { ["Mark of the Wild"] = true } })
    caster(c, {}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(said(c):find("suggesting Mark of the Wild", 1, true), "still explained: " .. said(c))
end

tests["druid: the switch and the role are kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon, "dps")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    t.eq(addon2.settings:get(D.ROLE), "dps", "the role kept")
    caster(c2, BUFFED); c2.setTarget(ENEMY); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Cat Form")
end

return tests
