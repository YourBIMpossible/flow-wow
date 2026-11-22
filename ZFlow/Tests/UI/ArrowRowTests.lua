-- Arrow.Row when the kernel refuses the row (LEDGER 54, T6).
local _, ns = ...

local A = ns.Arrow

return {
    ["row: a refusal is remembered for that kernel, and is one arrow problem"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        k.store:open()
        -- Another row already has the arrows' place.
        t.ok(k:Setting({ key = "other.layout", scope = "account", type = "table",
                         label = "Other", path = A.PATH }) ~= nil)
        t.eq(A.Row(k), nil, "refused")
        t.eq(A.Row(k), nil)
        t.eq(A.Saved(k), { arrows = nil })
        t.eq(A.Saved(k), { arrows = nil })
        t.eq(k.problems:count("setting"), 1, "asked of the kernel once")
        t.eq(k.problems:count("arrow"), 1, "one problem of the arrow")

        -- Another kernel is asked on its own account.
        local k2 = ns.Kernel({}, ns.make.fakeClient())
        k2.store:open()
        t.ok(A.Row(k2) ~= nil, "taken there")
        t.ok(A.Row(k2) == A.Row(k2), "and the same row each time")
        t.eq(k2.problems:count(), 0)
    end,
}
