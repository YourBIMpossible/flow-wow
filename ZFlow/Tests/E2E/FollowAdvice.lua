local _, ns = ...
-- Follow advice end to end (G47, lead section 397 item 15), on the whole
-- add-on loaded on a fake client. In a group, when your leader is far away,
-- one advisor line says how far and which way. Alone, near, or where the
-- leader is not known: no line. TEXT ONLY: no follow, target, assist or
-- cast call is made. Offline; made-up names. Not tested in game.
local tests = {}

local MAP = 1411
-- Calls that would act for the player; each is spied on and must stay at 0.
local ACTS = { "followUnit", "targetUnit", "assistUnit", "castSpell", "castSpellByName", "follow" }

local function start(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(12)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setGrouped(opts.grouped)
    if opts.grouped then
        c.setParty({ { unit = "party1", name = "Ander" }, { unit = "party2", name = "Bee" } })
        if type(c.setGroupLeader) == "function" then c.setGroupLeader("party1") end
    else
        c.setParty({})
        if type(c.setGroupLeader) == "function" then c.setGroupLeader(false) end
    end
    if opts.at then c.setUnitPosition("party1", MAP, opts.at[1], opts.at[2]) end
    local calls = 0
    for _, name in ipairs(ACTS) do
        local real = c[name]
        c[name] = function(...)
            calls = calls + 1
            if type(real) == "function" then return real(...) end
        end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, function() return calls end
end

local function prompt(addon)
    local F = ns.Nav and ns.Nav.FollowAdvice or {}
    for _, p in ipairs(addon.advisor.List()) do
        if F.PROMPT ~= nil and p.id == F.PROMPT then return p.text end
    end
    return nil
end

tests["follow advice e2e: leader far gives the line; nothing is followed or targeted"] = function(t)
    local _, addon, calls = start({ grouped = true, at = { 0.8, 0.5 } })
    t.eq(prompt(addon), "Your leader Ander is 300 yd away to the E: catch up.")
    t.eq(calls(), 0, "no follow, target, assist or cast call")
end

tests["follow advice e2e: alone, leader near, or leader not known: no line"] = function(t)
    local _, a1, n1 = start({ grouped = false })
    t.eq(prompt(a1), nil, "not grouped")
    local _, a2, n2 = start({ grouped = true, at = { 0.51, 0.5 } })
    t.eq(prompt(a2), nil, "leader near")
    local _, a3, n3 = start({ grouped = true })
    t.eq(prompt(a3), nil, "where the leader is is not known")
    t.eq(n1() + n2() + n3(), 0, "no follow, target, assist or cast call")
end

tests["follow advice e2e: the line comes when the leader moves away and goes when back"] = function(t)
    local c, addon = start({ grouped = true, at = { 0.51, 0.5 } })
    t.eq(prompt(addon), nil)
    c.setUnitPosition("party1", MAP, 0.5, 0.2)
    c.advance(5, 20)
    t.eq(prompt(addon), "Your leader Ander is 300 yd away to the N: catch up.")
    c.setUnitPosition("party1", MAP, 0.5, 0.49)
    c.advance(5, 20)
    t.eq(prompt(addon), nil)
end

return tests
