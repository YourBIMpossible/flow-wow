-- UI/KitProbe.lua (lead DISPATCH section 297 item 3 and section 303 item
-- 5): the parts the window kit would like to use are asked of the client
-- once per login, out of combat, and what the client said of each row is
-- kept in the saved diagnostics (the account table's diag.kitProbe), where
-- tools\zflow-read-diag.ps1 prints it. Through the real entry point
-- (KitProbe.Start on a kernel, the login events) over the fake client, on
-- which every other row of the parts list fails. Made-up answers; not
-- tested in game.
-- Fails before the module: ns.KitProbe is nil, so every test fails its
-- first check ("ns.KitProbe answers Start", got false).
local _, ns = ...

-- Every other row of the parts list fails, with a text of its own.
local function failing(row) return "no such part: " .. tostring(row.name) end
local function script()
    local fails = {}
    for i, row in ipairs(ns.KitParts.rows) do
        if i % 2 == 0 then fails[row.id] = true end
    end
    return fails, function(row)
        if fails[row.id] then return failing(row) end
        return nil
    end
end

-- opts.combat: in combat at login. opts.refused: the probe itself refuses
-- (setKitProbeCombat). opts.raises: the probe raises. opts.noProbe: a
-- client with no such read. opts.account: the saved account table (a
-- reload). opts.say: the probe's script (default: every other row fails).
local function start(t, opts)
    opts = opts or {}
    local P = ns.KitProbe
    local ok = type(P) == "table" and type(P.Start) == "function" and type(ns.KitParts) == "table"
    t.ok(ok, "ns.KitProbe answers Start")
    if not ok then return nil end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local fails, say = script()
    c.setKitProbe(opts.say or say)
    if opts.raises then c.setKitProbe(function() error("probe-broke", 0) end) end
    if opts.noProbe then c.kitProbe = nil end
    if opts.combat then c.setCombat(true) end
    if opts.refused then c.setKitProbeCombat(true) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = P.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, k, api, fails
end

local function kept(c)
    local diag = c.saved(ns.id.accountDB).diag
    if type(diag) ~= "table" then return nil end
    return diag.kitProbe
end

local tests = {}

tests["kit probe: asked once at login, and each row's answer is in the saved diagnostics"] = function(t)
    local c, k, api, fails = start(t)
    if c == nil then return end
    t.eq(c.kitProbeCalls, 1, "asked once")
    local record = kept(c)
    t.ok(type(record) == "table" and type(record.rows) == "table", "diag.kitProbe is saved, with rows")
    if type(record) ~= "table" or type(record.rows) ~= "table" then return end
    local works, missing = 0, 0
    for _, row in ipairs(ns.KitParts.rows) do
        if fails[row.id] then
            missing = missing + 1
            t.eq(record.rows[row.id], failing(row), row.id)
        else
            works = works + 1
            t.eq(record.rows[row.id], "works", row.id)
        end
    end
    t.ok(works > 0 and missing > 0, "half fail, half work: " .. works .. " and " .. missing)
    t.eq(record.rows.EJ_LOADED, "no", "the journal answer is a row of its own")
    local n = 0
    for _ in pairs(record.rows) do n = n + 1 end
    t.eq(n, #ns.KitParts.rows + 1, "one answer per row, and the journal's")
    t.eq(record.at, c.uptime(), "when it was asked")
    t.eq(type(record.interface), "string", "with the client build it was asked on")
    t.eq(api.done(), true)
    t.eq(api.result(), record, "the read hands back the same answers")
    t.ok(api.result() ~= record, "as a table of its own, not the saved one")
    t.eq(k.problems:count(ns.KitProbe.KIND), 0, "no problem")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setCombat(true)
    c.setCombat(false)
    t.eq(c.kitProbeCalls, 1, "a zone change or a later fight does not ask again")
end

tests["kit probe: ns.use hands the kit the last record"] = function(t)
    local c, k, api = start(t)
    if c == nil then return end
    k:Load()
    local used = k.use(ns.KitProbe.NAME)
    t.ok(type(used) == "table" and type(used.Result) == "function", "use(KitProbe.NAME) answers Result")
    if type(used) ~= "table" or type(used.Result) ~= "function" then return end
    t.ok(used.Result() == api.result(), "the same record")
    t.eq(ns.KitProbe.Works(used.Result(), "T2"), true)
    t.eq(ns.KitProbe.Works(used.Result(), "T5"), false)
end

tests["kit probe: in combat at login it waits, and asks once when the fight ends"] = function(t)
    local c, _, api = start(t, { combat = true })
    if c == nil then return end
    t.eq(kept(c), nil, "nothing saved in combat")
    t.eq(api.result(), nil, "and no record yet")
    t.eq(api.done(), false)
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(kept(c), nil, "a zone change in the fight saves nothing either")
    c.setCombat(false)
    local record = kept(c)
    t.ok(type(record) == "table", "saved once out of combat")
    if type(record) ~= "table" then return end
    t.eq(record.rows.T2, "works")
    t.eq(api.done(), true)
    local n = c.kitProbeCalls
    c.setCombat(true)
    c.setCombat(false)
    t.eq(c.kitProbeCalls, n, "and not again after the next fight")
end

tests["kit probe: a probe the client refuses is asked again at the end of the fight, not before"] = function(t)
    local c, _, api = start(t, { refused = true })
    if c == nil then return end
    t.eq(c.kitProbeCalls, 1, "asked at login")
    t.eq(kept(c), nil, "refused: nothing saved")
    c.advance(30, 60)
    t.eq(c.kitProbeCalls, 1, "not asked on a timer")
    c.setKitProbeCombat(false)
    t.eq(kept(c), nil, "not before the fight is said to be over")
    c.fire("PLAYER_REGEN_ENABLED")
    t.eq(c.kitProbeCalls, 2)
    t.ok(type(kept(c)) == "table", "saved when the fight ends")
    t.eq(api.done(), true)
    c.fire("PLAYER_REGEN_ENABLED")
    t.eq(c.kitProbeCalls, 2, "once")
end

tests["kit probe: a reload asks again, and the new answer replaces the saved one"] = function(t)
    local c = start(t)
    if c == nil then return end
    local account = c.saved(ns.id.accountDB)
    local first = kept(c)
    t.ok(type(first) == "table", "saved at the first login")
    if type(first) ~= "table" then return end
    t.eq(first.rows.T5, failing(ns.KitParts.ById("T5")))
    -- The reload: a new client and kernel over the same saved table.
    local c2, _, api2 = start(t, { account = account, say = { T2 = "gone now" } })
    if c2 == nil then return end
    t.eq(c2.kitProbeCalls, 1, "asked again")
    local second = kept(c2)
    t.ok(second ~= first, "a new record")
    t.eq(second.rows.T2, "gone now")
    t.eq(second.rows.T5, "works", "the old answer is not kept")
    t.eq(api2.result().rows.T2, "gone now")
end

tests["kit probe: a probe that raises is a problem, saves nothing and is not asked again"] = function(t)
    local c, k, api = start(t, { raises = true })
    if c == nil then return end
    t.eq(kept(c), nil, "nothing saved")
    t.eq(api.result(), nil)
    t.eq(api.done(), true)
    local list = k.problems:list(ns.KitProbe.KIND)
    t.eq(#list, 1, "one problem")
    t.ok(#list == 1 and tostring(list[1].text):find("probe-broke", 1, true) ~= nil, "what it raised")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setCombat(true)
    c.setCombat(false)
    t.eq(c.kitProbeCalls, 1)
end

tests["kit probe: a client with no such read saves nothing, raises nothing, and says why"] = function(t)
    local c, k, api = start(t, { noProbe = true })
    if c == nil then return end
    t.eq(kept(c), nil)
    t.eq(api.result(), nil)
    t.eq(k.problems:count(ns.KitProbe.KIND), 1, "no data is never silent: one problem says why")
end

tests["kit probe: a journal re-ask that fails says why, and the old answer is not left standing"] = function(t)
    local c, k = start(t)
    if c == nil then return end
    t.eq(kept(c).rows.EJ_LOADED, "no")
    local before = k.problems:count(ns.KitProbe.KIND)
    c.setKitProbeCombat(true)
    c.setLoaded("Blizzard_EncounterJournal", true)
    c.fire("ADDON_LOADED", "Blizzard_EncounterJournal")
    t.eq(kept(c).rows.EJ_LOADED, ns.KitProbe.NOT_KNOWN, "a re-ask in a fight: not known, not the old no")
    t.eq(k.problems:count(ns.KitProbe.KIND), before + 1, "and one problem says the re-ask was refused")
    t.eq(kept(c).rows.T2, "works", "the other answers are kept")
end

-- The REAL client's kitProbe (Core/Client.lua), on a hand-built client
-- table: a template counts only when the frame handed back carries one of
-- the row's proof fields; every frame made to ask with is unnamed, never
-- shown, and let go afterwards; no add-on is loaded.
tests["kit probe: the real client tells a template from a plain frame, and lets every frame go"] = function(t)
    local made, loads = {}, 0
    local env = { UIParent = {} }
    env.InCombatLockdown = function() return false end
    env.IsAddOnLoaded = function() return false end
    env.LoadAddOn = function() loads = loads + 1 end
    env.GameTooltip = {}
    env.CreateFrame = function(kind, name, parent, template)
        if template == "MissingTemplate" then error("Couldn't find inherited node: MissingTemplate", 0) end
        local f = { kind = kind, name = name, parent = parent, template = template, shown = false, shows = 0 }
        function f:Hide() self.shown = false end
        function f:Show()
            self.shown = true
            self.shows = self.shows + 1
        end
        function f:ClearAllPoints() end
        function f:SetParent(p)
            self.parent = p
            self.freed = p == nil
        end
        if template == "RealTemplate" then f.CloseButton = {} end
        made[#made + 1] = f
        return f
    end
    local c = ns.make.client(env)
    t.eq(type(c.kitProbe), "function", "the client answers kitProbe")
    if type(c.kitProbe) ~= "function" then return end
    local rows = {
        { id = "A", kind = "template", name = "RealTemplate", frameType = "Frame", proof = { "CloseButton" } },
        { id = "B", kind = "template", name = "PlainTemplate", frameType = "Frame", proof = { "CloseButton" } },
        { id = "C", kind = "template", name = "MissingTemplate", frameType = "Frame", proof = { "CloseButton" } },
        { id = "D", kind = "global", name = "GameTooltip" },
        { id = "E", kind = "global", name = "C_Texture.GetAtlasInfo" },
    }
    local out, why = c.kitProbe(rows)
    t.ok(type(out) == "table", "an answer: " .. tostring(why))
    if type(out) ~= "table" then return end
    t.eq(out.A, "works", "the frame carries a field the template is known by")
    t.eq(out.B, "made, not confirmed", "a frame with none of them is not counted as the template")
    t.ok(type(out.C) == "string" and out.C:find("MissingTemplate", 1, true) ~= nil, "a raise is the row's text: " .. tostring(out.C))
    t.eq({ out.D, out.E }, { "works (table)", "nil" }, "client names")
    t.eq(out.EJ_LOADED, "no")
    t.eq(loads, 0, "no add-on is loaded")
    t.eq(#made, 3, "one holder and the two frames the client made; the missing one made none")
    for i, f in ipairs(made) do
        t.eq(f.name, nil, "frame " .. i .. " is unnamed: no global is made")
        t.eq({ f.shows, f.shown, f.freed }, { 0, false, true }, "frame " .. i .. ": never shown, hidden and let go")
    end
    made = {}
    out = c.kitProbe({})
    t.eq({ type(out) == "table" and out.EJ_LOADED, #made }, { "no", 0 }, "with no rows no frame is made at all")
    env.InCombatLockdown = function() return true end
    local none, reason = c.kitProbe(rows)
    t.eq(none, nil, "nothing is asked in a fight")
    t.eq(reason, "combat")
end

tests["kit probe: the journal loading later re-records only whether it is loaded"] = function(t)
    local c = start(t)
    if c == nil then return end
    t.eq(kept(c).rows.EJ_LOADED, "no")
    c.fire("ADDON_LOADED", "SomeOtherAddon")
    t.eq(c.kitProbeCalls, 1, "another add-on asks nothing")
    c.setLoaded("Blizzard_EncounterJournal", true)
    c.fire("ADDON_LOADED", "Blizzard_EncounterJournal")
    t.eq(kept(c).rows.EJ_LOADED, "yes")
    t.eq(kept(c).rows.T2, "works", "the other answers are kept")
    t.eq(c.kitProbeCalls, 2, "asked once more, with no rows")
end

tests["kit probe: Works says true, false, or nil for a row not asked yet"] = function(t)
    local P = ns.KitProbe
    local ok = type(P) == "table" and type(P.Works) == "function"
    t.ok(ok, "ns.KitProbe answers Works")
    if not ok then return end
    local record = { rows = { T2 = "works", G1 = "works (table)", T56 = "works (as Button)", T5 = "no such template",
        A1 = "made, not confirmed", A2 = "no atlas info", G4 = "nil", X1 = "workshop", EJ_LOADED = "no" } }
    t.eq(P.Works(record, "T2"), true)
    t.eq(P.Works(record, "G1"), true, "a client name that is there")
    t.eq(P.Works(record, "T56"), true, "made as its second kind")
    t.eq(P.Works(record, "T5"), false)
    t.eq(P.Works(record, "A1"), false, "not confirmed is not works")
    t.eq(P.Works(record, "A2"), false)
    t.eq(P.Works(record, "G4"), false)
    t.eq(P.Works(record, "X1"), false, "only the word itself")
    t.eq(P.Works(record, "T3"), nil, "a row with no answer")
    t.eq(P.Works(nil, "T2"), nil, "no record yet")
    t.eq(P.Works({}, "T2"), nil)
    t.eq(P.Works(record, nil), nil)
end

-- Lead sections 319 and 322: the probe's answers reach the kit's drawer,
-- and what each window drew is kept in the saved diagnostics.
tests["kit probe: its answers are handed to the drawer, and what a window drew is saved"] = function(t)
    local c, _, _, fails = start(t)
    if c == nil then return end
    t.eq(type(c.kitSaid), "function", "the fake keeps what kitKnown was told")
    if type(c.kitSaid) ~= "function" then return end
    local said = c.kitSaid()
    local asked, wrong = 0, 0
    for _, row in ipairs(ns.KitParts.rows) do
        asked = asked + 1
        local works = said[row.id] == "works"
        if works == (fails[row.id] == true) then wrong = wrong + 1 end
    end
    t.ok(asked > 0, "rows were asked")
    t.eq(wrong, 0, "the drawer was told each row as the probe found it")
    c.kitDrawnTell("SellList", { frame = "fallback", button = "first" })
    local diag = c.saved(ns.id.accountDB).diag
    t.eq(type(diag) == "table" and diag.kitDrawn and diag.kitDrawn.SellList,
        { frame = "fallback", button = "first" }, "kept beside the probe's answers")
end

return tests