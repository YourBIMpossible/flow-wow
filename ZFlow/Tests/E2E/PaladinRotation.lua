local _, ns = ...
-- Lead section 187. The Paladin rotation end to end, on the whole add-on
-- loaded on a fake client: the setting -> the client's reads -> the chooser
-- -> the icon the player sees and the line the diag word gives. Each test
-- changes what the client answers and looks at the icon and the words.
-- Offline: the reads are the fake client's, not the game's.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local AURA = { ["Devotion Aura"] = true }
local READY = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200 }
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local ENEMY = { exists = true, hostile = true, dead = false }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass(opts.class or "PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    if not opts.deadUnknown then c.setDead(false) end
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

-- A paladin with the seal up, an enemy targeted, every read given.
local function fighting(c)
    c.setPlayerBuffs(SEALED); c.setTarget(ENEMY); c.setStealthed(false)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Judgement"], true)
    c.setCurrentSpell(IDS["Attack"], true); c.setCombat(true)
    c.advance(1, 5)
end

tests["paladin: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Devotion Aura", "no aura on: the aura first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["paladin: aura, then blessing, then seal with an enemy, then attack, then judge"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.texture, "tex:Devotion Aura")
    c.setPlayerBuffs(AURA); c.advance(1, 5)
    t.eq(icon.texture, "tex:Blessing of Might", "the buff changed: the next one")
    c.setPlayerBuffs(READY); c.setTarget(ENEMY); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "an enemy targeted: the seal")
    c.setPlayerBuffs(SEALED); c.setStealthed(false)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Judgement"], true)
    c.setCurrentSpell(IDS["Attack"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Attack", "not swinging yet")
    c.setCurrentSpell(IDS["Attack"], true); c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Judgement", "swinging, seal up")
    t.ok(said(c):find("suggesting Judgement", 1, true), said(c))
end

tests["paladin: reads not given yet say what is missing, and show nothing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.shown, true, "the read arrived: shown")
    t.eq(icon.texture, "tex:Devotion Aura")
    -- Buffs that cannot be read: no buff is asked for.
    c.setPlayerBuffs(nil); c.advance(1, 5)
    t.eq(icon.shown, false, "buffs not read: no buff suggested")
end

-- The defect: seal up, enemy targeted, range not read. The list had Attack
-- and Judgement ready and stopped on the range; the player was told
-- "nothing out of range".
tests["paladin: range not read is the reason given, not that nothing is out of range"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(SEALED); c.setTarget(ENEMY); c.setStealthed(false)
    c.setCurrentSpell(IDS["Attack"], false); on(c, addon)
    t.eq(icon.shown, false, "range not known: nothing suggested")
    local line = said(c)
    t.ok(line:find("not known whether it is in range", 1, true), line)
    t.ok(line:find("Judgement", 1, true), "names the spells: " .. line)
    t.ok(not line:find("(nothing out of range)", 1, true), line)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Judgement"], true); c.advance(1, 5)
    t.eq(icon.shown, true, "the range arrived")
    t.eq(icon.texture, "tex:Attack")
end

tests["paladin: Judgement on cooldown is passed by, and comes back when ready"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Judgement")
    c.setSpellCooldown(IDS["Judgement"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Judgement"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Judgement"], false); c.advance(1, 5)
    t.eq(icon.shown, true, "ready again")
    t.eq(icon.texture, "tex:Judgement")
    -- Out of range: still the spell to get to, and the words say it is out of range.
    c.setInRange(IDS["Judgement"], false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
end

tests["paladin: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Judgement"] = true, ["Blessing of Might"] = true } })
    c.setPlayerBuffs(AURA); on(c, addon)
    t.ok(not (icon.shown and icon.texture == "tex:Blessing of Might"), "no blessing learned: not asked for")
    fighting(c)
    t.ok(not (icon.shown and icon.texture == "tex:Judgement"), "Judgement not learned")
end

tests["paladin: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Judgement")
    local function attacking() return icon.shown and (icon.texture == "tex:Judgement" or icon.texture == "tex:Attack") end
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not attacking(), "dead target: no attack, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not attacking(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["paladin: no picture for the spell hides the icon, never a blank one"] = function(t)
    local c, addon, icon = start({ noTexture = { ["Devotion Aura"] = true } })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(said(c):find("suggesting Devotion Aura", 1, true), "still explained: " .. said(c))
end

tests["paladin: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Devotion Aura")
end

tests["a class with no pack: on, and it says so"] = function(t)
    local c, addon, icon = start({ class = "MAGE" })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(#said(c) > 0, "the diag word has a rotation line")
end

return tests
