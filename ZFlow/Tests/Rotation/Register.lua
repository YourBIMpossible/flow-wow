local _, ns = ...

-- Runs with or without the kernel files loaded: without them there is no
-- registry, and the pack is reached through ns.Packs alone.
-- The runner builds the kernel before the packs load, so the registry is
-- always there. Both tests say so outright: without it they fail, not skip.
local function shallow(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- The "register" problem recorded for one classPack key, or nil.
local function refusal(key)
    for _, p in ipairs(ns.problems:list("register")) do
        if p.owner == "classPack:" .. key then return p end
    end
end

return {
    ["the druid pack is on ns.Packs, and registered when the kernel is loaded"] = function(t)
        t.ok(type(ns.Packs.DRUID) == "table", "ns.Packs.DRUID")
        t.ok(type(ns.Get) == "function", "the kernel is loaded: ns.Get is there")
        t.eq(ns:Get("classPack", "DRUID"), ns.Packs.DRUID, "registered as a classPack")
        t.ok(ns:Get("classPack", "DRUID") == ns.Packs.DRUID, "the very table, not a copy")
    end,

    ["a pack that fails PackCheck is refused by the registry"] = function(t)
        t.eq((ns.PackCheck({})), false, "an empty pack fails")
        t.ok(type(ns.Register) == "function" and type(ns.Get) == "function" and type(ns.problems) == "table",
            "the kernel is loaded: the shared registry is there")
        -- The shipped classPack kind (Rotation/Pack.lua), on the shared kernel.
        -- Each refusal leaves one "register" problem in ns.problems.
        local _, why = ns.PackCheck({})
        local before = #ns.problems:list("register")
        t.eq(ns:Register("classPack", "TEST_EMPTY_PACK", {}), nil, "the shipped kind refuses an empty pack")
        t.eq(ns:Get("classPack", "TEST_EMPTY_PACK"), nil, "and it is not in the registry")
        t.eq(#ns.problems:list("register"), before + 1, "one problem recorded for it")
        local p = refusal("TEST_EMPTY_PACK")
        t.ok(p ~= nil, "the problem names the kind and the key")
        t.eq(p and p.text, table.concat(why, "; "), "and gives PackCheck's own reasons")
        -- A real pack with one required part taken out.
        local broken = shallow(ns.Packs.DRUID)
        broken.lists = nil
        t.eq((ns.PackCheck(broken)), false, "the druid pack without its lists fails PackCheck")
        t.eq(ns:Register("classPack", "TEST_NO_LISTS", broken), nil, "the shipped kind refuses it")
        t.eq(ns:Get("classPack", "TEST_NO_LISTS"), nil, "and it is not in the registry")
        t.ok(refusal("TEST_NO_LISTS") ~= nil, "with a problem recorded")
        t.eq(ns:Get("classPack", "DRUID"), ns.Packs.DRUID, "the good pack is still the one registered")
        -- The same rule on a fresh kernel with a kind built here.
        t.ok(type(ns.Kernel) == "function" and type(ns.make) == "table" and type(ns.make.fakeClient) == "function",
            "a fresh kernel can be built")
        local k = ns.Kernel({}, ns.make.fakeClient())
        k:Kind{ name = "classPack", row = function(row) return (ns.PackCheck(row)) end }
        t.eq(k:Register("classPack", "BAD", {}), nil, "refused")
        t.eq(k:Register("classPack", "DRUID", ns.Packs.DRUID), ns.Packs.DRUID, "a good pack is taken")
    end,
}
