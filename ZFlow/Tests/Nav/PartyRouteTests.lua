local _, ns = ...

-- Tests for ZFlow/Nav/PartyRoute.lua (G48, P-TRIP): the shared party route
-- as add-on messages. Pure parts only: encode, decode, chunk and parse.
-- Made-up places and names.

local tests = {}

local function P() return ns.Nav.PartyRoute end

local function route(n, label)
    local stops = {}
    for i = 1, n do
        stops[i] = { label = (label or "Stop") .. " " .. i, detail = "Boars slain: 0/4",
                     place = { map = 1436, x = i / 100, y = 0.5 } }
    end
    return { kind = "quests", label = "straight", stops = stops }
end

tests["party route: encode and decode give the same stops back"] = function(t)
    local run, why = P().Decode(P().Encode(route(3)))
    t.ok(run ~= nil, tostring(why))
    t.eq(run and #run.steps, 3)
    local s = run and run.steps[2]
    t.eq(s and s.label, "Stop 2")
    t.eq(s and s.detail, "Boars slain: 0/4")
    t.eq(s and s.place, { map = 1436, x = 0.02, y = 0.5 })
    t.eq(s and s.kind, "party")
end

tests["party route: separators and percent signs in a label survive"] = function(t)
    local run = P().Decode(P().Encode(route(1, "A|b;c,d%e\nf")))
    t.eq(run and run.steps[1].label, "A|b;c,d%e\nf 1")
end

tests["party route: every message fits the add-on message limit, with a count"] = function(t)
    local msgs = P().Chunks("ab12", P().Encode(route(12, string.rep("Long quest name ", 2))), 1)
    t.ok(type(msgs) == "table" and #msgs > 1, "more than one chunk")
    for i, m in ipairs(msgs or {}) do
        t.ok(#m <= P().MAX_BYTES, "chunk " .. i .. " is " .. #m .. " bytes")
        local p = P().Parse(m, 1)
        t.eq(p and p.type, "R")
        t.eq(p and p.seq, i)
        t.eq(p and p.count, #msgs)
        t.eq(p and p.sid, "ab12")
    end
end

tests["party route: chunks joined in order decode to the route"] = function(t)
    local payload = P().Encode(route(12))
    local msgs = P().Chunks("s1", payload, 1)
    local parts = {}
    for i, m in ipairs(msgs or {}) do parts[i] = P().Parse(m, 1).data end
    t.eq(table.concat(parts), payload)
end

tests["party route: an ask parses; malformed and unknown-version messages do not"] = function(t)
    local q = P().Parse(P().Ask("n1", 1), 1)
    t.eq(q and q.type, "Q")
    t.eq(q and q.nonce, "n1")
    for _, bad in ipairs({ "", "hello", "1|R|s|x|2|abc", "1|R|s|3|2|abc", "1|Z|s", "9|Q|n1", "1|R|s|1|0|a" }) do
        local p, why = P().Parse(bad, 1)
        t.eq(p, nil, bad)
        t.ok(type(why) == "string", "why for " .. bad)
    end
    t.eq(P().Parse(nil, 1), nil)
end

tests["party route: a payload that is not a route does not decode"] = function(t)
    for _, bad in ipairs({ "", "nonsense", "quests,x;a,b,c,d,e" }) do
        local run, why = P().Decode(bad)
        t.eq(run, nil, bad)
        t.ok(type(why) == "string", "why for " .. bad)
    end
end

tests["party route: a route too long to send is refused with a reason"] = function(t)
    local msgs, why = P().Chunks("s", string.rep("x", P().MAX_BYTES * (P().MAX_CHUNKS + 1)), 1)
    t.eq(msgs, nil)
    t.ok(type(why) == "string", "why")
end

tests["party route: no more than MAX_STOPS stops are encoded"] = function(t)
    local run = P().Decode(P().Encode(route(P().MAX_STOPS + 5)))
    t.eq(run and #run.steps, P().MAX_STOPS)
end

-- FLOW-PARITY B-39: shared edits (move first, add a stop, mark done for all).
local function steps3()
    return P().Decode(P().Encode(route(3))).steps
end

tests["party route: an edit moves a stop first, marks one done, adds one in front"] = function(t)
    local first = P().ApplyEdit(steps3(), "F", "3")
    t.eq(first and first[1].label, "Stop 3")
    t.eq(first and #first, 3)
    local done = P().ApplyEdit(steps3(), "D", "1")
    t.eq(done and #done, 2)
    t.eq(done and done[1].label, "Stop 2")
    local added = P().ApplyEdit(steps3(), "A", P().StopRecord({ label = "Meet here", place = { map = 1436, x = 0.4, y = 0.6 } }))
    t.eq(added and #added, 4)
    t.eq(added and added[1].label, "Meet here")
    t.eq(added and added[1].place, { map = 1436, x = 0.4, y = 0.6 })
end

tests["party route: an edit on a stop that is not there changes nothing"] = function(t)
    local s = steps3()
    for _, bad in ipairs({ { "F", "9" }, { "D", "0" }, { "D", "x" }, { "Q", "1" }, { "A", "a,b" } }) do
        local out, why = P().ApplyEdit(s, bad[1], bad[2])
        t.eq(out, nil, bad[1] .. bad[2])
        t.ok(type(why) == "string", "why for " .. bad[1] .. bad[2])
    end
    t.eq(#s, 3)
end

tests["party route: an edit message parses back with its clock"] = function(t)
    local e = P().Parse(P().EditMsg("s1", 4, "F", "2", 1), 1)
    t.eq(e and e.type, "E")
    t.eq(e and e.sid, "s1")
    t.eq(e and e.clock, 4)
    t.eq(e and e.op, "F")
    t.eq(e and e.arg, "2")
    t.eq(P().Parse("1|E|s1|x|F|2", 1), nil)
end

-- FLOW-PARITY B-45: who plans the party route.
tests["party route: the group leader plans when on it, else the first name"] = function(t)
    t.eq(P().Leader("Bo", { "Al", "Cy" }, "Cy"), "Cy")
    t.eq(P().Leader("Bo", { "Al", "Cy" }, "Zed"), "Al")
    t.eq(P().Leader("Bo", {}, nil), "Bo")
    t.eq(P().Leader("Bo-Realm", { "al-Realm" }, "AL"), "al-Realm")
end

tests["party route: a join message parses on and off"] = function(t)
    t.eq(P().Parse(P().JoinMsg(true, 1), 1), { type = "J", on = true })
    t.eq(P().Parse(P().JoinMsg(false, 1), 1), { type = "J", on = false })
    t.eq(P().Parse("1|J|2", 1), nil)
end

-- FLOW-PARITY B-42 and B-44: whose quests the route covers, and whom to ask.
-- A member's progress is B-41's (Nav/PartyProgress.lua): { [quest id] =
-- { complete, objectives = { { have, need } } } }. Lead section 843.2: the
-- route keeps steps by quest id and objective, as Flow's PartyHelp.lua
-- H.Keep (:381-399) and H.QuestsOnly (:404-411). Fails before: steps were
-- matched by title, which B-41 does not send.
local PROG = {
    Al = { [10] = { complete = false, objectives = { { have = 2, need = 8 }, { have = 5, need = 5 } } },
           [11] = { complete = true, objectives = {} } },
    Cy = { [11] = { complete = true, objectives = {} } },
}

tests["party route: to do counts only quests not complete"] = function(t)
    t.eq(P().ToDo(PROG.Al), 1)
    t.eq(P().ToDo(PROG.Cy), 0)
    t.eq(P().ToDo(nil), 0)
end

tests["party route: the route covers mine, just one member's, or everyone joined"] = function(t)
    t.eq(P().Covered("mine", nil, PROG, {}), nil)
    t.eq(P().Covered("theirs", "Al", PROG, {}), { Al = PROG.Al })
    t.eq(P().Covered("theirs", "Zed", PROG, {}), nil)
    t.eq(P().Covered("combined", nil, PROG, { Cy = true }), { Cy = PROG.Cy })
end

tests["party route: just their quests keeps your steps of their quests, by quest and objective"] = function(t)
    local steps = {
        { quest = 10, objective = 1, label = "Boars" },      -- theirs, 2/8: kept
        { quest = 10, objective = 2, label = "Herbs" },      -- theirs, 5/5 done: dropped
        { quest = 11, turnIn = true, label = "Hand in" },    -- they hand it in too: kept
        { quest = 12, objective = 1, label = "Wolves" },     -- not theirs: dropped
        { label = "Sell junk" },                             -- no quest: dropped
        { label = "Party stop", kind = "party" },            -- the party route's own: kept
    }
    local kept = P().KeepFor(steps, { Al = PROG.Al })
    local labels = {}
    for i, s in ipairs(kept) do labels[i] = s.label end
    t.eq(labels, { "Boars", "Hand in", "Party stop" })
    t.eq(#P().KeepFor(steps, nil), 6, "nobody covered: every step")
end

tests["party route: asks once per member, only with quests to do, only on your own route"] = function(t)
    local asked = {}
    t.eq(P().AskWho("Al", PROG, asked, "mine", "Bo"), "Al")
    asked.Al = true
    t.eq(P().AskWho("Al", PROG, asked, "mine", "Bo"), nil)
    t.eq(P().AskWho("Cy", PROG, {}, "mine", "Bo"), nil)
    t.eq(P().AskWho("Al", PROG, {}, "combined", "Bo"), nil)
    t.eq(P().AskWho("Bo", { Bo = PROG.Al }, {}, "mine", "Bo"), nil)
end

-- Lead section 843.2: B-41's progress reaches the party route by itself:
-- PartyRoute reads partyProgress (Names, Progress) on its own tick. Fails
-- before: nothing fed it.
tests["party route: the members' progress from B-41 is fed in"] = function(t)
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = P().Declare(k, d)
    k:Module({ name = "partyProgress", provides = {
        Names = function() return { "Al" } end,
        Progress = function(name) return PROG[name] end,
        All = function() return PROG end,
    } })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.advance(P().FEED_EVERY + 1, 3)
    local kept = api.Filter({ { quest = 10, objective = 1, label = "Boars" }, { quest = 12, objective = 1, label = "Wolves" } })
    t.eq(#kept, 2, "your own route as made: every step")
    api.SetScope("theirs", "Al")
    t.eq(api.Scope(), "theirs", "Al's progress is there, so you can help them")
    kept = api.Filter({ { quest = 10, objective = 1, label = "Boars" }, { quest = 12, objective = 1, label = "Wolves" } })
    t.eq(#kept, 1)
    t.eq(kept[1].label, "Boars")
end

-- B-42 CHANGES-1 (lead section 856): on the party route ("combined") every
-- quest step, turn-in and party step is kept, as Flow's PartyHelp.lua
-- H.QuestsOnly (:406-415); only "theirs" keeps by a member's quests. Fails
-- before: a joined member who lacks your quest cut your step.
tests["party route B-42: on the party route your quest step stays when a member lacks it"] = function(t)
    local c = ns.make.fakeClient()
    c.setPlayerName("Bo")
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = P().Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    api.Progress("Al", PROG.Al)
    c.fire("CHAT_MSG_ADDON", ns.id.commPrefix, P().JoinMsg(true, ns.id.commVersion), "PARTY", "Al")
    api.SetScope("combined")
    local kept = api.Filter({
        { quest = 12, objective = 1, label = "Wolves" },
        { quest = 13, turnIn = true, label = "Hand in" },
        { label = "Party stop", party = true },
        { label = "Sell junk" },
    })
    local labels = {}
    for i, s in ipairs(kept) do labels[i] = s.label end
    t.eq(labels, { "Wolves", "Hand in", "Party stop" })
end

-- B-42 CHANGES-1 (lead section 861): a quest's pick-up is not a party route
-- step, as Flow's H.QuestsOnly drops "pickup:<id>" (PartyHelp.lua:409;
-- Focus.lua:48, :436-438). Fails before: it was kept by its quest id.
tests["party route B-42: on the party route a quest pick-up is left out"] = function(t)
    local kept = P().QuestsOnly({
        { kind = "pickup", quest = 14, label = "Pick up" },
        { quest = 12, objective = 1, label = "Wolves" },
    })
    t.eq(#kept, 1)
    t.eq(kept[1] and kept[1].label, "Wolves")
end

return tests
