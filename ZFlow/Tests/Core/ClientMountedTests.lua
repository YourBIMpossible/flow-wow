-- c.mounted() (S34, LEDGER 153/169): the read Nav/Legs.lua needs to tell a
-- trip on foot from one ridden. The real client over a hand-built
-- environment; ClientFake's own version is checked at the end.
--   c.mounted() -> true / false, or nil when the client will not say
-- Unknown stays unknown: nil is never "on foot".
local _, ns = ...

local tests = {}

tests["c.mounted: true, false, or not known"] = function(t)
    local asked = 0
    local c = ns.make.client({ IsMounted = function(...)
        asked = asked + 1
        t.eq(select("#", ...), 0, "asked with no argument")
        return true
    end })
    t.eq(c.mounted(), true)
    t.eq(asked, 1)
    t.eq(ns.make.client({ IsMounted = function() return false end }).mounted(), false)
    t.eq(ns.make.client({}).mounted(), nil, "no such call: not known, never false")
    t.eq(ns.make.client({ IsMounted = function() error("no") end }).mounted(), nil, "raised")
    t.eq(ns.make.client({ IsMounted = function() return nil end }).mounted(), nil, "no answer")
    t.eq(ns.make.client({ IsMounted = function() return 1 end }).mounted(), nil, "not a plain yes or no")
    local secret = ns.make.client({ IsMounted = function() return true end, issecretvalue = function() return true end })
    t.eq(secret.mounted(), nil, "a secret answer")
end

tests["fake client: mounted is unknown until set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.mounted(), nil)
    c.setMounted(true)
    t.eq(c.mounted(), true)
    c.setMounted(false)
    t.eq(c.mounted(), false)
    c.setMounted(nil)
    t.eq(c.mounted(), nil)
end

return tests
