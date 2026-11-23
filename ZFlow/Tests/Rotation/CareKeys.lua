local _, ns = ...
-- P-KEYS slice A (S12 care key, CHOOSE-2 friend heal, PRIEST-1, SHAMAN-1):
-- the care key plan and its attributes, the friend heal step, the class
-- rows, and the key frame's own-rows hook. The class tables are the
-- add-on's own (ns.Packs); which spells are known is made up here. Not
-- tested in game.
local tests = {}

local CK = ns.CareKeys
local R = ns.Rotation
local K = ns.KeyFrame

-- A snapshot whose spells are known, usable and off cooldown.
local function snap(names, over)
    local spells = {}
    for _, name in ipairs(names) do
        spells[name] = { known = true, usable = true, onCooldown = false }
    end
    local s = { dead = false, inCombat = false, spells = spells }
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

local PRIEST_KNOWN = { "Flash Heal", "Lesser Heal", "Heal", "Renew", "Dispel Magic", "Cure Disease",
    "Power Word: Shield", "Resurrection" }

tests["care plan: key quick heal on you, ctrl heal over time, shift other heal, alt item, more cure"] = function(t)
    local plan = CK.Plan(ns.Packs.PRIEST, snap(PRIEST_KNOWN), nil, 5512)
    t.eq(plan.key, { spell = "Flash Heal", unit = "player" }, "the quick heal")
    t.eq(plan.ctrl, { spell = "Renew", unit = "player" }, "the heal over time")
    t.eq(plan.shift, { spell = "Lesser Heal", unit = "player" }, "another heal, not the one on the key")
    t.eq(plan.alt, { item = 5512 }, "the healthstone or potion (N8)")
    t.eq(plan.more, { spell = "Dispel Magic", unit = "player" }, "the first cure; no bandage")
end

tests["care plan: one heal only leaves ctrl and shift empty"] = function(t)
    local plan = CK.Plan(ns.Packs.SHAMAN, snap({ "Healing Wave", "Cure Poison" }), nil, nil)
    t.eq(plan.key, { spell = "Healing Wave", unit = "player" })
    t.eq(plan.ctrl, nil, "a shaman has no heal over time")
    t.eq(plan.shift, nil, "not the same heal again")
    t.eq(plan.alt, nil, "no item carried")
    t.eq(plan.more, { spell = "Cure Poison", unit = "player" })
end

tests["care plan: the friend heal takes the key, the rest stays on you"] = function(t)
    local friend = { spell = "Heal", unit = "party2", step = "friendHeal" }
    local plan = CK.Plan(ns.Packs.PRIEST, snap(PRIEST_KNOWN), friend, nil)
    t.eq(plan.key, { spell = "Heal", unit = "party2" }, "the friend's heal")
    t.eq(plan.ctrl, { spell = "Renew", unit = "player" })
    t.eq(plan.shift, { spell = "Lesser Heal", unit = "player" }, "the quick heal is still not on shift")
    t.eq(plan.more, { spell = "Dispel Magic", unit = "player" })
end

tests["care plan: a spell not known or not read is left out; no class table or snapshot: nil"] = function(t)
    local s = snap({ "Lesser Heal" })
    s.spells["Flash Heal"] = { known = false }
    local plan = CK.Plan(ns.Packs.PRIEST, s, nil, nil)
    t.eq(plan.key, { spell = "Lesser Heal", unit = "player" })
    t.eq(plan.ctrl, nil, "Renew not read: left out")
    t.eq(plan.more, nil, "no cure known")
    t.eq(next(CK.Plan(ns.Packs.WARRIOR, snap({}), nil, nil)), nil, "a warrior: an empty plan")
    t.eq(CK.Plan(nil, snap({}), nil, nil), nil, "no class table")
    t.eq(CK.Plan(ns.Packs.PRIEST, nil, nil, nil), nil, "no snapshot")
end

tests["care rows: the spell type on the unit, the item type on Alt only, never a macro"] = function(t)
    local rows = CK.Rows({
        key = { spell = "Flash Heal", unit = "player" },
        ctrl = { spell = "Renew", unit = "player" },
        alt = { item = 5512 },
    })
    local by, count = {}, 0
    for _, row in ipairs(rows) do
        count = count + 1
        by[row.attr] = row.value
        t.ok(row.value ~= "macro", "no macro type: " .. row.attr)
        t.ok(not tostring(row.attr):find("macro", 1, true), "no macro attribute: " .. row.attr)
    end
    t.eq(count, 16, "key and four modifiers, three attributes each, and the item on Alt")
    t.eq(by.type, "spell"); t.eq(by.spell, "Flash Heal"); t.eq(by.unit, "player")
    t.eq(by["*type-ctrl"], "spell"); t.eq(by["*spell-ctrl"], "Renew"); t.eq(by["*unit-ctrl"], "player")
    t.eq(by["*type-shift"], nil, "nothing on Shift: cleared")
    t.eq(by["*type-alt"], "item"); t.eq(by["*item-alt"], "item:5512"); t.eq(by["*spell-alt"], nil)
    t.eq(by["*type-more"], nil)
    for _, row in ipairs(CK.Rows(nil)) do t.eq(row.value, nil, "no plan: every part cleared, " .. row.attr) end
end

-- A hand-made secure button with a lock the test turns.
local function button(lockRef)
    local h = { attrs = {}, sets = 0 }
    function h.set(attr, value)
        h.sets = h.sets + 1
        if lockRef.lock ~= false then return false, "lockdown" end
        h.attrs[attr] = value
        return true
    end
    function h.get(attr) return h.attrs[attr] end
    return h
end

tests["key frame: own rows are set out of a fight only, and read back"] = function(t)
    local lock = { lock = nil }
    local h = button(lock)
    local kf = K.New({ button = h, lockdown = function() return lock.lock end,
        rows = CK.Rows, signature = CK.Signature })
    local st = kf:want({ key = { spell = "Flash Heal", unit = "player" } })
    t.eq(st.state, "waiting", "lock not known: waits")
    t.eq(st.reason, "lockdownUnknown")
    t.eq(h.sets, 0, "nothing asked of the button")
    lock.lock = true
    t.eq(kf:try(true).state, "waiting", "in a fight: waits")
    t.eq(h.sets, 0)
    lock.lock = false
    st = kf:try(true)
    t.eq(st.state, "set")
    t.eq(h.attrs.spell, "Flash Heal"); t.eq(h.attrs.unit, "player"); t.eq(h.attrs.type, "spell")
    t.eq(kf:want(nil).state, "cleared", "nothing wanted: cleared")
    t.eq(h.attrs.spell, nil)
end

tests["key frame: own rows that cannot be made fail plainly"] = function(t)
    local kf = K.New({ button = button({ lock = false }), lockdown = function() return false end,
        rows = function() error("bad plan") end })
    local st = kf:want({ key = { spell = "Heal", unit = "player" } })
    t.eq(st.state, "failed")
    t.eq(st.reason, "plan")
end

-- CHOOSE-2: the friend heal.
local function friendSnap(friends, over)
    local s = snap(PRIEST_KNOWN, over)
    s.friends = friends
    return s
end

tests["friend heal: a hurt friendly target gets the first heal ready"] = function(t)
    local got = R.FriendHeal(friendSnap({ { unit = "target", dead = false, hurt = true } }), ns.Packs.PRIEST)
    t.eq(got and got.spell, "Flash Heal"); t.eq(got and got.unit, "target")
    t.eq(got and got.step, "friendHeal")
    t.ok(got ~= nil and not tostring(got.reason):find("target", 1, true), "the reason names no unit")
end

tests["friend heal: a dead friend out of a fight is revived, never in a fight"] = function(t)
    local friends = { { unit = "party1", dead = false, hurt = false }, { unit = "party2", dead = true } }
    local got = R.FriendHeal(friendSnap(friends), ns.Packs.PRIEST)
    t.eq(got and got.spell, "Resurrection"); t.eq(got and got.unit, "party2")
    t.eq(R.FriendHeal(friendSnap(friends, { inCombat = true }), ns.Packs.PRIEST), nil, "in a fight: no revive")
    t.eq(R.FriendHeal(friendSnap(friends, { inCombat = "nil" }), ns.Packs.PRIEST), nil,
        "not known whether in a fight: no revive")
    local shaman = snap({ "Healing Wave", "Ancestral Spirit" })
    shaman.friends = friends
    got = R.FriendHeal(shaman, ns.Packs.SHAMAN)
    t.eq(got and got.spell, "Ancestral Spirit"); t.eq(got and got.unit, "party2")
end

tests["friend heal: a cure for a friend's debuff the class removes"] = function(t)
    local s = friendSnap({ { unit = "party1", dead = false, hurt = false, debuffTypes = { Magic = "Sleep" } } })
    local got = R.FriendHeal(s, ns.Packs.PRIEST)
    t.eq(got and got.spell, "Dispel Magic"); t.eq(got and got.unit, "party1")
    s = friendSnap({ { unit = "party1", dead = false, hurt = false, debuffTypes = { Curse = "Hex" } } })
    t.eq(R.FriendHeal(s, ns.Packs.PRIEST), nil, "a curse: a priest removes none")
end

tests["friend heal: a friend known out of reach is passed by; reach not known never excludes (PK-3)"] = function(t)
    local far = {}
    for _, name in ipairs({ "Flash Heal", "Lesser Heal", "Heal", "Renew", "Power Word: Shield" }) do far[name] = false end
    local friends = {
        { unit = "party1", dead = false, hurt = true, reach = far },
        { unit = "party2", dead = false, hurt = true },
    }
    local got = R.FriendHeal(friendSnap(friends), ns.Packs.PRIEST)
    t.eq(got and got.unit, "party2", "the first friend is out of reach: the next")
    t.eq(got and got.spell, "Flash Heal")
    got = R.FriendHeal(friendSnap({ { unit = "party1", dead = false, hurt = true, reach = { ["Flash Heal"] = false } } }),
        ns.Packs.PRIEST)
    t.eq(got and got.spell, "Lesser Heal", "one heal out of reach: the next heal that may reach")
    got = R.FriendHeal(friendSnap({ { unit = "party1", dead = false, hurt = true, reach = {} } }), ns.Packs.PRIEST)
    t.eq(got and got.unit, "party1", "reach not known: not excluded")
    got = R.FriendHeal(friendSnap({ { unit = "party1", dead = false, hurt = true, reach = { ["Flash Heal"] = true } } }),
        ns.Packs.PRIEST)
    t.eq(got and got.spell, "Flash Heal", "in reach")
    got = R.FriendHeal(friendSnap({ { unit = "party1", dead = true, reach = { Resurrection = false } },
        { unit = "party2", dead = true } }), ns.Packs.PRIEST)
    t.eq(got and got.unit, "party2", "a revive out of reach: the next dead friend")
    got = R.FriendHeal(friendSnap({ { unit = "party1", dead = false, hurt = false, debuffTypes = { Magic = "Sleep" },
        reach = { ["Dispel Magic"] = false } } }), ns.Packs.PRIEST)
    t.eq(got, nil, "a cure out of reach: none")
end

tests["friends: with the pack, each care spell's reach is read; not known stays not known (PK-3)"] = function(t)
    local c = ns.make.fakeClient()
    c.setParty({ { unit = "party1", guid = "Player-1" } })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setSpellId("Flash Heal", 2061); c.setSpellId("Dispel Magic", 527)
    local list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and list[1].reach, {}, "late data: no reach read yet, nothing excluded")
    c.setReach("party1", 2061, false); c.setReach("party1", 527, true)
    list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and list[1].reach, { ["Flash Heal"] = false, ["Dispel Magic"] = true })
    c.setReachFails(true)
    list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and #list, 1, "the reach read raised: the friend stays")
    t.eq(list and list[1].reach, {}, "the reach read raised: not known")
    c.setReachFails(false)
    list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and list[1].reach and list[1].reach["Flash Heal"], false, "the read recovers")
    t.eq(CK.Friends(c)[1].reach, nil, "no pack: no reach read")
end

-- K7-1 (P-KEYS-RAID-REACH): in a raid the reach is read for raid units the
-- same way; a spell whose reach is not given stays not known, never false.
tests["friends: in a raid, each care spell's reach is read for the raid unit; not known stays not known (K7-1)"] = function(t)
    local c = ns.make.fakeClient()
    c.setParty({ { unit = "raid3", guid = "Player-3" } })
    c.setUnitCare("raid3", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setSpellId("Flash Heal", 2061); c.setSpellId("Dispel Magic", 527)
    c.setReach("raid3", 2061, true)
    local list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and list[1].unit, "raid3")
    t.eq(list and list[1].reach, { ["Flash Heal"] = true }, "Dispel Magic not given: left out, not known")
    c.setReach("raid3", 527, false)
    list = CK.Friends(c, ns.Packs.PRIEST)
    t.eq(list and list[1].reach, { ["Flash Heal"] = true, ["Dispel Magic"] = false })
end

tests["friend heal: Shield when no heal is ready; a skipped or unread spell is passed by"] = function(t)
    local s = friendSnap({ { unit = "target", dead = false, hurt = true } })
    for _, name in ipairs({ "Flash Heal", "Lesser Heal", "Heal", "Renew" }) do s.spells[name].onCooldown = true end
    local got = R.FriendHeal(s, ns.Packs.PRIEST)
    t.eq(got and got.spell, "Power Word: Shield")
    s = friendSnap({ { unit = "target", dead = false, hurt = true } })
    s.spells["Flash Heal"].onCooldown = nil
    got = R.FriendHeal(s, ns.Packs.PRIEST, { skip = { ["Lesser Heal"] = true } })
    t.eq(got and got.spell, "Heal", "cooldown not read and skipped: the next heal")
end

tests["friend heal: nobody read, nobody hurt, or no care rows: nothing"] = function(t)
    local got, note = R.FriendHeal(friendSnap(nil), ns.Packs.PRIEST)
    t.eq(got, nil); t.ok(note ~= nil, "a note")
    t.eq(R.FriendHeal(friendSnap({ { unit = "party1", dead = false, hurt = false } }), ns.Packs.PRIEST), nil)
    t.eq(R.FriendHeal(friendSnap({ { unit = "party1", dead = false } }), ns.Packs.PRIEST), nil,
        "hurt not known: not hurt")
    t.eq(R.FriendHeal(friendSnap({ { unit = "party1", hurt = true } }), ns.Packs.WARRIOR), nil, "no care rows")
    t.eq(R.FriendHeal(nil, ns.Packs.PRIEST), nil)
end

tests["friend heal: not one of the main key's steps"] = function(t)
    for _, name in ipairs(R.STEPS) do t.ok(name ~= "friendHeal", "not a main step: " .. name) end
    t.ok(type(R._steps.friendHeal) == "function", "a step of its own")
end

-- PRIEST-1 and SHAMAN-1: the rows for another player.
tests["packs: priest and shaman care rows, each spell a first guess with a row"] = function(t)
    local want = {
        PRIEST = { revive = "Resurrection", has = { "Flash Heal", "Power Word: Shield" } },
        SHAMAN = { revive = "Ancestral Spirit", has = { "Healing Wave" } },
    }
    for class, w in pairs(want) do
        local p = ns.Packs[class]
        t.ok(type(p.care) == "table", class .. ": care rows")
        if type(p.care) == "table" then
            t.eq(p.care.revive, w.revive, class)
            t.eq(p.care.evidence, "first guess", class)
            local set = {}
            for _, name in ipairs(p.care.friend or {}) do
                set[name] = true
                t.ok(p.spells[name] ~= nil, class .. ": a spell row for " .. name)
            end
            for _, name in ipairs(w.has) do t.ok(set[name], class .. ": " .. name .. " for a friend") end
            t.eq(p.spells[w.revive] and p.spells[w.revive].evidence, "first guess", class .. " revive row")
        end
        local ok, problems = ns.PackCheck(p)
        t.ok(ok, class .. " pack checks: " .. table.concat(type(problems) == "table" and problems or {}, "; "))
    end
end

tests["pack check: a care spell with no row is a problem"] = function(t)
    local p = {}
    for k, v in pairs(ns.Packs.SHAMAN) do p[k] = v end
    p.care = { friend = { "Chain Heal" }, revive = "Ancestral Spirit", evidence = "first guess" }
    t.eq(ns.PackCheck(p), false, "Chain Heal has no spell row")
end

-- The friend list, from the client.
tests["friends: your party, never yourself or a foe; your target by its group token, first"] = function(t)
    local c = ns.make.fakeClient()
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setParty({ { unit = "party1", guid = "Player-1" }, { unit = "party2", guid = "Player-2" } })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = true })
    c.setUnitCare("party2", { exists = true, friend = true, isSelf = false, dead = false, hurt = false })
    c.setUnitDebuffs("party2", { Disease = "Plague" })
    local list = CK.Friends(c)
    t.eq(list and #list, 2, "no target token: the party only")
    if not list then return end
    t.eq(list[1], { unit = "party1", dead = true })
    t.eq(list[2], { unit = "party2", dead = false, hurt = false, debuffTypes = { Disease = "Plague" } })
    c.setGuid("target", "Player-2")
    list = CK.Friends(c)
    t.eq(list and #list, 2, "your target in the group: listed once")
    t.eq(list and list[1].unit, "party2", "your target first, by its group token")
    t.eq(list and list[2].unit, "party1")
    c.setUnitCare("party1", { exists = true, friend = false, dead = false, hurt = true })
    t.eq(#CK.Friends(c), 1, "a foe: left out")
    for _, e in ipairs(CK.Friends(c)) do t.ok(e.unit ~= "target", "never the target token") end
end

tests["friends: a friendly target not in your group is left out"] = function(t)
    local c = ns.make.fakeClient()
    c.setGuid("target", "Player-9")
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setParty({ { unit = "party1", guid = "Player-1" } })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = false })
    local list = CK.Friends(c)
    t.eq(list and #list, 1)
    t.eq(list and list[1].unit, "party1")
    c.setParty({})
    t.eq(CK.Friends(c), nil, "no group, nothing read: not the target")
end

tests["friends: the target token is the group row whose guid matches"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(CK.TargetUnit(c), nil, "nothing known")
    c.setParty({ { unit = "raid3", guid = "Player-3" }, { unit = "raid7", guid = "Player-7" } })
    t.eq(CK.TargetUnit(c), nil, "no target guid")
    c.setGuid("target", "Player-7")
    t.eq(CK.TargetUnit(c), "raid7")
    c.setGuid("target", "Creature-1")
    t.eq(CK.TargetUnit(c), nil, "not in the group")
    c.setGuid("target", "Player-3"); c.setPartyFails(true)
    t.eq(CK.TargetUnit(c), nil, "the party read raised")
    c.setPartyFails(false)
    t.eq(CK.TargetUnit(c), "raid3", "the read recovers")
    t.eq(CK.TargetUnit(nil), nil)
end

tests["friends: a read that fails leaves that unit out; no reads at all is nil"] = function(t)
    local c = ns.make.fakeClient()
    c.setGuid("target", "Player-1")
    c.setParty({ { unit = "party1", guid = "Player-1" } })
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setUnitCare("party1", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setPartyFails(true)
    t.eq(CK.Friends(c), nil, "the party read raised: nothing read, never the target token")
    c.setPartyFails(false); c.setUnitCareFails(true)
    t.eq(CK.Friends(c), nil, "nothing read")
    c.setUnitCareFails(false)
    local list = CK.Friends(c) or {}
    t.eq(#list, 1, "the read recovers")
    t.eq(list[1] and list[1].unit, "party1")
    t.eq(CK.Friends(nil), nil)
end

return tests
