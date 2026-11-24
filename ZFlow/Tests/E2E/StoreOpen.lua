local _, ns = ...
-- Core/Store.lua through its real entry, on the whole add-on loaded on a
-- fake client: the login opens the saved data. A section saved as
-- something other than a table is replaced with an empty one, the old
-- value is kept once under recovered.<key>, and /zflow diag records why.
-- Saved data from a newer build is never written to; the reason is in the
-- snapshot, and the other scope still opens. Made-up saved values. Not
-- tested in game.
local tests = {}

local function boot(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, char or {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The kernel part of the newest snapshot /zflow diag kept.
local function diagKernel(c)
    c.slashes[ns.id.slash]("diag")
    local snaps = c.saved(ns.id.accountDB).diag.snaps
    return snaps[#snaps].kernel
end

local function problem(kernel, kind, owner)
    for _, p in ipairs(kernel.problems or {}) do
        if p.kind == kind and p.owner == owner then return p end
    end
    return nil
end

tests["store open: a section saved as a string is replaced, the old value is kept, diag says where"] = function(t)
    local c = boot({ settings = "not a table" })
    local db = c.saved(ns.id.accountDB)
    t.eq(type(db.settings), "table", "the section is a table again")
    t.eq(db.recovered and db.recovered.settings, "not a table", "the old value is kept once")
    local p = problem(diagKernel(c), "store", "account")
    t.ok(p ~= nil, "diag lists a store problem for the account data")
    t.eq(p and p.text, "settings was a string, not a table; it was replaced with an empty table; "
        .. "the old value is kept under recovered.settings in the account data")
end

tests["store open: an older kept value is never overwritten, and diag says the new one is lost"] = function(t)
    local c = boot({ layout = 7, recovered = { layout = "older" } })
    local db = c.saved(ns.id.accountDB)
    t.eq(type(db.layout), "table", "the section is a table again")
    t.eq(db.recovered.layout, "older", "the older kept value stands")
    local p = problem(diagKernel(c), "store", "account")
    t.eq(p and p.text, "layout was a number, not a table; it was replaced with an empty table; "
        .. "the old value is lost: recovered.layout in the account data already holds an older one")
end

tests["store open: saved data from a newer build is not written to; the character data still opens"] = function(t)
    local c, addon = boot({ schema = 99, settings = { kept = "as it was" } })
    local db = c.saved(ns.id.accountDB)
    local why = "saved schema 99 is newer than this build's 1"
    t.eq(db.schema, 99, "the schema number is left as it was")
    t.eq(db.settings, { kept = "as it was" }, "the account settings are left as they were")
    t.eq(addon.store.blocked.account, why, "writes to the account data are blocked")
    t.eq(addon.store.blocked.char, nil, "the character data is not blocked")
    t.eq(type(c.saved(ns.id.charDB).settings), "table", "the character data opened")
    local kernel = diagKernel(c)
    t.eq(kernel.blocked, { account = why }, "diag says which data is blocked and why")
    t.eq(problem(kernel, "schema", "account") and problem(kernel, "schema", "account").text, why)
end

tests["store open: clean saved data opens with no store or schema problem"] = function(t)
    local c, addon = boot({ settings = {} }, { settings = {} })
    t.eq(addon.store.opened, true, "the store opened")
    local kernel = diagKernel(c)
    t.eq(kernel.storeOpened, true)
    t.eq(kernel.blocked, {}, "nothing blocked")
    t.eq(problem(kernel, "store", "account"), nil, "no store problem")
    t.eq(problem(kernel, "schema", "account"), nil, "no schema problem")
end

return tests
