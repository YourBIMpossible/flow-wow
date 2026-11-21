-- Self-tests for selling safety, saved data and diagnostics (lane W1).
-- Same style as Modules/Tests.lua: made-up inputs, Flow's own seams only,
-- and anything a test touches is put back.

local _, ns = ...

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

-- Lines in a log list that contain `text`.
local function count(log, text)
    local n = 0
    for _, l in ipairs(log) do
        if tostring(l):find(text, 1, true) then n = n + 1 end
    end
    return n
end

ns:Register("test", "safety: auto-sell at vendors is off until you turn it on (F-002)", function(t)
    local V = ns.vendor
    local fresh = {}
    V.SellDefaults(fresh)
    t:eq(fresh.autoAll, false, "no saved choice: auto-sell everything is off")
    t:eq(fresh.autoJunk, true, "grey junk still auto-sells")
    local chose = { autoAll = true }
    V.SellDefaults(chose)
    t:eq(chose.autoAll, true, "a saved choice to turn it on is kept")
    local row = ns:Get("setupItem", "autoAll")
    t:eq(row and row.suggested, false, "\"Flow suggests\" doesn't turn it on")
    t:ok(row and row.why:find("Off unless you turn it on", 1, true), "the setup text says it's off")
end)

ns:Register("test", "safety: gear Flow can't score for your class is kept (F-001)", function(t)
    local D = ns.disposition
    t:eq(D.ClassScored(nil), false, "no class data: not scored")
    t:eq(D.ClassScored({ weights = {} }), false, "no roles: not scored")
    t:eq(D.ClassScored({ weights = { dps = {} } }), false, "empty weights: not scored")
    t:eq(D.ClassScored({ weights = { dps = { str = 1 } } }), true, "weights: scored")
    local v = D.UnscoredGearVerdict({ canUse = true }, false)
    t:eq(v and v.action, "keep", "wearable, unscored: kept")
    v = D.UnscoredGearVerdict({ canUse = false, needsTraining = true }, false)
    t:eq(v and v.action, "keep", "trainable, unscored: kept")
    t:eq(D.UnscoredGearVerdict({ canUse = false }, false), nil, "can't wear it at all: other rules decide")
    t:eq(D.UnscoredGearVerdict({ canUse = true }, true), nil, "scored class: other rules decide")
    local r, before, after = ns:Get("disposition", "unscoredClass"),
        ns:Get("disposition", "laterOrOtherRole"), ns:Get("disposition", "unneededGear")
    t:ok(r and before and after and before.order < r.order and r.order < after.order,
        "checked after upgrades and before \"not better: sell\"")
end)

ns:Register("test", "safety: a sell rule that errors keeps the item, logged once (F-010)", function(t)
    local D = ns.disposition
    local list = {
        { key = "zzBoom", r = { check = function() error("boom") end } },
        { key = "zzSellIt", r = { check = function() return { action = "sell", reason = "sell it" } end } },
    }
    -- Flow's own log, caught for the test (and put back).
    local log = {}
    local function catch(_, _, msg) log[#log + 1] = msg end
    if not (ns.db and ns.db.diag) then t:ok(true, "no diagnostics yet"); return end
    with(ns, "Log", catch, function()
        with(D, "ruleFailed", {}, function()
            local v = D.VerdictFrom({ id = 1 }, list)
            t:eq(v.action, "keep", "the item is kept, not passed to a rule that sells it")
            t:eq(v.rule, "zzBoom", "the failed rule's verdict")
            D.VerdictFrom({ id = 2 }, list)
            t:eq(count(log, "zzBoom"), 1, "the error is in the diagnostics log once")
        end)
        local err = "zz test error " .. tostring(log)   -- (new each run: logged once a session)
        ns._logError("ZZ_TEST_EVENT", err)
        ns._logError("ZZ_TEST_EVENT", err)
        t:eq(count(log, err), 1, "an event handler's error is logged once")
    end)
end)

ns:Register("test", "safety: one character's hides and buybacks don't go to alts (F-013)", function(t)
    local account = { nav = { hidden = { ["7:1"] = true } }, sell = { never = { [123] = true } } }
    local main, alt = {}, {}
    ns:SplitCharacterData(account, main, { class = "PALADIN" })
    t:ok(account.nav.hidden and account.nav.hidden["7:1"], "the character loaded at the split keeps its hidden step")
    t:ok(account.sell.never and account.sell.never[123], "and its buyback list")
    ns:StoreCharacterData(account, main)
    ns:SplitCharacterData(account, alt, { class = "DRUID" })
    t:ok(not (account.nav.hidden and account.nav.hidden["7:1"]), "an alt starts with no hidden steps")
    t:ok(not (account.sell.never and account.sell.never[123]), "and its own buyback list")
    ns:StoreCharacterData(account, alt)
    t:ok(account.legacyShared["nav.hidden"]["7:1"], "the parked old data is untouched")
    ns:SplitCharacterData(account, main, { class = "PALADIN" })
    t:ok(account.nav.hidden and account.nav.hidden["7:1"], "the first character's data is still its own")

    local S = ns.gear.sets
    local got = S.AdoptSetRoles({ tank = "Tank", dps = "Ret" }, { "Ret" }, nil)
    t:ok(got and got.dps == "Ret" and got.tank == nil, "set roles: only sets this character has")
    got = S.AdoptSetRoles({ tank = "Tank", heal = "Old" }, { "Tank" }, { heal = "Holy" })
    t:ok(got and got.tank == "Tank" and got.heal == "Holy", "a role chosen since wins")
    t:eq(S.AdoptSetRoles({ tank = "Tank" }, { "Mine" }, nil), nil, "none of its sets: nothing adopted")
end)

ns:Register("test", "safety: a clearly better auction price beats disenchanting (F-003)", function(t)
    local D = ns.disposition
    t:eq(D.AuctionBeatsDisenchant(50000, 2000), true, "5 gold seen, 20 silver vendor: auction")
    t:eq(D.AuctionBeatsDisenchant(5000, 2000), false, "little more than vendor: disenchant")
    t:eq(D.AuctionBeatsDisenchant(9000, 0), false, "under a gold after the cut: disenchant")
    t:eq(D.AuctionBeatsDisenchant(12000, 0), true, "over a gold after the cut: auction")
    t:eq(D.AuctionBeatsDisenchant(nil, 2000), false, "no price seen: disenchant")
end)

ns:Register("test", "safety: Well Fed food is never sold as outgrown (F-004)", function(t)
    local D = ns.disposition
    t:eq(D.OutgrownVerdict("food", 1, 45, true), nil, "Well Fed food: kept")
    t:eq(D.OutgrownVerdict("food", 1, 45, nil), nil, "tooltip not read yet: kept")
    local v = D.OutgrownVerdict("food", 1, 45, false)
    t:eq(v and v.action, "sell", "plain outgrown food: sold")
    v = D.OutgrownVerdict("drink", 1, 45, nil)
    t:eq(v and v.action, "sell", "outgrown drink: sold")
    t:eq(D.OutgrownVerdict("food", 44, 45, false), nil, "not outgrown: kept")
end)

ns:Register("test", "safety: the diagnostics header doesn't name the character (F-021)", function(t)
    local line = ns.diag.HeaderLine("PALADIN", "1.0", 12, "Elwynn Forest")
    t:ok(line:find("PALADIN", 1, true) and line:find("level 12", 1, true), "class and level are there")
    t:eq(line:match("^character %((.-)%),"), "PALADIN", "no name or realm before the class")
end)

ns:Register("test", "safety: an upgrade once you train its weapon skill is Need, with a vendor badge (F-005)", function(t)
    local R, G, MM = ns.rollHint, ns.gear, ns.merchantMarks
    local trainable = { canUse = false, needsTraining = true, skill = "Swords", diffs = { dps = 3.2, tank = -1 } }
    local v = R.Verdict(trainable, "dps")
    t:eq(v and v.roll, "need", "a trainable upgrade: Need, as the bags keep it")
    t:ok(v and v.text:find("once you train Swords", 1, true), "and it says which skill to train")
    t:eq((R.ArrowFor(v)), true, "the roll window gets the upgrade arrow")
    t:eq(R.Fate(v, true, true), "need", "not sent to disenchant or the vendor")
    v = R.Verdict({ canUse = false, needsTraining = true, diffs = { dps = 0.1 } }, "dps")
    t:eq(v and v.roll, "greed", "trainable but not better: Greed")
    t:eq(R.Verdict({ canUse = false }, "dps").roll, "greed", "can't wear it at all: still Greed")
    t:eq(G.MarkDiffs(trainable), trainable.diffs, "bag and roll marks show the trainable item's scores")
    t:eq(MM.Diffs(trainable), trainable.diffs, "the vendor badge shows them too")
    t:eq(MM.UpgradeFor(trainable, "dps"), 3.2, "and the vendor calls it an upgrade")
    t:eq(MM.Diffs({ canUse = false }), nil, "unwearable gear: no badge")
    t:eq(G.MarkDiffs({ canUse = true }), nil, "no scores: no badge")
end)

ns:Register("test", "safety: a dual wielder's one-hander is compared with the off hand too (F-006)", function(t)
    local W = ns.gear.WeaponSlots
    local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
    t:ok(same(W("INVTYPE_WEAPON", false, true, "INVTYPE_WEAPON"), { 16 }), "can't dual wield: the main hand only")
    t:ok(same(W("INVTYPE_WEAPON", true, true, "INVTYPE_WEAPON"), { 16, 17 }), "dual wielding: the weaker of both hands")
    t:ok(same(W("INVTYPE_WEAPON", true, false, nil), { 16, 17 }), "dual wielder with an empty off hand: it fills it")
    t:ok(same(W("INVTYPE_WEAPON", true, true, "INVTYPE_SHIELD"), { 16 }), "a shield in the off hand: the main hand only")
    t:ok(same(W("INVTYPE_WEAPON", true, true, nil), { 16 }), "off hand not loaded yet: the main hand only")
    t:ok(same(W("INVTYPE_WEAPONOFFHAND", true, true, "INVTYPE_WEAPON"), { 17 }), "an off-hand weapon: the off hand")
    t:ok(same(W("INVTYPE_SHIELD", true, true, "INVTYPE_WEAPON"), { 17 }), "a shield: the off hand")
end)

ns:Register("test", "safety: one \"bags nearly full\" threshold for merchant, bank and quest items (F-008)", function(t)
    local N, B, QG = ns.BAGS_NEARLY_FULL, ns.banker, ns.questBags
    t:eq(ns.BagsNearlyFull(N), true, "at the threshold: nearly full")
    t:eq(ns.BagsNearlyFull(N + 1), false, "one more free: not")
    t:eq(ns.BagsNearlyFull(nil), false, "not known: not nearly full")
    t:eq(B.WorthAStop(1, N), true, "the bank step agrees at the threshold")
    t:eq(B.WorthAStop(1, N + 1), false, "and above it")
    local g = { key = "1:done", weight = 1 }
    QG.MarkStep(g, 2, N)
    t:eq(g.keep, true, "a quest hand-in is pulled forward at the threshold")
    g = { key = "1:done", weight = 1 }
    QG.MarkStep(g, 2, N + 1)
    t:ok(not g.keep, "and not above it")
    local plan = { slots = 2, turnin = { { title = "Q", slots = 2 } }, bank = {}, sell = {} }
    t:eq(#QG.Advice(plan, N), 1, "quest-item advice speaks at the threshold")
    t:eq(#QG.Advice(plan, N + 1), 0, "and not above it")
end)

ns:Register("test", "safety: saved-data updates run once each, in order (F-014)", function(t)
    local runs = {}
    local function m(key, order, fn)
        return { key = key, value = { order = order, run = fn or function(db) runs[#runs + 1] = key; db[key] = true end } }
    end
    local db = {}
    local ran = ns:RunMigrations(db, false, { m("zzB", 2), m("zzA", 1), m("zzC", 2) })
    t:eq(table.concat(ran, ","), "zzA,zzB,zzC", "in order, then by key")
    t:eq(db.version, 2, "the version is the highest order applied")
    ran = ns:RunMigrations(db, false, { m("zzB", 2), m("zzA", 1), m("zzC", 2) })
    t:eq(#ran, 0, "a second load runs none of them again")
    ran = ns:RunMigrations(db, false, { m("zzA", 1), m("zzLate", 1) })
    t:eq(table.concat(ran, ","), "zzLate", "one added later with a low order still runs, once")
    local boom = m("zzBoom", 3, function() error("boom") end)
    local _, failed = ns:RunMigrations(db, false, { boom })
    t:eq(#failed, 1, "one that errors is reported")
    t:ok(not db.migrations.zzBoom and db.version == 2, "and not marked done")
    ran = ns:RunMigrations(db, false, { m("zzBoom", 3) })
    t:eq(table.concat(ran, ","), "zzBoom", "so it's tried again next load")
    local fresh = {}
    ran = ns:RunMigrations(fresh, true, { m("zzFresh", 1) })
    t:ok(#ran == 0 and fresh.migrations.zzFresh and not fresh.zzFresh, "a fresh install marks them done without running")
    t:eq(#runs, 5, "each ran exactly once")
end)
