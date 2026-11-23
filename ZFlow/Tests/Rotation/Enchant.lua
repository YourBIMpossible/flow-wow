local _, ns = ...
-- N64 (lead section 243): the weapon enchant read, checked, and what is
-- said of it. Made-up answers in the shape of Plexy's P-READS note (item
-- 5). Not tested in game.
local tests = {}

local E = ns.Enchant

local function client(answer)
    return { weaponEnchant = function() return answer end }
end

tests["enchant: the read is checked: has a boolean, left a number of seconds"] = function(t)
    local got = E.Read(client({
        main = { has = true, left = 1200, charges = 40 },
        off = { has = "yes", left = -5, charges = 0 / 0 },
    }))
    t.eq(got.main, { has = true, left = 1200, charges = 40 })
    t.eq(got.off, {}, "an answer not of the shape: not known")
end

tests["enchant: no read, a read that raises, or no table: nil"] = function(t)
    t.eq(E.Read({}), nil, "no read on this client")
    t.eq(E.Read(nil), nil)
    t.eq(E.Read(client(nil)), nil, "no answer")
    t.eq(E.Read(client("main")), nil, "not a table")
    t.eq(E.Read({ weaponEnchant = function() error("read failed") end }), nil, "the read raised")
end

tests["enchant: judged gone only for a hand seen with one"] = function(t)
    t.eq(E.Judge({ has = true, left = 1200 }, true), "on")
    t.eq(E.Judge({ has = true }, false), "on", "on, the time left not known")
    t.eq(E.Judge({ has = true, left = E.WARN }, true), "low")
    t.eq(E.Judge({ has = true, left = 30 }, nil), "low")
    t.eq(E.Judge({ has = false }, true), "gone", "it had one")
    t.eq(E.Judge({ has = false }, nil), nil, "never seen with one: not asked about")
    t.eq(E.Judge({}, true), nil, "not known")
    t.eq(E.Judge(nil, true), nil)
end

tests["enchant: the word says what it knows, in plain words"] = function(t)
    local off = E.Lines({ on = false })
    t.ok(off[1]:find("is off", 1, true) ~= nil, "off: says so")
    local none = E.Lines({ on = true, read = nil })
    t.ok(none[1]:find("no weapon enchant read", 1, true) ~= nil, "no read: says so")
    local lines = E.Lines({
        on = true,
        read = { main = { has = true, left = 125 }, off = { has = false } },
        seen = { off = true },
    })
    t.eq(lines[1], "main-hand: enchant on, 3 minutes left.")
    t.ok(lines[2]:find("off-hand: no enchant", 1, true) == 1, "the off-hand bare")
    t.ok(lines[2]:find("reminded", 1, true) ~= nil, "it had one: reminded")
    lines = E.Lines({ on = true, read = { main = { has = true } } })
    t.eq(lines[1], "main-hand: enchant on, the time left not known.")
    t.eq(lines[2], "off-hand: not known.")
end

tests["enchant: the setting names its topic and words"] = function(t)
    local found
    for row in ns.settings:each() do
        if row.key == E.SETTING then found = row end
    end
    t.ok(found ~= nil, "the setting row")
    if not found then return end
    t.eq(found.default, false, "off by default")
    t.eq(found.scope, "char")
    t.eq(found.group, "buffs")
    local words = table.concat(found.synonyms or {}, " ")
    t.ok(words:find("poison", 1, true) ~= nil, "poison")
    t.ok(words:find("imbue", 1, true) ~= nil, "imbue")
end

return tests
