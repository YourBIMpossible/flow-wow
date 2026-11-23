local _, ns = ...
-- S15 click slots and S29 move handle (P-KEYS slice C, lead section 236):
-- the whole add-on on a fake client, a priest. Off by default: no row is
-- made. Switched on with the rotation, a row of secure buttons holds the
-- rotation key's suggestion, the care key's, and the plan's modifier
-- parts, each cast only by the player's click on it. Set out of a fight
-- only; frozen in one. The row's handle moves it out of a fight, the place
-- kept in the add-on's own layout. Section 236: a reload, late spell data,
-- and a lock read that is not known, then is. No macro type, nothing bound.
--
-- What the fake client cannot express: the click itself and the drag on
-- screen. Spell ids are made up; not tested in game.
local tests = {}

local S = ns.ClickSlots
local D = ns.RotationDriver
local G = ns.MoveGuides
local IDS = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Smite"] = 585,
}
local NAME = ns.id.framePrefix .. "ClickSlots"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 600)
    c.setPlayerBuffs({})
    for name, id in pairs(IDS) do
        if name ~= opts.late then c.setSpellId(name, id) end
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then
        addon.settings:set(D.SETTING, true)
        addon.settings:set(S.SETTING, true)
        c.advance(3, 5)
    end
    return c, addon
end

local function slotRow(c)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == NAME then return h end
    end
    return nil
end

local function slot(h, name)
    for i, s in ipairs(S.SLOTS) do
        if s == name then return h.slots[i] end
    end
    return nil
end

local function noBindsNoMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
end

local function lines(c, word)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](word)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

tests["click slots: off by default, no row made"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(S.SETTING), false, "off by default")
    local row = addon.settings:row(S.SETTING)
    t.ok(row ~= nil, "a settings row")
    if row then
        t.eq({ row.scope, row.type, row.default, row.group }, { "char", "bool", false, "combat" })
        t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, "with synonyms")
    end
    addon.settings:set(D.SETTING, true); c.advance(3, 5)
    t.eq(slotRow(c), nil, "no row with the rotation alone")
    t.ok(lines(c, S.WORD):find("off", 1, true) ~= nil, "the word says it is off")
    noBindsNoMacros(t, c)
end

tests["click slots: the key, the care key and the plan's parts, shown with their icons"] = function(t)
    local c = start({ on = true })
    local h = slotRow(c)
    t.ok(h ~= nil, "the row was made")
    if not h then return end
    t.eq(h.shown, true, "the row is shown")
    local key = slot(h, "key")
    t.eq({ key.attrs.type, key.attrs.spell }, { "spell", "Power Word: Fortitude" }, "the rotation's suggestion")
    t.eq(key.shown, true)
    t.eq(key.icon, "tex:Power Word: Fortitude")
    local care = slot(h, "care")
    t.eq({ care.attrs.type, care.attrs.spell, care.attrs.unit }, { "spell", "Flash Heal", "player" }, "the care key's")
    t.eq(care.icon, "tex:Flash Heal")
    t.ok(lines(c, S.WORD):find("Power Word: Fortitude", 1, true) ~= nil, "the word names the key slot")
    noBindsNoMacros(t, c)
end

tests["click slots: the target changes in a fight; the care slot keeps the friend"] = function(t)
    local c = start({ on = true })
    local h = slotRow(c)
    if not h then t.ok(false, "no row"); return end
    c.setGuid("target", "Player-1")
    c.setParty({ { unit = "party1", guid = "Player-1" } })
    local hurt = { exists = true, friend = true, isSelf = false, dead = false, hurt = true }
    c.setUnitCare("target", hurt); c.setUnitCare("party1", hurt)
    c.advance(3, 5)
    t.eq(slot(h, "care").attrs.unit, "party1", "planned on the friend you target, by its group token")
    c.setCombat(true); c.advance(1, 5)
    c.setGuid("target", "Creature-1")
    c.setUnitCare("target", { exists = true, friend = false, dead = false, hurt = true })
    c.advance(5, 10)
    t.eq(slot(h, "care").attrs.unit, "party1", "an enemy targeted in the fight: still the friend")
    local careAt
    for i, s in ipairs(S.SLOTS) do
        if s == "care" then careAt = i end
    end
    for _, g in ipairs(h.given) do
        if g.slot == careAt and tostring(g.attr):find("unit", 1, true) then
            t.ok(g.value ~= "target", "never the target token: " .. tostring(g.attr))
        end
    end
    c.setCombat(false); c.advance(3, 5)
    c.setGuid("target", "Player-9"); c.setUnitCare("target", hurt)
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = false })
    c.advance(3, 5)
    t.eq(slot(h, "care").attrs.unit, "player", "a friend not in your group is left out")
    noBindsNoMacros(t, c)
end

tests["click slots: switched off, the row is cleared and hidden"] = function(t)
    local c, addon = start({ on = true })
    local h = slotRow(c)
    if not h then t.ok(false, "no row"); return end
    addon.settings:set(S.SETTING, false); c.advance(3, 5)
    t.eq(h.shown, false, "hidden")
    t.eq(slot(h, "key").attrs.spell, nil, "nothing held")
    t.eq(slot(h, "key").shown, false)
end

tests["click slots: frozen in a fight, set after it"] = function(t)
    local c = start({ on = true })
    local h = slotRow(c)
    if not h then t.ok(false, "no row"); return end
    c.setCombat(true); c.advance(1, 5)
    local given = #h.given
    c.setPlayerBuffs({ ["Power Word: Fortitude"] = 1800 }); c.advance(5, 10)
    t.eq(#h.given, given, "nothing asked of the row in the fight")
    t.eq(slot(h, "key").attrs.spell, "Power Word: Fortitude", "it keeps what it had")
    c.setCombat(false); c.advance(3, 5)
    t.eq(slot(h, "key").attrs.spell, "Inner Fire", "set after the fight")
    t.eq(slot(h, "key").icon, "tex:Inner Fire")
    noBindsNoMacros(t, c)
end

tests["click slots: the lock not known waits, then sets when it is a plain false"] = function(t)
    local c, addon = start()
    c.setLockdown(nil)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(S.SETTING, true)
    t.eq(pcall(c.advance, 3, 5), true, "no error escapes")
    t.eq(slotRow(c), nil, "no row made while the lock is not known")
    c.setLockdown(false); c.advance(3, 5)
    local h = slotRow(c)
    t.ok(h ~= nil, "made once the lock is read")
    if h then t.eq(slot(h, "key").attrs.spell, "Power Word: Fortitude") end
end

-- SC-2: one row not made (here the lock comes on as it is made) is not the
-- end of it: the next try, once the lock is a plain false, makes it.
tests["click slots: a row not made as the lock comes on is made on a later try"] = function(t)
    local c, addon = start()
    local make, asked = c.clickRow, 0
    c.clickRow = function(spec)
        asked = asked + 1
        if asked == 1 then c.setLockdown(true) end
        return make(spec)
    end
    addon.settings:set(D.SETTING, true)
    addon.settings:set(S.SETTING, true)
    c.advance(3, 5)
    t.eq(asked, 1, "asked once, then frozen by the lock")
    t.eq(slotRow(c), nil, "no row while the lock is on")
    c.setLockdown(false); c.advance(3, 5)
    local h = slotRow(c)
    t.ok(h ~= nil, "made on the next try once the lock is a plain false")
    if h then t.eq(slot(h, "key").attrs.spell, "Power Word: Fortitude") end
    t.eq(asked, 2, "asked once more, not every tick")
    noBindsNoMacros(t, c)
end

tests["click slots: a client with no row maker: the status says no frame"] = function(t)
    local c, addon = start()
    c.clickRow = nil
    addon.settings:set(D.SETTING, true)
    addon.settings:set(S.SETTING, true)
    c.advance(3, 5)
    t.eq(addon.clickSlots.status().state, "noFrame")
end

tests["click slots: late spell data fills the slot when it arrives"] = function(t)
    local late = "Power Word: Fortitude"
    local c = start({ on = true, late = late })
    local h = slotRow(c)
    if not h then t.ok(false, "no row"); return end
    t.ok(slot(h, "key").attrs.spell ~= late, "not suggested while its id is not known")
    c.setSpellId(late, IDS[late]); c.advance(3, 5)
    t.eq(slot(h, "key").attrs.spell, late, "on the key slot once it is known")
    t.eq(slot(h, "key").icon, "tex:" .. late)
    t.eq(slot(h, "care").attrs.spell, "Flash Heal")
    noBindsNoMacros(t, c)
end

tests["click slots: the handle moves the row out of a fight and the place is kept"] = function(t)
    local c, addon = start({ on = true })
    local h = slotRow(c)
    if not h then t.ok(false, "no row"); return end
    t.eq(h.point, S.DEFAULT_POINT, "the authored place at first")
    t.eq(c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 }), true)
    t.eq(h.point, { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 })
    local saved = addon.settings:get(S.LAYOUT)
    t.eq(type(saved) == "table" and saved.point, { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 }, "kept in the layout")
    c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", 990, 590 })
    t.eq(h.point, { "BOTTOMLEFT", "BOTTOMLEFT", 1000 - S.Width(), 600 - S.SIZE }, "kept on the screen")
    c.setCombat(true)
    t.eq({ c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", 10, 10 }) }, { false, "lockdown" })
    t.eq(h.point, { "BOTTOMLEFT", "BOTTOMLEFT", 1000 - S.Width(), 600 - S.SIZE }, "not moved in a fight")
end

tests["click slots: setting and place read back after a reload"] = function(t)
    local c = start({ on = true })
    c.dragHandle(NAME, { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 })
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    c2.advance(3, 5)
    t.eq(addon2.settings:get(S.SETTING), true, "the setting read back")
    local h = slotRow(c2)
    t.ok(h ~= nil, "the row made again")
    if not h then return end
    t.eq(h.point, { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 }, "where it was left")
    t.eq(slot(h, "key").attrs.spell, "Power Word: Fortitude", "set again after the reload")
    noBindsNoMacros(t, c2)
end

tests["click slots: the alignment guides watch the row once it is there"] = function(t)
    local c, addon = start()
    c.setFrameRect(NAME, { l = 400, r = 612, b = 100, t = 132 })
    addon.settings:set(D.SETTING, true)
    addon.settings:set(S.SETTING, true)
    c.advance(3, 5)
    t.ok(c.watched(NAME), "the guides watch the row's frame")
    local found = false
    for _, fr in ipairs(G.FRAMES) do if fr.key == "ClickSlots" then found = true end end
    t.ok(found, "listed with the frames the guides know")
end

return tests
