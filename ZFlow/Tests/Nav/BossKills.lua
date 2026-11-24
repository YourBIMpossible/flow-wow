-- Boss kills (lead section 305, the data for the in-dungeon tracker, item
-- (d) of section 303): does the client report a boss kill? Read only: the
-- encounter events are listened to, counted in the account's diag record
-- and said by the diag word, and the kills of this instance visit are
-- kept for the tracker. Fake client; made-up encounters. Not tested in game.
local _, ns = ...
local tests = {}

local K = ns.BossKills

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    for _, e in ipairs(opts.refused or {}) do c.setEventFault(e, true) end
    c.setInstance(opts.instance or { inside = true, kind = "party" })
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    local api = K.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag
end

local function said(c, diag)
    local from = #c.printed
    diag.commands[K.WORD]("")
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, " / ")
end

tests["boss kills: names"] = function(t)
    t.eq(K.NAME, "bossKills")
    t.eq(K.WORD, "bosskills")
    t.eq(K.PATH, "diag.bossKills")
    t.eq(K.EVENTS, { "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_ENTERING_WORLD" })
end

tests["boss kills: an encounter won is a kill of this visit, counted for the account"] = function(t)
    local k, c, api = start()
    c.fire("ENCOUNTER_START", 1001, "Rhahk'Zor", 1, 5)
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    t.eq(api.Kills(), { { id = 1001, name = "Rhahk'Zor" } })
    t.eq(k.store:get("account", K.PATH), { ends = 1, kills = 1 })
end

tests["boss kills: an encounter lost is counted as an end, not a kill"] = function(t)
    local k, c, api = start()
    c.fire("ENCOUNTER_END", 1002, "Sneed", 1, 5, 0)
    t.eq(api.Kills(), {})
    t.eq(k.store:get("account", K.PATH), { ends = 1, kills = 0 })
end

tests["boss kills: BOSS_KILL is counted on its own and names a kill once"] = function(t)
    local k, c, api = start()
    c.fire("BOSS_KILL", 1003, "Gilnid")
    c.fire("ENCOUNTER_END", 1003, "Gilnid", 1, 5, 1)
    t.eq(api.Kills(), { { id = 1003, name = "Gilnid" } }, "one kill, whichever event said it")
    t.eq(k.store:get("account", K.PATH), { ends = 1, kills = 1, bossKill = 1 })
end

tests["boss kills: leaving the instance starts a new visit; the account counts stay"] = function(t)
    local k, c, api = start()
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.setInstance({ inside = false, kind = "none" })
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(api.Kills(), {})
    t.eq(k.store:get("account", K.PATH).kills, 1)
end

tests["boss kills: an event with no encounter id is not a kill"] = function(t)
    local k, c, api = start()
    c.fire("ENCOUNTER_END", nil, "Nobody", 1, 5, 1)
    c.fire("BOSS_KILL", "x", "Nobody")
    t.eq(api.Kills(), {})
    t.eq(k.problems:count(), 0)
end

tests["boss kills: the diag word says what was seen, or that nothing was yet"] = function(t)
    local _, c, _, diag = start()
    t.eq(diag.help[K.WORD], K.HELP)
    local before = said(c, diag)
    t.ok(before:find(K.NOT_YET, 1, true) ~= nil, before)
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    local after = said(c, diag)
    t.ok(after:find("ENCOUNTER_END seen 1 time, 1 of them a kill", 1, true) ~= nil, after)
    t.ok(after:find(ns.id.title, 1, true) == 1, "from the add-on, by its title")
end

tests["boss kills: an event the client did not take is said, so the answer is known"] = function(t)
    local _, c, _, diag = start({ refused = { "BOSS_KILL" } })
    local line = said(c, diag)
    t.ok(line:find("the client does not have BOSS_KILL", 1, true) ~= nil, line)
end

-- Twin review 17:11, F8: an instance read that does not answer is not
-- "outside": the kills of this visit stay.
tests["boss kills F8: an unknown instance read keeps this visit's kills"] = function(t)
    local _, c, api = start()
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.setInstance(nil)
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(api.Kills(), { { id = 1001, name = "Rhahk'Zor" } })
end

-- F8: through the real entry, the add-on's own module on the whole add-on.
tests["boss kills F8: the add-on's own module, through its real entry"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setInstance({ inside = true, kind = "party" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    local api = addon.use(K.NAME)
    t.ok(api ~= nil, "declared on the add-on")
    t.eq(api and api.Kills(), { { id = 1001, name = "Rhahk'Zor" } })
    t.eq(addon.store:get("account", K.PATH), { ends = 1, kills = 1 })
end

tests["boss kills: the counts are kept over a reload"] = function(t)
    local _, c = start()
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    local k2 = start({ account = c.saved(ns.id.accountDB) })
    t.eq(k2.store:get("account", K.PATH), { ends = 1, kills = 1 })
end

-- Lead section 303 (d): the tracker is told of each kill, and asks whether
-- the client can report kills at all.
tests["boss kills (d): each kill is said on the bus"] = function(t)
    local k, c = start()
    local said = {}
    k.bus:on("test", K.EVENT, function() said[#said + 1] = true end)
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.fire("ENCOUNTER_END", 1002, "Sneed", 1, 5, 0)
    t.eq(#said, 1, "a kill, not an encounter lost")
end

tests["boss kills (d): reported unless the client took neither event"] = function(t)
    local _, _, api = start()
    t.eq(api.Reported(), true)
    local _, _, one = start({ refused = { "BOSS_KILL" } })
    t.eq(one.Reported(), true, "one event is enough")
    local _, _, none = start({ refused = { "ENCOUNTER_END", "BOSS_KILL" } })
    t.eq(none.Reported(), false)
end

return tests
