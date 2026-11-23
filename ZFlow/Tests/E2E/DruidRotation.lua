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

-- ------------------------------------- N58 (lead section 241): your form

-- Spell ids for the forms not in IDS. Plausible, not read here.
local FORM_IDS = { ["Bear Form"] = 5487, ["Dire Bear Form"] = 9634, ["Travel Form"] = 783 }

local function learn(c, name, id)
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
end

-- A form you cast: the cast event, then a second.
local function castId(c, name)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", FORM_IDS[name] or IDS[name])
    c.advance(1, 5)
end

-- The form kept for the role (dps unless named), or nil.
local function kept(c, key, role)
    local char = c.saved(ns.id.charDB)
    local state = type(char) == "table" and char.state or nil
    local own = type(state) == "table" and state.ownCasts or nil
    local mine = type(own) == "table" and own[role or "dps"] or nil
    return type(mine) == "table" and mine[key] or nil
end

-- The form chosen with the word, or nil.
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

-- A damage druid knowing Bear Form and Travel Form, in no form, buffed, an
-- enemy targeted: Cat Form asked for.
local function ready()
    local c, addon, icon = start()
    learn(c, "Bear Form", FORM_IDS["Bear Form"]); learn(c, "Travel Form", FORM_IDS["Travel Form"])
    caster(c, BUFFED); c.setTarget(ENEMY); on(c, addon, "dps")
    return c, addon, icon
end

-- Gap: before N58 the Druid pack had no form row, so a form you cast was
-- never kept: the kept and icon checks below are red on the old code.
tests["druid N58: the form you cast is kept and asked for; the one suggested is not"] = function(t)
    local c, _, icon = ready()
    t.eq(icon.texture, "tex:Cat Form", "nothing cast: Cat Form, as before")
    castId(c, "Cat Form")
    t.eq(kept(c, "form"), nil, "PC-1: the suggested form cast is not a choice")
    castId(c, "Bear Form")
    t.eq(kept(c, "form"), "Bear Form", "kept for the role")
    caster(c, BUFFED)
    t.eq(icon.texture, "tex:Bear Form", "in no form: the one you cast")
    learn(c, "Dire Bear Form", FORM_IDS["Dire Bear Form"]); c.advance(1, 5)
    t.eq(icon.texture, "tex:Dire Bear Form", "Dire Bear Form known: the kept bear's later rank")
end

-- Gap: Travel Form and Aquatic Form are for a moment. Red on the old code
-- at the first kept check (no form row); without `temporary` the Travel
-- Form cast would replace the kept Bear Form.
tests["druid N58: Travel Form is never kept; the kept form stays"] = function(t)
    local c, _, icon = ready()
    castId(c, "Bear Form")
    t.eq(kept(c, "form"), "Bear Form", "kept first")
    castId(c, "Travel Form")
    t.eq(kept(c, "form"), "Bear Form", "Travel Form: not kept")
    caster(c, BUFFED)
    t.eq(icon.texture, "tex:Bear Form", "the kept form still asked for")
    local line = word(c, "form travel")
    t.eq(picked(c, "form"), nil, "the word cannot choose Travel Form: " .. line)
end

tests["druid N58: the form word chooses one; auto clears it; a reload keeps it"] = function(t)
    local c, _, icon = ready()
    castId(c, "Bear Form")
    local line = word(c, "form auto")
    t.ok(line:find("auto", 1, true), line)
    t.eq(kept(c, "form"), nil, "auto forgets the cast")
    t.eq(icon.texture, "tex:Cat Form", "auto: Cat Form")
    line = word(c, "form bear")
    t.ok(line:find("Bear Form", 1, true), line)
    t.eq(picked(c, "form"), "Bear Form")
    t.eq(icon.texture, "tex:Bear Form", "the chosen form")
    local c2, _, icon2 = reload(c)
    learn(c2, "Bear Form", FORM_IDS["Bear Form"])
    caster(c2, BUFFED); c2.setTarget(ENEMY); c2.advance(1, 5)
    t.eq(icon2.texture, "tex:Bear Form", "over a reload")
end

tests["druid N58: the spell name raising once: not kept; read again: kept"] = function(t)
    local c = ready()
    local name = c.spellName
    c.spellName = function() error("made-up failure") end
    castId(c, "Bear Form")
    t.eq(kept(c, "form"), nil, "the name could not be read: nothing kept")
    c.spellName = name
    castId(c, "Bear Form")
    t.eq(kept(c, "form"), "Bear Form", "read again: kept")
end

-- ------------------------- section 247 item 2: a healer's form, a moment

-- A healing druid knowing Bear Form, in no form, buffed, an enemy targeted.
local function healer(opts)
    local c, addon, icon = start(opts)
    learn(c, "Bear Form", FORM_IDS["Bear Form"])
    caster(c, BUFFED); c.setTarget(ENEMY); on(c, addon, "heal")
    return c, addon, icon
end

-- Gap: before this, a healer's Bear Form cast in a fight was kept for the
-- healer role, and asked for in every fight after. Red on the old code at
-- the kept check and the next-fight icon check.
tests["druid 247: a healer casts Bear in a fight, leaves it, and is not asked for Bear in the next"] = function(t)
    local c, _, icon = healer()
    c.setCombat(true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Bear Form", "a healer is not asked for Bear before any cast")
    castId(c, "Bear Form")
    c.setFormName("Bear Form"); c.advance(1, 5)
    t.eq(kept(c, "form", "heal"), nil, "the cast is not kept for the healer role")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(1, 5)
    caster(c, BUFFED)
    c.setCombat(true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Bear Form", "the next fight: not asked for Bear")
    t.eq(kept(c, "form", "heal"), nil, "still nothing kept")
end

tests["druid 247: a healer's form out of a fight is not kept either"] = function(t)
    local c, _, icon = healer()
    castId(c, "Bear Form")
    t.eq(kept(c, "form", "heal"), nil, "out of a fight: not kept")
    c.setCombat(true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Bear Form", "the fight after: not asked for Bear")
end

tests["druid 247: a healer's form word keeps it; form auto forgets it"] = function(t)
    local c, _, icon = healer()
    local line = word(c, "form bear")
    t.eq(picked(c, "form"), "Bear Form", line)
    c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Bear Form", "the chosen form is asked for in a fight")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(1, 5)
    line = word(c, "form auto")
    t.eq(picked(c, "form"), nil, line)
    c.setCombat(true); c.advance(1, 5)
    t.ok(icon.texture ~= "tex:Bear Form", "auto: not asked for Bear")
end

tests["druid 247: a healer's form saved by an older build is not asked for"] = function(t)
    local c = healer()
    local char = c.saved(ns.id.charDB)
    char.state = char.state or {}
    char.state.ownCasts = { heal = { form = "Bear Form" } }
    local c2, addon2, icon2 = start({ account = c.saved(ns.id.accountDB), char = char })
    learn(c2, "Bear Form", FORM_IDS["Bear Form"])
    caster(c2, BUFFED); c2.setTarget(ENEMY); on(c2, addon2, "heal")
    c2.setCombat(true); c2.advance(1, 5)
    t.ok(icon2.texture ~= "tex:Bear Form", "the old saved healer form is ignored")
end

tests["druid 247: tank and damage keep the form they cast, as built"] = function(t)
    local c, addon = ready()
    castId(c, "Bear Form")
    t.eq(kept(c, "form"), "Bear Form", "damage: kept")
    addon.settings:set(D.ROLE, "tank"); c.advance(1, 5)
    c.setCombat(true); c.advance(1, 5)
    castId(c, "Cat Form")
    t.eq(kept(c, "form", "tank"), "Cat Form", "tank: kept")
end

-- ---------------------- N50 / GAP DRUID-2 (P-SELFBUFF, section 236): tree
-- The known-spell tree on the whole add-on: Moonkin Form, a Balance talent
-- (options.trees, a first guess), known marks the druid as Balance, and the
-- Cat Form rule stays off. Spell id plausible, not read here.
local MOONKIN = 24858

tests["druid N50: Moonkin Form learned late: the tree appears and Cat Form stops"] = function(t)
    local c, _, icon = ready()
    t.eq(icon.texture, "tex:Cat Form", "no talent spell known: Cat Form, as today")
    c.setSpellId("Moonkin Form", MOONKIN); c.setSpell(MOONKIN, { known = false }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Cat Form", "Moonkin Form not known yet: still Cat Form")
    learn(c, "Moonkin Form", MOONKIN); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Cat Form"), "Moonkin Form learned: no Cat Form")
end

tests["druid N50: a Balance druid is still not offered Cat Form after a reload"] = function(t)
    local c = ready()
    learn(c, "Moonkin Form", MOONKIN); c.advance(1, 5)
    local c2, _, icon2 = reload(c)
    learn(c2, "Bear Form", FORM_IDS["Bear Form"]); learn(c2, "Moonkin Form", MOONKIN)
    caster(c2, BUFFED); c2.setTarget(ENEMY); c2.advance(1, 5)
    t.ok(icon2 ~= nil, "the icon is there after the reload")
    t.ok(not (icon2.shown and icon2.texture == "tex:Cat Form"), "read again after the reload: no Cat Form")
end

tests["druid N50: the talent read raising: today's behaviour, and the tick goes on"] = function(t)
    local c, _, icon = ready()
    c.setSpellId("Moonkin Form", MOONKIN)
    local spell = c.spell
    c.spell = function(id)
        if id == MOONKIN then error("broke") end
        return spell(id)
    end
    c.advance(1, 5)
    t.eq(icon.shown, true, "still suggesting")
    t.eq(icon.texture, "tex:Cat Form", "tree not known: Cat Form, as today")
end

-- Lead section 238: the cat's finisher waits on options.combo (ROGUE-2's
-- machinery, Rotation/Combo.lua). Spell id plausible, not read here.
local BITE = 22568

tests["druid combo: a cat with five combo points is told Ferocious Bite"] = function(t)
    local c, addon, icon = start()
    learn(c, "Ferocious Bite", BITE); c.setInRange(BITE, true)
    on(c, addon, "dps")
    clawing(c, { Rake = true })
    t.eq(icon.texture, "tex:Claw", "no points: build")
    c.setCombo(4, 5); c.advance(1, 5)
    t.eq(icon.texture, "tex:Claw", "four points: still build")
    c.setCombo(5, 5); c.advance(1, 5)
    t.eq(icon.texture, "tex:Ferocious Bite", "five points: the finisher")
end

tests["druid combo: points not read: your own Claws are counted"] = function(t)
    local c, addon, icon = start()
    learn(c, "Ferocious Bite", BITE); c.setInRange(BITE, true)
    on(c, addon, "dps")
    clawing(c, { Rake = true })
    for i = 1, 4 do
        c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", IDS["Claw"]); c.advance(1, 5)
        t.eq(icon.texture, "tex:Claw", "after " .. i .. " Claw(s): not due")
    end
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", IDS["Claw"]); c.advance(1, 5)
    t.eq(icon.texture, "tex:Ferocious Bite", "five Claws counted: the finisher")
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", BITE); c.advance(1, 5)
    t.eq(icon.texture, "tex:Claw", "the bite spent them: build again")
end

return tests
