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
    -- CF-32 / CF-33c: a second seal, the long blessings and Righteous Fury,
    -- known; with no role chosen none of them changes the present rule.
    ["Seal of the Crusader"] = 21082, ["Blessing of Kings"] = 20217, ["Blessing of Wisdom"] = 19742,
    ["Blessing of Protection"] = 1022, ["Righteous Fury"] = 25780,
}
-- A seal with an id (so its name can be read from a cast) that you do not
-- know: as after a talent reset took it away.
local UNKNOWN = { ["Seal of Justice"] = 20164 }
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
    for name, id in pairs(UNKNOWN) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = false })
        c.setSpellCooldown(id, false)
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

-- ---------------------------------------- CF-32, CF-33c (lead sections 226, 227)

-- You cast a spell yourself (or `unit` did): the client tells of it by id.
local function cast(c, name, unit)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "Cast-3-0-0-0-0-0", IDS[name] or UNKNOWN[name])
    c.advance(1, 5)
end

-- What is kept for this character: the seal or the blessing, or nil.
local function kept(c, key)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local own = type(state) == "table" and state.ownCasts or nil
    return type(own) == "table" and own[key] or nil
end

local function reload(c)
    return start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
end

tests["paladin: a seal you cast yourself is the seal from then on, and over a reload"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    t.eq(icon.texture, "tex:Seal of Righteousness", "before any cast: the present rule")
    cast(c, "Seal of the Crusader")
    t.eq(kept(c, "seal"), "Seal of the Crusader", "kept for the character")
    t.eq(icon.texture, "tex:Seal of the Crusader", "seal down: the one you cast")
    c.setCombat(true); c.advance(1, 5); c.setCombat(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of the Crusader", "a fight ending does not drop it")
    cast(c, "Seal of Righteousness")
    t.eq(icon.texture, "tex:Seal of Righteousness", "another seal cast: that one")
    cast(c, "Seal of the Crusader")
    local c2, _, icon2 = reload(c)
    c2.setPlayerBuffs(READY); c2.advance(1, 5)
    t.eq(icon2.shown, true, "on after the reload")
    t.eq(icon2.texture, "tex:Seal of the Crusader", "the seal you cast, kept over a reload")
end

tests["paladin: only your own cast of a seal you know changes the seal"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    cast(c, "Seal of the Crusader", "party1")
    cast(c, "Seal of the Crusader", "target")
    t.eq(kept(c, "seal"), nil, "another unit's cast: nothing kept")
    t.eq(icon.texture, "tex:Seal of Righteousness", "and the present rule holds")
    cast(c, "Judgement")
    t.eq(kept(c, "seal"), nil, "a spell that is no seal: nothing kept")
    t.eq(kept(c, "blessing"), nil)
    t.eq(icon.texture, "tex:Seal of Righteousness")
    cast(c, "Seal of Justice")
    t.eq(kept(c, "seal"), "Seal of Justice", "a seal is kept as cast")
    t.eq(icon.texture, "tex:Seal of Righteousness", "not known now: the present rule")
    cast(c, "Seal of the Crusader")
    t.eq(icon.texture, "tex:Seal of the Crusader", "your own cast of a seal you know: that one")
end

tests["paladin: a long blessing you cast yourself sticks; Protection does not"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(AURA); on(c, addon)
    t.eq(icon.texture, "tex:Blessing of Might", "before any cast: the present rule")
    cast(c, "Blessing of Kings")
    t.eq(icon.texture, "tex:Blessing of Kings", "blessing down: the one you cast")
    cast(c, "Blessing of Protection")
    t.eq(kept(c, "blessing"), "Blessing of Kings", "a short blessing is not kept")
    t.eq(icon.texture, "tex:Blessing of Kings")
    cast(c, "Blessing of Wisdom")
    t.eq(icon.texture, "tex:Blessing of Wisdom", "another long blessing: that one")
    local c2, _, icon2 = reload(c)
    c2.setPlayerBuffs(AURA); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Blessing of Wisdom", "kept over a reload")
end

tests["paladin: Righteous Fury for a tank, out of a fight, when it is not up"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "tank")
    c.setPlayerBuffs(READY); on(c, addon)
    t.eq(icon.texture, "tex:Righteous Fury", "tank, known, not up, out of a fight")
    t.ok(said(c):find("suggesting Righteous Fury", 1, true), said(c))
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Righteous Fury"] = 1500 })
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "up: the seal next")
    c.setPlayerBuffs(READY); c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "in a fight: not asked for")
end

tests["paladin: Righteous Fury never for a role that is not tank"] = function(t)
    for _, role in ipairs({ "dps", "heal", "none" }) do
        local c, addon, icon = start()
        if role ~= "none" then addon.settings:set(D.ROLE, role) end
        c.setPlayerBuffs(READY); on(c, addon)
        t.eq(icon.texture, "tex:Seal of Righteousness", role .. ": known and not up, still not asked for")
        if role == "none" then
            addon.settings:set(D.ROLE, "tank"); c.advance(1, 5)
            t.eq(icon.texture, "tex:Righteous Fury", "the same, as a tank: asked for")
        end
    end
end

tests["a class with no pack: on, and it says so"] = function(t)
    local c, addon, icon = start({ class = "DEATHKNIGHT" })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(#said(c) > 0, "the diag word has a rotation line")
end

return tests
