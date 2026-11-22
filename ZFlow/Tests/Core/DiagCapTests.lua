-- The bound on what Diag saves (L6-S): the newest KEEP snapshots, the names
-- table once with its client build and not in each snapshot, and the counts
-- of snapshots and of starts kept beside them. Fake client; no game client
-- is involved.
local _, ns = ...

local Diag = ns.Diag

local function env()
    return {
        GetMoney = function() return 5 end,
        GetBuildInfo = function() return "1.16.1", "7777", "Nov 1 2026", 16001 end,
        NUM_BAG_SLOTS = 4,
    }
end

-- saved: the account table of an earlier start, or nil.
local function start(e, saved)
    local c = ns.make.fakeClient({ env = e or env() })
    c.setSaved(ns.id.accountDB, saved or {})
    local k = ns.Kernel({}, c)
    local d = Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, d
end

local function saved(c) return c.saved(ns.id.accountDB).diag end

-- How many values a table writes when saved: every key of every table,
-- a table met twice counted twice, as the saved file repeats it.
local function nodes(v, depth)
    if type(v) ~= "table" then return 1 end
    depth = depth or 0
    if depth > 30 then return 1 end
    local n = 1
    for _, x in pairs(v) do n = n + nodes(x, depth + 1) end
    return n
end

return {
    ["diag cap: the newest KEEP snapshots are kept"] = function(t)
        local _, c, d = start()
        t.eq(Diag.KEEP, 20)
        for i = 1, 3 * Diag.KEEP do d.snapshot("n" .. i) end
        local s = saved(c)
        t.eq(#s.snaps, Diag.KEEP)
        t.eq(s.snaps[Diag.KEEP].why, "n" .. (3 * Diag.KEEP))
        t.eq(s.snaps[1].why, "n" .. (2 * Diag.KEEP + 1))
    end,

    ["diag cap: the count of snapshots and of starts is kept past the trim"] = function(t)
        local _, c, d = start()
        for _ = 1, 50 do d.snapshot("again") end
        local s = saved(c)
        t.eq(s.count, 51)
        t.eq(s.starts, 1)
        local _, c2, d2 = start(nil, c.saved(ns.id.accountDB))
        for _ = 1, 50 do d2.snapshot("again") end
        s = saved(c2)
        t.eq(s.starts, 2, "a second start is counted")
        t.eq(s.count, 102)
        t.eq(#s.snaps, Diag.KEEP)
    end,

    ["diag cap: the names table is saved once, with its build, not in a snapshot"] = function(t)
        local _, c, d = start()
        for _ = 1, 5 do d.snapshot("again") end
        local s = saved(c)
        for i = 1, #s.snaps do
            t.eq(s.snaps[i].names, nil, "no names table in a saved snapshot")
        end
        t.ok(type(s.names) == "table", "kept beside the snapshots")
        if type(s.names) ~= "table" then return end
        t.eq(s.names.build, "1.16.1 (7777)")
        t.eq(s.names.names["GetMoney"], "function")
        t.eq(s.names.names["NUM_BAG_SLOTS"], "number")
        t.eq(s.names.names["GetContainerNumSlots"], "nil", "an absent name is still recorded")
        local n = 0
        for _ in pairs(s.names.names) do n = n + 1 end
        t.eq(n, #Diag.NAMES)
    end,

    ["diag cap: Collect still answers the names; Save takes them out"] = function(t)
        local k, c = start()
        local snap = Diag.Collect(k, "test")
        t.eq(snap.names["GetMoney"], "function")
        Diag.Save(k, snap)
        t.eq(snap.names, nil)
        t.eq(saved(c).names.names["GetMoney"], "function")
    end,

    ["diag cap: a new build replaces the names table, it does not add one"] = function(t)
        local _, c = start()
        t.eq(saved(c).names.build, "1.16.1 (7777)")
        local e = env()
        e.GetBuildInfo = function() return "1.16.2", "7801" end
        e.GetMoney = nil
        local _, c2 = start(e, c.saved(ns.id.accountDB))
        local s = saved(c2)
        t.eq(s.names.build, "1.16.2 (7801)")
        t.eq(s.names.names["GetMoney"], "nil", "the names of the build now running")
        t.eq(s.names[1], nil)
        t.eq(s.names[2], nil)
    end,

    ["diag cap: a client that does not say its build is build unknown"] = function(t)
        t.eq(Diag.BuildKey(ns.make.fakeClient({ env = {} })), "unknown")
        t.eq(Diag.BuildKey(ns.make.fakeClient({ env = { GetBuildInfo = function() error("boom") end } })), "unknown")
        t.eq(Diag.BuildKey(ns.make.fakeClient({ env = { GetBuildInfo = function() return nil end } })), "unknown")
        t.eq(Diag.BuildKey(ns.make.fakeClient({ env = { GetBuildInfo = function() return "1.16.1" end } })), "1.16.1")
        local hidden = { GetBuildInfo = function() return "1.16.1", "7777" end, issecretvalue = function() return true end }
        t.eq(Diag.BuildKey(ns.make.fakeClient({ env = hidden })), "unknown")
    end,

    ["diag cap: saved size stops growing once KEEP snapshots are held"] = function(t)
        local _, c, d = start()
        for _ = 1, Diag.KEEP do d.snapshot("again") end
        local full = nodes(saved(c))
        for _ = 1, 10 * Diag.KEEP do d.snapshot("again") end
        local later = nodes(saved(c))
        t.ok(later <= full + full / Diag.KEEP,
            "200 more snapshots add less than one snapshot of size: " .. full .. " then " .. later)
    end,

    ["diag cap: the names are a small part of each snapshot no longer"] = function(t)
        local _, c, d = start()
        for _ = 1, Diag.KEEP do d.snapshot("again") end
        local s = saved(c)
        local names = nodes(s.names)
        t.ok(names > #Diag.NAMES, "the names table is all there, once")
        t.ok(nodes(s) < nodes(s.snaps) + 2 * names + nodes(s.api) + 10,
            "beside the snapshots there is one names table, the api and the counts")
    end,
}
