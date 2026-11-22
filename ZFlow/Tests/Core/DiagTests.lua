-- The diagnostic collector over the fake client: what a snapshot holds,
-- where it is saved, when one is taken, and that a paused addon still
-- collects. No game client is involved.
local _, ns = ...

local function env()
    return {
        GetMoney = function() return 12345 end,
        GetBuildInfo = function() return "1.16.1", "7777", "Nov 1 2026", 16001 end,
        UnitClass = function(unit) return "Paladin", "PALADIN", 2 end,
        GetNumSpellTabs = function() error("not now") end,
        NUM_BAG_SLOTS = 4,
        C_Map = { GetBestMapForUnit = function() return 1411 end },
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if slot == 2 then return { stackCount = 3, itemID = 2318, sub = {} } end
            end,
            GetContainerItemLink = function() return "item:2318" end,
        },
        GetItemInfo = function(link) return "Light Leather", link, 1 end,
    }
end

local function start(opts)
    local c = ns.make.fakeClient({ env = env() })
    if opts and opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Boot()
    return k, c, d
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("VARIABLES_LOADED")
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

return {
    ["shape: values, types and one level of a table answer"] = function(t)
        local row = ns.Diag.Shape(true, 5, "a", nil, { x = 1, y = {} })
        t.eq(row.ok, true)
        t.eq(row.n, 4)
        t.eq(row.types, { "number", "string", "nil", "table" })
        t.eq(row.values, { v1 = 5, v2 = "a", v4 = { x = 1, y = "table" } })
        t.eq(ns.Diag.Shape(false, "boom"), { ok = false, n = 1, types = { "string" }, values = { v1 = "boom" } })
    end,

    ["collect: names, reads, shapes and kernel state"] = function(t)
        local k, c = start()
        c.setMoney(99)
        c.setBagItems({ { item = 2318, count = 4 } })
        login(c)
        local snap = ns.Diag.Collect(k, "test")
        t.eq(snap.why, "test")
        t.eq(snap.names["GetMoney"], "function")
        t.eq(snap.names["C_Map.GetBestMapForUnit"], "function")
        t.eq(snap.names["NUM_BAG_SLOTS"], "number")
        t.eq(snap.names["GetContainerNumSlots"], "nil", "an absent name is recorded as nil, not left out")
        t.eq(snap.reads.money, 99)
        t.eq(snap.reads.bagStacks, 1)
        t.eq(snap.known.money, true)
        t.eq(snap.known.position, false, "an unknown read is marked, since nil leaves no trace when saved")
        t.eq(snap.reads.predecessorLoaded, false)
        t.eq(snap.shapes.build.values, { v1 = "1.16.1", v2 = "7777", v3 = "Nov 1 2026", v4 = 16001 })
        t.eq(snap.shapes.class.values.v2, "PALADIN")
        t.eq(snap.shapes.bestMap.values.v1, 1411)
        t.eq(snap.shapes.spellTabs.ok, false, "a call that errors is recorded, it does not stop the snapshot")
        t.eq(snap.shapes.level.ok, false, "a name the client lacks is recorded as not callable")
        t.eq(snap.shapes.slotInfo.values.v1, { stackCount = 3, itemID = 2318, sub = "table" })
        t.eq(snap.shapes.itemInfo.values.v1, "Light Leather")
        t.eq(snap.kernel.phase, "running")
        t.eq(snap.kernel.paused, false)
        t.eq(snap.kernel.storeOpened, true)
    end,

    ["start: login saves one snapshot with the timing marks in order"] = function(t)
        local _, c = start()
        t.eq(c.savedExists(ns.id.accountDB), false, "nothing is written before the client has loaded saved data")
        c.setSaved(ns.id.accountDB, {})
        login(c)
        c.fire("PLAYER_ENTERING_WORLD")
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.count, 1, "a second entering-world (a zone change) takes no second login snapshot")
        local snap = d.snaps[1]
        t.eq(snap.why, "login")
        t.eq(snap.timing.order, { "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })
        t.eq(snap.timing.fileLoad.accountData, false)
        t.eq(snap.timing.ADDON_LOADED.accountData, true)
        t.eq(snap.timing.ADDON_LOADED.phase ~= "running", true, "the kernel had not loaded at ADDON_LOADED")
        t.eq(snap.timing.PLAYER_ENTERING_WORLD.phase, "running")
    end,

    ["start: another addon's ADDON_LOADED is not ours"] = function(t)
        local _, c, d = start()
        c.fire("ADDON_LOADED", "SomethingElse")
        t.eq(d.timing.ADDON_LOADED, nil)
        t.eq(#d.timing.order, 0)
    end,

    ["start: a window opening takes a snapshot named for it"] = function(t)
        local _, c = start()
        login(c)
        c.fire("MERCHANT_SHOW")
        c.fire("TRAINER_SHOW")
        c.setBankOpen(true)
        local snaps = c.saved(ns.id.accountDB).diag.snaps
        t.eq({ snaps[1].why, snaps[2].why, snaps[3].why, snaps[4].why }, { "login", "vendor", "trainer", "bank" })
        t.eq(snaps[4].reads.bankOpen, true)
    end,

    ["save: only the newest twelve are kept, the count keeps rising"] = function(t)
        local _, c, d = start()
        login(c)
        for _ = 1, 20 do d.snapshot("again") end
        local saved = c.saved(ns.id.accountDB).diag
        t.eq(#saved.snaps, 12)
        t.eq(saved.count, 21)
        t.eq(saved.snaps[12].why, "again")
    end,

    ["slash: diag saves and says so, clear forgets, anything else reports state"] = function(t)
        local _, c = start()
        login(c)
        local run = c.slashes[ns.id.slash]
        t.eq(type(run), "function")
        run("diag")
        t.eq(c.saved(ns.id.accountDB).diag.count, 2)
        t.ok(c.printed[#c.printed]:find("snapshot 2", 1, true), c.printed[#c.printed])
        run(" DIAG clear ")
        t.eq(c.saved(ns.id.accountDB).diag, nil)
        run("")
        t.ok(c.printed[#c.printed]:find("running", 1, true), c.printed[#c.printed])
    end,

    ["guard: a paused addon still collects and records why it paused"] = function(t)
        local k, c = start({ predecessor = true })
        login(c)
        t.eq(k.paused, true)
        local snap = c.saved(ns.id.accountDB).diag.snaps[1]
        t.eq(snap.kernel.paused, true)
        t.eq(snap.kernel.phase, "paused")
        t.eq(snap.kernel.storeOpened, false, "a paused addon opens no store")
        t.eq(snap.reads.predecessorLoaded, true)
        t.eq(type(snap.kernel.pauseText), "string")
    end,

    ["errors: kept once with a count, marked ours or not, saved with the snapshot"] = function(t)
        local _, c, d = start()
        c.raise("Interface/AddOns/" .. ns.id.addon .. "/Core/X.lua:5: boom")
        c.raise("Interface/AddOns/" .. ns.id.addon .. "/Core/X.lua:5: boom")
        c.raise("Interface/AddOns/Other/y.lua:1: theirs")
        login(c)
        local e = c.saved(ns.id.accountDB).diag.snaps[1].timing.errors
        t.eq(#e, 2)
        t.eq({ e[1].count, e[1].ours, e[2].count, e[2].ours }, { 2, true, 1, false })
        for i = 1, 100 do c.raise("different " .. i) end
        t.eq(#d.timing.errors, 40, "the list is capped")
    end,

    ["session: each login counts a start and names the character when the client says"] = function(t)
        local _, c = start()
        login(c)
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.starts, 1)
        t.eq(d.snaps[1].timing.start, 1)
        t.eq(d.snaps[1].timing.realm, "Testrealm")
        t.eq(d.snaps[1].timing.character, nil, "a client that will not name the character leaves it unknown")
    end,

    ["collect: a client that answers nothing still gives a snapshot"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local snap = ns.Diag.Collect(k, "bare")
        t.eq(snap.names["GetMoney"], "nil")
        t.eq(snap.known.money, false)
        t.eq(snap.shapes.build.ok, false)
        t.eq(snap.shapes.slotInfo, nil)
    end,
}
