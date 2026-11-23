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

return tests
