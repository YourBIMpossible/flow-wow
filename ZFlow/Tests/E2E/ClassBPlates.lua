local _, ns = ...
-- Lead section 242 (MAGE-3, MAGE-4, PRIEST-6): the whole add-on loaded on a
-- fake client, in a fight with an enemy targeted. A second enemy on a
-- nameplate that Polymorph or Shackle Undead can hold, or a cast on a
-- nameplate that is not your target, is named on the rotation icon caption
-- with the spell; the key holds exactly what it holds with no suggestion,
-- so nothing is cast on a unit the add-on chose. Fade, in a group with an
-- enemy on you, is cast on you. The spell card shows the tip for Mind
-- Soothe, Mind Control and Levitate.
--
-- The nameplate reads are the fake client here (setPlateEnemies,
-- setPlateCasts); the real reads are P-READS (Plexy), so the rows stay
-- PARTLY. Made-up names and spell ids. Not tested in game.
local tests = {}

local D = ns.RotationDriver

local SPELLS = {
    MAGE = {
        ["Frost Armor"] = 9001, ["Arcane Intellect"] = 9002, ["Frostbolt"] = 9005, ["Fireball"] = 9006,
        ["Polymorph"] = 9010, ["Counterspell"] = 9011,
    },
    PRIEST = {
        ["Smite"] = 9101, ["Fade"] = 9102, ["Shackle Undead"] = 9103, ["Power Word: Fortitude"] = 9104,
        ["Inner Fire"] = 9105,
    },
    ROGUE = { ["Sinister Strike"] = 9201, ["Kick"] = 9202 },
}
local ENEMY = { exists = true, hostile = true, dead = false }
local GNOLL = { unit = "nameplate1", name = "Gnoll", isTarget = true, creature = "Humanoid", controlled = false }
local KOBOLD = { unit = "nameplate2", name = "Kobold", isTarget = false, creature = "Humanoid", controlled = false }
local GHOUL = { unit = "nameplate2", name = "Ghoul", isTarget = false, creature = "Undead", controlled = false }
local CAST = { unit = "nameplate3", name = "Shaman", spell = "Healing Wave", interruptible = true, isTarget = false }

local function start(class, opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass(class); c.setFaction("Alliance"); c.setLevel(30); c.setDead(false)
    local buffs = {}
    for name, id in pairs(SPELLS[class]) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name); c.setInRange(id, true)
        buffs[name] = 1800
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    addon.settings:set(D.SETTING, true)
    c.setPlayerBuffs(buffs); c.setTarget(ENEMY); c.setStealthed(false)
    if opts.grouped ~= nil then c.setGrouped(opts.grouped) end
    if opts.enemies then c.setPlateEnemies(opts.enemies) end
    if opts.casts then c.setPlateCasts(opts.casts) end
    c.setCombat(true)
    c.advance(2, 10)
    return c, addon, icon
end

local function view(addon)
    local use = addon.use(D.NAME)
    return type(use) == "table" and use.View() or nil
end

local function picked(addon)
    local v = view(addon)
    local s = type(v) == "table" and v.suggestion or nil
    return type(s) == "table" and s or nil
end

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

-- The key holds what it holds with no suggestion; the spell and the unit
-- are on no attribute.
local function keyUntouched(t, addon, class, spell, unit)
    local v = view(addon)
    local plan = addon.KeyPlan(addon.Packs[class], nil)
    t.eq(v.attrs, addon.cast.Attributes(nil, plan, nil, v.lockdown, nil), "the key holds the no-suggestion attributes")
    for _, row in ipairs(v.attrs.button or {}) do
        t.ok(row.value ~= spell, spell .. " is on no attribute: " .. tostring(row.attr))
        t.ok(row.value ~= unit, "the plate unit is on no attribute: " .. tostring(row.attr))
    end
end

tests["class b e2e: mage, a second humanoid: Polymorph named on the caption, the key untouched"] = function(t)
    local c, addon, icon = start("MAGE", { enemies = { GNOLL, KOBOLD } })
    local s = picked(addon)
    t.ok(s ~= nil, "a suggestion")
    if not s then return end
    t.eq({ s.step, s.spell, s.unit, s.member, s.look }, { "cc", "Polymorph", "nameplate2", "Kobold", true })
    t.eq(icon and icon.texture, "tex:Polymorph")
    t.eq(icon and icon.captionText, "Polymorph on Kobold", "the caption names the enemy, live")
    keyUntouched(t, addon, "MAGE", "Polymorph", "nameplate2")
    local line = said(c)
    t.ok(line:find("suggesting Polymorph for nameplate2 (cc; look only, nothing cast)", 1, true) ~= nil, line)
    t.ok(not line:find("Kobold", 1, true), "the diag line holds no name")
end

tests["class b e2e: mage, another enemy casting: Counterspell named on the caption, before crowd control"] = function(t)
    local _, addon, icon = start("MAGE", { enemies = { GNOLL, KOBOLD }, casts = { CAST } })
    local s = picked(addon)
    t.ok(s ~= nil, "a suggestion")
    if not s then return end
    t.eq({ s.step, s.spell, s.unit, s.member, s.look }, { "plateCast", "Counterspell", "nameplate3", "Shaman", true })
    t.eq(icon and icon.captionText, "Counterspell on Shaman")
    keyUntouched(t, addon, "MAGE", "Counterspell", "nameplate3")
end

tests["class b e2e: mage, the reads not there: the plain rotation"] = function(t)
    local _, addon = start("MAGE")
    local s = picked(addon)
    t.ok(s ~= nil and s.step ~= "cc" and s.step ~= "plateCast", "no plate step without the reads: " .. tostring(s and s.step))
end

tests["class b e2e: rogue, another enemy casting: Kick through the same read"] = function(t)
    local _, addon, icon = start("ROGUE", { casts = { CAST } })
    local s = picked(addon)
    t.eq(s and s.spell, "Kick")
    t.eq(s and s.step, "plateCast")
    t.eq(icon and icon.captionText, "Kick on Shaman")
end

tests["class b e2e: priest, a second undead: Shackle Undead; a humanoid: none"] = function(t)
    local _, addon, icon = start("PRIEST", { enemies = { GNOLL, GHOUL } })
    local s = picked(addon)
    t.eq(s and s.spell, "Shackle Undead")
    t.eq(icon and icon.captionText, "Shackle Undead on Ghoul")
    keyUntouched(t, addon, "PRIEST", "Shackle Undead", "nameplate2")
    local _, addon2 = start("PRIEST", { enemies = { GNOLL, KOBOLD } })
    local s2 = picked(addon2)
    t.ok(s2 == nil or s2.spell ~= "Shackle Undead", "Shackle holds undead only")
end

tests["class b e2e: priest in a group, an enemy on you: Fade, on the key; alone: no Fade"] = function(t)
    local onYou = { { unit = "nameplate1", name = "Gnoll", isTarget = true, threat = 3 } }
    local c, addon, icon = start("PRIEST", { grouped = true, enemies = onYou })
    local s = picked(addon)
    t.eq(s and s.step, "threat")
    t.eq(s and s.spell, "Fade")
    t.eq(s and s.look, nil, "cast on you: not look only")
    t.eq(icon and icon.texture, "tex:Fade")
    t.ok(said(c):find("suggesting Fade", 1, true) ~= nil, said(c))
    local _, alone = start("PRIEST", { grouped = false, enemies = onYou })
    local s2 = picked(alone)
    t.ok(s2 == nil or s2.spell ~= "Fade", "alone: no Fade")
end

tests["class b e2e: the spell card shows the tip for Levitate, and none for Fade"] = function(t)
    local c = start("PRIEST")
    local before = #c.printed
    c.learnSpell({ id = 1706, name = "Levitate", rank = "Rank 1" })
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    local text = table.concat(out, "\n")
    t.ok(text:find("New spell: Levitate (Rank 1)", 1, true) ~= nil, text)
    t.ok(text:find("Tip: ", 1, true) ~= nil, "the tip line: " .. text)
    before = #c.printed
    c.learnSpell({ id = 586, name = "Fade", rank = "Rank 1" })
    out = {}
    for i = before + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    t.eq(#out, 1, "Fade: the name line only")
end

return tests
