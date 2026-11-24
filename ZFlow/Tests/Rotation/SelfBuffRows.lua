local _, ns = ...

-- P-SELFBUFF (remaining rows, class parity): every class pack says which
-- self-buff rows it has, which do not apply to the class as a row (and
-- why), and which wait (N50: a talent spell; never guessed). A listed row
-- must be a "buff" rule in one of the pack's lists. Pure: the packs and the
-- chooser only.

local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- The rows each class must have at least (the rows before this change and
-- the new imbue rows).
local MUST = {
    WARRIOR = { "Battle Shout" },
    PALADIN = { "Devotion Aura", "Righteous Fury", "Blessing of Might", "Seal of Righteousness" },
    HUNTER = { "Aspect of the Hawk", "Aspect of the Monkey" },
    ROGUE = { "Slice and Dice" },
    PRIEST = { "Power Word: Fortitude", "Inner Fire", "Power Word: Shield" },
    SHAMAN = { "Lightning Shield", "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon" },
    MAGE = { "Frost Armor", "Arcane Intellect" },
    WARLOCK = { "Demon Armor", "Demon Skin" },
    DRUID = { "Mark of the Wild", "Thorns" },
}

local function buffRule(pack, name)
    for _, list in pairs(pack.lists or {}) do
        for _, rule in ipairs(list) do
            if rule.spell == name and rule.kind == "buff" then return rule end
        end
    end
    return nil
end

for _, class in ipairs(CLASSES) do
    tests["P-SELFBUFF " .. class .. ": the pack lists its self-buff rows, and each is a buff rule"] = function(t)
        local pack = ns.Packs[class]
        local sb = pack and pack.options and pack.options.selfBuffs
        t.eq(type(sb), "table", class .. ": options.selfBuffs is there")
        if type(sb) ~= "table" then return end
        t.eq(type(sb.rows), "table", class .. ": rows")
        t.eq(type(sb.none), "table", class .. ": none (does not apply, with why)")
        t.eq(type(sb.waits), "table", class .. ": waits (N50 and other reads)")
        for _, name in ipairs(sb.rows or {}) do
            t.ok(buffRule(pack, name) ~= nil, class .. ": listed row is a buff rule: " .. tostring(name))
        end
        local listed = {}
        for _, name in ipairs(sb.rows or {}) do listed[name] = true end
        for _, name in ipairs(MUST[class]) do
            t.ok(listed[name] == true, class .. ": row listed: " .. name)
        end
        for _, row in ipairs(sb.none or {}) do
            t.eq(type(row.what), "string", class .. ": a none entry names what")
            t.eq(type(row.why), "string", class .. ": and says why")
        end
        for _, row in ipairs(sb.waits or {}) do
            t.eq(type(row.spell), "string", class .. ": a wait names the spell")
            t.eq(type(row.on), "string", class .. ": what it waits on")
            t.eq(type(row.why), "string", class .. ": and why")
            t.eq(buffRule(pack, row.spell), nil, class .. ": a waiting row is not suggested: " .. tostring(row.spell))
        end
    end
end

tests["P-SELFBUFF rogue: the poison is not a row (an item use); the reason is stated"] = function(t)
    local sb = ns.Packs.ROGUE.options.selfBuffs
    local found
    for _, row in ipairs(type(sb) == "table" and sb.none or {}) do
        if row.what == "poison" then found = row end
    end
    t.ok(found ~= nil, "the rogue's none list names the poison")
    t.ok(found and found.why:find("item", 1, true) ~= nil, "because it is the use of an item")
    for _, list in pairs(ns.Packs.ROGUE.lists) do
        for _, rule in ipairs(list) do
            t.ok(not rule.spell:find("Poison", 1, true), "no poison step: " .. rule.spell)
        end
    end
end

tests["P-SELFBUFF: the snapshot keeps your weapon enchant as a map"] = function(t)
    local s = ns.SnapshotOf({ weaponEnchant = { main = false, off = 300 } })
    t.eq(s.weaponEnchant, { main = false, off = 300 }, "kept")
    s = ns.SnapshotOf({})
    t.eq(s.weaponEnchant, nil, "not read: nil")
end

tests["P-SELFBUFF: the driver serves your weapon enchant by hand; raised or no read is nil"] = function(t)
    local D = ns.RotationDriver
    local c = ns.make.fakeClient()
    local pack = ns.Packs.SHAMAN
    c.setWorn(16, "item:25"); c.setWorn(17, "item:26")
    c.setWeaponEnchant({ main = { has = true, left = 600 }, off = { has = false } })
    local read = D.Read(c, pack, {})
    t.eq(read("weaponEnchant"), { main = 600, off = false }, "seconds left on, false bare")
    c.setWeaponEnchant({ main = { has = true } })
    t.eq(read("weaponEnchant"), { main = true }, "on, time not shown: true; a hand not read is left out")
    c.setWeaponEnchant({ main = {} })
    t.eq(read("weaponEnchant"), {}, "a hand with nothing known is left out")
    c.setWeaponEnchant(nil)
    t.eq(read("weaponEnchant"), nil, "not read")
    c.setWeaponEnchantFails(true)
    t.eq(read("weaponEnchant"), nil, "a read that raises: nil")
    t.eq(D.Read({}, pack, {})("weaponEnchant"), nil, "no such read: nil")
end

tests["P-SELFBUFF: only a worn weapon counts; slot 16 empty or unread leaves the main hand out"] = function(t)
    local D = ns.RotationDriver
    local c = ns.make.fakeClient()
    local pack = ns.Packs.SHAMAN
    c.setWeaponEnchant({ main = { has = false } })
    c.setWorn(16, false)
    local read = D.Read(c, pack, {})
    t.eq(read("weaponEnchant"), {}, "slot 16 empty (unarmed): the main hand is left out")
    c.setWornUnread(true)
    t.eq(read("weaponEnchant"), {}, "slot 16 not read: left out")
    c.setWornUnread(false); c.setWorn(16, "item:25")
    t.eq(read("weaponEnchant"), { main = false }, "a weapon worn and bare: false")
    local raising = { weaponEnchant = function() return { main = { has = false } } end,
                      wornLinks = function() error("broke") end }
    t.eq(D.Read(raising, pack, {})("weaponEnchant"), {}, "the worn read raising: left out")
end

-- The shaman's imbue, chosen by the pack: out of a fight, the main hand
-- read bare or under a minute.
local function imbueSnap(over)
    local s = { dead = false, inCombat = false, hostile = false, formKnown = true,
                buffs = { ["Lightning Shield"] = 600 }, targetDebuffs = {}, current = {},
                weaponEnchant = { main = false },
                spells = { ["Rockbiter Weapon"] = { known = true, usable = true, onCooldown = false, inRange = true },
                           ["Lightning Shield"] = { known = true, usable = true, onCooldown = false, inRange = true } } }
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

tests["P-SELFBUFF shaman: no imbue on the main hand: the imbue you know"] = function(t)
    local got = ns.Choose(imbueSnap(), ns.Packs.SHAMAN)
    t.eq(got and got.spell, "Rockbiter Weapon", "bare main hand: Rockbiter Weapon")
    got = ns.Choose(imbueSnap({ weaponEnchant = { main = 1200 } }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "twenty minutes on: not asked")
    got = ns.Choose(imbueSnap({ weaponEnchant = { main = true } }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "on, time not shown: not asked")
    got = ns.Choose(imbueSnap({ weaponEnchant = { main = 30 } }), ns.Packs.SHAMAN)
    t.eq(got and got.spell, "Rockbiter Weapon", "half a minute left: asked")
    got = ns.Choose(imbueSnap({ weaponEnchant = "nil" }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "not read: not asked")
    got = ns.Choose(imbueSnap({ weaponEnchant = {} }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "the main hand not known: not asked")
    got = ns.Choose(imbueSnap({ form = "Ghost Wolf" }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "in Ghost Wolf: not asked")
end

tests["P-SELFBUFF shaman: in a fight only a bare hand asks; the first imbue known wins"] = function(t)
    local got = ns.Choose(imbueSnap({ inCombat = true, weaponEnchant = { main = 30 } }), ns.Packs.SHAMAN)
    t.ok(not (got and got.spell == "Rockbiter Weapon"), "in a fight, still on: not asked")
    got = ns.Choose(imbueSnap({ inCombat = true }), ns.Packs.SHAMAN)
    t.eq(got and got.spell, "Rockbiter Weapon", "in a fight, bare: asked")
    local s = imbueSnap()
    s.spells["Windfury Weapon"] = { known = true, usable = true, onCooldown = false, inRange = true }
    got = ns.Choose(s, ns.Packs.SHAMAN)
    t.eq(got and got.spell, "Windfury Weapon", "Windfury known: it comes first")
end

return tests
