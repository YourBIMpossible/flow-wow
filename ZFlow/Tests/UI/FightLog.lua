-- The fights word of the slash command (G29) and the wiring that feeds the
-- fight reader from the client. The combat-log feed and the id reads are
-- not in the fake client yet (CLIENT NEED), so each test puts them on its
-- own fake in the shape that was asked for. Every event list is written by
-- hand; none is from a real fight.
local _, ns = ...

local ME, MOB = "Player-1-0000AAAA", "Creature-0-1-0000CCCC"

local function spell(sub, src, srcName, dst, dstName, id, name, amount, over)
    return { 1000, sub, false, src, srcName, 0, 0, dst, dstName, 0, 0, id, name, 1, amount, over }
end
local function swing(src, srcName, dst, dstName, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, 0, 0, dst, dstName, 0, 0, amount }
end

-- A fake client with the asked-for reads on it.
--   opts.noFeed  the client has no combat-log read
--   opts.me      the player's id (nil: the client will not say)
local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local watchers = {}
    -- The fake has these reads of its own now (Core/ClientFake.lua); these
    -- tests put their own in their place, or none.
    c.watchCombatLog = nil
    if not opts.noFeed then
        function c.watchCombatLog(fn)
            watchers[#watchers + 1] = fn
            return true
        end
    end
    function c.playerGUID() return opts.me end
    function c.petGUID() return opts.pet end
    function c.combatLog(ev)
        for i = 1, #watchers do watchers[i](unpack(ev, 1, 16)) end
    end
    return c
end

local function start(opts)
    local c = client(opts)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local log = ns.FightLog.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, d, log
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

return {
    ["fight log: the word is added to the slash command"] = function(t)
        local _, _, d = start({ me = ME })
        t.eq(ns.FightLog.WORD, "fights")
        t.eq(type(d.commands[ns.FightLog.WORD]), "function")
    end,

    ["fight log: the word brings its line for the help word when there is a place for it"] = function(t)
        local c = client({ me = ME })
        local k = ns.Kernel({}, c)
        local diag = { commands = {}, help = {} }
        ns.FightLog.Start(k, diag)
        t.ok(type(diag.help[ns.FightLog.WORD]) == "string" and diag.help[ns.FightLog.WORD] ~= "",
            "the fights word has no description")
        -- and it starts without one
        local bare = { commands = {} }
        ns.FightLog.Start(ns.Kernel({}, client({ me = ME })), bare)
        t.eq(type(bare.commands[ns.FightLog.WORD]), "function")
        ns.FightLog.Start(ns.Kernel({}, client({ me = ME })), nil)
        t.ok(true)
    end,

    ["fight log: before any fight it says there are none"] = function(t)
        local _, c = start({ me = ME })
        t.eq(said(c, "fights"), { ns.id.title .. ": " .. ns.Fights.NONE })
    end,

    ["fight log: a fight between the combat start and end is recorded and shown"] = function(t)
        local _, c, _, log = start({ me = ME })
        c.advance(10)
        c.setCombat(true)
        c.combatLog(spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100))
        c.combatLog(swing(MOB, "Boar", ME, "Me", 12))
        c.advance(12)
        c.setCombat(false)
        local list = log.fights()
        t.eq(#list, 1)
        t.eq(list[1].open, false)
        t.eq(list[1].dealt.total, 100)
        t.eq(list[1].taken.total, 12)
        t.eq(list[1].ended - list[1].started, 12)
        t.eq(said(c, "fights"), {
            ns.id.title .. ": fights (1 kept, newest first):",
            ns.id.title .. ": 1. 12s (type unknown): dealt 100 in 1 hit, taken 12 in 1 hit, healing done 0, healing received 0",
        })
    end,

    ["fight log: the word with a number shows that fight's spells"] = function(t)
        local _, c = start({ me = ME })
        c.setCombat(true)
        c.combatLog(spell("SPELL_DAMAGE", ME, "Me", MOB, "Boar", 5176, "Wrath", 100))
        c.advance(3)
        c.setCombat(false)
        local lines = said(c, "fights 1")
        t.eq(#lines, 2)
        t.eq(lines[2], ns.id.title .. ": dealt: Wrath 100 (1 hit)")
        t.eq(said(c, "fights 4"), { ns.id.title .. ": there is no fight 4; 1 is kept." })
    end,

    ["fight log: events outside combat are in no fight"] = function(t)
        local _, c, _, log = start({ me = ME })
        c.combatLog(swing(ME, "Me", MOB, "Boar", 10))
        t.eq(log.fights(), {})
        t.eq(said(c, "fights"), { ns.id.title .. ": " .. ns.Fights.NONE })
    end,

    ["fight log: a client with no combat-log read says so, and records nothing"] = function(t)
        local _, c, _, log = start({ me = ME, noFeed = true })
        c.setCombat(true)
        c.setCombat(false)
        t.eq(log.feed(), false)
        t.eq(said(c, "fights"), { ns.id.title .. ": " .. ns.FightLog.NO_FEED })
    end,

    ["fight log: a client that will not say who you are says so"] = function(t)
        local _, c, _, log = start({ me = nil })
        c.setCombat(true)
        c.combatLog(swing(ME, "Me", MOB, "Boar", 10))
        c.setCombat(false)
        t.eq(log.fights()[1].dealt.total, 0)
        local lines = said(c, "fights")
        t.eq(lines[#lines], ns.id.title .. ": " .. ns.FightLog.NO_ME)
    end,

    ["fight log: who you are is asked again at the next fight"] = function(t)
        local opts = { me = nil }
        local _, c, _, log = start(opts)
        c.setCombat(true)
        c.setCombat(false)
        opts.me = ME
        c.setCombat(true)
        c.combatLog(swing(ME, "Me", MOB, "Boar", 10))
        c.setCombat(false)
        t.eq(log.fights()[1].dealt.total, 10)
    end,

    ["fight log: nothing of a fight is saved"] = function(t)
        local _, c = start({ me = ME })
        local function count(tbl)
            local n = 0
            for _ in pairs(tbl) do n = n + 1 end
            return n
        end
        local account, char = count(c.saved(ns.id.accountDB)), count(c.saved(ns.id.charDB) or {})
        c.setCombat(true)
        c.combatLog(swing(ME, "Me", MOB, "Boar", 10))
        c.setCombat(false)
        said(c, "fights")
        t.eq(count(c.saved(ns.id.accountDB)), account)
        t.eq(count(c.saved(ns.id.charDB) or {}), char)
    end,

    ["fight log: no line spells the predecessor's name"] = function(t)
        local _, c = start({ me = ME })
        c.setCombat(true)
        c.combatLog(swing(ME, "Me", MOB, "Boar", 10))
        c.setCombat(false)
        local lines = said(c, "fights 1")
        t.ok(#lines > 1, "nothing was listed")
        for i = 1, #lines do
            local rest = lines[i]:gsub(ns.id.title, ""):gsub(ns.id.slash, "")
            t.ok(rest:find("Flow", 1, true) == nil and rest:find("flow", 1, true) == nil, lines[i])
        end
    end,
}
