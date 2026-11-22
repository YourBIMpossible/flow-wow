-- Fight types (G28) and the death report (G30), both read by the pure fight
-- reader. Every event list here is written by hand; none is from a real
-- fight. No game client is involved.
local _, ns = ...

local ME, MOB, OTHER = "Player-1-0000AAAA", "Creature-0-1-0000CCCC", "Player-1-0000DDDD"
-- The affiliation bits the reader takes as its first guess.
local MINE, PARTY, RAID, OUTSIDER = 1, 2, 4, 8

local function spell(src, srcName, srcFlags, dst, dstName, dstFlags, name, amount)
    return { 1000, "SPELL_DAMAGE", false, src, srcName, srcFlags, 0, dst, dstName, dstFlags, 0, 1, name, 1, amount }
end
local function swing(src, srcName, srcFlags, dst, dstName, dstFlags, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, srcFlags, 0, dst, dstName, dstFlags, 0, amount }
end
local function fall(dst, dstName, amount)
    return { 1000, "ENVIRONMENTAL_DAMAGE", false, nil, nil, nil, 0, dst, dstName, MINE, 0, "Falling", amount }
end

local function feed(rec, at, ev)
    return rec:event(at, unpack(ev, 1, 16))
end

local function recorder()
    local rec = ns.Fights.New()
    rec:setMe(ME, nil)
    return rec
end

local function mine(rec, at, amount)
    feed(rec, at, swing(ME, "Me", MINE, MOB, "Boar", OUTSIDER, amount or 10))
end
local function hitMe(rec, at, amount)
    feed(rec, at, swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, amount or 12))
end

return {
    ["fight types: a fight whose target rank was never read is unknown"] = function(t)
        local rec = recorder()
        rec:enter(1)
        mine(rec, 2)
        rec:leave(3)
        local f = rec:list()[1]
        t.eq(f.group, false)
        t.eq(f.elite, nil)
        t.eq(ns.Fights.Kind(f), "unknown")
    end,

    ["fight types: alone against a target read as normal is solo"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:sawRank("normal")
        mine(rec, 2)
        rec:leave(3)
        local f = rec:list()[1]
        t.eq(f.elite, false)
        t.eq(ns.Fights.Kind(f), "solo")
    end,

    ["fight types: an elite, rare elite or boss target makes the fight elite, and a later normal one does not undo it"] = function(t)
        local ranks = { "elite", "rareelite", "worldboss" }
        for i = 1, #ranks do
            local rec = recorder()
            rec:enter(1)
            rec:sawRank(ranks[i])
            rec:sawRank("normal")
            mine(rec, 2)
            rec:leave(3)
            t.eq(ns.Fights.Kind(rec:list()[1]), "elite")
        end
    end,

    ["fight types: a party or raid member in the log makes the fight group"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:sawRank("normal")
        t.eq(feed(rec, 2, spell(OTHER, "Friend", PARTY, MOB, "Boar", OUTSIDER, "Wrath", 50)), false)
        rec:leave(3)
        t.eq(rec:list()[1].group, true)
        t.eq(rec:list()[1].dealt.total, 0)
        t.eq(ns.Fights.Kind(rec:list()[1]), "group")

        rec:enter(4)
        rec:sawRank("elite")
        feed(rec, 5, spell(MOB, "Boar", OUTSIDER, OTHER, "Friend", RAID, "Bite", 50))
        rec:leave(6)
        t.eq(ns.Fights.Kind(rec:list()[1]), "group")
    end,

    ["fight types: a stranger in the log does not make a group"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:sawRank("normal")
        feed(rec, 2, spell(OTHER, "Stranger", OUTSIDER, MOB, "Boar", OUTSIDER, "Wrath", 50))
        mine(rec, 2)
        rec:leave(3)
        t.eq(ns.Fights.Kind(rec:list()[1]), "solo")
    end,

    ["fight types: when no event said who is in your group the type is unknown, not solo"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:sawRank("normal")
        feed(rec, 2, swing(ME, "Me", nil, MOB, "Boar", nil, 10))
        rec:leave(3)
        local f = rec:list()[1]
        t.eq(f.group, nil)
        t.eq(f.dealt.total, 10)
        t.eq(ns.Fights.Kind(f), "unknown")
        -- and an elite that was read does not settle it either
        rec:enter(4)
        rec:sawRank("elite")
        rec:leave(5)
        t.eq(ns.Fights.Kind(rec:list()[1]), "unknown")
    end,

    ["fight types: a rank word the reader does not know is not read as normal"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:sawRank("something new")
        rec:sawRank(nil)
        rec:sawRank(7)
        mine(rec, 2)
        rec:leave(3)
        t.eq(rec:list()[1].elite, nil)
        t.eq(ns.Fights.Kind(rec:list()[1]), "unknown")
    end,

    ["fight types: a rank seen outside a fight belongs to no fight"] = function(t)
        local rec = recorder()
        rec:sawRank("elite")
        rec:enter(1)
        rec:sawRank("normal")
        mine(rec, 2)
        rec:leave(3)
        rec:sawRank("elite")
        rec:enter(4)
        mine(rec, 5)
        rec:leave(6)
        local list = rec:list()
        t.eq(ns.Fights.Kind(list[2]), "solo")
        t.eq(ns.Fights.Kind(list[1]), "unknown")
    end,

    ["fight types: the type of something that is not a fight is unknown"] = function(t)
        t.eq(ns.Fights.Kind(nil), "unknown")
        t.eq(ns.Fights.Kind({}), "unknown")
    end,

    ["fight types: the list says the type of each fight"] = function(t)
        local rec = recorder()
        rec:enter(0)
        rec:sawRank("normal")
        mine(rec, 1)
        rec:leave(4)
        rec:enter(10)
        rec:sawRank("elite")
        mine(rec, 11)
        rec:leave(12)
        rec:enter(20)
        feed(rec, 21, spell(OTHER, "Friend", PARTY, MOB, "Boar", OUTSIDER, "Wrath", 50))
        rec:leave(23)
        t.eq(ns.Fights.Lines(rec:list(), 30), {
            "fights (3 kept, newest first):",
            "1. 3s (group): dealt 0, taken 0, healing done 0, healing received 0",
            "2. 2s (elite): dealt 10 in 1 hit, taken 0, healing done 0, healing received 0",
            "3. 4s (solo): dealt 10 in 1 hit, taken 0, healing done 0, healing received 0",
        })
    end,

    ["death: before any death there is none"] = function(t)
        t.eq(recorder():death(), nil)
    end,

    ["death: the hits on you in the seconds before it are kept, oldest first, and older ones are not"] = function(t)
        local rec = recorder()
        rec:enter(0)
        hitMe(rec, 1, 5)
        feed(rec, 14, spell(MOB, "Kobold Mage", OUTSIDER, ME, "Me", MINE, "Fireball", 450))
        hitMe(rec, 18.5, 12)
        mine(rec, 19, 99)
        local d = rec:died(20)
        t.eq(d.at, 20)
        t.eq(d.timed, true)
        t.eq(d.window, ns.Fights.WINDOW)
        t.eq(d.hits, {
            { before = 6, name = "Fireball", amount = 450, from = "Kobold Mage" },
            { before = 1.5, name = ns.Fights.MELEE, amount = 12, from = "Boar" },
        })
        t.eq(rec:death(), d)
    end,

    ["death: what is given out is a copy"] = function(t)
        local rec = recorder()
        hitMe(rec, 1, 5)
        local d = rec:died(2)
        d.hits[1].amount = 999
        d.hits[2] = { before = 0, name = "made up", amount = 1 }
        t.eq(rec:death().hits, { { before = 1, name = ns.Fights.MELEE, amount = 5, from = "Boar" } })
    end,

    ["death: a death outside a fight still has what hit you"] = function(t)
        local rec = recorder()
        feed(rec, 7, fall(ME, "Me", 300))
        local d = rec:died(7)
        t.eq(d.hits, { { before = 0, name = "falling", amount = 300 } })
        t.eq(rec:list(), {})
    end,

    ["death: an amount that was not read is kept as not read"] = function(t)
        local rec = recorder()
        feed(rec, 3, spell(MOB, "Kobold Mage", OUTSIDER, ME, "Me", MINE, "Fireball", nil))
        local d = rec:died(4)
        t.eq(#d.hits, 1)
        t.eq(d.hits[1].amount, nil)
        t.eq(d.hits[1].name, "Fireball")
    end,

    ["death: without times the last few hits are given, marked as not timed"] = function(t)
        local rec = recorder()
        for i = 1, 8 do hitMe(rec, nil, i) end
        local d = rec:died(nil)
        t.eq(d.timed, false)
        t.eq(d.at, nil)
        t.eq(#d.hits, ns.Fights.UNTIMED)
        t.eq(d.hits[1].amount, 8 - ns.Fights.UNTIMED + 1)
        t.eq(d.hits[#d.hits].amount, 8)
        t.eq(d.hits[1].before, nil)
    end,

    ["death: a hit without a time is left out of a timed report"] = function(t)
        local rec = recorder()
        hitMe(rec, nil, 1)
        hitMe(rec, 5, 2)
        local d = rec:died(6)
        t.eq(#d.hits, 1)
        t.eq(d.hits[1].amount, 2)
    end,

    ["death: only a fixed number of hits is remembered"] = function(t)
        local rec = recorder()
        for i = 1, ns.Fights.RECENT + 15 do hitMe(rec, 100, i) end
        local d = rec:died(100)
        t.eq(#d.hits, ns.Fights.RECENT)
        t.eq(d.hits[#d.hits].amount, ns.Fights.RECENT + 15)
        t.eq(d.hits[1].amount, 16)
    end,

    ["death: hits on others are not in it, and without your id nothing is"] = function(t)
        local rec = recorder()
        feed(rec, 1, swing(MOB, "Boar", OUTSIDER, OTHER, "Friend", PARTY, 40))
        mine(rec, 1, 10)
        t.eq(rec:died(2).hits, {})
        local blind = ns.Fights.New()
        hitMe(blind, 1, 12)
        t.eq(blind:died(2).hits, {})
    end,

    ["death: the text names each hit, how long before, and the total"] = function(t)
        local rec = recorder()
        feed(rec, 14, spell(MOB, "Kobold Mage", OUTSIDER, ME, "Me", MINE, "Fireball", 450))
        hitMe(rec, 18.5, 12)
        feed(rec, 19, spell(MOB, "Kobold Mage", OUTSIDER, ME, "Me", MINE, "Frostbolt", nil))
        feed(rec, 20, fall(ME, "Me", 300))
        t.eq(ns.Fights.DeathLines(rec:died(20)), {
            "you died. Damage taken in the last 10s: 762 in 3 hits, 1 amount not read. Oldest first:",
            "6.0s before: Fireball 450 from Kobold Mage",
            "1.5s before: melee 12 from Boar",
            "1.0s before: Frostbolt (amount not read) from Kobold Mage",
            "0.0s before: falling 300",
        })
    end,

    ["death: the text says so when nothing was read"] = function(t)
        local rec = recorder()
        t.eq(ns.Fights.DeathLines(rec:died(20)), { "you died. No damage to you was read in the last 10s." })
        t.eq(ns.Fights.DeathLines(rec:died(nil)), { "you died. No damage to you was read before it." })
        t.eq(ns.Fights.DeathLines(nil), { ns.Fights.NO_DEATH })
    end,

    ["death: the text without times says the times are not known"] = function(t)
        local rec = recorder()
        hitMe(rec, nil, 12)
        t.eq(ns.Fights.DeathLines(rec:died(nil)), {
            "you died. The last 1 hit on you (times not known), oldest first:",
            "melee 12 from Boar",
        })
    end,
}
