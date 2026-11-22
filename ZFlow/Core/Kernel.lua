-- Kernel: builds the services onto a table. The addon's own table is one
-- kernel (the last lines here); a test builds a fresh one over a fake client:
--   local k = ns.Kernel({}, ns.make.fakeClient())
-- Feature files loaded after this one use ns:Setting, ns:Kind, ns:Register,
-- ns:Module, ns.use, ns.store, ns.settings, ns.bus, ns.sched.
local _, ns = ...

function ns.Kernel(k, client, id)
    k.client = client
    k.id = id or ns.id
    k.problems = ns.make.problems()
    k.meter = ns.make.meter(k)
    k.store = ns.make.store(k)
    k.settings = ns.make.settings(k)
    k.bus = ns.make.bus(k)
    k.sched = ns.make.sched(k)
    ns.make.kinds(k)
    ns.make.modules(k)
    return k
end

ns.Kernel(ns, ns.client)
ns:Boot()
