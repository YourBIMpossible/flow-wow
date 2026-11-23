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
    -- PC-3: the seal for a healer in a group.
    ["Seal of Wisdom"] = 20166,
}
-- A seal with an id (so its name can be read from a cast) that you do not
-- know: as after a talent reset took it away.
local UNKNOWN = { ["Seal of Justice"] = 20164 }
local AURA = { ["Devotion Aura"] = true }
-- PC-2: only the blessing picked for you counts as up, so every role's is up.
local READY = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Blessing of Wisdom"] = 200,
                ["Blessing of Kings"] = 200 }
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

-- What is kept for this character: the seal or the blessing you cast for a
-- role (no role chosen: dps, as the old add-on did), or nil (N12).
local function kept(c, key, role)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local own = type(state) == "table" and state.ownCasts or nil
    local mine = type(own) == "table" and own[role or "dps"] or nil
    return type(mine) == "table" and mine[key] or nil
end

-- The seal or blessing chosen with the word, or nil.
local function picked(c, key)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local choice = type(state) == "table" and state.ownChoice or nil
    return type(choice) == "table" and choice[key] or nil
end

-- A blessing you cast that lands on you: the cast, then your own buffs show
-- it (UNIT_AURA for you), then it wears off again (`after`, the buffs left).
local function bless(c, name, after)
    cast(c, name)
    local now = {}
    for k, v in pairs(after) do now[k] = v end
    now[name] = 300
    c.setPlayerBuffs(now); c.fire("UNIT_AURA", "player"); c.advance(1, 5)
    c.setPlayerBuffs(after); c.advance(1, 5)
end

-- A word typed after the slash command; the lines it printed, as one.
local function word(c, text)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, " / ")
end

-- A fight starts and ends: what you cast for that fight alone is over.
local function fightPasses(c)
    c.setCombat(true); c.advance(1, 5); c.setCombat(false); c.advance(1, 5)
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
    bless(c, "Blessing of Kings", AURA)
    t.eq(icon.texture, "tex:Blessing of Kings", "blessing down: the one you cast")
    bless(c, "Blessing of Protection", AURA)
    t.eq(kept(c, "blessing"), "Blessing of Kings", "a short blessing is not kept")
    t.eq(icon.texture, "tex:Blessing of Kings")
    bless(c, "Blessing of Wisdom", AURA)
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
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 200, ["Righteous Fury"] = 1500 })
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "up: the seal next")
    -- PC-4: under 30 s left, out of a fight: refreshed.
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 200, ["Righteous Fury"] = 20 })
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Righteous Fury", "under 30 s left: asked for again")
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

-- ------------------------------------------------ N12, N13 (lead section 228)

tests["paladin: Kings cast as dps in Auto is suggested in the next fight; each role keeps its own"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(AURA); on(c, addon)
    t.eq(icon.texture, "tex:Blessing of Might", "dps, nothing cast: Might")
    bless(c, "Blessing of Kings", AURA)
    t.eq(kept(c, "blessing", "dps"), "Blessing of Kings", "kept for dps")
    fightPasses(c)
    t.eq(icon.texture, "tex:Blessing of Kings", "the next fight over, blessing down: Kings")
    addon.settings:set(D.ROLE, "heal"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Blessing of Wisdom", "healing, none cast for it: Wisdom")
    addon.settings:set(D.ROLE, "dps"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Blessing of Kings", "back to dps: its own again")
    t.eq(kept(c, "blessing", "heal"), nil, "nothing kept for healing")
end

tests["paladin: the present blessing follows the role: healing Wisdom, tanking Kings, else Might"] = function(t)
    for _, case in ipairs({ { "heal", "tex:Blessing of Wisdom" }, { "tank", "tex:Blessing of Kings" },
                            { "dps", "tex:Blessing of Might" } }) do
        local c, addon, icon = start()
        addon.settings:set(D.ROLE, case[1])
        c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Righteous Fury"] = true }); on(c, addon)
        t.eq(icon.texture, case[2], case[1])
    end
end

tests["paladin: a seal cast is kept for the role you play"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(READY); on(c, addon)
    cast(c, "Seal of the Crusader")
    fightPasses(c)
    t.eq(icon.texture, "tex:Seal of the Crusader", "dps: the one cast")
    addon.settings:set(D.ROLE, "heal"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "healing, none cast for it: the present rule")
    addon.settings:set(D.ROLE, "dps"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of the Crusader", "back to dps")
end

tests["paladin: a blessing cast that never lands on you is not kept"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(AURA); on(c, addon)
    cast(c, "Blessing of Kings")
    c.fire("UNIT_AURA", "player"); c.advance(1, 5)
    t.eq(kept(c, "blessing"), nil, "your buffs show no Kings: not kept")
    local withKings = { ["Devotion Aura"] = true, ["Blessing of Kings"] = 300 }
    c.setPlayerBuffs(withKings); c.fire("UNIT_AURA", "party1"); c.advance(1, 5)
    t.eq(kept(c, "blessing"), nil, "another unit's auras: not read as yours")
    c.advance(5, 5)
    c.fire("UNIT_AURA", "player"); c.advance(1, 5)
    t.eq(kept(c, "blessing"), nil, "it shows only long after the cast: not kept")
    c.setPlayerBuffs(AURA); c.advance(1, 5)
    t.eq(icon.texture, "tex:Blessing of Might", "the present rule holds")
    -- Kings already on you, cast on someone else: your Kings is not renewed.
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 200 })
    cast(c, "Blessing of Kings")
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 199 }); c.fire("UNIT_AURA", "player")
    c.advance(1, 5)
    t.eq(kept(c, "blessing"), nil, "yours not renewed by the cast: not kept")
    bless(c, "Blessing of Kings", AURA)
    t.eq(kept(c, "blessing"), "Blessing of Kings", "it lands on you: kept")
end

tests["paladin: the seal word chooses a seal; your cast still wins for one fight; auto clears"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    local line = word(c, "seal crusader")
    t.ok(line:find(ns.id.title, 1, true) == 1, "said under the add-on's title: " .. line)
    t.ok(line:find("Seal of the Crusader", 1, true), line)
    t.eq(picked(c, "seal"), "Seal of the Crusader", "kept for the character")
    t.eq(icon.texture, "tex:Seal of the Crusader", "the chosen seal")
    cast(c, "Seal of Righteousness")
    t.eq(icon.texture, "tex:Seal of Righteousness", "your own cast wins")
    t.eq(kept(c, "seal"), nil, "with a seal chosen, a cast is not kept for the role")
    fightPasses(c)
    t.eq(icon.texture, "tex:Seal of the Crusader", "the fight over: the chosen one again")
    local c2, _, icon2 = reload(c)
    c2.setPlayerBuffs(READY); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Seal of the Crusader", "the choice kept over a reload")
    line = word(c, "seal auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(picked(c, "seal"), nil, "the choice cleared")
    t.eq(icon.texture, "tex:Seal of Righteousness", "auto: the present rule")
end

tests["paladin: choosing a seal forgets the seals you cast; a seal not known keeps the usual one"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    cast(c, "Seal of the Crusader")
    fightPasses(c)
    t.eq(kept(c, "seal"), "Seal of the Crusader")
    local line = word(c, "seal justice")
    t.eq(kept(c, "seal"), nil, "the cast one forgotten")
    t.ok(line:find("Seal of Justice", 1, true), line)
    t.ok(line:find("usual one holds", 1, true), "says the usual one holds until it is known: " .. line)
    t.eq(icon.texture, "tex:Seal of Righteousness", "not known: the present rule")
    line = word(c, "seal banana")
    t.ok(line:find("righteousness, crusader, command, justice, light, wisdom, fury", 1, true),
         "lists the names: " .. line)
    t.eq(picked(c, "seal"), "Seal of Justice", "an unknown name changes nothing")
end

tests["paladin: the blessing word chooses a blessing; casts do not change it; auto clears"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(AURA); on(c, addon)
    local line = word(c, "blessing kings")
    t.ok(line:find("Blessing of Kings", 1, true), line)
    t.eq(icon.texture, "tex:Blessing of Kings", "the chosen blessing")
    bless(c, "Blessing of Wisdom", AURA)
    t.eq(icon.texture, "tex:Blessing of Kings", "a cast does not change a chosen blessing")
    t.eq(kept(c, "blessing"), nil, "nor is it kept")
    line = word(c, "blessing protection")
    t.ok(line:find("might, wisdom, kings, salvation, light, sanctuary", 1, true), "lists the names: " .. line)
    t.eq(picked(c, "blessing"), "Blessing of Kings", "Protection is no blessing to keep")
    word(c, "blessing auto")
    t.eq(picked(c, "blessing"), nil)
    t.eq(icon.texture, "tex:Blessing of Might", "auto: the present rule")
end

tests["paladin: only your own aura counts: another paladin's Devotion Aura does not"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 })
    c.setOwnBuffs({ ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 })
    on(c, addon)
    t.eq(icon.texture, "tex:Devotion Aura", "someone else's aura up, yours not: Devotion Aura")
    c.setOwnBuffs({ ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 })
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Devotion Aura"), "yours up: not asked for")
    c.setOwnBuffs(nil); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Devotion Aura"), "your own auras not read: not asked for")
end

-- ------------------------------------- MyBuddy review of the merge (PC-1 to PC-7)

-- A spell learned now: its id, known, ready, its picture.
local function learn(c, name, id)
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
end

-- The lines printed since `from` that hold `text`, as one.
local function printedSince(c, from, text)
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find(text, 1, true) then out[#out + 1] = line end
    end
    return table.concat(out, " / ")
end

tests["paladin PC-1: casting the seal that was suggested is not kept; a later Command takes over"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(READY); on(c, addon)
    t.eq(icon.texture, "tex:Seal of Righteousness", "suggested: Righteousness")
    cast(c, "Seal of Righteousness")
    t.eq(kept(c, "seal"), nil, "the suggested seal cast: not your choice")
    learn(c, "Seal of Command", 20375); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Command", "Command learned: it takes over")
    cast(c, "Seal of the Crusader")
    t.eq(kept(c, "seal"), "Seal of the Crusader", "a seal other than the suggested one: kept")
    t.eq(icon.texture, "tex:Seal of the Crusader")
end

tests["paladin PC-1: casting the blessing that was suggested is not kept"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(AURA); on(c, addon)
    t.eq(icon.texture, "tex:Blessing of Might")
    bless(c, "Blessing of Might", AURA)
    t.eq(kept(c, "blessing"), nil, "the suggested blessing cast: not your choice")
    bless(c, "Blessing of Kings", AURA)
    t.eq(kept(c, "blessing"), "Blessing of Kings", "another one: kept")
end

tests["paladin PC-2: another blessing up does not hide yours; a Greater blessing counts"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 600, ["Seal of Righteousness"] = 25 })
    on(c, addon)
    t.eq(icon.texture, "tex:Blessing of Might", "someone's Kings up, your Might not: Might")
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Greater Blessing of Might"] = 600, ["Seal of Righteousness"] = 25 })
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Blessing of Might"), "Greater Blessing of Might up: not asked for")
    word(c, "blessing kings")
    t.eq(icon.texture, "tex:Blessing of Kings", "a new choice applies at once, the old one still up")
end

tests["paladin PC-2: in a fight another seal counts as missing; out of one it is left alone"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of the Crusader"] = 25 })
    on(c, addon)
    t.ok(not (icon.shown and icon.texture == "tex:Seal of Righteousness"), "out of a fight, a seal up: left alone")
    c.setTarget(ENEMY); c.setStealthed(false); c.setInRange(IDS["Judgement"], true)
    c.setInRange(IDS["Attack"], true); c.setCurrentSpell(IDS["Attack"], true); c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "in a fight, Crusader up but Righteousness picked: Righteousness")
end

tests["paladin PC-3: a healer in a group is given Seal of Wisdom"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "heal")
    c.setPlayerBuffs(READY); on(c, addon)
    t.eq(icon.texture, "tex:Seal of Righteousness", "group not read: Righteousness")
    c.setGrouped(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Wisdom", "in a group: Wisdom")
    c.setGrouped(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of Righteousness", "alone: Righteousness")
end

tests["paladin PC-5: sent, then the aura, then the cast: the blessing is kept"] = function(t)
    local c, addon = start()
    c.setPlayerBuffs(AURA); on(c, addon)
    local id = IDS["Blessing of Kings"]
    c.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-3-0-0-0-0-1", id)
    c.setPlayerBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 300 }); c.fire("UNIT_AURA", "player")
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-1", id)
    c.advance(1, 5)
    t.eq(kept(c, "blessing"), "Blessing of Kings", "the aura before the cast still counts")
end

tests["paladin PC-7: one line says when a cast becomes the kept seal or blessing; the setting stops it"] = function(t)
    local c, addon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(READY); on(c, addon)
    t.eq(addon.settings:get(ns.OwnCasts.SAY), true, "on by default, as the old add-on")
    local from = #c.printed + 1
    cast(c, "Seal of the Crusader")
    local line = printedSince(c, from, "Seal of")
    t.ok(line:find(ns.id.title .. ": Seal of the Crusader", 1, true) == 1, "said under the title: " .. line)
    t.ok(line:find("damage", 1, true), "names the role: " .. line)
    from = #c.printed + 1
    cast(c, "Seal of the Crusader")
    t.eq(printedSince(c, from, "Seal of"), "", "the same seal again: nothing new to say")
    addon.settings:set(ns.OwnCasts.SAY, false)
    from = #c.printed + 1
    cast(c, "Seal of Justice")
    t.eq(kept(c, "seal"), "Seal of Justice", "kept all the same")
    t.eq(printedSince(c, from, "Seal of"), "", "the setting off: nothing said")
end

-- Section 236 (a): data late or in parts: your own buffs not read at the
-- first aura event, read at the next.
tests["paladin 236a: your own buffs not read at first, then read: the blessing is kept"] = function(t)
    local c, addon = start()
    c.setPlayerBuffs(AURA); on(c, addon)
    local id = IDS["Blessing of Kings"]
    c.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-3-0-0-0-0-2", id)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-2", id)
    c.setOwnBuffs(nil); c.fire("UNIT_AURA", "player"); c.advance(1, 5)
    t.eq(kept(c, "blessing"), nil, "not read yet: nothing kept, nothing dropped")
    c.setOwnBuffs({ ["Devotion Aura"] = true, ["Blessing of Kings"] = 300 }); c.fire("UNIT_AURA", "player")
    c.advance(1, 5)
    t.eq(kept(c, "blessing"), "Blessing of Kings", "read now: kept")
end

-- Section 236 (b): a reload in the middle keeps the choice and the setting.
tests["paladin 236b: a reload keeps the word's choice, the kept seal and the line switched off"] = function(t)
    local c, addon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    word(c, "blessing kings")
    addon.settings:set(ns.OwnCasts.SAY, false)
    cast(c, "Seal of the Crusader")
    local c2, addon2, icon2 = reload(c)
    c2.setPlayerBuffs(AURA); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Blessing of Kings", "the word's choice kept")
    c2.setPlayerBuffs(READY); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Seal of the Crusader", "the seal you cast kept")
    t.eq(addon2.settings:get(ns.OwnCasts.SAY), false, "the setting kept")
    local from = #c2.printed + 1
    c2.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-3", UNKNOWN["Seal of Justice"])
    c2.advance(1, 5)
    t.eq(kept(c2, "seal"), "Seal of Justice", "a new seal kept after the reload")
    t.eq(printedSince(c2, from, "Seal of"), "", "and nothing said: the setting is still off")
end

-- Section 236 (c): a read that raises, then recovers.
tests["paladin 236c: the spell name or your own buffs raising once, then fine"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs({ ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 })
    c.setOwnBuffs({ ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 })
    on(c, addon)
    t.eq(icon.texture, "tex:Devotion Aura", "no aura of yours: Devotion Aura")
    local name = c.spellName
    c.spellName = function() error("made-up failure") end
    cast(c, "Seal of the Crusader")
    t.eq(kept(c, "seal"), nil, "the name could not be read: nothing kept")
    c.spellName = name
    cast(c, "Seal of the Crusader")
    t.eq(kept(c, "seal"), "Seal of the Crusader", "read again: kept")
    local own = c.ownBuffs
    c.ownBuffs = function() error("made-up failure") end
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Devotion Aura"), "your own buffs not read: no aura asked for")
    t.eq(addon.rotationDriver.view().stale, nil, "the tick went on: not a kept old view")
    c.ownBuffs = own
    c.advance(1, 5)
    t.eq(icon.texture, "tex:Devotion Aura", "read again: asked for")
end

-- ------------------------------------- N58 (lead section 241): your choice

-- The defect: a seal cast in a fight overwrote the seal kept for the role.
-- Flow kept it for that fight only.
tests["paladin N58: a seal cast in a fight is for that fight; the role's kept seal stays"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    c.setPlayerBuffs(READY); on(c, addon)
    cast(c, "Seal of the Crusader")
    t.eq(kept(c, "seal"), "Seal of the Crusader", "out of a fight: kept for the role")
    c.setTarget(ENEMY); c.setCombat(true); c.advance(1, 5)
    local from = #c.printed + 1
    cast(c, "Seal of Righteousness")
    t.eq(kept(c, "seal"), "Seal of the Crusader", "in a fight: the role's kept seal is not changed")
    t.eq(icon.texture, "tex:Seal of Righteousness", "this fight: the one cast in it")
    t.eq(printedSince(c, from, "Seal of"), "", "nothing said: the role's did not change")
    c.setCombat(false); c.advance(1, 5)
    c.setTarget(nil); c.setPlayerBuffs(READY); c.advance(1, 5)
    t.eq(icon.texture, "tex:Seal of the Crusader", "the fight over: the role's again")
    local c2, _, icon2 = reload(c)
    c2.setPlayerBuffs(READY); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Seal of the Crusader", "over a reload: the role's")
end

tests["paladin N58: a seal cast with the fight not read is kept for the fight only"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs(READY); on(c, addon)
    cast(c, "Seal of the Crusader")
    local fightRead = c.inCombat
    c.inCombat = function() error("made-up failure") end
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", UNKNOWN["Seal of Justice"])
    c.inCombat = fightRead
    c.advance(1, 5)
    t.eq(kept(c, "seal"), "Seal of the Crusader", "not known whether a fight is on: the role's stays")
    c.setCombat(true); c.advance(1, 5); c.setCombat(false); c.advance(1, 5)
    cast(c, "Seal of Righteousness")
    t.eq(kept(c, "seal"), "Seal of Righteousness", "read again, out of a fight: kept for the role")
    t.eq(icon.texture, "tex:Seal of Righteousness")
end

local AURA_IDS = { ["Retribution Aura"] = 7294, ["Concentration Aura"] = 19746 }
local function castId(c, name)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", AURA_IDS[name])
    c.advance(1, 5)
end
local NO_AURA = { ["Blessing of Might"] = 200, ["Blessing of Wisdom"] = 200, ["Blessing of Kings"] = 200 }

tests["paladin N58: the aura you cast is the one asked for; auto goes back to Devotion"] = function(t)
    local c, addon, icon = start()
    addon.settings:set(D.ROLE, "dps")
    learn(c, "Retribution Aura", AURA_IDS["Retribution Aura"])
    c.setPlayerBuffs(NO_AURA); on(c, addon)
    t.eq(icon.texture, "tex:Devotion Aura", "none cast: Devotion Aura")
    castId(c, "Retribution Aura")
    t.eq(kept(c, "aura"), "Retribution Aura", "kept for the role")
    t.eq(icon.texture, "tex:Retribution Aura", "no aura on: the one you cast")
    c.setPlayerBuffs({ ["Retribution Aura"] = true, ["Blessing of Might"] = 200 }); c.advance(1, 5)
    t.ok(not (icon.texture == "tex:Retribution Aura" or icon.texture == "tex:Devotion Aura"), "yours up: no aura asked")
    c.setSpellId("Concentration Aura", AURA_IDS["Concentration Aura"])
    c.setSpell(AURA_IDS["Concentration Aura"], { known = false })
    castId(c, "Concentration Aura")
    t.eq(kept(c, "aura"), "Concentration Aura", "cast, kept even when not known: the word list says so")
    c.setPlayerBuffs(NO_AURA); c.advance(1, 5)
    t.eq(icon.texture, "tex:Devotion Aura", "a kept aura you do not know: Devotion Aura")
    castId(c, "Retribution Aura")
    local c2, _, icon2 = reload(c)
    learn(c2, "Retribution Aura", AURA_IDS["Retribution Aura"])
    c2.setPlayerBuffs(NO_AURA); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Retribution Aura", "over a reload")
    local line = word(c, "aura auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(kept(c, "aura"), nil, "auto forgets the cast")
    t.eq(icon.texture, "tex:Devotion Aura", "auto: Devotion Aura")
end

tests["paladin N58: the aura word chooses one; your buffs not read, then read"] = function(t)
    local c, addon, icon = start()
    learn(c, "Retribution Aura", AURA_IDS["Retribution Aura"])
    c.setPlayerBuffs(NO_AURA); on(c, addon)
    local line = word(c, "aura retribution")
    t.ok(line:find("Retribution Aura", 1, true), line)
    t.eq(picked(c, "aura"), "Retribution Aura")
    t.eq(icon.texture, "tex:Retribution Aura", "the chosen aura")
    local own = c.ownBuffs
    c.ownBuffs = function() error("made-up failure") end
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Retribution Aura"), "your buffs not read: no aura asked")
    c.ownBuffs = own; c.advance(1, 5)
    t.eq(icon.texture, "tex:Retribution Aura", "read again: the chosen aura")
end

-- N58, B3 (PARTLY): Oath of Light. A made-up spell id: the real one was
-- never read from a WoW: Forever trainer.
local OATH = 990101

tests["paladin N58: Oath of Light only once you cast it; auto, a reload, buffs read again"] = function(t)
    local c, addon, icon = start()
    learn(c, "Oath of Light", OATH)
    c.setPlayerBuffs(READY); on(c, addon)
    t.ok(icon.texture ~= "tex:Oath of Light", "never cast: not asked for (auto)")
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", OATH); c.advance(1, 5)
    t.eq(kept(c, "oath"), "Oath of Light", "your cast is kept for the role")
    t.eq(icon.texture, "tex:Oath of Light", "not up: asked for")
    local up = {}
    for k, v in pairs(READY) do up[k] = v end
    up["Oath of Light"] = true
    c.setPlayerBuffs(up); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Oath of Light", "up: not asked")
    c.setPlayerBuffs(READY)
    local buffs = c.playerBuffs
    c.playerBuffs = function() error("made-up failure") end
    c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Oath of Light"), "buffs not read: not asked")
    c.playerBuffs = buffs; c.advance(1, 5)
    t.eq(icon.texture, "tex:Oath of Light", "read again: asked for")
    local c2, _, icon2 = reload(c)
    learn(c2, "Oath of Light", OATH)
    c2.setPlayerBuffs(READY); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Oath of Light", "over a reload")
    local line = word(c, "oath auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(kept(c, "oath"), nil, "auto forgets the cast")
    t.ok(icon.texture ~= "tex:Oath of Light", "auto: not asked for")
    line = word(c, "oath light")
    t.eq(picked(c, "oath"), "Oath of Light", line)
end

-- PC-8: a made-up id; the real one was never read from a WoW: Forever trainer.
local CRUSADER = 990201

tests["paladin PC-8: in melee with Crusader Strike known, it comes once Judgement is on cooldown"] = function(t)
    local c, addon, icon = start()
    learn(c, "Crusader Strike", CRUSADER)
    on(c, addon); fighting(c)
    c.setInRange(CRUSADER, true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Judgement", "Judgement first")
    c.setSpellCooldown(IDS["Judgement"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Crusader Strike", "Judgement on cooldown: Crusader Strike")
    t.ok(said(c):find("suggesting Crusader Strike", 1, true), said(c))
    c.setTarget({ exists = false }); c.advance(1, 5)
    -- PS-2 (lead section 275), LF-2: the reason is the missing target. The
    -- control: only the target changes back, and the strike comes back.
    t.ok(icon.texture ~= "tex:Crusader Strike" or icon.shown ~= true, "no target: no strike - " .. said(c))
    c.setTarget(ENEMY); c.advance(1, 5)
    t.eq(icon.texture, "tex:Crusader Strike", "the target back, nothing else changed: the strike again")
    t.eq(icon.shown, true, "and shown")
end

tests["a class with no pack: on, and it says so"] = function(t)
    local c, addon, icon = start({ class = "DEATHKNIGHT" })
    c.setPlayerBuffs({}); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(#said(c) > 0, "the diag word has a rotation line")
end

return tests
