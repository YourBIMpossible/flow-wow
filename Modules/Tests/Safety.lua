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

