local _, ns = ...
-- The window kit's login probe (lead sections 297, 303, 307; UI/KitProbe.lua)
-- on the whole add-on loaded on a fake client, through its real entries:
-- the first PLAYER_ENTERING_WORLD of a login, the end of a fight that
-- held it back, and the journal add-on loading later. What it gives is the
-- saved diagnostics (diag.kitProbe), which the diag reader prints. Unknown
-- data: a client with no probe read. Offline: the fake client's answers,
-- not the game's. Not tested in game.
local tests = {}

-- opts.before(c): runs before the add-on loads.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function saved(c)
    local db = c.saved(ns.id.accountDB)
    return type(db.diag) == "table" and db.diag.kitProbe or nil
end

local function firstRow()
    local rows = ns.KitParts and ns.KitParts.rows
    return type(rows) == "table" and rows[1] or nil
end

tests["kit probe: asked once at login, the answers kept in the saved diagnostics, a zone change asks nothing"] = function(t)
    local row = firstRow()
    t.ok(row ~= nil and type(row.id) == "string", "the kit has rows to ask about")
    if not row then return end
    local c, addon = boot({ before = function(fc) fc.setKitProbe({ [row.id] = "missing: no such template" }) end })
    t.eq(c.kitProbeCalls, 1, "asked once")
    local rec = saved(c)
    t.ok(type(rec) == "table" and type(rec.rows) == "table", "the answer is in the saved diagnostics")
    if type(rec) ~= "table" or type(rec.rows) ~= "table" then return end
    t.eq(rec.rows[row.id], "missing: no such template", "what the client said, as it said it")
    t.eq(ns.KitProbe.Works(rec, row.id), false, "a row the client said no to does not work")
    local works = 0
    for id, text in pairs(rec.rows) do
        if id ~= row.id and id ~= "EJ_LOADED" and text == ns.KitProbe.WORKS then works = works + 1 end
    end
    t.eq(works, #ns.KitParts.rows - 1, "every other row works")
    t.eq(rec.rows.EJ_LOADED, "no", "the journal is not loaded")
    t.eq(c.addonLoaded(ns.KitProbe.JOURNAL), false, "and the probe did not load it")
    t.eq(rec.at, 1000, "when it was asked")

    local use = addon.use(ns.KitProbe.NAME)
    local result = use and use.Result and use.Result() or nil
    t.eq(result and result.rows[row.id], "missing: no such template", "the kit reads the same answer")
    t.ok(result ~= rec, "the kit's record is not the saved table itself")

    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    t.eq(c.kitProbeCalls, 1, "a zone change asks nothing")
    t.eq(addon.problems:count(ns.KitProbe.KIND), 0, "no problem recorded")
end

tests["kit probe: in a fight at login it waits for the fight's end, and the journal loading later is asked again"] = function(t)
    local c = boot({ before = function(fc) fc.setCombat(true) end })
    t.eq(saved(c), nil, "held back in the fight: nothing saved")
    local calls = c.kitProbeCalls
    t.ok(calls <= 1, "asked at most once, refused")
    c.setCombat(false)
    t.eq(c.kitProbeCalls, calls + 1, "asked when the fight ends")
    local rec = saved(c)
    t.ok(type(rec) == "table" and type(rec.rows) == "table", "and saved")
    if type(rec) ~= "table" then return end
    t.eq(rec.rows.EJ_LOADED, "no")
    c.setCombat(true)
    c.setCombat(false)
    t.eq(c.kitProbeCalls, calls + 1, "a later fight asks nothing")

    c.setLoaded(ns.KitProbe.JOURNAL, true)
    c.fire("ADDON_LOADED", ns.KitProbe.JOURNAL)
    t.eq(c.kitProbeCalls, calls + 2, "the journal loading is asked once")
    t.eq(saved(c).rows.EJ_LOADED, "yes", "and its row is re-recorded")
end

tests["kit probe: unknown data: a client with no probe read saves nothing and says why in the problems"] = function(t)
    local c, addon = boot({ before = function(fc) fc.kitProbe = nil end })
    t.eq(saved(c), nil, "nothing saved")
    local problems = addon.problems:list(ns.KitProbe.KIND)
    t.eq(#problems, 1, "one problem")
    t.eq(problems[1] and problems[1].text, ns.KitProbe.NO_READ, "saying the client has no probe read")
    local use = addon.use(ns.KitProbe.NAME)
    t.eq(use and use.Result and use.Result() or nil, nil, "the kit is given no record")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(#addon.problems:list(ns.KitProbe.KIND), 1, "not asked again at a zone change")
end

return tests
