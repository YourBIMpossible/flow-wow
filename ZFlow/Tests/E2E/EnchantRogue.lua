local _, ns = ...
-- N64 (lead section 243): the weapon enchant reminder on the whole add-on
-- loaded on a fake client: a rogue with poison on both hands. Off by
-- default. Switched on, a hand seen with an enchant is watched: a line in
-- chat once when it runs low and once when it is gone, out of a fight
-- only; a fight holds the line until it ends. Nothing is cast, used or
-- bound.
--
-- The read is the fake's c.weaponEnchant() in the shape Plexy's P-READS
-- note names (item 5); the real read is not in Core/Client.lua yet. Not
-- tested in game. The row stays PARTLY.
local tests = {}

local E = ns.Enchant

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("ROGUE"); c.setFaction("Alliance"); c.setLevel(30)
    c.setDead(false); c.setCombat(false)
    if opts.enchant ~= "none" then
        c.setWeaponEnchant(opts.enchant or {
            main = { has = true, left = 1800, charges = 60 },
            off = { has = true, left = 1800, charges = 60 },
        })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- What was printed since `from` that names a weapon enchant.
local function saidSince(c, from)
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("weapon enchant", 1, true) then out[#out + 1] = line end
    end
    return out
end

local function word(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](E.WORD)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

tests["enchant e2e: off by default, nothing said"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(E.SETTING), false, "off by default")
    local from = #c.printed + 1
    c.setWeaponEnchant({ main = { has = false }, off = { has = false } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(10, 10)
    t.eq(#saidSince(c, from), 0, "off: nothing said")
    t.ok(word(c):find("is off", 1, true) ~= nil, "the word says it is off")
end

tests["enchant e2e: a hand that had poison: gone is said once"] = function(t)
    local c, addon = start()
    addon.settings:set(E.SETTING, true); c.advance(6, 10)
    local from = #c.printed + 1
    c.setWeaponEnchant({ main = { has = false }, off = { has = true, left = 1700 } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(1, 2)
    local said = saidSince(c, from)
    t.eq(#said, 1, "one line")
    t.ok(said[1] and said[1]:find("main-hand weapon enchant is gone", 1, true) ~= nil, tostring(said[1]))
    c.advance(30, 30)
    t.eq(#saidSince(c, from), 1, "not said again while it stays gone")
    -- Put on again, then gone again: said again.
    c.setWeaponEnchant({ main = { has = true, left = 1800 }, off = { has = true, left = 1700 } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(1, 2)
    c.setWeaponEnchant({ main = { has = false }, off = { has = true, left = 1690 } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(1, 2)
    t.eq(#saidSince(c, from), 2, "gone again after it was put on: said again")
end

tests["enchant e2e: running low is said once, then gone once"] = function(t)
    local c, addon = start()
    addon.settings:set(E.SETTING, true); c.advance(6, 10)
    local from = #c.printed + 1
    c.setWeaponEnchant({ main = { has = true, left = 240 }, off = { has = true, left = 1700 } })
    c.advance(6, 10)
    local said = saidSince(c, from)
    t.eq(#said, 1, "one line")
    t.ok(said[1] and said[1]:find("runs out in 4 minutes", 1, true) ~= nil, tostring(said[1]))
    c.setWeaponEnchant({ main = { has = true, left = 200 }, off = { has = true, left = 1690 } })
    c.advance(6, 10)
    t.eq(#saidSince(c, from), 1, "still low: not said again")
    c.setWeaponEnchant({ main = { has = false }, off = { has = true, left = 1680 } })
    c.advance(6, 10)
    said = saidSince(c, from)
    t.eq(#said, 2, "gone: one more line")
    t.ok(said[2] and said[2]:find("is gone", 1, true) ~= nil, tostring(said[2]))
end

tests["enchant e2e: a hand never seen with an enchant is not asked about"] = function(t)
    local c, addon = start({ enchant = { main = { has = true, left = 1800 }, off = { has = false } } })
    addon.settings:set(E.SETTING, true); c.advance(6, 10)
    local from = #c.printed + 1
    c.advance(30, 30)
    t.eq(#saidSince(c, from), 0, "a bare off-hand from the start: nothing said")
end

tests["enchant e2e: in a fight the line waits for its end"] = function(t)
    local c, addon = start()
    addon.settings:set(E.SETTING, true); c.advance(6, 10)
    c.setCombat(true); c.advance(1, 2)
    local from = #c.printed + 1
    c.setWeaponEnchant({ main = { has = false }, off = { has = true, left = 1700 } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(20, 20)
    t.eq(#saidSince(c, from), 0, "in a fight: nothing said")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(1, 2)
    local said = saidSince(c, from)
    t.eq(#said, 1, "the fight over: said once")
    t.ok(said[1] and said[1]:find("is gone", 1, true) ~= nil, tostring(said[1]))
end

local function problems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

tests["enchant e2e: no read, or a read that raises: nothing said, nothing escapes"] = function(t)
    local c, addon = start({ enchant = "none" })
    addon.settings:set(E.SETTING, true); c.advance(6, 10)
    t.ok(word(c):find("no weapon enchant read", 1, true) ~= nil, "the word says there is no read")
    c.setWeaponEnchant({ main = { has = true, left = 1800 } }); c.advance(6, 10)
    local before = problems(addon)
    c.setWeaponEnchantFails(true)
    local from = #c.printed + 1
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(20, 20)
    t.eq(#saidSince(c, from), 0, "the read raises: nothing said")
    t.eq(problems(addon), before, "the raise did not escape the module")
    t.ok(word(c):find("no weapon enchant read", 1, true) ~= nil, "the word: not read")
    c.setWeaponEnchantFails(false)
    from = #c.printed + 1
    c.setWeaponEnchant({ main = { has = false } })
    c.fire("UNIT_INVENTORY_CHANGED", "player"); c.advance(1, 2)
    t.eq(#saidSince(c, from), 1, "read again: the bare hand is said")
end

tests["enchant e2e: the setting is read back after a reload"] = function(t)
    local c, addon = start()
    addon.settings:set(E.SETTING, true); c.advance(3, 5)
    local _, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(E.SETTING), true, "the setting read back")
end

return tests
