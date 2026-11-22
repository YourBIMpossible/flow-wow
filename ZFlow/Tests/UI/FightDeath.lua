-- The death report (G30) and the fight types (G28) as the player meets
-- them: what is printed at a death, the death word, and the target rank
-- read that tells an elite. The combat-log feed, the id read and the target
-- rank read are not in the fake client yet (CLIENT NEED), so each test puts
-- them on its own fake in the shape that was asked for. Every event list is
-- written by hand; none is from a real fight.
local _, ns = ...

local ME, MOB = "Player-1-0000AAAA", "Creature-0-1-0000CCCC"
local MINE, OUTSIDER = 1, 8

local function swing(src, srcName, srcFlags, dst, dstName, dstFlags, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, srcFlags, 0, dst, dstName, dstFlags, 0, amount }
end

-- opts.noFeed: no combat-log read. opts.noRank: no target rank read.
-- opts.rank: what the target rank read answers now.
local function client(opts)
    local c = ns.make.fakeClient()
    local watchers = {}
    if not opts.noFeed then
        function c.watchCombatLog(fn)
            watchers[#watchers + 1] = fn
            return true
        end
    end
    function c.playerGUID() return ME end
    function c.petGUID() return nil end
    if not opts.noRank then
        function c.targetRank() return opts.rank end
    end
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
    return c, log
end

local function since(c, before)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    return since(c, before)
end

local function fight(c, amount)
    c.combatLog(swing(ME, "Me", MINE, MOB, "Boar", OUTSIDER, amount or 10))
end

return {
    ["fight death: your death prints what hit you in the seconds before"] = function(t)
        local c = start({})
        c.advance(100)
        c.setCombat(true)
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 40))
        c.advance(2)
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 60))
        local before = #c.printed
        c.fire("PLAYER_DEAD")
        t.eq(since(c, before), {
            ns.id.title .. ": you died. Damage taken in the last 10s: 100 in 2 hits. Oldest first:",
            ns.id.title .. ": 2.0s before: melee 40 from Boar",
            ns.id.title .. ": 0.0s before: melee 60 from Boar",
        })
    end,

    ["fight death: the death word shows the last death again"] = function(t)
        local c = start({})
        t.eq(said(c, "fights death"), { ns.id.title .. ": " .. ns.Fights.NO_DEATH })
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 40))
        c.fire("PLAYER_DEAD")
        c.advance(60)
        t.eq(said(c, "fights death"), {
            ns.id.title .. ": you died. Damage taken in the last 10s: 40 in 1 hit. Oldest first:",
            ns.id.title .. ": 0.0s before: melee 40 from Boar",
        })
    end,

    ["fight death: a death before any fight still knows who you are"] = function(t)
        -- No fight was started, so the id was never asked for at a fight
        -- start: the hit before the first death is read all the same.
        local c, log = start({})
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 40))
        c.fire("PLAYER_DEAD")
        t.eq(#log.death().hits, 1)
    end,

    ["fight death: with no combat-log read a death prints nothing"] = function(t)
        local c, log = start({ noFeed = true })
        local before = #c.printed
        c.fire("PLAYER_DEAD")
        t.eq(since(c, before), {})
        t.eq(log.death(), nil)
        t.eq(said(c, "fights death"), { ns.id.title .. ": " .. ns.FightLog.NO_FEED })
    end,

    ["fight death: nothing of a death is saved"] = function(t)
        local c = start({})
        local function count(tbl)
            local n = 0
            for _ in pairs(tbl) do n = n + 1 end
            return n
        end
        local account, char = count(c.saved(ns.id.accountDB)), count(c.saved(ns.id.charDB) or {})
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 40))
        c.fire("PLAYER_DEAD")
        said(c, "fights death")
        t.eq(count(c.saved(ns.id.accountDB)), account)
        t.eq(count(c.saved(ns.id.charDB) or {}), char)
    end,

    ["fight death: no line spells the name of the predecessor"] = function(t)
        local c = start({})
        c.combatLog(swing(MOB, "Boar", OUTSIDER, ME, "Me", MINE, 40))
        c.fire("PLAYER_DEAD")
        local lines = said(c, "fights death")
        t.ok(#lines > 1, "nothing was listed")
        for i = 1, #lines do
            local rest = lines[i]:gsub(ns.id.title, ""):gsub(ns.id.slash, "")
            t.ok(rest:find("Flow", 1, true) == nil and rest:find("flow", 1, true) == nil, lines[i])
        end
    end,

    ["fight type: the target rank is read when the fight starts"] = function(t)
        local opts = { rank = "normal" }
        local c, log = start(opts)
        c.setCombat(true)
        fight(c)
        c.advance(3)
        c.setCombat(false)
        t.eq(ns.Fights.Kind(log.fights()[1]), "solo")
        t.eq(said(c, "fights")[2],
            ns.id.title .. ": 1. 3s (solo): dealt 10 in 1 hit, taken 0, healing done 0, healing received 0")
    end,

    ["fight type: a new target in the fight is read too"] = function(t)
        local opts = { rank = "normal" }
        local c, log = start(opts)
        c.setCombat(true)
        fight(c)
        opts.rank = "elite"
        c.fire("PLAYER_TARGET_CHANGED")
        c.setCombat(false)
        t.eq(ns.Fights.Kind(log.fights()[1]), "elite")
        -- a target picked after the fight changes nothing
        opts.rank = "normal"
        c.setCombat(true)
        fight(c)
        c.setCombat(false)
        opts.rank = "elite"
        c.fire("PLAYER_TARGET_CHANGED")
        t.eq(ns.Fights.Kind(log.fights()[1]), "solo")
    end,

    ["fight type: no target at the start is not read as normal"] = function(t)
        local opts = { rank = nil }
        local c, log = start(opts)
        c.setCombat(true)
        fight(c)
        c.setCombat(false)
        t.eq(ns.Fights.Kind(log.fights()[1]), "unknown")
    end,

    ["fight type: a client with no target rank read leaves the type unknown"] = function(t)
        local c, log = start({ noRank = true })
        c.setCombat(true)
        fight(c)
        c.fire("PLAYER_TARGET_CHANGED")
        c.advance(3)
        c.setCombat(false)
        t.eq(ns.Fights.Kind(log.fights()[1]), "unknown")
        t.eq(said(c, "fights")[2],
            ns.id.title .. ": 1. 3s (type unknown): dealt 10 in 1 hit, taken 0, healing done 0, healing received 0")
    end,
}
