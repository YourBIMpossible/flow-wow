-- Fight recording (G29): the pure reader that turns combat-log events into
-- fight records. Every event list here is written by hand; none is from a
-- real fight. No game client is involved.
local _, ns = ...

local ME, PET, MOB, OTHER = "Player-1-0000AAAA", "Pet-0-1-0000BBBB", "Creature-0-1-0000CCCC", "Player-1-0000DDDD"

-- A spell event in the layout the reader takes as its first guess:
-- 1 time, 2 subevent, 4 source id, 5 source name, 8 target id, 9 target
-- name, 12 spell id, 13 spell name, 15 amount, 16 overhealing.
local function spell(sub, src, srcName, dst, dstName, id, name, amount, over)
    return { 1000, sub, false, src, srcName, 0, 0, dst, dstName, 0, 0, id, name, 1, amount, over }
end
local function swing(src, srcName, dst, dstName, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, 0, 0, dst, dstName, 0, 0, amount }
end
local function environment(dst, dstName, kind, amount)
    return { 1000, "ENVIRONMENTAL_DAMAGE", false, nil, nil, 0, 0, dst, dstName, 0, 0, kind, amount }
end

local function feed(rec, at, ev)
    return rec:event(at, unpack(ev, 1, 16))
end

local function recorder(keep)
    local rec = ns.Fights.New(keep)
    rec:setMe(ME, PET)
    return rec
end

return {
    ["fights: entering and leaving combat makes one fight with its start and end"] = function(t)
        local rec = recorder()
        t.eq(rec:list(), {})
        rec:enter(10)
        local open = rec:list()
        t.eq(#open, 1)
        t.eq(open[1].open, true)
        t.eq(open[1].started, 10)
        t.eq(open[1].ended, nil)
        rec:leave(25)
        local done = rec:list()
        t.eq(#done, 1)
        t.eq(done[1].open, false)
        t.eq(done[1].started, 10)
        t.eq(done[1].ended, 25)
    end,

    ["fights: entering twice opens one fight, and leaving with none open does nothing"] = function(t)
        local rec = recorder()
        rec:leave(5)
        t.eq(rec:list(), {})
        rec:enter(10)
        rec:enter(12)
        t.eq(#rec:list(), 1)
        t.eq(rec:list()[1].started, 10)
        rec:leave(20)
        rec:leave(30)
        t.eq(rec:list()[1].ended, 20)
    end,

    ["fights: damage you did is summed by spell, with its hits"] = function(t)
        local rec = recorder()
        rec:enter(1)
        t.eq(feed(rec, 2, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100)), true)
        t.eq(feed(rec, 3, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 150)), true)
        t.eq(feed(rec, 4, spell("SPELL_PERIODIC_DAMAGE", ME, "Me", MOB, "Boar", 8921, "Moonfire", 20)), true)
        rec:leave(9)
        local f = rec:list()[1]
        t.eq(f.dealt.total, 270)
        t.eq(f.dealt.hits, 3)
        t.eq(f.dealt.spells.Wrath, { total = 250, hits = 2 })
        t.eq(f.dealt.spells.Moonfire, { total = 20, hits = 1 })
        t.eq(f.taken.total, 0)
        t.eq(f.taken.hits, 0)
    end,

    ["fights: a swing is melee, and its amount is read from the swing place"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, swing(ME, "Me", MOB, "Boar", 33))
        feed(rec, 3, swing(MOB, "Boar", ME, "Me", 12))
        local f = rec:list()[1]
        t.eq(f.dealt.spells[ns.Fights.MELEE], { total = 33, hits = 1 })
        t.eq(f.taken.spells[ns.Fights.MELEE], { total = 12, hits = 1 })
        t.eq(f.dealt.total, 33)
        t.eq(f.taken.total, 12)
    end,

    ["fights: damage you took is summed by spell, and the surroundings count"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, spell("SPELL_DAMAGE", MOB, "Mage", ME, "Me", 133, "Fireball", 80))
        feed(rec, 3, environment(ME, "Me", "FALLING", 45))
        local f = rec:list()[1]
        t.eq(f.taken.total, 125)
        t.eq(f.taken.hits, 2)
        t.eq(f.taken.spells.Fireball, { total = 80, hits = 1 })
        t.eq(f.taken.spells["falling"], { total = 45, hits = 1 })
    end,

    ["fights: healing you did and healing you got are kept apart, with the overhealing"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, spell("SPELL_HEAL", ME, "Me", OTHER, "Friend", 5185, "Healing Touch", 200, 50))
        feed(rec, 3, spell("SPELL_PERIODIC_HEAL", OTHER, "Friend", ME, "Me", 774, "Rejuvenation", 30, 0))
        local f = rec:list()[1]
        t.eq(f.healed.total, 200)
        t.eq(f.healed.over, 50)
        t.eq(f.healed.spells["Healing Touch"], { total = 200, hits = 1 })
        t.eq(f.received.total, 30)
        t.eq(f.received.over, 0)
        t.eq(f.received.spells.Rejuvenation, { total = 30, hits = 1 })
        t.eq(f.dealt.total, 0)
    end,

    ["fights: a heal on yourself is healing done and healing got"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, spell("SPELL_HEAL", ME, "Me", ME, "Me", 5185, "Healing Touch", 90, 10))
        local f = rec:list()[1]
        t.eq(f.healed.total, 90)
        t.eq(f.received.total, 90)
    end,

    ["fights: an event that is not about you is not counted"] = function(t)
        local rec = recorder()
        rec:enter(1)
        t.eq(feed(rec, 2, spell("SPELL_DAMAGE", OTHER, "Friend", MOB, "Boar", 133, "Fireball", 500)), false)
        t.eq(feed(rec, 3, swing(MOB, "Boar", OTHER, "Friend", 70)), false)
        t.eq(feed(rec, 4, spell("SPELL_HEAL", OTHER, "Friend", OTHER, "Friend", 1, "Heal", 70)), false)
        local f = rec:list()[1]
        t.eq(f.dealt.total, 0)
        t.eq(f.taken.total, 0)
        t.eq(f.healed.total, 0)
        t.eq(f.received.total, 0)
    end,

    ["fights: your pet's damage is yours, and is marked as the pet's"] = function(t)
        local rec = recorder()
        rec:enter(1)
        t.eq(feed(rec, 2, swing(PET, "Cat", MOB, "Boar", 14)), true)
        t.eq(feed(rec, 3, spell("SPELL_DAMAGE", PET, "Cat", MOB, "Boar", 16827, "Claw", 22)), true)
        -- what the pet takes is not what you took
        t.eq(feed(rec, 4, swing(MOB, "Boar", PET, "Cat", 9)), false)
        local f = rec:list()[1]
        t.eq(f.dealt.total, 36)
        t.eq(f.dealt.spells[ns.Fights.PET .. ns.Fights.MELEE], { total = 14, hits = 1 })
        t.eq(f.dealt.spells[ns.Fights.PET .. "Claw"], { total = 22, hits = 1 })
        t.eq(f.taken.total, 0)
    end,

    ["fights: an amount that is not a number is counted as not read, never as 0 damage"] = function(t)
        local rec = recorder()
        rec:enter(1)
        t.eq(feed(rec, 2, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", nil)), true)
        t.eq(feed(rec, 3, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", "lots")), true)
        feed(rec, 4, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 40))
        local f = rec:list()[1]
        t.eq(f.dealt.total, 40)
        t.eq(f.dealt.hits, 1)
        t.eq(f.dealt.unread, 2)
        t.eq(f.dealt.spells.Wrath, { total = 40, hits = 1 })
    end,

    ["fights: a spell with no name is listed by its number, and one with neither is unknown"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, nil, 10))
        feed(rec, 3, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", nil, nil, 5))
        local f = rec:list()[1]
        t.eq(f.dealt.spells["spell 5176"], { total = 10, hits = 1 })
        t.eq(f.dealt.spells[ns.Fights.UNKNOWN], { total = 5, hits = 1 })
    end,

    ["fights: an event that is neither damage nor healing is not counted"] = function(t)
        local rec = recorder()
        rec:enter(1)
        t.eq(feed(rec, 2, spell("SPELL_MISSED", ME, "Me", MOB, "Boar", 5176, "Wrath", "RESIST")), false)
        t.eq(feed(rec, 3, spell("SPELL_AURA_APPLIED", ME, "Me", ME, "Me", 774, "Rejuvenation", "BUFF")), false)
        t.eq(feed(rec, 4, { 1000, nil }), false)
        t.eq(feed(rec, 5, {}), false)
        local f = rec:list()[1]
        t.eq(f.dealt.hits + f.taken.hits + f.healed.hits + f.received.hits, 0)
        t.eq(f.dealt.unread + f.taken.unread, 0)
    end,

    ["fights: an event outside a fight is not put in one, and is counted as outside"] = function(t)
        local rec = recorder()
        t.eq(feed(rec, 1, swing(ME, "Me", MOB, "Boar", 10)), false)
        t.eq(rec:list(), {})
        t.eq(rec:outside(), 1)
        rec:enter(2)
        rec:leave(3)
        t.eq(feed(rec, 4, swing(ME, "Me", MOB, "Boar", 10)), false)
        t.eq(rec:outside(), 2)
        t.eq(rec:list()[1].dealt.total, 0)
    end,

    ["fights: without your own id nothing is counted, and nothing is guessed from a name"] = function(t)
        local rec = ns.Fights.New()
        rec:enter(1)
        t.eq(feed(rec, 2, swing(ME, "Me", MOB, "Boar", 10)), false)
        t.eq(feed(rec, 3, swing(nil, "Me", nil, "Me", 10)), false)
        t.eq(rec:list()[1].dealt.total, 0)
        t.eq(rec:list()[1].taken.total, 0)
        t.eq(rec:knowsMe(), false)
        rec:setMe(ME)
        t.eq(rec:knowsMe(), true)
        t.eq(feed(rec, 4, swing(ME, "Me", MOB, "Boar", 10)), true)
        -- a pet id that was never given matches nothing
        t.eq(feed(rec, 5, swing(nil, "Cat", MOB, "Boar", 10)), false)
    end,

    ["fights: a fixed number of fights is kept, the oldest dropped first"] = function(t)
        t.ok(type(ns.Fights.KEEP) == "number" and ns.Fights.KEEP >= 1, "there is no fixed number")
        local rec = recorder()
        for i = 1, ns.Fights.KEEP + 3 do
            rec:enter(i * 10)
            rec:leave(i * 10 + 5)
        end
        local list = rec:list()
        t.eq(#list, ns.Fights.KEEP)
        t.eq(list[1].started, (ns.Fights.KEEP + 3) * 10, "the newest is not first")
        t.eq(list[#list].started, 4 * 10, "the oldest three were not the ones dropped")
        local small = recorder(2)
        for i = 1, 5 do small:enter(i) small:leave(i + 0.5) end
        t.eq(#small:list(), 2)
        small:enter(99)
        t.eq(#small:list(), 2, "the open fight does not count toward the fixed number")
    end,

    ["fights: the list is a copy: changing it changes no record"] = function(t)
        local rec = recorder()
        rec:enter(1)
        feed(rec, 2, swing(ME, "Me", MOB, "Boar", 10))
        rec:leave(3)
        local list = rec:list()
        list[1].dealt.total = 999
        list[1].dealt.spells[ns.Fights.MELEE].total = 999
        list[1] = nil
        t.eq(rec:list()[1].dealt.total, 10)
        t.eq(rec:list()[1].dealt.spells[ns.Fights.MELEE].total, 10)
    end,

    ["fight lines: no fights says so in one line"] = function(t)
        local lines = ns.Fights.Lines({}, 0)
        t.eq(#lines, 1)
        t.eq(lines[1], ns.Fights.NONE)
    end,

    ["fight lines: one line a fight, newest first, with what was done and taken"] = function(t)
        local rec = recorder()
        rec:enter(10)
        feed(rec, 11, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100))
        feed(rec, 12, swing(MOB, "Boar", ME, "Me", 12))
        rec:leave(22)
        rec:enter(40)
        feed(rec, 41, swing(ME, "Me", MOB, "Boar", 7))
        feed(rec, 42, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", nil))
        t.eq(ns.Fights.Lines(rec:list(), 45), {
            "fights (2 kept, newest first):",
            "1. still going, 5s so far (type unknown): dealt 7 in 1 hit, taken 0, healing done 0, healing received 0, 1 amount not read",
            "2. 12s (type unknown): dealt 100 in 1 hit, taken 12 in 1 hit, healing done 0, healing received 0",
        })
    end,

    ["fight lines: a length that is not known is said to be not known"] = function(t)
        local rec = recorder()
        rec:enter(nil)
        rec:leave(nil)
        local lines = ns.Fights.Lines(rec:list(), nil)
        t.eq(lines[2], "1. length not known (type unknown): dealt 0, taken 0, healing done 0, healing received 0")
    end,

    ["fight lines: one fight by number lists its spells, biggest first"] = function(t)
        local rec = recorder()
        rec:enter(10)
        feed(rec, 11, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 8921, "Moonfire", 20))
        feed(rec, 11, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100))
        feed(rec, 11, spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100))
        feed(rec, 12, swing(MOB, "Boar", ME, "Me", 12))
        feed(rec, 13, spell("SPELL_HEAL", ME, "Me", ME, "Me", 5185, "Healing Touch", 90, 10))
        rec:leave(22)
        t.eq(ns.Fights.Lines(rec:list(), 30, 1), {
            "1. 12s (type unknown): dealt 220 in 3 hits, taken 12 in 1 hit, healing done 90, healing received 90",
            "dealt: Wrath 200 (2 hits), Moonfire 20 (1 hit)",
            "taken: " .. ns.Fights.MELEE .. " 12 (1 hit)",
            "healing done: Healing Touch 90 (1 hit), 10 of it overhealing",
            "healing received: Healing Touch 90 (1 hit), 10 of it overhealing",
        })
    end,

    ["fight lines: a number that is not a kept fight says how many are kept"] = function(t)
        local rec = recorder()
        rec:enter(1)
        rec:leave(2)
        t.eq(ns.Fights.Lines(rec:list(), 5, 7), { "there is no fight 7; 1 is kept." })
        t.eq(ns.Fights.Lines({}, 5, 1), { ns.Fights.NONE })
    end,
}
