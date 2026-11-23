local _, ns = ...
-- N39, N40, N26 and N27 (P-KEYS slice E) on the whole add-on loaded on a
-- fake client: a paladin, the rotation and the key frame (the easy key)
-- switched on. N39: an enemy targeted out of a fight, not swinging yet,
-- the key holds Attack (a spell, never a macro) until the swing is on; a
-- setting turns it off and a list of enemies never gets it. N40: an enemy
-- casting in a fight, the icon says to stop it with an interrupt you have
-- (advice only: /stopcasting is a macro, never made). N26: the game
-- putting a spell on your bars is said in chat and kept in a list. N27:
-- the spells list, Bar, Key or Skip per spell, which the key obeys. Per
-- lead section 236: data arriving late, a reload, and a read that fails
-- then recovers. Made-up spell ids and an enemy name.
--
-- What the fake client cannot express: the press and the swing. The test
-- sees the attributes on the secure button. Nothing is bound, nothing put
-- on a bar and no macro is made (section 246). Not tested in game.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local ATTACK, LIST, PLACED = "rotation.autoAttack", "rotation.spellsList", "rotation.placedNotice"
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Judgement"] = 20271, ["Hammer of Justice"] = 853,
}
local ATTACK_ID = 6603
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local ENEMY = "Training Dummy"

local function learn(c, name, id)
    c.setSpellId(name, id)
    c.setSpell(id, { known = true, usable = true })
    c.setSpellCooldown(id, false)
    c.setSpellTexture(id, "tex:" .. name)
    c.setInRange(id, true)
end

-- opts.account / opts.char: saved tables (a reload). opts.noAttack: Attack
-- not read yet (its data arrives late).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false); c.setStealthed(false)
    for name, id in pairs(IDS) do learn(c, name, id) end
    if not opts.noAttack then
        learn(c, "Attack", ATTACK_ID)
        c.setCurrentSpell(ATTACK_ID, false)
    end
    c.setPlayerBuffs(SEALED)
    c.setTarget({ exists = false })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
    return c, addon
end

local function button(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h end
    end
    return nil
end

local function attr(c, name)
    local h = button(c)
    if not h then return nil end
    return h.attrs[name]
end

-- Every spell the key holds, on any modifier.
local function onKey(c)
    local out = {}
    local h = button(c)
    if not h then return out end
    for key, value in pairs(h.attrs) do
        if type(key) == "string" and key:find("spell") and type(value) == "string" then out[value] = true end
    end
    return out
end

local function suggested(addon)
    local view = addon.rotationDriver.view()
    if type(view) ~= "table" then return nil end
    return view.suggestion
end

local function said(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return table.concat(out, "\n")
end

local function slash(c, text)
    local from = #c.printed
    c.slashes[ns.id.slash](text)
    return said(c, from)
end

local function nothingWritten(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "no binding written") end
    if type(c.secureMacros) == "function" then t.eq(#c.secureMacros(), 0, "no macro made") end
    t.ok(attr(c, "type") ~= "macro", "never a macro")
end

local function rowOf(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function pull(c)
    c.setTarget({ exists = true, hostile = true, dead = false })
    c.setTargetName(ENEMY)
    c.advance(1, 5)
end

local function engaged(addon)
    local s = suggested(addon)
    return type(s) == "table" and s.engage == true
end

local function adviceStop(addon)
    local s = suggested(addon)
    return type(s) == "table" and tostring(s.reason):find("Stop its", 1, true) ~= nil
end

local function spellOf(addon)
    local s = suggested(addon)
    if type(s) ~= "table" then return nil end
    return s.spell
end

tests["spell keys: each row is on the Combat topic, with a group and words to find it by"] = function(t)
    local c, addon = start()
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
    for _, key in ipairs({ ATTACK, LIST, PLACED }) do
        t.ok(rowOf(c, key) ~= nil, "a row for " .. key .. " in the settings window")
        local row = addon.settings:row(key)
        t.ok(type(row) == "table" and type(row.group) == "string" and row.group:find("^combat") ~= nil,
            key .. " has a combat group")
        t.ok(type(row) == "table" and type(row.synonyms) == "table" and #row.synonyms > 0, key .. " has synonyms")
        t.eq(addon.settings:get(key), true, key .. " is on")
    end
end

-- N39 -------------------------------------------------------------------

tests["auto attack: an enemy targeted out of a fight: the key holds Attack until the swing is on"] = function(t)
    local c, addon = start()
    pull(c)
    t.ok(engaged(addon), "start attacking is suggested")
    t.eq(attr(c, "type"), "spell")
    t.eq(attr(c, "spell"), "Attack", "the key holds Attack")
    c.setCurrentSpell(ATTACK_ID, true); c.advance(1, 5)
    t.ok(not engaged(addon), "swinging: not suggested again")
    t.ok(attr(c, "spell") ~= "Attack", "swinging: the key goes back to the rotation")
    nothingWritten(t, c)
end

tests["auto attack: in a fight the key is never changed to start it"] = function(t)
    local c, addon = start()
    c.setCombat(true)
    pull(c)
    t.ok(not engaged(addon), "in a fight: no engage step")
    t.ok(attr(c, "spell") ~= "Attack", "the key is not set to Attack in a fight")
    nothingWritten(t, c)
end

-- SE-1: the press on Attack starts the fight. The key frame cannot change
-- in combat lockdown, so a key still holding Attack then would toggle the
-- swing off on the next press (Attack toggles; first guess, not seen in
-- game). PLAYER_REGEN_DISABLED is handled before the lock is on (first
-- guess, not seen in this client): Attack is taken off the key there.
tests["auto attack: Attack on the key, then the fight starts: the key no longer holds Attack"] = function(t)
    local c = start()
    pull(c)
    t.eq(attr(c, "spell"), "Attack", "the key holds Attack before the press")
    -- The press: the swing goes on and the fight starts before the next
    -- tick; the lock comes on after PLAYER_REGEN_DISABLED is handled.
    c.setLockdown(false)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setCombat(true)
    c.setLockdown(true)
    t.ok(onKey(c)["Attack"] == nil, "in the fight the key holds no Attack a second press would toggle off")
    c.advance(1, 5)
    t.ok(onKey(c)["Attack"] == nil, "still no Attack on the key in the fight")
    nothingWritten(t, c)
end

-- SE6-1: the other order. The lock is already on when PLAYER_REGEN_DISABLED
-- is handled: Attack cannot be taken off and stays on the key all fight.
-- The add-on cannot change that; a diag timing mark says it happened.
tests["auto attack: the lock is on before the fight starts: Attack stays, a diag mark says so"] = function(t)
    local c, addon = start()
    pull(c)
    t.eq(attr(c, "spell"), "Attack", "the key holds Attack before the press")
    t.eq(addon.diag.timing.KEYS_FIGHT_START_WAITED, nil, "no mark before the fight")
    c.setCurrentSpell(ATTACK_ID, true)
    c.setLockdown(true)
    c.setCombat(true)
    t.eq(attr(c, "spell"), "Attack", "the lock was on: nothing could be set")
    local m = addon.diag.timing.KEYS_FIGHT_START_WAITED
    t.ok(type(m) == "table", "the diag timing has the mark")
    local listed = false
    for _, e in ipairs(addon.diag.timing.order) do
        if e == "KEYS_FIGHT_START_WAITED" then listed = true end
    end
    t.ok(listed, "listed in the timing order")
    nothingWritten(t, c)
end

-- SE6-1: the usual order leaves no mark.
tests["auto attack: the fight starts before the lock: no waited mark"] = function(t)
    local c, addon = start()
    pull(c)
    c.setLockdown(false)
    c.setCurrentSpell(ATTACK_ID, true)
    c.setCombat(true)
    c.setLockdown(true)
    t.eq(addon.diag.timing.KEYS_FIGHT_START_WAITED, nil, "Attack came off: no mark")
end

tests["auto attack: the setting off: the key does not hold Attack"] = function(t)
    local c, addon = start()
    addon.settings:set(ATTACK, false)
    pull(c)
    t.ok(not engaged(addon), "switched off")
    t.ok(attr(c, "spell") ~= "Attack", "the key keeps the rotation")
    addon.settings:set(ATTACK, true); c.advance(1, 5)
    t.ok(engaged(addon), "on again")
end

tests["auto attack: an enemy on the no-auto-attack list never gets it, kept through a reload"] = function(t)
    local c, addon = start()
    pull(c)
    local text = slash(c, "attack never")
    t.ok(text:find(ENEMY, 1, true) ~= nil, "the enemy named: " .. text)
    c.advance(1, 5)
    t.ok(not engaged(addon), "listed: not suggested")
    t.ok(attr(c, "spell") ~= "Attack", "listed: the key keeps the rotation")
    text = slash(c, "attack")
    t.ok(text:find(ENEMY, 1, true) ~= nil, "the list names it: " .. text)

    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    pull(c2)
    t.ok(not engaged(addon2), "still listed after a reload")
    slash(c2, "attack forget " .. ENEMY)
    c2.advance(1, 5)
    t.ok(engaged(addon2), "forgotten: suggested again")
    t.eq(attr(c2, "spell"), "Attack")
end

-- SE-4: a target whose name is not read, with the list kept, is not known:
-- the attack is not given up for it. Counted, and a diag timing mark says
-- it happened.
tests["auto attack: a target name not read with the list kept: not given up, counted, marked"] = function(t)
    local c, addon = start()
    pull(c)
    slash(c, "attack never")
    c.advance(1, 5)
    t.ok(not engaged(addon), "listed: not suggested")
    t.eq(addon.diag.timing.ROTATION_TARGET_NAME_UNREAD, nil, "no mark while the name is read")
    c.setTargetName(nil)
    c.advance(1, 5)
    t.ok(engaged(addon), "the name not read: not given up")
    local counts = type(addon.rotationDriver.counts) == "function" and addon.rotationDriver.counts() or {}
    t.ok((counts.targetNameUnread or 0) >= 1, "counted")
    t.ok(type(addon.diag.timing.ROTATION_TARGET_NAME_UNREAD) == "table", "the diag timing has the mark")
    nothingWritten(t, c)
end

-- SD-3: a key actions read (KA.Read or KA.Pick) that raises is still not
-- an error of the tick: the suggestion stands. It is counted, and a diag
-- timing mark says it happened.
tests["key actions: a read that raises is counted and marked, the tick goes on"] = function(t)
    local c, addon = start()
    -- The add-on loaded on the fake has its own namespace: its KeyActions.
    local KA = addon.KeyActions
    local read = KA.Read
    t.eq(addon.diag.timing.ROTATION_KEY_ACTIONS_RAISED, nil, "no mark before")
    local asked = 0
    KA.Read = function()
        asked = asked + 1
        error("a read that raises")
    end
    local ran = pcall(c.advance, 1, 5)
    KA.Read = read
    t.ok(ran, "no error escapes the tick")
    t.ok(asked > 0, "the key actions were read: " .. asked)
    local counts = type(addon.rotationDriver.counts) == "function" and addon.rotationDriver.counts() or {}
    t.ok((counts.keyActionsRaised or 0) >= 1, "counted")
    t.ok(type(addon.diag.timing.ROTATION_KEY_ACTIONS_RAISED) == "table", "the diag timing has the mark")
    t.eq(addon.rotationDriver.errors(), 0, "not an error of the tick")
    t.ok(addon.rotationDriver.view() ~= nil, "the suggestion stands")
end

tests["auto attack: Attack read late: nothing until it is read, then the key holds it"] = function(t)
    local c, addon = start({ noAttack = true })
    pull(c)
    t.ok(not engaged(addon), "Attack not read: not suggested")
    learn(c, "Attack", ATTACK_ID)
    c.setCurrentSpell(ATTACK_ID, false)
    c.advance(1, 5)
    t.ok(engaged(addon), "read: suggested")
    t.eq(attr(c, "spell"), "Attack")
end

-- N40 -------------------------------------------------------------------

tests["stop a cast: an enemy casting in a fight: the icon says to stop it with your interrupt"] = function(t)
    local c, addon = start()
    c.setCombat(true)
    pull(c)
    c.setTargetCast("Heal"); c.advance(1, 5)
    t.eq(spellOf(addon), "Hammer of Justice")
    local s = suggested(addon)
    t.ok(type(s) == "table" and tostring(s.reason):find("Stop its Heal", 1, true) ~= nil, "the reason names the cast")
    c.setTargetCast(nil); c.advance(1, 5)
    t.ok(not adviceStop(addon), "cast over: no advice")
    nothingWritten(t, c)
end

tests["stop a cast: the cast read fails, then recovers"] = function(t)
    local c, addon = start()
    c.setCombat(true)
    pull(c)
    c.setTargetCast("Heal")
    c.setTargetCastFails(true); c.advance(1, 5)
    t.ok(not adviceStop(addon), "not read: no advice")
    t.ok(addon.rotationDriver.view().stale ~= true, "the step still ran")
    c.setTargetCastFails(false); c.advance(1, 5)
    t.eq(spellOf(addon), "Hammer of Justice", "read again: the advice")
end

-- N26 -------------------------------------------------------------------

tests["placed notice: the game puts a spell on your bars: said in chat and kept in the list"] = function(t)
    local c = start()
    local from = #c.printed
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", 465, 3)
    local text = said(c, from)
    t.ok(text:find("Devotion Aura", 1, true) ~= nil, "the spell named: " .. text)
    t.ok(text:find("Action Bar 1, slot 3", 1, true) ~= nil, "the place named")
    text = slash(c, "autoplace")
    t.ok(text:find("Devotion Aura", 1, true) ~= nil, "the list names it: " .. text)
    slash(c, "autoplace forget")
    text = slash(c, "autoplace")
    t.ok(text:find("Devotion Aura", 1, true) == nil, "forgotten")
    nothingWritten(t, c)
end

tests["placed notice: the setting off: nothing said, nothing kept"] = function(t)
    local c, addon = start()
    addon.settings:set(PLACED, false)
    local from = #c.printed
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", 465, 3)
    t.eq(said(c, from), "", "nothing said")
    t.ok(slash(c, "autoplace"):find("Devotion Aura", 1, true) == nil, "nothing kept")
end

tests["placed notice: a spell whose name arrives late is named in the list once read; kept through a reload"] = function(t)
    local c = start()
    local from = #c.printed
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", 9999, 26)
    t.ok(said(c, from):find("spell 9999", 1, true) ~= nil, "named by id")
    c.setSpellId("Blessing of Wisdom", 9999)
    t.ok(slash(c, "autoplace"):find("Blessing of Wisdom", 1, true) ~= nil, "named once read")
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.setSpellId("Blessing of Wisdom", 9999)
    local text = slash(c2, "autoplace")
    t.ok(text:find("Blessing of Wisdom", 1, true) ~= nil and text:find("Right Bar, slot 2", 1, true) ~= nil,
        "kept through a reload: " .. text)
end

-- N27 -------------------------------------------------------------------

tests["spells list: the list names your rotation's spells and their choice"] = function(t)
    local c = start()
    local text = slash(c, "spells")
    t.ok(text:find("Judgement: key", 1, true) ~= nil, "Key by default: " .. text)
    text = slash(c, "spells skip judgement")
    t.ok(text:find("Judgement: skip", 1, true) ~= nil, "set, any case: " .. text)
    text = slash(c, "spells skip Not A Spell")
    t.ok(text:find("not a spell", 1, true) ~= nil, "a name not in your rotation is refused: " .. text)
end

tests["spells list: Skip: never suggested and off the key; Key again: back"] = function(t)
    local c, addon = start()
    c.setCombat(true)
    pull(c)
    local spell = spellOf(addon)
    t.ok(type(spell) == "string", "something is suggested in a fight")
    if type(spell) ~= "string" then return end
    slash(c, "spells skip " .. spell); c.advance(1, 5)
    t.ok(spellOf(addon) ~= spell, "skipped: not suggested")
    t.eq(onKey(c)[spell], nil, "skipped: off the key")
    slash(c, "spells key " .. spell); c.advance(1, 5)
    t.eq(spellOf(addon), spell, "key again: suggested")
    nothingWritten(t, c)
end

tests["spells list: Bar: kept off the key; the list off obeys no choice"] = function(t)
    local c, addon = start()
    local held
    for spell in pairs(onKey(c)) do
        if spell ~= "Attack" then held = spell end
    end
    t.ok(type(held) == "string", "the key holds a spell out of a fight")
    if type(held) ~= "string" then return end
    slash(c, "spells bar " .. held); c.advance(1, 5)
    t.eq(onKey(c)[held], nil, "bar: off the key")
    addon.settings:set(LIST, false); c.advance(1, 5)
    t.eq(onKey(c)[held], true, "the list off: back on the key")
    addon.settings:set(LIST, true); c.advance(1, 5)
    t.eq(onKey(c)[held], nil, "on again: off the key")
    nothingWritten(t, c)
end

tests["spells list: the choices are kept in the add-on's saved settings through a reload"] = function(t)
    local c = start()
    slash(c, "spells skip Judgement")
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.ok(slash(c2, "spells"):find("Judgement: skip", 1, true) ~= nil, "kept")
    t.eq(onKey(c2)["Judgement"], nil, "obeyed after the reload")
end

return tests
