-- The diagnostic collector over the fake client: what a snapshot holds,
-- where it is saved, when one is taken, and that a paused addon still
-- collects. No game client is involved.
local _, ns = ...

local function env()
    return {
        GetMoney = function() return 12345 end,
        GetBuildInfo = function() return "1.16.1", "7777", "Nov 1 2026", 16001 end,
        UnitClass = function() return "Paladin", "PALADIN", 2 end,
        GetRealmName = function() return "Testrealm" end,
        GetNumSpellTabs = function() error("not now") end,
        NUM_BAG_SLOTS = 4,
        C_Map = { GetBestMapForUnit = function() return 1411 end },
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if slot == 2 then return { stackCount = 3, itemID = 2318, sub = {} } end
            end,
            GetContainerItemLink = function() return "item:2318" end,
        },
        GetItemInfo = function(link) return "Light Leather", link, 1 end,
    }
end

local function start(opts)
    local c = ns.make.fakeClient({ env = env() })
    if opts and opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Boot()
    return k, c, d
end

-- A plain deep copy, to compare saved data before and after a command.
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("VARIABLES_LOADED")
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

-- How many printed lines hold the text.
local function said(c, text)
    local n = 0
    for i = 1, #c.printed do
        if c.printed[i]:find(text, 1, true) then n = n + 1 end
    end
    return n
end

return {
    ["shape: values, types and one level of a table answer"] = function(t)
        local row = ns.Diag.Shape(true, 5, "a", nil, { x = 1, y = {} })
        t.eq(row.ok, true)
        t.eq(row.n, 4)
        t.eq(row.types, { "number", "string", "nil", "table" })
        t.eq(row.values, { v1 = 5, v2 = "a", v4 = { x = 1, y = "table" } })
        t.eq(ns.Diag.Shape(false, "boom"), { ok = false, n = 1, types = { "string" }, values = { v1 = "boom" } })
    end,

    ["collect: names, reads, shapes and kernel state"] = function(t)
        local k, c = start()
        c.setMoney(99)
        c.setBagItems({ { item = 2318, count = 4 } })
        login(c)
        local snap = ns.Diag.Collect(k, "test")
        t.eq(snap.why, "test")
        t.eq(snap.names["GetMoney"], "function")
        t.eq(snap.names["C_Map.GetBestMapForUnit"], "function")
        t.eq(snap.names["NUM_BAG_SLOTS"], "number")
        t.eq(snap.names["GetContainerNumSlots"], "nil", "an absent name is recorded as nil, not left out")
        t.eq(snap.reads.money, 99)
        t.eq(snap.reads.bagStacks, 1)
        t.eq(snap.known.money, true)
        t.eq(snap.known.position, false, "an unknown read is marked, since nil leaves no trace when saved")
        t.eq(snap.reads.predecessorLoaded, false)
        t.eq(snap.shapes.build.values, { v1 = "1.16.1", v2 = "7777", v3 = "Nov 1 2026", v4 = 16001 })
        t.eq(snap.shapes.class.values.v2, "PALADIN")
        t.eq(snap.shapes.bestMap.values.v1, 1411)
        t.eq(snap.shapes.spellTabs.ok, false, "a call that errors is recorded, it does not stop the snapshot")
        t.eq(snap.shapes.level.ok, false, "a name the client lacks is recorded as not callable")
        t.eq(snap.shapes.slotInfo.values.v1, { stackCount = 3, itemID = 2318, sub = "table" })
        t.eq(snap.shapes.itemInfo.values.v1, "Light Leather")
        t.eq(snap.kernel.phase, "running")
        t.eq(snap.kernel.paused, false)
        t.eq(snap.kernel.storeOpened, true)
    end,

    ["start: login saves one snapshot with the timing marks in order"] = function(t)
        local _, c = start()
        t.eq(c.savedExists(ns.id.accountDB), false, "nothing is written before the client has loaded saved data")
        c.setSaved(ns.id.accountDB, {})
        login(c)
        c.fire("PLAYER_ENTERING_WORLD")
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.count, 1, "a second entering-world (a zone change) takes no second login snapshot")
        local snap = d.snaps[1]
        t.eq(snap.why, "login")
        t.eq(snap.timing.order, { "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })
        t.eq(snap.timing.fileLoad.accountData, false)
        t.eq(snap.timing.ADDON_LOADED.accountData, true)
        t.eq(snap.timing.ADDON_LOADED.phase ~= "running", true, "the kernel had not loaded at ADDON_LOADED")
        t.eq(snap.timing.PLAYER_ENTERING_WORLD.phase, "running")
    end,

    ["start: another addon's ADDON_LOADED is not ours"] = function(t)
        local _, c, d = start()
        c.fire("ADDON_LOADED", "SomethingElse")
        t.eq(d.timing.ADDON_LOADED, nil)
        t.eq(#d.timing.order, 0)
    end,

    ["start: a window opening takes a snapshot named for it"] = function(t)
        local _, c = start()
        login(c)
        c.fire("MERCHANT_SHOW")
        c.fire("TRAINER_SHOW")
        c.setBankOpen(true)
        local snaps = c.saved(ns.id.accountDB).diag.snaps
        t.eq({ snaps[1].why, snaps[2].why, snaps[3].why, snaps[4].why }, { "login", "vendor", "trainer", "bank" })
        t.eq(snaps[4].reads.bankOpen, true)
    end,

    ["save: only the newest twenty are kept, the count keeps rising"] = function(t)
        local _, c, d = start()
        login(c)
        for _ = 1, 50 do d.snapshot("again") end
        local saved = c.saved(ns.id.accountDB).diag
        t.eq(#saved.snaps, 20)
        t.eq(saved.count, 51)
        t.eq(saved.snaps[20].why, "again")
    end,

    ["windows: a repeated event is one opening; a later one is another"] = function(t)
        local _, c = start()
        login(c)
        for _ = 1, 4 do c.fire("TRADE_SKILL_SHOW") end
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.count, 2, "four events inside the gap take one snapshot")
        c.advance(6)
        t.eq(d.count, 3, "one late look, a few seconds after the opening")
        t.eq(d.snaps[3].why, "profession-late")
        c.fire("TRADE_SKILL_SHOW")
        t.eq(d.count, 4)
        c.advance(6)
        local late = 0
        for i = 1, d.count do
            if d.snaps[i].why == "profession-late" then late = late + 1 end
        end
        t.eq(late, 2, "and one per opening")
    end,

    ["profession: an empty full list falls back to the shown list"] = function(t)
        local e = env()
        e.C_TradeSkillUI = {
            GetAllRecipeIDs = function() return {} end,
            GetFilteredRecipeIDs = function() return { 2660, 2661 } end,
            GetRecipeInfo = function(recipe) return { recipeID = recipe } end,
            GetBaseProfessionInfo = function() return { professionID = 164 } end,
            GetProfessionInfoBySkillLineID = function(line) return { professionID = line } end,
        }
        local s = ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
        t.eq(s.recipeCount.values.v1, 0)
        t.eq(s.recipeShownCount.values.v1, 2)
        t.eq(s.recipeInfo.values.v1.recipeID, 2660)
        t.eq(s.tradeByLine.values.v1.professionID, 164)
        t.eq(s.tradeChildren.ok, false, "a call the client lacks is recorded, not an error")
    end,

    ["windows: the list arriving takes one more snapshot, once per opening"] = function(t)
        local _, c = start()
        login(c)
        c.fire("TRAINER_UPDATE")
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.count, 1, "no trainer window was opened")
        c.fire("TRAINER_SHOW")
        c.fire("TRAINER_UPDATE")
        c.fire("TRAINER_UPDATE")
        t.eq(d.count, 3)
        t.eq({ d.snaps[2].why, d.snaps[3].why }, { "trainer", "trainer-ready" })
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        t.eq(d.snaps[5].why, "profession-ready")
    end,

    ["login: one settled snapshot a few seconds later, then no more listening"] = function(t)
        local _, c = start()
        login(c)
        local d = c.saved(ns.id.accountDB).diag
        c.advance(4)
        t.eq(d.count, 1)
        c.advance(5)
        t.eq(d.count, 2)
        t.eq(d.snaps[2].why, "settled")
        c.advance(30, 3)
        t.eq(d.count, 2)
    end,

    ["session: an empty realm is unknown, the other realm call is asked"] = function(t)
        local e = env()
        e.GetRealmName = function() return "" end
        local c = ns.make.fakeClient({ env = e })
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        k:Boot()
        login(c)
        t.eq(c.saved(ns.id.accountDB).diag.snaps[1].timing.realm, nil)
        e.GetNormalizedRealmName = function() return "Other" end
        local c2 = ns.make.fakeClient({ env = e })
        local k2 = ns.Kernel({}, c2)
        ns.Diag.Start(k2)
        k2:Boot()
        login(c2)
        t.eq(c2.saved(ns.id.accountDB).diag.snaps[1].timing.realm, "Other")
    end,

    ["session: with both realm calls empty, the realm comes from the full name"] = function(t)
        local e = env()
        e.GetRealmName = function() return "" end
        e.GetNormalizedRealmName = function() return "" end
        e.UnitFullName = function() return "Tester", "Fullrealm" end
        local c = ns.make.fakeClient({ env = e })
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        k:Boot()
        login(c)
        t.eq(c.saved(ns.id.accountDB).diag.snaps[1].timing.realm, "Fullrealm")
    end,

    ["api: namespace members and matching global names are saved at each start"] = function(t)
        local _, c = start()
        login(c)
        local api = c.saved(ns.id.accountDB).diag.api
        t.eq(api.namespaces["C_Map"], { GetBestMapForUnit = "function" })
        t.eq(api.namespaces["C_Bank"], false, "a namespace the client lacks is recorded as absent")
        t.eq(api.globals["^C_"], { "C_Container", "C_Map" })
        t.eq(api.globals["Realm"], { "GetRealmName" })
    end,

    ["collect: the namespaced calls are asked and chained from what they answer"] = function(t)
        local e = env()
        e.UnitHealth = function() return 120 end
        e.issecretvalue = function() return false end
        e.C_QuestLog = { GetInfo = function(i) return { questID = 40 + i, title = "Q" } end,
            GetQuestObjectives = function(id) return { { text = "obj " .. id } } end }
        e.C_SpellBook = { GetSpellBookItemInfo = function() return { spellID = 635 } end }
        e.C_Spell = { GetSpellInfo = function(id) return { name = "Holy Light", spellID = id } end }
        local big = {}
        for i = 1, 200 do big[i] = 1000 + i end
        e.C_TradeSkillUI = { GetAllRecipeIDs = function() return big end,
            GetRecipeInfo = function(id) return { recipeID = id, name = "R" } end }
        local c = ns.make.fakeClient({ env = e })
        local snap = ns.Diag.Collect(ns.Kernel({}, c), "test")
        local S = snap.shapes
        t.eq(S.healthText.values.v1, "120")
        t.eq(S.healthSecret.values.v1, false)
        t.eq(S.healthIsItself.values.v1, true)
        t.eq(S.questObjectives.ok, true)
        t.eq(S.spellInfo.values.v1.name, "Holy Light")
        t.eq(S.recipeCount.values.v1, 200)
        t.eq(S.recipeInfo.values.v1.recipeID, 1001)
        t.eq(S.recipeSchematic.ok, false)
    end,

    ["shape: a big table answer is cut to sixty keys"] = function(t)
        local big = {}
        for i = 1, 500 do big[i] = i end
        local n = 0
        for _ in pairs(ns.Diag.Shape(true, big).values.v1) do n = n + 1 end
        t.eq(n, 60)
    end,

    ["slash: diag saves and says so, clear forgets, anything else reports state"] = function(t)
        local _, c = start()
        login(c)
        local run = c.slashes[ns.id.slash]
        t.eq(type(run), "function")
        run("diag")
        t.eq(c.saved(ns.id.accountDB).diag.count, 2)
        t.ok(c.printed[#c.printed]:find("snapshot 2", 1, true), c.printed[#c.printed])
        run(" DIAG clear ")
        t.eq(c.saved(ns.id.accountDB).diag, nil)
        run("")
        t.ok(c.printed[#c.printed]:find("running", 1, true), c.printed[#c.printed])
    end,

    ["guard: a paused addon still collects and records why it paused"] = function(t)
        local k, c = start({ predecessor = true })
        login(c)
        t.eq(k.paused, true)
        local snap = c.saved(ns.id.accountDB).diag.snaps[1]
        t.eq(snap.kernel.paused, true)
        t.eq(snap.kernel.phase, "paused")
        t.eq(snap.kernel.storeOpened, false, "a paused addon opens no store")
        t.eq(snap.reads.predecessorLoaded, true)
        t.eq(type(snap.kernel.pauseText), "string")
    end,

    ["errors: kept once with a count, marked ours or not, saved with the snapshot"] = function(t)
        local _, c, d = start()
        c.raise("Interface/AddOns/" .. ns.id.addon .. "/Core/X.lua:5: boom")
        c.raise("Interface/AddOns/" .. ns.id.addon .. "/Core/X.lua:5: boom")
        c.raise("Interface/AddOns/Other/y.lua:1: theirs")
        login(c)
        local e = c.saved(ns.id.accountDB).diag.snaps[1].timing.errors
        t.eq(#e, 2)
        t.eq({ e[1].count, e[1].ours, e[2].count, e[2].ours }, { 2, true, 1, false })
        for i = 1, 100 do c.raise("different " .. i) end
        t.eq(#d.timing.errors, 40, "the list is capped")
    end,

    ["session: each login counts a start and names the character when the client says"] = function(t)
        local _, c = start()
        login(c)
        local d = c.saved(ns.id.accountDB).diag
        t.eq(d.starts, 1)
        t.eq(d.snaps[1].timing.start, 1)
        t.eq(d.snaps[1].timing.realm, "Testrealm")
        t.eq(d.snaps[1].timing.character, nil, "a client that will not name the character leaves it unknown")
    end,

    ["collect: a client that answers nothing still gives a snapshot"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local snap = ns.Diag.Collect(k, "bare")
        t.eq(snap.names["GetMoney"], "nil")
        t.eq(snap.known.money, false)
        t.eq(snap.shapes.build.ok, false)
        t.eq(snap.shapes.slotInfo, nil)
    end,

    -- ------------------------------------------------------ import report
    ["import report: the counts, then each adjusted value with its reason"] = function(t)
        local lines, counts = ns.Diag.ImportReport({
            ok = true,
            dropped = {
                { key = "a.one", why = "dropped", reason = "on purpose" },
                { key = "a.two", why = "dropped", reason = "on purpose" },
                { key = "b.bad", why = "malformed", reason = "expected a number" },
            },
            adjusted = {
                { key = "buffButton.scale", from = 9, to = 2, reason = "outside the sizes a frame can take" },
                { key = "x.name", from = "Long", to = "L", reason = "cut" },
            },
        })
        t.eq(counts, { dropped = 2, adjusted = 2, malformed = 1, unknown = 0, superseded = 0, other = 0, vendor = 0,
            incompatible = 0 })
        t.eq(lines, {
            "import: 2 dropped, 2 adjusted, 1 malformed.",
            "import: adjusted buffButton.scale: 9 to 2 (outside the sizes a frame can take)",
            'import: adjusted x.name: "Long" to "L" (cut)',
        })
    end,

    ["import report: nothing left behind or changed is three zeroes"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, dropped = {}, adjusted = {} })
        t.eq(lines, { "import: 0 dropped, 0 adjusted, 0 malformed." })
        t.eq(counts, { dropped = 0, adjusted = 0, malformed = 0, unknown = 0, superseded = 0, other = 0, vendor = 0,
            incompatible = 0 })
    end,

    ["import report: entries left behind for another reason are not counted as dropped"] = function(t)
        local lines, counts = ns.Diag.ImportReport({
            ok = true,
            dropped = {
                { key = "a", why = "unknown" }, { key = "b", why = "unknown" },
                { key = "c", why = "superseded" }, { key = "d", why = "dropped" },
                { key = "e" }, "not an entry",
            },
            adjusted = {},
        })
        t.eq(counts, { dropped = 1, adjusted = 0, malformed = 0, unknown = 2, superseded = 1, other = 2, vendor = 0,
            incompatible = 0 })
        t.eq(lines, {
            "import: 1 dropped, 0 adjusted, 0 malformed.",
            "import: also left behind: 2 with no row, 1 superseded, 2 with no category.",
        })
    end,

    ["import report: an import that did not succeed says why and counts nothing"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = false, reason = "too new", dropped = { { why = "dropped" } } })
        t.eq(lines, { "import: nothing was read: too new" })
        t.eq(counts.dropped, 0)
        t.eq((ns.Diag.ImportReport(nil)), { "import: there is no result to report." })
        t.eq((ns.Diag.ImportReport("x")), { "import: there is no result to report." })
    end,

    ["import report: missing lists and a broken adjusted entry do not raise"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, adjusted = { "broken", { key = "k", from = false, to = true } } })
        t.eq(counts.adjusted, 2)
        t.eq(lines, {
            "import: 0 dropped, 2 adjusted, 0 malformed.",
            "import: adjusted nil: nil to nil (no reason given)",
            "import: adjusted k: false to true (no reason given)",
        })
    end,

    ["import report: what the import itself returns is reported as it lists it"] = function(t)
        local result = ns.Import.FromFlow({ buffButton = { scale = 9, enabled = "yes" } }, nil)
        local lines, counts = ns.Diag.ImportReport(result)
        t.eq(counts.adjusted, #result.adjusted)
        t.eq(counts.adjusted, 1)
        t.eq(counts.malformed, 1)
        t.eq(counts.dropped + counts.malformed + counts.unknown + counts.superseded + counts.other, #result.dropped)
        local entry = result.adjusted[1]
        t.eq(lines[#lines], "import: adjusted buffButton.scale: 9 to 2 (" .. entry.reason .. ")")
    end,

    ["slash: import with no predecessor data says so and creates none"] = function(t)
        local _, c = start()
        login(c)
        local before = #c.printed
        c.slashes[ns.id.slash]("import")
        t.eq(#c.printed, before + 1)
        t.ok(c.printed[#c.printed]:find("nothing to read", 1, true), c.printed[#c.printed])
        t.eq(c.savedExists(ns.id.predecessorDB), false)
        t.eq(c.savedExists(ns.id.predecessorCharDB), false)
    end,

    ["slash: import prints the report and writes nothing"] = function(t)
        local _, c = start()
        login(c)
        local flow = c.saved(ns.id.predecessorDB)
        flow.buffButton = { scale = 9, enabled = "yes" }
        local own0 = copy(c.saved(ns.id.accountDB))
        local char0 = copy(c.saved(ns.id.charDB))
        local before = #c.printed
        c.slashes[ns.id.slash](" IMPORT ")
        local expected = ns.Diag.ImportReport(ns.Import.FromFlow({ buffButton = { scale = 9, enabled = "yes" } }, nil))
        t.eq(#c.printed, before + #expected)
        for i = 1, #expected do
            t.eq(c.printed[before + i], ns.id.title .. ": " .. expected[i])
        end
        t.eq(flow, { buffButton = { scale = 9, enabled = "yes" } })
        -- The store makes its tables at login; the slash changes nothing in
        -- either, not even the snapshot count (R3).
        t.eq(c.saved(ns.id.accountDB), own0, "account table unchanged")
        t.eq(c.saved(ns.id.charDB), char0, "character table unchanged")
        t.eq(c.savedExists(ns.id.predecessorCharDB), false)
    end,

    ["slash: import reads the predecessor's character data when the client has it"] = function(t)
        local _, c = start()
        login(c)
        c.saved(ns.id.predecessorDB)
        c.saved(ns.id.predecessorCharDB).stray = 1
        local before = #c.printed
        c.slashes[ns.id.slash]("import")
        t.ok(c.printed[before + 2] and c.printed[before + 2]:find("1 with no row", 1, true),
            tostring(c.printed[before + 2]))
    end,

    ["slash: import hands the import copies, so the predecessor's live tables cannot change (R4)"] = function(t)
        local _, c = start()
        login(c)
        local flow = c.saved(ns.id.predecessorDB)
        flow.buffButton = { scale = 9 }
        c.saved(ns.id.predecessorCharDB).note = { text = "kept" }
        local real = ns.Import.FromFlow
        local seenA, seenC
        ns.Import.FromFlow = function(a, ch)
            seenA, seenC = a, ch
            a.buffButton.scale = 1
            ch.note.text = "changed"
            return real(a, ch)
        end
        local ran, err = pcall(c.slashes[ns.id.slash], "import")
        ns.Import.FromFlow = real
        t.ok(ran, tostring(err))
        t.ok(seenA ~= nil and seenA ~= flow, "the account table handed in is a copy")
        t.ok(seenC ~= nil and seenC ~= c.saved(ns.id.predecessorCharDB), "the character table handed in is a copy")
        t.eq(flow, { buffButton = { scale = 9 } })
        t.eq(c.saved(ns.id.predecessorCharDB), { note = { text = "kept" } })
    end,

    ["import report: each vendor automation Flow had on gets a line; it stays off (IR8)"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, dropped = {}, adjusted = {},
            vendorToConfirm = { { key = "autoRepair", to = true, sameAsFlowDefault = true },
                                { key = "autoSell", to = true }, "broken" } })
        t.eq(counts.vendor, 2)
        t.eq(lines, {
            "import: 0 dropped, 0 adjusted, 0 malformed.",
            "import: 2 vendor automations were on in Flow; each stays off until you confirm it.",
            "import: confirm autoRepair (it is Flow's own default, so it may not be a choice you made)",
            "import: confirm autoSell",
            "import: 1 vendor entry could not be read; it stays off.",
        })
    end,

    ["import report: unreadable vendor entries are counted apart, never named (DI1, DI2)"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, dropped = {}, adjusted = {},
            vendorToConfirm = { "broken", {}, { key = false } } })
        t.eq(counts.vendor, 0)
        t.eq(lines, {
            "import: 0 dropped, 0 adjusted, 0 malformed.",
            "import: 3 vendor entries could not be read; each stays off.",
        })
    end,

    ["import report: no vendor list, or an empty one, adds no line (IR8)"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, dropped = {}, adjusted = {}, vendorToConfirm = {} })
        t.eq(lines, { "import: 0 dropped, 0 adjusted, 0 malformed." })
        t.eq(counts.vendor, 0)
    end,

    ["import report D8: the incompatible entries of a merge are counted and each is listed"] = function(t)
        local lines, counts = ns.Diag.ImportReport({ ok = true, dropped = {}, adjusted = {} },
            { ok = true, incompatible = { "account.settings.nav", "account.layout.a|b" } })
        t.eq(lines, {
            "import: 0 dropped, 0 adjusted, 0 malformed.",
            "import: 2 source values were incompatible with what is stored; each stored value was kept.",
            "import: incompatible account.settings.nav",
            "import: incompatible account.layout.a||b",
        })
        t.eq(counts.incompatible, 2)
        local one = ns.Diag.ImportReport({ ok = true }, { incompatible = { "char.layout.x" } })
        t.eq(one[2], "import: 1 source value was incompatible with what is stored; the stored value was kept.")
        t.eq(one[3], "import: incompatible char.layout.x")
    end,

    ["import report D8: no merge report, an empty one or a broken one adds no line"] = function(t)
        local base = { "import: 0 dropped, 0 adjusted, 0 malformed." }
        for _, merge in ipairs({ false, "x", {}, { incompatible = {} }, { incompatible = "all" } }) do
            local lines, counts = ns.Diag.ImportReport({ ok = true }, merge or nil)
            t.eq(lines, base)
            t.eq(counts.incompatible, 0)
        end
        -- Only a path that is text can be named; anything else is not printed.
        local lines, counts = ns.Diag.ImportReport({ ok = true }, { incompatible = { 4, "", "char.layout.x", {} } })
        t.eq(counts.incompatible, 1)
        t.eq(lines[3], "import: incompatible char.layout.x")
        t.eq(#lines, 3)
    end,

    ["import report: a | from saved data is doubled, so chat shows it as typed (IR13)"] = function(t)
        local lines = ns.Diag.ImportReport({ ok = true, dropped = {},
            adjusted = { { key = "a|cff", from = "x|r", to = "y", reason = "r|n" } } })
        t.eq(lines[2], 'import: adjusted a||cff: "x||r" to "y" (r||n)')
        t.eq((ns.Diag.ImportReport({ ok = false, reason = "bad|r" })), { "import: nothing was read: bad||r" })
    end,

    ["slash: an import that raises is recorded as a problem and said in one line (IR13)"] = function(t)
        local k, c = start()
        login(c)
        c.saved(ns.id.predecessorDB).x = 1
        local real = ns.Import.FromFlow
        ns.Import.FromFlow = function() error("boom") end
        local before = #c.printed
        local ran, err = pcall(c.slashes[ns.id.slash], "import")
        ns.Import.FromFlow = real
        t.ok(ran, tostring(err))
        t.eq(#c.printed, before + 1)
        t.eq(c.printed[#c.printed], ns.id.title .. ": the import could not be read.")
        local p = k.problems:list("diag")
        t.eq(#p, 1)
        t.eq(p[1].owner, "import")
    end,

    ["slash: the help line names both words (IR13)"] = function(t)
        local _, c = start()
        login(c)
        c.slashes[ns.id.slash]("")
        local line = c.printed[#c.printed]
        t.ok(line:find(ns.id.slash .. " diag", 1, true), line)
        t.ok(line:find(ns.id.slash .. " import", 1, true), line)
    end,

    ["slash: import's copy closes a loop, keeps sharing and copies table keys (C6)"] = function(t)
        local _, c = start()
        login(c)
        local flow = c.saved(ns.id.predecessorDB)
        local shared, key = { n = 1 }, { k = 1 }
        flow.self = flow
        flow.a, flow.b = shared, shared
        flow[key] = "by table"
        local real = ns.Import.FromFlow
        local seen
        ns.Import.FromFlow = function(a) seen = a; return { ok = false, reason = "stub" } end
        local ran, err = pcall(c.slashes[ns.id.slash], "import")
        ns.Import.FromFlow = real
        t.ok(ran, tostring(err))
        t.ok(type(seen) == "table" and seen ~= flow, "a copy is handed in")
        t.ok(seen.self == seen, "the loop closes on the copy")
        t.ok(seen.a == seen.b and seen.a ~= shared, "one copy, shared where the original shares")
        t.eq(seen.a, { n = 1 })
        local copiedKey
        for k2, v in pairs(seen) do if type(k2) == "table" then copiedKey = k2; t.eq(v, "by table") end end
        t.ok(copiedKey ~= nil and copiedKey ~= key, "a table key is copied")
        t.eq(copiedKey, { k = 1 })
    end,

    ["identity: the predecessor's character table name is read from Core/Identity.lua (R6)"] = function(t)
        t.eq(ns.id.predecessorCharDB, "FlowCharDB")
    end,

    -- WOW-DIAG-VISIBILITY
    ["slash: diag says when the client gives no time (CU7)"] = function(t)
        local _, c = start()
        login(c)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, "the client gives no time"), 0, "a client with time gets no such line")
        c.setTime(false)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, ns.id.title .. ": the client gives no time; nothing that waits for a time runs."), 1)
    end,

    ["slash: diag gives the price watch's show count and last reason (PW1)"] = function(t)
        local c = ns.make.fakeClient({ env = env() })
        c.setClock(5000)
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        local w = ns.PriceWatch.Declare(k)
        k:Boot()
        login(c)
        local line = ns.id.title .. ": price watch: "
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, line .. "0 shows; last: none yet."), 1)
        -- A window that cannot be read: the refusal is said.
        c.setMerchant(nil)
        c.setMerchantOpen(true)
        t.eq(w.last().ok, false)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, line .. "1 show; last: refused, the merchant window could not be read."), 1)
        -- A window that is read.
        c.setMerchantOpen(false)
        c.setMerchant({ { index = 1, item = "item:2318", price = 60, stack = 1 } })
        c.setMerchantOpen(true)
        t.eq(w.last().ok, true, tostring(w.last().reason))
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, line .. "2 shows; last: read, 1 recorded."), 1)
        -- Read, with a remark of the reading.
        c.setMerchantOpen(false)
        c.setMerchant({})
        c.setMerchantOpen(true)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, line .. "3 shows; last: read, 0 recorded, nothing with a price in coin was read."), 1)
        -- Switched off: said, with no count.
        k:SwitchOff(ns.PriceWatch.NAME, "test")
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, line .. "not running (off)."), 1)
    end,

    ["slash: diag has no price watch line on a kernel that has no price watch (PW1)"] = function(t)
        local _, c = start()
        login(c)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, "price watch"), 0)
        t.ok(#c.printed > 0, "the snapshot line is printed")
    end,

    ["sched: held counts the work that waits for combat to end, and says when combat is not known (CU6)"] = function(t)
        local k, c = start()
        login(c)
        t.ok(type(k.sched.held) == "function", "sched:held exists")
        if type(k.sched.held) ~= "function" then return end
        local ran = 0
        local function work() ran = ran + 1 end
        t.eq({ k.sched:held() }, { 0, false })
        k.sched:afterCombat("x", work)
        t.eq(ran, 1, "out of combat it runs at once")
        t.eq({ k.sched:held() }, { 0, false })
        c.inCombat = function() return nil end
        local cancel = k.sched:afterCombat("x", work)
        k.sched:afterCombat("x", work)
        k.sched:every("x", 1, work, { when = "outOfCombat" })
        k.sched:every("x", 1, function() end)
        t.eq({ k.sched:held() }, { 2, true }, "the timed job is not due yet")
        c.advance(2, 4)
        t.eq(ran, 1, "nothing of it ran")
        t.eq({ k.sched:held() }, { 3, true })
        cancel()
        t.eq({ k.sched:held() }, { 2, true }, "a cancelled job is not counted")
        c.inCombat = function() return true end
        t.eq({ k.sched:held() }, { 2, false }, "in a fight they are held, and combat is known")
        c.inCombat = function() return false end
        t.eq({ k.sched:held() }, { 0, false }, "out of combat nothing is held")
    end,

    ["slash: diag counts the jobs held because combat is not known (CU6)"] = function(t)
        local k, c = start()
        login(c)
        local function work() end
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, "combat is not known"), 0, "no line while combat is known")
        c.inCombat = function() return true end
        k.sched:afterCombat("x", work)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, "combat is not known"), 0, "a fight is not an unknown")
        c.inCombat = function() return nil end
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, ns.id.title .. ": combat is not known; 1 job is held until it is."), 1)
        k.sched:afterCombat("x", work)
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, ns.id.title .. ": combat is not known; 2 jobs are held until it is."), 1)
        k.sched:off("x")
        c.slashes[ns.id.slash]("diag")
        t.eq(said(c, ns.id.title .. ": combat is not known; 0 jobs are held until it is."), 1)
    end,

    -- DV2
    ["slash: a diag line that raises is a problem and one line; the snapshot line still comes"] = function(t)
        local c = ns.make.fakeClient({ env = env() })
        c.setClock(5000)
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        ns.PriceWatch.Declare(k)
        k:Boot()
        login(c)
        local got = k.use(ns.PriceWatch.NAME)
        t.ok(type(got) == "table" and type(got.Shows) == "function", "the price watch answers Shows")
        if type(got) ~= "table" then return end
        got.Shows = function() error("shows broke") end
        c.setTime(false)
        local before = k.problems:count("diag")
        local ok, err = pcall(c.slashes[ns.id.slash], "diag")
        t.ok(ok, "the command does not raise: " .. tostring(err))
        t.eq(said(c, "kept. Reload or log out to write it to disk."), 1, "the snapshot line")
        t.eq(said(c, ns.id.title .. ": the client gives no time; nothing that waits for a time runs."), 1,
            "the lines before it are still said")
        t.eq(said(c, ns.id.title .. ": the price watch line failed; it is kept as a problem."), 1, "one line instead")
        t.eq(said(c, "price watch: "), 0, "and no half line")
        t.eq(k.problems:count("diag"), before + 1)
        local p = k.problems:list("diag")
        local last = p[#p]
        t.ok(last ~= nil and last.owner == "price watch" and tostring(last.text):find("shows broke", 1, true) ~= nil,
            "the problem row names the line and carries the error")
    end,
    -- Lead section 245 item 2 (LOW-MED): the profession window opening and
    -- closing are kept in the timing marks, so a capture shows each event
    -- fired on the client (an event name is not a global, so Diag.NAMES
    -- can not say it).
    ["windows: the profession window show and close are marked"] = function(t)
        local _, c, d = start()
        c.setSaved(ns.id.accountDB, {})
        login(c)
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_CLOSE")
        d.snapshot("after")
        local saved = c.saved(ns.id.accountDB).diag
        local timing = saved.snaps[#saved.snaps].timing
        t.ok(type(timing.TRADE_SKILL_SHOW) == "table", "the show marked")
        t.ok(type(timing.TRADE_SKILL_CLOSE) == "table", "the close marked")
        t.eq({ timing.order[5], timing.order[6] }, { "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" })
    end,

    -- Lead section 245 item 2 (LOW-MED): the recipe colour and skill up
    -- fields c.recipes reads each get a capture field of their own.
    ["profession: the recipe colour and skill up fields are captured"] = function(t)
        local e = env()
        e.C_TradeSkillUI = {
            GetAllRecipeIDs = function() return { 2660 } end,
            GetRecipeInfo = function(recipe) return { recipeID = recipe, relativeDifficulty = 1, numSkillUps = 2 } end,
        }
        local S = ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
        t.eq(S.recipeDifficulty and S.recipeDifficulty.values.v1, 1)
        t.eq(S.recipeSkillUps and S.recipeSkillUps.values.v1, 2)
        e.C_TradeSkillUI.GetRecipeInfo = function(recipe) return { recipeID = recipe } end
        S = ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
        t.eq(S.recipeDifficulty and S.recipeDifficulty.types[1], "nil", "a field the client leaves out reads as nil")
        t.eq(S.recipeSkillUps and S.recipeSkillUps.ok, true)
    end,

    -- Lead section 248 OC-1 (LOW): Oath of Light, read as a buff on you (a
    -- first guess), gets capture fields: the spell by name and the aura by
    -- its id. Made-up spell id; not seen in game.
    ["paladin oath: the spell and the aura on you are captured"] = function(t)
        local e = env()
        local asked = {}
        e.C_Spell = { GetSpellInfo = function(v)
            if v == "Oath of Light" then return { name = v, spellID = 99001 } end
        end }
        e.C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
            asked[#asked + 1] = id
            return { name = "Oath of Light", spellId = id, duration = 0 }
        end }
        local S = ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
        t.eq(S.oathSpell and S.oathSpell.ok, true)
        t.eq(asked, { 99001 }, "the aura asked by the spell id")
        t.eq(S.oathAura and S.oathAura.ok, true)
        t.eq(S.oathAura and S.oathAura.types[1], "table")
        e.C_Spell.GetSpellInfo = function() return nil end
        S = ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
        t.eq(S.oathSpell and S.oathSpell.types[1], "nil", "the spell not known")
        t.eq(S.oathAura, nil, "no id: the aura not asked")
        local named = {}
        for _, n in ipairs(ns.Diag.NAMES) do named[n] = true end
        t.ok(named["C_UnitAuras.GetPlayerAuraBySpellID"], "the aura read is named")
        t.ok(named["C_Spell.GetSpellInfo"], "the spell read is named")
    end,
}
