local _, ns = ...

-- Runs with or without the kernel files loaded: without them there is no
-- registry, and the pack is reached through ns.Packs alone.
return {
    ["the druid pack is on ns.Packs, and registered when the kernel is loaded"] = function(t)
        t.ok(type(ns.Packs.DRUID) == "table", "ns.Packs.DRUID")
        if type(ns.Get) == "function" then
            t.eq(ns:Get("classPack", "DRUID"), ns.Packs.DRUID, "registered as a classPack")
        end
    end,

    ["a pack that fails PackCheck is refused by the registry"] = function(t)
        t.eq((ns.PackCheck({})), false, "an empty pack fails")
        if type(ns.Kernel) == "function" and ns.make and ns.make.fakeClient then
            local k = ns.Kernel({}, ns.make.fakeClient())
            k:Kind{ name = "classPack", row = function(row) return (ns.PackCheck(row)) end }
            t.eq(k:Register("classPack", "BAD", {}), nil, "refused")
            t.eq(k:Register("classPack", "DRUID", ns.Packs.DRUID), ns.Packs.DRUID, "a good pack is taken")
        end
    end,
}
