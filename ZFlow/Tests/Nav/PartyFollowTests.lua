local _, ns = ...

-- Tests for ZFlow/Nav/PartyFollow.lua (FLOW-PARITY A1-49, lead section
-- 828.3): a party member who follows another asks them for their spot,
-- and the one followed sends where they are as add-on messages on the
-- party channel, so the arrow can point at them on another map. Pure
-- encode and decode, then the module on fake clients: off by default,
-- only in a party, only while followed, throttled, own echo and strangers
-- ignored, and Follow's step on another map. Made-up names. Not tested in
-- game.

local tests = {}

local function PF() return ns.Nav.PartyFollow end

local MAP, OTHER = 1411, 1429

-- r[key] is a number within a hair of want.
local function close(r, key, want)
    if type(r) ~= "table" or type(r[key]) ~= "number" then return false end
    return math.abs(r[key] - want) < 0.0001
end

tests["party follow: encode and decode give the same messages back"] = function(t)
    local s = PF().EncodeSpot(OTHER, 0.25, 0.75, 1)
    local d, why = PF().Decode(s, 1)
    t.ok(d ~= nil, tostring(why))
    t.eq(d and d.kind, "spot")
    t.eq(d and d.map, OTHER)
    t.ok(close(d, "x", 0.25), "x")
    t.ok(close(d, "y", 0.75), "y")
    local a = PF().EncodeAsk("Bob-Realm", 1)
    local q = PF().Decode(a, 1)
    t.eq(q and q.kind, "ask")
    t.eq(q and q.name, "Bob")
end

tests["party follow: malformed, unknown-version and too-long messages do not decode"] = function(t)
    local bad = { "", "hello", "1|S", "1|S|1411|0.5", "2|S|1411|0.5|0.5", "1|Q|1411|0.5|0.5",
        "1|S|x|0.5|0.5", "1|S|1411|1.5|0.5", "1|S|1411|0.5|-0.1", "1|S|1411|0.5|0.5|9",
        "1|S|0|0.5|0.5", "1|S|99999999|0.5|0.5", "1|S|1411|nan|0.5", "1|S|1411|0.5.5|0.5",
        "1|A|", "1|A|Bob|Cid", "1|A|%s%s", "1|A|" .. string.rep("a", 60),
        "1|S|1411|0.5|0.5" .. string.rep(" ", 300) }
    for _, m in ipairs(bad) do
        local d, why = PF().Decode(m, 1)
        t.eq(d, nil, m)
        t.ok(type(why) == "string", "why for " .. m)
    end
    t.eq(PF().Decode(nil, 1), nil)
    t.eq(PF().Decode({}, 1), nil)
end

-- A client for `me`; opts.party: party rows (false: alone); opts.on: the
-- setting turned on (it is off by default); opts.follow: declare Follow.
local function start(me, opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setPlayerName(me)
    c.setAddonName(me)
    c.setZone(1, MAP)
    c.setPosition(MAP, 0.5, 0.5)
    if opts.party ~= false then
        c.setGrouped(true)
        c.setParty(opts.party or { { unit = "party1", name = "Bob" } })
    else
        c.setGrouped(false)
        c.setParty({})
    end
    local k = ns.Kernel({}, c)
    PF().Declare(k)
    if opts.follow then ns.Nav.Follow.Declare(k) end
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.on then k.settings:set(PF().SETTING, true) end
    return k, c
end

local function sent(c, kind)
    local n = 0
    for _, m in ipairs(c.addonSent) do
        if m.prefix == PF().Prefix() then
            local d = PF().Decode(m.text, ns.id.commVersion)
            if d and (kind == nil or d.kind == kind) then n = n + 1 end
        end
    end
    return n
end

local function ask(c, from, name)
    c.addonDeliver(PF().Prefix(), PF().EncodeAsk(name or "Ann", ns.id.commVersion), "PARTY", from or "Bob")
end

tests["party follow: module started, its setting off by default"] = function(t)
    local k = start("Ann")
    t.eq((k:ModuleState(PF().NAME)), "started")
    local row = k.settings:row(PF().SETTING)
    t.ok(row ~= nil, "a setting row")
    t.eq(row and row.default, false)
    t.eq(k.settings:get(PF().SETTING), false)
    local api = k.use(PF().NAME)
    t.ok(type(api.Want) == "function" and type(api.Where) == "function", "Want and Where")
end

tests["party follow: off by default nothing is sent, even when asked"] = function(t)
    local k, c = start("Ann")
    ask(c)
    k.use(PF().NAME).Want("Bob")
    c.advance(PF().EVERY + 1)
    t.eq(sent(c), 0)
end

tests["party follow: the one followed sends their spot on the party channel"] = function(t)
    local _, c = start("Ann", { on = true })
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 0, "nobody follows: nothing")
    ask(c)
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 1)
    local m = c.addonSent[#c.addonSent]
    t.eq(m and m.channel, "PARTY")
    local d = PF().Decode(m and m.text, ns.id.commVersion)
    t.eq(d and d.map, MAP)
end

tests["party follow: an ask for someone else sends nothing"] = function(t)
    local _, c = start("Ann", { on = true })
    ask(c, "Bob", "Cid")
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 0)
end

tests["party follow: nothing is sent outside a party, or in a raid"] = function(t)
    local k, c = start("Ann", { on = true, party = false })
    ask(c)
    k.use(PF().NAME).Want("Bob")
    c.advance(PF().EVERY + 1)
    t.eq(#c.addonSent, 0)
    local _, r = start("Ann", { on = true, party = { { unit = "raid1", name = "Bob" } } })
    ask(r)
    r.advance(PF().EVERY + 1)
    t.eq(#r.addonSent, 0)
end

tests["party follow: throttled, sent only when the spot changed, and only while followed"] = function(t)
    local _, c = start("Ann", { on = true })
    ask(c)
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 1)
    -- Same spot: nothing more.
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 1)
    -- Moved: waits for the throttle.
    c.setPosition(MAP, 0.6, 0.5)
    c.advance(0.1)
    c.setPosition(MAP, 0.7, 0.5)
    c.advance(0.1)
    t.eq(sent(c, "spot"), 1)
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), 2)
    -- The ask is not renewed: it runs out and nothing more is sent.
    c.advance(PF().HOLD + 1)
    local before = sent(c, "spot")
    c.setPosition(MAP, 0.1, 0.1)
    c.advance(PF().EVERY + 1)
    t.eq(sent(c, "spot"), before)
end

tests["party follow: the follower asks, throttled, while it wants a spot"] = function(t)
    local k, c = start("Ann", { on = true })
    local api = k.use(PF().NAME)
    api.Want("Bob")
    c.advance(0.1)
    t.eq(sent(c, "ask"), 1)
    api.Want("Bob")
    c.advance(1)
    t.eq(sent(c, "ask"), 1, "not again at once")
    api.Want("Bob")
    c.advance(PF().ASK_EVERY + 1)
    api.Want("Bob")
    c.advance(0.1)
    t.eq(sent(c, "ask"), 2)
    -- Not wanted any more: no more asks.
    c.advance(PF().ASK_EVERY * 3)
    t.eq(sent(c, "ask"), 2)
end

tests["party follow: a member's spot is kept; own echo, strangers and wrong channel are not"] = function(t)
    local k, c = start("Ann", { on = true })
    local spot = PF().EncodeSpot(OTHER, 0.3, 0.4, ns.id.commVersion)
    c.addonDeliver(PF().Prefix(), spot, "PARTY", "Ann")
    c.addonDeliver(PF().Prefix(), spot, "PARTY", "Zed")
    c.addonDeliver(PF().Prefix(), spot, "GUILD", "Bob")
    c.addonDeliver(PF().Prefix(), "1|S|nonsense", "PARTY", "Bob")
    local api = k.use(PF().NAME)
    t.eq(api.Where("Ann"), nil)
    t.eq(api.Where("Zed"), nil)
    t.eq(api.Where("Bob"), nil)
    c.addonDeliver(PF().Prefix(), spot, "PARTY", "Bob-Realm")
    local w = api.Where("Bob")
    t.eq(w and w.map, OTHER)
    -- Too old: not used.
    c.advance(PF().STALE + 1)
    t.eq(api.Where("Bob"), nil)
end

tests["party follow: Follow points at the shared spot when the member is on another map"] = function(t)
    local k, c = start("Ann", { on = true, follow = true })
    local follow = k.use("follow")
    t.ok(follow and follow.Pick("party1"), "Bob picked")
    -- The game gives no position for Bob (another map).
    t.eq(follow.Step(), nil, "nothing known yet")
    c.advance(0.1)
    t.ok(sent(c, "ask") >= 1, "Ann asked Bob for his spot")
    c.addonDeliver(PF().Prefix(), PF().EncodeSpot(OTHER, 0.3, 0.4, ns.id.commVersion), "PARTY", "Bob")
    local step = follow.Step()
    t.eq(step and step.place and step.place.map, OTHER)
    t.ok(close(step and step.place, "x", 0.3), "x")
    -- The game's own read wins when it has one.
    c.setUnitPosition("party1", MAP, 0.7, 0.2)
    step = follow.Step()
    t.eq(step and step.place and step.place.map, MAP)
end

-- Lead section 833: a spot is kept only from a member of the party the
-- client lists (alone or in a raid: none), and only with the setting on.
tests["party follow: nothing is kept alone, in a raid or with the setting off"] = function(t)
    local spot = PF().EncodeSpot(OTHER, 0.3, 0.4, ns.id.commVersion)
    local k, c = start("Ann", { on = true, party = false })
    c.addonDeliver(PF().Prefix(), spot, "PARTY", "Bob")
    t.eq(k.use(PF().NAME).Where("Bob"), nil, "alone")
    local kr, r = start("Ann", { on = true, party = { { unit = "raid1", name = "Bob" } } })
    r.addonDeliver(PF().Prefix(), spot, "PARTY", "Bob")
    t.eq(kr.use(PF().NAME).Where("Bob"), nil, "in a raid")
    local ko, o = start("Ann")
    o.addonDeliver(PF().Prefix(), spot, "PARTY", "Bob")
    t.eq(ko.use(PF().NAME).Where("Bob"), nil, "setting off")
end

return tests
