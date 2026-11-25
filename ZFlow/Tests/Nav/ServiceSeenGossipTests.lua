-- Tests for the gossip learning of ZFlow/Nav/ServiceSeen.lua (A2-27): the
-- services an npc offers in its gossip window are saved with its place,
-- through the same store and cap as a service window. The gossip read is
-- not in the fake client (CLIENT NEED), so a made-up one is set on the
-- test's own fake here. Made-up npcs, test only. Not tested in game.
local _, ns = ...

local S = ns.ServiceSeen
local tests = {}

local KEEPER = { guid = "Creature-0-1-2-3-77-0", name = "Innkeeper Test" }

-- opts: char (saved table), npc (what serviceNpc() answers), options (what
-- gossipOptions() answers; false: the client has no such read), repair.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClock(5000)
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.25)
    local held = { npc = opts.npc, options = opts.options, repair = opts.repair, reads = 0 }
    c.serviceNpc = function() return held.npc end
    c.merchantRepairs = function() return held.repair end
    if opts.options ~= false then
        c.gossipOptions = function()
            held.reads = held.reads + 1
            if held.raise then error("the gossip read broke") end
            return held.options
        end
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local w = S.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, w, held
end

local function places(c)
    local root = c.saved(ns.id.charDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.places or nil
    return type(root) == "table" and root.services or nil
end

local function size(v)
    local n = 0
    if type(v) == "table" then
        for _ in pairs(v) do n = n + 1 end
    end
    return n
end

tests["service gossip: the names are the ones agreed"] = function(t)
    t.eq(S.GOSSIP_EVENT, "GOSSIP_SHOW")
    t.eq(S.GOSSIP_KINDS, { vendor = "vendor", taxi = "flight", banker = "banker", binder = "innkeeper" })
end

tests["service gossip: the rule maps the game's option types, in order, each once"] = function(t)
    t.eq(S.GossipKinds({ { type = "vendor" }, { type = "binder" } }), { "vendor", "innkeeper" })
    t.eq(S.GossipKinds({ { type = "taxi", icon = 5 }, { type = "banker" }, { type = "taxi" } }),
        { "flight", "banker" })
    t.eq(S.GossipKinds({ { type = "gossip" }, { type = "trainer" }, { type = "battlemaster" } }), {})
end

tests["service gossip: the rule ignores what is not an option with a type"] = function(t)
    t.eq(S.GossipKinds(nil), {})
    t.eq(S.GossipKinds("vendor"), {})
    t.eq(S.GossipKinds({ "vendor", 7, false, {}, { type = 3 }, { type = "" }, { name = "vendor" } }), {})
    -- The game's own type names only: another spelling is not guessed at.
    t.eq(S.GossipKinds({ { type = "Vendor" }, { type = "innkeeper" }, { type = "flight" } }), {})
    -- An icon alone says nothing here.
    t.eq(S.GossipKinds({ { icon = 132060 } }), {})
end

tests["service gossip: a vendor and an innkeeper option save one place with both kinds"] = function(t)
    local k, c, w, held = start({ npc = KEEPER, options = { { type = "vendor" }, { type = "binder" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), { [KEEPER.guid] = {
        guid = KEEPER.guid, name = "Innkeeper Test", map = 1411, x = 0.5, y = 0.25,
        kinds = { vendor = true, innkeeper = true }, seen = 5000, n = 1,
    } })
    t.eq(w.last(), { kind = "service", service = "vendor", services = { "vendor", "innkeeper" },
                     gossip = true, ok = true, key = KEEPER.guid, name = "Innkeeper Test" })
    t.eq(held.reads, 1, "the options are read once")
    t.eq(k.problems:count(), 0)
end

tests["service gossip: an npc with no guid is saved by its name"] = function(t)
    local _, c = start({ npc = { name = "Stable Hand" }, options = { { type = "taxi" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), { ["Stable Hand"] = {
        name = "Stable Hand", map = 1411, x = 0.5, y = 0.25, kinds = { flight = true }, seen = 5000, n = 1,
    } })
end

tests["service gossip: options of an unknown type save nothing"] = function(t)
    local k, c, w = start({ npc = KEEPER, options = { { type = "gossip" }, { type = "trainer" }, { icon = 9 } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last(), nil, "nothing was read as a sighting")
    t.eq(k.problems:count(), 0)
end

tests["service gossip: an unknown option beside a known one is left out"] = function(t)
    local _, c = start({ npc = KEEPER, options = { { type = "gossip" }, { type = "banker" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c)[KEEPER.guid].kinds, { banker = true })
end

tests["service gossip: no options, or an answer that is no list, saves nothing"] = function(t)
    local _, c, w, held = start({ npc = KEEPER, options = {} })
    c.fire("GOSSIP_SHOW")
    held.options = nil
    c.fire("GOSSIP_SHOW")
    held.options = "vendor"
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last(), nil)
end

tests["service gossip: the kinds merge onto a place its service window saved"] = function(t)
    local _, c, w, held = start({ npc = KEEPER, repair = true, options = { { type = "vendor" }, { type = "binder" } } })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[KEEPER.guid].kinds, { vendor = true, repair = true })
    -- No merchant window is open at the gossip: the client now says "no
    -- repair", and that must not take the mark off.
    held.repair = false
    c.setPosition(1411, 0.502, 0.25)
    c.fire("GOSSIP_SHOW")
    local e = places(c)[KEEPER.guid]
    t.eq(e.kinds, { vendor = true, repair = true, innkeeper = true })
    t.eq({ e.x, e.y, e.n }, { 0.5, 0.25, 2 }, "the saved spot stays, one more sighting")
    t.eq(w.last().moved, false)
    t.eq(w.last().repair, nil, "the gossip says nothing of repairs")
    t.eq(size(places(c)), 1)
end

tests["service gossip: a trade mark already saved is kept"] = function(t)
    local rows = { [KEEPER.guid] = { guid = KEEPER.guid, name = KEEPER.name, map = 1411, x = 0.5, y = 0.25,
                                     kinds = { vendor = true }, trade = true, n = 3 } }
    local _, c = start({ npc = KEEPER, char = { learned = { places = { services = rows } } },
                         options = { { type = "vendor" }, { type = "taxi" } } })
    c.fire("GOSSIP_SHOW")
    local e = places(c)[KEEPER.guid]
    t.eq(e.trade, true)
    t.eq(e.kinds, { vendor = true, flight = true })
    t.eq(e.n, 4)
end

tests["service gossip: a service window after the gossip adds to the same place"] = function(t)
    local _, c = start({ npc = KEEPER, repair = false, options = { { type = "binder" } } })
    c.fire("GOSSIP_SHOW")
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[KEEPER.guid].kinds, { innkeeper = true, vendor = true })
    t.eq(size(places(c)), 1)
end

-- Lead section 657 item 1: a visit that opens the gossip window and then
-- a service window of the same npc is ONE sighting, not two. A new gossip
-- window is a new visit; another npc's window is its own sighting.
-- Red before: the service window after the gossip counted once more.
tests["service gossip: gossip and then that npc's service window is one visit, counted once"] = function(t)
    local _, c, w, held = start({ npc = KEEPER, repair = true, options = { { type = "vendor" }, { type = "binder" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c)[KEEPER.guid].n, 1, "the gossip window: one sighting")
    c.fire("MERCHANT_SHOW")
    local e = places(c)[KEEPER.guid]
    t.eq(e.n, 1, "the vendor window of the same visit does not count again")
    t.eq(e.kinds, { vendor = true, innkeeper = true, repair = true }, "what the vendor window says is still taken")
    t.eq(w.last().ok, true, "and it is still a good report")
    c.fire("CONFIRM_BINDER")
    t.eq(places(c)[KEEPER.guid].n, 1, "nor does another window of that visit")
    c.fire("GOSSIP_SHOW")
    t.eq(places(c)[KEEPER.guid].n, 2, "the gossip window again: a new visit")
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[KEEPER.guid].n, 2, "and its vendor window is that same visit")
    -- Another npc in between ends the visit.
    local other = { guid = "Creature-0-0-0-0-777-0", name = "Other Trader" }
    held.npc = other
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[other.guid].n, 1, "another npc's window is its own sighting")
    held.npc = KEEPER
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[KEEPER.guid].n, 3, "back at the first npc with no gossip window: a sighting of its own")
end

tests["service gossip: a service window with no gossip before it counts as it always did"] = function(t)
    local _, c = start({ npc = KEEPER, repair = false, options = false })
    c.fire("MERCHANT_SHOW")
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[KEEPER.guid].n, 2, "two vendor windows, two sightings")
end

tests["service gossip: a client with no gossip read changes nothing"] = function(t)
    local k, c, w = start({ npc = KEEPER, options = false })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last(), nil)
    t.eq(k.problems:count(), 0)
    -- The service windows still work as before.
    c.fire("BANKFRAME_OPENED")
    t.eq(places(c)[KEEPER.guid].kinds, { banker = true })
    t.eq(w.last(), { kind = "service", service = "banker", ok = true, key = KEEPER.guid,
                     name = "Innkeeper Test" })
end

tests["service gossip: no npc known writes nothing"] = function(t)
    local _, c, w, held = start({ options = { { type = "vendor" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the npc is not known")
    held.npc = { guid = "", name = "" }
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil, "empty words are no name")
end

tests["service gossip: no position writes nothing"] = function(t)
    local _, c, w = start({ npc = KEEPER, options = { { type = "vendor" } } })
    c.setPosition(nil)
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the position is not known")
end

tests["service gossip: past the cap a new place is not written, a known one still is"] = function(t)
    local rows = {}
    for i = 1, S.MAX do
        rows["npc " .. i] = { map = 1, x = 0.5, y = 0.5, kinds = { vendor = true }, n = 1 }
    end
    local _, c, w, held = start({ npc = KEEPER, char = { learned = { places = { services = rows } } },
                                  options = { { type = "vendor" }, { type = "binder" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the list of places is full")
    t.eq(places(c)[KEEPER.guid], nil)
    t.eq(size(places(c)), S.MAX, "the cap holds")
    held.npc = { name = "npc 1" }
    c.fire("GOSSIP_SHOW")
    t.eq(w.last().ok, true)
    t.eq(places(c)["npc 1"].kinds, { vendor = true, innkeeper = true })
    t.eq(size(places(c)), S.MAX)
end

tests["service gossip: saved places that are not a table are not written over"] = function(t)
    local _, c, w = start({ npc = KEEPER, char = { learned = { places = { services = "junk" } } },
                            options = { { type = "vendor" } } })
    c.fire("GOSSIP_SHOW")
    t.eq(places(c), "junk")
    t.eq(w.last().reason, "the places cannot be saved")
end

tests["service gossip: a read that raises writes nothing and raises nothing"] = function(t)
    local k, c, w, held = start({ npc = KEEPER, options = { { type = "vendor" } } })
    held.raise = true
    c.fire("GOSSIP_SHOW")
    t.eq(held.reads, 1, "the read was tried")
    t.eq(places(c), nil)
    t.eq(w.last(), nil)
    t.eq(k.problems:count(), 0, "nothing is counted against the module")
    -- The next window, with the read mended, is learned as usual.
    held.raise = nil
    c.fire("GOSSIP_SHOW")
    t.eq(places(c)[KEEPER.guid].kinds, { vendor = true })
end

tests["service gossip: the read alone, with no kernel"] = function(t)
    t.eq(S.Gossip(nil, nil), nil)
    t.eq(S.Gossip({}, nil), nil)
    t.eq(S.Gossip({ gossipOptions = function() return { { type = "gossip" } } end }, nil), nil)
    local r = S.Gossip({ gossipOptions = function() return { { type = "banker" } } end }, nil)
    t.eq(r, { kind = "service", service = "banker", services = { "banker" }, gossip = true,
              ok = false, reason = "the npc is not known" })
end

return tests
