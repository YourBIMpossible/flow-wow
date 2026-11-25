local _, ns = ...

-- Tests for ZFlow/Nav/PartyProgress.lua (FLOW-PARITY B-41, lead section
-- 825.1): party members exchange their quest progress as add-on messages
-- on the party channel. Pure encode and decode, then the module on a fake
-- client: sent only in a party, throttled, kept per member, a member who
-- leaves dropped. Made-up quests and names. Not tested in game.

local tests = {}

local function PP() return ns.Nav.PartyProgress end

local function log()
    return {
        { id = 83, title = "Wolves", complete = true, objectives = { { text = "Wolf slain: 6/6", done = true } } },
        { id = 86, title = "Boars", complete = false, objectives = {
            { text = "Boar slain: 2/4", done = false }, { text = "Find the cart", done = false } } },
    }
end

tests["party progress: encode and decode give the same progress back"] = function(t)
    local msgs = PP().Encode(PP().Mine(log()), 1)
    t.eq(msgs and #msgs, 1)
    local d, why = PP().Decode(msgs and msgs[1], 1)
    t.ok(d ~= nil, tostring(why))
    t.eq(d and d.seq, 1)
    t.eq(d and d.count, 1)
    t.eq(d and d.quests[83], { complete = true, objectives = {} })
    t.eq(d and d.quests[86], { complete = false, objectives = { { have = 2, need = 4 }, { have = 0, need = 1 } } })
end

tests["party progress: a long log splits into messages that each fit"] = function(t)
    local rows = {}
    for i = 1, 30 do
        rows[i] = { id = 100000 + i, title = "Q", complete = false, objectives = {
            { text = "A: 1/10", done = false }, { text = "B: 2/10", done = false }, { text = "C: 3/10", done = false } } }
    end
    local msgs = PP().Encode(PP().Mine(rows), 1)
    t.ok(type(msgs) == "table" and #msgs > 1, "more than one message")
    local seen = 0
    for i, m in ipairs(msgs or {}) do
        t.ok(#m <= PP().MAX_BYTES, "message " .. i .. " is " .. #m .. " bytes")
        local d = PP().Decode(m, 1)
        t.eq(d and d.seq, i)
        t.eq(d and d.count, #msgs)
        for _ in pairs(d and d.quests or {}) do seen = seen + 1 end
    end
    t.eq(seen, 30)
end

tests["party progress: malformed, unknown-version and too-long messages do not decode"] = function(t)
    local bad = { "", "hello", "1|G", "1|G|1|1", "2|G|1|1|83=c", "1|X|1|1|83=c", "1|G|0|1|83=c",
        "1|G|2|1|83=c", "1|G|1|9|83=c", "1|G|1|1|x=c", "1|G|1|1|83=q", "1|G|1|1|83=5/x",
        "1|G|1|1|83=-1/4", "1|G|1|1|0=c", "1|G|1|1|83=c,83=c", "1|G|1|1|99999999=c",
        "1|G|1|1|83=c;loadstring", "1|G|1|1|" .. string.rep("83=c,", 60) .. "84=c" }
    for _, m in ipairs(bad) do
        local d, why = PP().Decode(m, 1)
        t.eq(d, nil, m)
        t.ok(type(why) == "string", "why for " .. m)
    end
    t.eq(PP().Decode(nil, 1), nil)
    t.eq(PP().Decode({}, 1), nil)
end

-- A player named Ann; opts.party: the party rows; opts.on = false: the
-- setting turned off.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setPlayerName("Ann")
    c.setAddonName("Ann")
    c.setQuestLog(log())
    if opts.party ~= false then
        c.setGrouped(true)
        c.setParty(opts.party or { { unit = "party1", name = "Bob" } })
    else
        c.setGrouped(false)
        c.setParty({})
    end
    local k = ns.Kernel({}, c)
    PP().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.on == false then k.settings:set(PP().SETTING, false) end
    return k, c
end

local function sent(c)
    local n = 0
    for _, m in ipairs(c.addonSent) do
        if m.prefix == PP().Prefix() then n = n + 1 end
    end
    return n
end

tests["party progress: module started, with its setting and API"] = function(t)
    local k = start()
    t.eq((k:ModuleState(PP().NAME)), "started")
    t.ok(k.settings:row(PP().SETTING) ~= nil, "a setting row")
    local api = k.use(PP().NAME)
    t.ok(type(api.Progress) == "function" and type(api.All) == "function", "Progress and All")
end

tests["party progress: sent on the party channel after a quest log change"] = function(t)
    local _, c = start()
    c.fire("QUEST_LOG_UPDATE")
    c.advance(PP().EVERY + 1)
    t.eq(sent(c), 1)
    local m = c.addonSent[#c.addonSent]
    t.eq(m and m.channel, "PARTY")
end

tests["party progress: nothing is sent outside a party, or in a raid, or with the setting off"] = function(t)
    local _, c = start({ party = false })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(PP().EVERY + 1)
    t.eq(#c.addonSent, 0)
    local _, r = start({ party = { { unit = "raid1", name = "Bob" } } })
    r.fire("QUEST_LOG_UPDATE")
    r.advance(PP().EVERY + 1)
    t.eq(#r.addonSent, 0)
    local _, o = start({ on = false })
    o.fire("QUEST_LOG_UPDATE")
    o.advance(PP().EVERY + 1)
    t.eq(#o.addonSent, 0)
end

tests["party progress: throttled, and nothing sent when nothing changed"] = function(t)
    local _, c = start()
    c.fire("QUEST_LOG_UPDATE")
    c.advance(PP().EVERY + 1)
    t.eq(sent(c), 1)
    -- No change: nothing more.
    c.fire("QUEST_LOG_UPDATE")
    c.advance(PP().EVERY + 1)
    t.eq(sent(c), 1)
    -- A change right away waits for the throttle.
    local rows = log()
    rows[2].objectives[1].text = "Boar slain: 3/4"
    c.setQuestLog(rows)
    c.fire("UNIT_QUEST_LOG_CHANGED", "player")
    c.advance(0.1)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(0.1)
    t.eq(sent(c), 1)
    c.advance(PP().EVERY + 1)
    t.eq(sent(c), 2)
end

tests["party progress: a member's progress is kept by name; your own echo is not"] = function(t)
    local k, c = start()
    local msgs = PP().Encode(PP().Mine(log()), ns.id.commVersion)
    c.addonDeliver(PP().Prefix(), msgs[1], "PARTY", "Bob-Realm")
    c.addonDeliver(PP().Prefix(), msgs[1], "PARTY", "Ann")
    local api = k.use(PP().NAME)
    local bob = api.Progress("Bob")
    t.ok(bob ~= nil, "Bob kept")
    t.eq(bob and bob[83] and bob[83].complete, true)
    t.eq(api.Progress("Ann"), nil)
    local names = 0
    for _ in pairs(api.All()) do names = names + 1 end
    t.eq(names, 1)
end

tests["party progress: wrong prefix, wrong channel or malformed text is ignored"] = function(t)
    local k, c = start()
    local msgs = PP().Encode(PP().Mine(log()), ns.id.commVersion)
    c.addonPrefix("Other")
    c.addonDeliver("Other", msgs[1], "PARTY", "Bob")
    c.addonDeliver(PP().Prefix(), msgs[1], "GUILD", "Bob")
    c.addonDeliver(PP().Prefix(), "1|G|1|1|nonsense", "PARTY", "Bob")
    t.eq(k.use(PP().NAME).Progress("Bob"), nil)
end

tests["party progress: a member who leaves the party is dropped"] = function(t)
    local k, c = start({ party = { { unit = "party1", name = "Bob" }, { unit = "party2", name = "Cid" } } })
    local msgs = PP().Encode(PP().Mine(log()), ns.id.commVersion)
    c.addonDeliver(PP().Prefix(), msgs[1], "PARTY", "Bob")
    c.addonDeliver(PP().Prefix(), msgs[1], "PARTY", "Cid")
    local api = k.use(PP().NAME)
    t.ok(api.Progress("Bob") ~= nil and api.Progress("Cid") ~= nil, "both kept")
    c.setParty({ { unit = "party1", name = "Cid" } })
    c.fire("GROUP_ROSTER_UPDATE")
    t.eq(api.Progress("Bob"), nil)
    t.ok(api.Progress("Cid") ~= nil, "Cid still kept")
    c.setGrouped(false)
    c.setParty({})
    c.fire("GROUP_ROSTER_UPDATE")
    t.eq(api.Progress("Cid"), nil)
end

return tests
