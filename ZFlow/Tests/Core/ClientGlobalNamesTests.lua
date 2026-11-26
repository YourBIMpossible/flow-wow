-- F-19 (lead patch, Zen's CHANGES-1 of section 909): c.setGlobalNames, the
-- Key Bindings screen's names as plain string globals, over a hand-built
-- environment. It sets a name only while it is unset, never overwrites one,
-- skips anything not a string, and never raises. Made-up names. Not seen in
-- game.
--   c.setGlobalNames(names) -> how many it set
local _, ns = ...

local tests = {}

tests["c.setGlobalNames: an unset name is set, and the count is returned"] = function(t)
    local env = {}
    local c = ns.make.client(env)
    t.eq(c.setGlobalNames({ BINDING_HEADER_TEST = "Head", BINDING_NAME_TEST = "Entry" }), 2)
    t.eq(env.BINDING_HEADER_TEST, "Head")
    t.eq(env.BINDING_NAME_TEST, "Entry")
end

tests["c.setGlobalNames: a name already set is left as it was"] = function(t)
    local env = { BINDING_HEADER_TEST = "Another add-on's" }
    local c = ns.make.client(env)
    t.eq(c.setGlobalNames({ BINDING_HEADER_TEST = "Ours", BINDING_NAME_TEST = "Entry" }), 1)
    t.eq(env.BINDING_HEADER_TEST, "Another add-on's", "never overwritten")
    t.eq(env.BINDING_NAME_TEST, "Entry")
end

tests["c.setGlobalNames: a name or text that is not a string is skipped"] = function(t)
    local env = {}
    local c = ns.make.client(env)
    t.eq(c.setGlobalNames({ [1] = "Number name", BINDING_NAME_TEST = 5, BINDING_HEADER_TEST = "Head" }), 1)
    t.eq(env[1], nil)
    t.eq(env.BINDING_NAME_TEST, nil)
    t.eq(env.BINDING_HEADER_TEST, "Head")
end

tests["c.setGlobalNames: a non-table argument returns 0"] = function(t)
    local c = ns.make.client({})
    t.eq(c.setGlobalNames(nil), 0)
    t.eq(c.setGlobalNames("BINDING_NAME_TEST"), 0)
    t.eq(c.setGlobalNames(7), 0)
end

return tests
