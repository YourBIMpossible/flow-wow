local _, ns = ...
-- N63 (lead sections 245, 246): heal and cures on the unit under your
-- mouse, on the whole add-on loaded on a fake client: a priest. Off by
-- default; switched on, one secure button holds the heal and the cures as
-- the spell type on the unit "mouseover", set out of a fight only; a
-- change in a fight waits for its end; switched off, it is cleared. No
-- macro type, and nothing is bound (the add-on has no binding call; the
-- player binds the button on the settings page, section 245).
--
-- What the fake client cannot express: the press itself, and which unit
-- is under the mouse. The test sees the attributes set on the button, not
-- the spell cast. Spell ids are made up; not tested in game. The row stays
-- PARTLY.
local tests = {}

local M = ns.Mouseover
local IDS = {
    ["Flash Heal"] = 2061, ["Dispel Magic"] = 527, ["Cure Disease"] = 528, ["Abolish Disease"] = 552,
}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = name ~= "Abolish Disease", usable = true })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function button(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find(M.BUTTON, 1, true) then return h end
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

tests["priest mouseover: off by default, no button made"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(M.SETTING), false, "off by default")
    t.eq(button(c), nil, "no button made")
    t.ok(lines(c, M.WORD):find("is off", 1, true) ~= nil, "the word says it is off")
end

tests["priest mouseover: set out of a fight, a change in a fight waits"] = function(t)
    local c, addon = start()
    addon.settings:set(M.SETTING, true); c.advance(3, 5)
    local h = button(c)
    t.ok(h ~= nil, "the button was made")
    if not h then return end
    t.eq(h.attrs.type, "spell"); t.eq(h.attrs.spell, "Flash Heal"); t.eq(h.attrs.unit, "mouseover")
    t.eq(h.attrs["*spell-shift"], "Dispel Magic"); t.eq(h.attrs["*unit-shift"], "mouseover")
    t.eq(h.attrs["*spell-ctrl"], "Cure Disease")
    t.ok(lines(c, M.WORD):find("shift: Dispel Magic", 1, true) ~= nil, "the word names the parts")

    c.setCombat(true); c.advance(1, 5)
    local given = #h.given
    c.setSpell(IDS["Abolish Disease"], { known = true, usable = true })
    c.advance(5, 10)
    t.eq(#h.given, given, "in a fight nothing is asked of the button")
    t.eq(h.attrs["*spell-ctrl"], "Cure Disease", "in a fight the button keeps what it had")
    t.ok(lines(c, M.WORD):find("waiting", 1, true) ~= nil, "the word says it waits")

    c.setCombat(false); c.advance(1, 5)
    t.eq(h.attrs["*spell-ctrl"], "Abolish Disease", "after the fight: the new cure")
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

tests["priest mouseover: switched off, cleared out of a fight only"] = function(t)
    local c, addon = start()
    addon.settings:set(M.SETTING, true); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    c.setCombat(true); c.advance(1, 5)
    addon.settings:set(M.SETTING, false); c.advance(3, 5)
    t.eq(h.attrs.spell, "Flash Heal", "in a fight: kept")
    c.setCombat(false); c.advance(1, 5)
    t.eq(h.attrs.spell, nil, "after the fight: cleared")
    t.eq(h.attrs.type, nil); t.eq(h.attrs["*spell-shift"], nil)
end

tests["priest mouseover: the setting is read back after a reload"] = function(t)
    local c, addon = start()
    addon.settings:set(M.SETTING, true); c.advance(3, 5)
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.advance(3, 5)
    t.eq(addon2.settings:get(M.SETTING), true, "the setting read back")
    local h = button(c2)
    t.eq(h and h.attrs.spell, "Flash Heal", "set again after the reload")
end

tests["priest mouseover: a part refused is said once and tried again after a fight"] = function(t)
    local c, addon = start()
    c.failSecureAttr("*spell-shift", true)
    addon.settings:set(M.SETTING, true); c.advance(3, 5)
    local h = button(c)
    if not h then t.ok(false, "no button"); return end
    t.eq(h.attrs.spell, "Flash Heal", "the rest is set")
    t.eq(h.attrs["*spell-shift"], nil, "the refused part is not")
    local given = #h.given
    c.advance(5, 10)
    t.eq(#h.given, given, "not asked again each look")
    c.failSecureAttr("*spell-shift", false)
    c.setCombat(true); c.advance(1, 5); c.setCombat(false); c.advance(1, 5)
    t.eq(h.attrs["*spell-shift"], "Dispel Magic", "after the fight: set")
end

return tests
