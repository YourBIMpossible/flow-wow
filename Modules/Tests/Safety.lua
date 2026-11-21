-- Self-tests for selling safety, saved data and diagnostics (lane W1).
-- Same style as Modules/Tests.lua: made-up inputs, Flow's own seams only,
-- and anything a test touches is put back.

local _, ns = ...

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

