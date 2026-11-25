local _, ns = ...
-- Spells to put on the action bars (parity C-48, Flow Builtins.lua:179-210),
-- on the whole add-on loaded on a fake client. A known rotation spell that is
-- on no bar is an advisor line "Put X on your action bars"; it goes when the
-- spell is on a bar, when the bars are not read, when the player chose to
-- skip it, or with the setting off. Nothing is placed. Not tested in game.
local tests = {}

local FROSTBOLT, FIREBALL = 116, 133

local function start(bars)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE"); c.setLevel(10); c.setCombat(false)
    c.setSpellId("Frostbolt", FROSTBOLT); c.setSpell(FROSTBOLT, { known = true })
    c.setSpellId("Fireball", FIREBALL); c.setSpell(FIREBALL, { known = true })
    c.setActionSpells(bars)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function lines(addon)
    local out = {}
    for _, p in ipairs(addon.advisor.List()) do
        if p.id:sub(1, 12) == "spells.bars." then out[#out + 1] = p.text end
    end
    return out
end

local function put(spell) return "Put " .. spell .. " on your action bars: " .. ns.id.title .. " will suggest it" end

local function changed(c)
    c.fire("ACTIONBAR_SLOT_CHANGED", 1)
    c.advance(1, 5)
end

tests["bar spells: a known rotation spell on no bar is a line; gone once it is on a bar"] = function(t)
    local c, addon = start({ ["Fireball"] = 1 })
    t.eq(lines(addon), { put("Frostbolt") }, "Fireball is on a bar, Frostbolt is not")
    c.setActionSpells({ ["Fireball"] = 1, ["Frostbolt"] = 2 })
    changed(c)
    t.eq(lines(addon), {}, "both on bars")
end

tests["bar spells: bars not read - no line (not known is not on no bar)"] = function(t)
    local _, addon = start(nil)
    t.eq(lines(addon), {})
end

tests["bar spells: a spell the player chose to skip has no line"] = function(t)
    local c, addon = start({})
    t.eq(lines(addon), { put("Frostbolt"), put("Fireball") }, "rotation order")
    addon.store:set("char", "rotation.spellChoices", { ["Frostbolt"] = "skip" })
    changed(c)
    t.eq(lines(addon), { put("Fireball") })
end

tests["bar spells: setting off - no line"] = function(t)
    local c, addon = start({})
    addon.settings:set("spells.barAdvice", false)
    changed(c)
    t.eq(lines(addon), {})
end

tests["bar spells: pure - lists in order, then heals for survival; unknown and covered left out"] = function(t)
    local B = ns.SpellBars
    if type(B) ~= "table" then return t.ok(false, "ns.SpellBars") end
    local pack = { lists = { default = { { spell = "A" }, { spell = "B" } }, aoe = { { spell = "C" }, { spell = "A" } } },
                   heals = { self = { "H" }, hots = { "R" } } }
    local known = { A = true, B = true, C = true, H = true }
    local rows = B.Missing(pack, function(n) return known[n] end, { B = 3 }, { C = true })
    t.eq(rows, { { spell = "A", why = "Rotation" }, { spell = "H", why = "Survival" } })
    t.eq(B.Missing(pack, function(n) return known[n] end, nil, {}), nil, "bars not read")
end

return tests
