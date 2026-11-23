local _, ns = ...
-- S12 care key (P-KEYS slice A, lead section 236): the whole add-on on a
-- fake client, a priest. Off by default; switched on with the rotation, a
-- second secure button holds the heal or cure the care key suggests: a
-- hurt friend, a dead friend out of a fight, else your quick heal on you,
-- with Ctrl, Shift, Alt and Ctrl+Shift parts. Set out of a fight only; a
-- change in a fight waits for its end. Section 236: a reload, late spell
-- data, and a unit read that fails then recovers. No macro type, and
-- nothing is bound by the add-on.
--
-- What the fake client cannot express: the press itself. Spell ids are
-- made up; not tested in game.
local tests = {}

local CK = ns.CareKeys
local D = ns.RotationDriver
local IDS = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Shield"] = 17, ["Resurrection"] = 2006,
}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false)
    for name, id in pairs(IDS) do
        if not (opts.late and name == "Renew") then c.setSpellId(name, id) end
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then
        addon.settings:set(D.SETTING, true)
        addon.settings:set(CK.SETTING, true)
        c.advance(3, 5)
    end
    return c, addon
end

local function button(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find(CK.BUTTON, 1, true) then return h end
    end
    return nil
end

local function lines(c, word)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](word)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

local FRIEND = { exists = true, friend = true, isSelf = false, dead = false, hurt = true }

local function noBindsNoMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

tests["priest care key: off by default, no button made"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(CK.SETTING), false, "off by default")
    addon.settings:set(D.SETTING, true); c.advance(3, 5)
    t.eq(button(c), nil, "no button made with the rotation alone")
    t.ok(lines(c, CK.WORD):find("is off", 1, true) ~= nil, "the word says it is off")
end

tests["priest care key: your quick heal on you, the parts on the modifiers"] = function(t)
    local c = start({ on = true })
    local h = button(c)
    t.ok(h ~= nil, "the button was made")
    if not h then return end
    t.eq({ h.attrs.type, h.attrs.spell, h.attrs.unit }, { "spell", "Flash Heal", "player" })
    t.eq(h.attrs["*spell-ctrl"], "Renew"); t.eq(h.attrs["*spell-shift"], "Lesser Heal")
    t.eq(h.attrs["*spell-more"], "Dispel Magic", "Ctrl+Shift: the cure, no bandage")
    t.ok(lines(c, CK.WORD):find("Flash Heal", 1, true) ~= nil, "the word names the key")
    noBindsNoMacros(t, c)
end

local function neverTarget(t, h)
    for _, g in ipairs(h.given) do
        if tostring(g.attr):find("unit", 1, true) then
            t.ok(g.value ~= "target", "never the target token: " .. tostring(g.attr))
        end
    end
end

local function targetInGroup(c, care)
    c.setGuid("target", "Player-1")
    c.setParty({ { unit = "party1", guid = "Player-1" } })
    c.setUnitCare("target", care)
    c.setUnitCare("party1", care)
end

tests["priest care key: a hurt friendly target takes the key by its group token"] = function(t)
    local c = start({ on = true })
    targetInGroup(c, FRIEND); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq({ h.attrs.spell, h.attrs.unit }, { "Flash Heal", "party1" })
    t.eq(h.attrs["*unit-ctrl"], "player", "the rest stays on you")
    targetInGroup(c, { exists = true, friend = false, dead = false, hurt = true }); c.advance(3, 5)
    t.eq(h.attrs.unit, "player", "a foe is never healed")
    neverTarget(t, h)
    noBindsNoMacros(t, c)
end

tests["priest care key: the target changes in a fight; the key keeps the friend"] = function(t)
    local c = start({ on = true })
    targetInGroup(c, FRIEND); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.unit, "party1", "planned on the friend you target")
    c.setCombat(true); c.advance(1, 5)
    c.setGuid("target", "Creature-1")
    c.setUnitCare("target", { exists = true, friend = false, dead = false, hurt = true })
    c.advance(5, 10)
    t.eq(h.attrs.unit, "party1", "an enemy targeted in the fight: the key still holds the friend")
    c.setParty({ { unit = "party1", guid = "Player-1" }, { unit = "party2", guid = "Player-2" } })
    c.setGuid("target", "Player-2")
    c.setUnitCare("party2", { exists = true, friend = true, isSelf = false, dead = false, hurt = false })
    c.advance(5, 10)
    t.eq(h.attrs.unit, "party1", "another friend targeted: still the planned friend")
    c.setCombat(false); c.advance(3, 5)
    t.eq(h.attrs.unit, "party1", "after the fight: the hurt friend")
    neverTarget(t, h)
end

-- Lead section 305 item 6 (P-KEYS-TOKEN-REINDEX, K7-2): the group order
-- changes, so the friend the key holds by "party1" is now "party2". On
-- GROUP_ROSTER_UPDATE the key is planned again at once, out of a fight;
-- in a fight nothing is written until PLAYER_REGEN_ENABLED.
local function swap(c)
    c.setParty({ { unit = "party1", guid = "Player-2" }, { unit = "party2", guid = "Player-1" } })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = false })
    c.setUnitCare("party2", FRIEND)
end

tests["priest care key: two members swap places, the key follows the friend"] = function(t)
    local c = start({ on = true })
    targetInGroup(c, FRIEND); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.unit, "party1", "planned on the friend you target")
    swap(c)
    c.fire("GROUP_ROSTER_UPDATE")
    t.eq(h.attrs.unit, "party2", "the roster changed: the same friend, by its new token")
    t.eq(h.attrs.spell, "Flash Heal")
    neverTarget(t, h)
    noBindsNoMacros(t, c)
end

tests["priest care key: two members swap in a fight, set again once it ends"] = function(t)
    local c = start({ on = true })
    targetInGroup(c, FRIEND); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    c.setCombat(true); c.advance(1, 5)
    local given = #c.secureGiven
    swap(c)
    c.fire("GROUP_ROSTER_UPDATE")
    t.eq(#c.secureGiven, given, "nothing written in the fight")
    t.eq(h.attrs.unit, "party1", "it keeps what it had")
    c.setCombat(false)
    t.eq(h.attrs.unit, "party2", "set to the new token as the fight ends")
    neverTarget(t, h)
end

tests["priest care key: a friendly target not in your group is left out"] = function(t)
    local c = start({ on = true })
    c.setGuid("target", "Player-9")
    c.setUnitCare("target", FRIEND); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.unit, "player", "the target is left out: the heal on you")
    neverTarget(t, h)
end

tests["priest care key: a dead friend out of a fight; in a fight it waits"] = function(t)
    local c = start({ on = true })
    c.setParty({ { unit = "party1" } })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = true })
    c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq({ h.attrs.spell, h.attrs.unit }, { "Resurrection", "party1" })
    c.setCombat(true); c.advance(1, 5)
    local given = #h.given
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.advance(5, 10)
    t.eq(#h.given, given, "in a fight nothing is asked of the button")
    t.eq(h.attrs.spell, "Resurrection", "in a fight the button keeps what it had")
    c.setCombat(false); c.advance(3, 5)
    t.eq({ h.attrs.spell, h.attrs.unit }, { "Flash Heal", "party1" }, "after the fight: the heal")
    noBindsNoMacros(t, c)
end

local HEALS = { "Flash Heal", "Lesser Heal", "Renew", "Power Word: Shield" }

local function twoHurt(c)
    c.setParty({ { unit = "party1", guid = "Player-1" }, { unit = "party2", guid = "Player-2" } })
    c.setUnitCare("party1", FRIEND); c.setUnitCare("party2", FRIEND)
end

local function far(c, unit, v)
    for _, name in ipairs(HEALS) do c.setReach(unit, IDS[name], v) end
end

tests["priest care key: a friend known out of reach is passed by (PK-3)"] = function(t)
    local c = start({ on = true })
    twoHurt(c); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.unit, "party1", "reach not known: the first hurt friend")
    far(c, "party1", false); c.advance(3, 5)
    t.eq({ h.attrs.spell, h.attrs.unit }, { "Flash Heal", "party2" }, "late data: party1 out of reach, the next friend")
    c.setReachFails(true)
    t.eq(pcall(c.advance, 3, 5), true, "a reach read that raises: no error escapes")
    t.eq(h.attrs.unit, "party1", "the reach read raised: not known, not excluded")
    c.setReachFails(false); c.advance(3, 5)
    t.eq(h.attrs.unit, "party2", "the read recovers")
    far(c, "party1", true); c.advance(3, 5)
    t.eq(h.attrs.unit, "party1", "back in reach")
    noBindsNoMacros(t, c)
end

tests["priest care key: out of reach is read again after a reload (PK-3)"] = function(t)
    local c = start({ on = true })
    local c2 = start({ on = true, account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    twoHurt(c2); far(c2, "party1", false); c2.advance(3, 5)
    local h = button(c2)
    t.eq(h and h.attrs.unit, "party2", "after the reload: the friend in reach")
end

tests["priest care key: the setting is read back after a reload"] = function(t)
    local c = start({ on = true })
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.advance(3, 5)
    t.eq(addon2.settings:get(CK.SETTING), true, "the setting read back")
    local h = button(c2)
    t.eq(h and h.attrs.spell, "Flash Heal", "set again after the reload")
    noBindsNoMacros(t, c2)
end

tests["priest care key: a unit read that fails, then recovers"] = function(t)
    local c = start({ on = true })
    targetInGroup(c, FRIEND)
    c.setUnitCareFails(true)
    t.eq(pcall(c.advance, 3, 5), true, "no error escapes")
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.unit, "player", "nothing read: the heal on you")
    c.setUnitCareFails(false); c.advance(3, 5)
    t.eq(h.attrs.unit, "party1", "the read recovers")
end

tests["priest care key: spell data that arrives late"] = function(t)
    local c = start({ on = true, late = true })
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs["*spell-ctrl"], nil, "Renew not read yet: left out")
    c.setSpellId("Renew", IDS.Renew); c.advance(3, 5)
    t.eq(h.attrs["*spell-ctrl"], "Renew", "read later: set")
end

tests["priest care key: switched off, cleared out of a fight only"] = function(t)
    local c, addon = start({ on = true })
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    c.setCombat(true); c.advance(1, 5)
    addon.settings:set(CK.SETTING, false); c.advance(3, 5)
    t.eq(h.attrs.spell, "Flash Heal", "in a fight: kept")
    c.setCombat(false); c.advance(3, 5)
    t.eq(h.attrs.spell, nil, "after the fight: cleared")
    t.eq(h.attrs["*spell-ctrl"], nil)
end

local function rowOf(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["priest care key: its key row is on the Combat topic, refused while off"] = function(t)
    local c, addon = start()
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
    local r = rowOf(c, "keys.care")
    t.ok(r ~= nil, "the care key row")
    if not r then return end
    local S = addon.SettingsKeys
    local set
    for _, b in ipairs(r.actions or {}) do if b.label == S.SET then set = b end end
    t.eq(set and set.enabled, false, "greyed while the care key is off")
    t.ok(type(r.why) == "string" and r.why:find(CK.LABEL, 1, true) ~= nil, tostring(r.why))
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}) end
end

return tests
