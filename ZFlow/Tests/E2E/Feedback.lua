local _, ns = ...
-- In-game feedback (row N73, lead section 247) on the whole add-on loaded on
-- a fake client, through its three entry points: the slash word, the
-- settings page (the row's own button) and the arrow menu's row. The player
-- writes through the fake's text entry, presses the window's buttons and
-- reads the copy box. Per lead section 236: data arriving late (the
-- character's name not readable yet), a reload in the middle, and a
-- diagnostics read that raises, then recovers. Offline: the fake client's
-- frames, not the game's. Not tested in game. Made-up names and words only.
local tests = {}

local NAMES = { name = "Zarkon", realm = "Stormrage", guild = "Knights of Zar" }

-- opts: account, char (saved tables), who (the names the client answers; a
-- field left nil is not readable), before(c), arrows.
local function boot(opts)
    opts = opts or {}
    local who = opts.who or { name = NAMES.name, realm = NAMES.realm, guild = NAMES.guild }
    -- The feedback is paused (lead section 284); these tests run it with
    -- the fake client internal switch on.
    local c = ns.make.fakeClient({ internal = { feedback = true }, env = {
        UnitName = function() return who.name end,
        GetRealmName = function() return who.realm end,
        GetGuildInfo = function() return who.guild end,
        GetBuildInfo = function() return "1.16.1", "7777" end,
    } })
    local account = opts.account or {}
    if opts.arrows then
        if type(account.layout) ~= "table" then account.layout = {} end
        account.layout.arrowIntroSeen = true
        c.setScreen(1024, 768)
        c.setZone(1, 1411)
        c.setFacing(0)
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setVersion("0.1.0")
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, who
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

local function window(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Feedback" then return p end
    end
    return nil
end

local function boxOf(c, which)
    for _, b in ipairs(c.copyBoxes or {}) do
        if type(b.spec) == "table" and b.spec.name == ns.id.framePrefix .. "Feedback" .. which then return b end
    end
    return nil
end

local function rowOf(p, key)
    for _, r in ipairs(p and p.rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function hasInfo(p, text)
    for _, r in ipairs(p and p.rows or {}) do
        if r.kind == "info" and tostring(r.text):find(text, 1, true) then return true end
    end
    return false
end

-- The player writes one field: presses its button, types, presses Enter.
local function write(c, p, field, text)
    if not p.press("write." .. field) then return false end
    local entry
    if type(c.textEntries) == "table" then entry = c.textEntries[#c.textEntries] end
    if not entry then return false end
    return entry.type(text)
end

-- The copied report: the player presses Copy report and reads the box.
local function copied(c, p)
    if not p.press("copy") then return nil end
    local box = boxOf(c, "Copy")
    if not box or box.shown ~= true then return nil end
    return box.text
end

local function lines(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
end

local function hasLine(text, line)
    for _, l in ipairs(lines(text)) do
        if l == line then return true end
    end
    return false
end

local function ready(t, c, addon)
    local ok = type(addon.Feedback) == "table" and type(c.textEntry) == "function"
    t.ok(ok, "the add-on has the feedback module and the fake has a text entry")
    return ok
end

-- Opens the window with the slash word and gives it back.
local function open(t, c)
    slash(c, "feedback")
    local p = window(c)
    t.ok(p ~= nil and p.shown() == true, "the feedback window is on the screen")
    return p
end

-- Entry points ---------------------------------------------------------------

-- Fails before: UI/Feedback.lua is absent: no slash word, no settings row,
-- no menu row.
tests["feedback opens from the slash word, from its settings row's button and from the arrow menu, and from nowhere before"] = function(t)
    local c, addon = boot({ arrows = true })
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    c.advance(30, 60)
    t.eq(window(c), nil, "no window is made until it is opened")
    t.eq(#c.textEntries, 0, "and no box to type in")
    t.eq(boxOf(c, "Copy"), nil)

    -- 1. The slash word.
    slash(c, "feedback")
    local p = window(c)
    t.ok(p ~= nil and p.shown() == true, "the slash word opens it")
    if not p then return end
    p.close()
    t.eq(p.shown(), false)

    -- 2. The settings: found by the owner's words, with a button that opens it.
    for _, word in ipairs({ "feedback", "bug", "report", "problem", "idea", "suggest" }) do
        local found = addon.SettingsPage.Search(addon, word)
        local hit = false
        for _, e in ipairs(found and found.results or {}) do
            if e.key == F.SETTING then hit = true end
        end
        t.ok(hit, "the settings search finds it by: " .. word)
    end
    slash(c, "settings feedback")
    local row
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == F.SETTING then row = r end
    end
    t.ok(row ~= nil, "the row is on the settings page")
    if not row then return end
    t.eq({ row.kind, row.value, row.topic }, { "toggle", false, "general" }, "a switch, off, under General")
    t.eq({ row.jumpKind, row.jump, row.jumpText }, { "open", F.SETTING, F.ROW_OPEN }, "with its own button")
    t.eq(c.optionsNav("open", row.jump), true)
    t.eq(p.shown(), true, "the button opens the window")
    p.close()

    -- 3. The arrow menu.
    slash(c, "arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    q.click("right")
    t.ok(#q.menuItems <= addon.Settings.Topics.MENU_MAX, "the top level is still short: " .. #q.menuItems)
    t.eq(q.pickRow("feedback"), true, "the menu has the row")
    t.eq(p.shown(), true, "and it opens the window")
    t.eq(#c.rowPanels > 0 and window(c) == p, true, "one window, not one for each way in")
end

-- Each kind of report ---------------------------------------------------------

-- Fails before: no feedback module.
tests["feedback: a problem, a suggestion and an idea each give their own report, and the preview is the copied text"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local problemsAtStart = addon.problems:count()
    local p = open(t, c)
    if not p then return end
    t.eq(rowOf(p, "copy").enabled, false, "nothing to copy before anything is written")
    t.eq(p.press("copy"), false)
    t.eq(rowOf(p, "write.happened"), nil, "the two more fields are a problem's")

    t.eq(p.press("kind.problem"), true)
    t.ok(rowOf(p, "write.happened") ~= nil and rowOf(p, "write.expected") ~= nil, "a problem asks two more, optional")
    t.eq(rowOf(p, "copy").enabled, false, "still no description")
    t.eq(write(c, p, "description", "The quest arrow spins at the bridge"), true)
    t.eq(rowOf(p, "copy").enabled, true)
    t.eq(write(c, p, "happened", "It turned twice and stopped"), true)
    t.eq(write(c, p, "expected", "It should point at the camp"), true)
    local problem = copied(c, p)
    t.eq(lines(problem), {
        ns.id.title .. " feedback: Problem report",
        "Description: The quest arrow spins at the bridge",
        "What happened: It turned twice and stopped",
        "What was expected: It should point at the camp",
    })
    t.eq(p.press("preview"), true)
    t.eq(boxOf(c, "Preview") and boxOf(c, "Preview").text, problem, "the preview is exactly the copied text")
    t.eq(addon.feedback.report(), problem, "and nothing is added to it after")

    t.eq(p.press("kind.suggest"), true)
    t.eq(lines(copied(c, p)), {
        ns.id.title .. " feedback: Suggested improvement",
        "Description: The quest arrow spins at the bridge",
    }, "what happened and what was expected do not ride along")
    t.eq(p.press("kind.idea"), true)
    t.eq(write(c, p, "description", "A sound when a rare is near"), true)
    t.eq(lines(copied(c, p)), { ns.id.title .. " feedback: Idea", "Description: A sound when a rare is near" })

    -- Escape in the box to type in changes nothing.
    t.eq(p.press("write.description"), true)
    c.textEntries[#c.textEntries].escape()
    t.eq(addon.feedback.form().description, "A sound when a rare is near")
    -- Start again.
    t.eq(p.press("clear"), true)
    t.eq(rowOf(p, "copy").enabled, false)
    t.ok(hasInfo(p, F.NOT_WRITTEN), "the form is empty again")
    t.eq(addon.problems:count(), problemsAtStart, "none of it listed a problem")
    t.eq(F.COPY, rowOf(p, "copy").label, "the button says what it does")
end

-- Diagnostics on and off --------------------------------------------------------

-- Fails before: no feedback module.
tests["feedback diagnostics: off by default with no diagnostics line at all; on, the add-on puts them together itself"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    t.eq(addon.settings:get(F.SETTING), false, "off until the player turns it on")
    local p = open(t, c)
    if not p then return end
    p.press("kind.idea")
    write(c, p, "description", "A thought")
    t.eq(rowOf(p, "diag").label, F.ATTACH .. "off")
    local off = copied(c, p)
    t.eq(#lines(off), 2)
    t.eq(off:find(F.DIAG_HEAD, 1, true), nil, "no diagnostics line")
    t.eq(off:find("Version", 1, true), nil)

    t.eq(p.press("diag"), true)
    t.eq(addon.settings:get(F.SETTING), true)
    t.eq(rowOf(p, "diag").label, F.ATTACH .. "on")
    local on = copied(c, p)
    t.ok(hasLine(on, F.DIAG_HEAD), "the diagnostics block: " .. tostring(on))
    t.ok(hasLine(on, "Version: 0.1.0; game build: 1.16.1 (7777)"), "version and build, read by the add-on")
    t.ok(hasLine(on, "State: running; paused: no; saved data loaded: yes"))
    local starts = {}
    for _, line in ipairs(lines(on)) do starts[#starts + 1] = line:match("^[^:]+") end
    for _, head in ipairs({ "Snapshot", "Client names asked", "Reads known", "Reads", "Events not registered",
        "Snapshots", "The add-on's own problems, newest first" }) do
        local found = false
        for _, start in ipairs(starts) do
            if start == head then found = true end
        end
        t.ok(found, "the allowlisted line: " .. head)
    end
    t.ok(#lines(on) - 2 <= F.MAX_DIAG_LINES and #on <= F.MAX_BYTES, "inside its caps")
    p.press("preview")
    t.eq(boxOf(c, "Preview").text, on, "the preview shows the diagnostics too: exactly what is copied")

    t.eq(p.press("diag"), true)
    t.eq(copied(c, p), off, "off again: gone")
end

-- Privacy (lead section 251) -----------------------------------------------------

local function lowHas(text, word)
    return tostring(text):lower():find(word, 1, true) ~= nil
end

-- A made-up problem of the add-on's own, with everything that must not be
-- shared in it: a Windows user folder, the character's and realm's names,
-- quoted text and an item link.
local function seededProblem(addon)
    addon.problems:add("made", "Zarkon", "C:\\Users\\Marlowe\\WoW\\Interface\\AddOns\\" .. ns.id.addon
        .. "\\UI\\Made.lua:12: Zarkon of Stormrage said \"meet Brannoch at dusk\" about "
        .. "|cff0070dd|Hitem:4321:0:0|h[Sword of Brannoch]|h|r in Knights of Zar")
end

-- Fails before the section 251 rework: the block read Diag's error list
-- (timing.errors), printed problem texts with only names masked (the path,
-- the quoted text and the link stayed), and typed paths were not cut.
tests["feedback privacy: names and a user folder seeded in the problems, in the error list and in the description never reach the preview"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    seededProblem(addon)
    -- Diag's error list (timing.errors): the add-on's own line and another add-on's.
    c.raise("C:\\Users\\Marlowe\\WoW\\Interface\\AddOns\\" .. ns.id.addon .. "\\UI\\Made.lua:12: Zarkon of Stormrage has no bags")
    c.raise("Interface\\AddOns\\Elsewhere\\Other.lua:3: whisper from Zarkon: the vault code is plum")
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "zarkon cannot loot on Stormrage, see C:\\Users\\Marlowe\\shot.png")
    write(c, p, "happened", "Knights of Zar bank tab stayed shut")
    p.press("diag")
    t.eq(p.press("preview"), true)
    local preview = boxOf(c, "Preview") and boxOf(c, "Preview").text
    t.ok(type(preview) == "string" and hasLine(preview, F.DIAG_HEAD), "a preview with diagnostics")
    if type(preview) ~= "string" then return end
    for _, word in ipairs({ "zarkon", "stormrage", "knights of zar", "marlowe", "users", "brannoch", "4321" }) do
        t.eq(lowHas(preview, word), false, word .. " is not in the preview: " .. preview)
    end
    -- The error list is never read: not the add-on's own line, not another add-on's.
    t.eq(lowHas(preview, "has no bags"), false, "Diag's error list is not read")
    t.eq(lowHas(preview, "elsewhere"), false)
    t.eq(lowHas(preview, "plum"), false)
    -- The typed words are there, with only the names and the path replaced.
    t.ok(preview:find("Description: " .. F.HIDDEN .. " cannot loot on " .. F.HIDDEN .. ", see " .. F.PATH, 1, true) ~= nil,
        "the description: " .. preview)
    t.ok(preview:find("What happened: " .. F.HIDDEN .. " bank tab stayed shut", 1, true) ~= nil)
    -- The add-on's own problem is there, cleaned: its file from the add-on's
    -- folder on, the names, the quoted text and the link replaced.
    t.ok(preview:find("made, " .. F.HIDDEN .. ": " .. ns.id.addon .. "\\UI\\Made.lua:12: " .. F.HIDDEN .. " of " .. F.HIDDEN
        .. " said " .. F.QUOTED .. " about " .. F.LINK .. " in " .. F.HIDDEN, 1, true) ~= nil, "the cleaned problem: " .. preview)
    -- The copied text is the preview, byte for byte.
    local report = copied(c, p)
    t.eq(report == preview, true, "the copy is the preview")
    t.eq(#tostring(report), #preview, "to the byte")
end

-- Fails before: the link stayed in the printed problem text.
tests["feedback privacy: an item link in one of the add-on's problems is stripped, bare item strings too"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    addon.problems:add("made", "loot", "could not price |cffffffff|Hitem:9876:0:0:0|h[Odd Trinket]|h|r nor item:5555:1")
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "Prices are missing")
    p.press("diag")
    local report = copied(c, p)
    t.ok(type(report) == "string" and report:find("could not price " .. F.LINK .. " nor " .. F.LINK, 1, true) ~= nil,
        "both are replaced: " .. tostring(report))
    for _, word in ipairs({ "9876", "5555", "odd trinket", "|h" }) do
        t.eq(lowHas(report, word), false, word)
    end
end

-- Fails before: there was no cleaner to raise, and no line for one left out.
tests["feedback privacy: the cleaner raising on one problem leaves the others and the written feedback"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    t.ok(type(F.Clean) == "function", "the module has its cleaner")
    if type(F.Clean) ~= "function" then return end
    addon.problems:add("made", "one", "the first is fine")
    addon.problems:add("made", "two", "the second is the boomline")
    addon.problems:add("made", "three", "the third is fine too")
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "The bags do not open")
    p.press("diag")
    local clean, n = F.Clean, #c.printed
    F.Clean = function(text, ...)
        if tostring(text):find("boomline", 1, true) then error("the cleaner raised") end
        return clean(text, ...)
    end
    local report = copied(c, p)
    F.Clean = clean
    t.ok(type(report) == "string", "there is a report")
    if type(report) ~= "string" then return end
    t.ok(hasLine(report, "Description: The bags do not open"), "the written feedback is whole")
    t.ok(report:find("the third is fine too", 1, true) ~= nil and report:find("the first is fine", 1, true) ~= nil,
        "the other problems are there: " .. report)
    t.eq(lowHas(report, "boomline"), false, "the one it raised on is left out")
    t.ok(hasLine(report, F.ERROR_DROPPED), "and one line says so")
    t.eq(#c.printed, n, "nothing is said to the player")
    -- Newest first.
    t.ok(report:find("the third is fine too", 1, true) < report:find("the first is fine", 1, true), "newest first")
end

-- Fails before: the block was not an allowlist test target (no snapshot
-- field but the kernel's was read; this pins that none can be added).
tests["feedback privacy: a field added to the snapshot, or text put where a count belongs, does not reach the report"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local p = open(t, c)
    if not p then return end
    p.press("kind.idea")
    write(c, p, "description", "A thought")
    p.press("diag")
    local collect = addon.Diag.Collect
    addon.Diag.Collect = function(k, why)
        local snap = collect(k, why)
        -- New fields nobody cleared.
        snap.plumtree = "plumtree"
        snap.shapes = { realm = { values = { v1 = "plumtree" } }, fullName = { values = { v1 = "plumtree" } } }
        snap.timing = { character = "plumtree", realm = "plumtree", errors = { { text = "plumtree", ours = true, count = 1 } } }
        snap.kernel.plumtree = "plumtree"
        snap.kernel.pauseText = "plumtree"
        snap.kernel.blocked = { account = "plumtree" }
        snap.reads.plumtree = "plumtree"
        snap.reads.money = "plumtree"
        snap.reads.position = { map = "plumtree" }
        snap.known.plumtree = true
        -- Text where a count, a yes or no, or a fixed word belongs.
        snap.at = "plumtree"
        snap.clock = "plumtree"
        snap.reads.inCombat = "plumtree"
        snap.reads.bagStacks = "plumtree"
        snap.kernel.phase = "plumtree"
        snap.kernel.eventsNotRegistered = { "plumtree" }
        snap.names = { plumtree = "plumtree" }
        return snap
    end
    local report = copied(c, p)
    addon.Diag.Collect = collect
    t.ok(type(report) == "string" and hasLine(report, F.DIAG_HEAD), "a report with diagnostics")
    t.eq(lowHas(report, "plumtree"), false, "none of it is in the report: " .. tostring(report))
    t.ok(hasLine(report, "State: other; paused: no; saved data loaded: yes"), "a phase that is not the kernel's reads other")
    t.ok(report:find("Client names asked: 1; missing: 0", 1, true) ~= nil, "the names table is two counts")
    t.ok(report:find("Events not registered: 1", 1, true) ~= nil, "an event list is a count")
end

-- (a) Data late: the character's name is not readable yet.
-- Fails before the rework: the texts came from Diag's error list.
tests["feedback late names: until the character's name can be read, the problems are only counted; then they come, cleaned"] = function(t)
    local c, addon, who = boot({ who = {} })
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    addon.problems:add("made", "bags", "Zarkon has no bags")
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "The bags do not open")
    p.press("diag")
    local early = copied(c, p)
    t.ok(type(early) == "string" and early:find("The add-on's own problems, newest first: ", 1, true) ~= nil,
        "the problems are counted: " .. tostring(early))
    t.eq(lowHas(early, "has no bags"), false, "but their texts are left out")
    t.eq(lowHas(early, "zarkon"), false)
    t.ok(hasLine(early, F.TEXTS_OUT), "and the report says why")
    -- The name arrives.
    who.name, who.realm = NAMES.name, NAMES.realm
    local late = copied(c, p)
    t.ok(late:find("made, bags: " .. F.HIDDEN .. " has no bags", 1, true) ~= nil, "the text is there now, cleaned: " .. tostring(late))
    t.eq(lowHas(late, "zarkon"), false)
    t.eq(hasLine(late, F.TEXTS_OUT), false)
end

-- (c) A diagnostics read that raises, then recovers; and one that answers nothing.
-- Fails before: no feedback module.
tests["feedback collection failure: a read that raises or answers nothing still gives the report, with one line; then it recovers"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local problemsAtStart = addon.problems:count()
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "The bags do not open")
    p.press("diag")
    local good = copied(c, p)
    t.ok(hasLine(good, F.DIAG_HEAD), "diagnostics while all is well")

    local n, version = #c.printed, c.version
    c.version = function() error("the client raised") end
    local broken = copied(c, p)
    c.version = version
    t.eq(lines(broken), { ns.id.title .. " feedback: Problem report", "Description: The bags do not open", F.NO_DIAG },
        "the feedback is whole, with one line")
    t.eq(#c.printed, n, "nothing is said to the player about it")
    p.press("preview")

    local collect = addon.Diag.Collect
    addon.Diag.Collect = function() return nil end
    local empty = copied(c, p)
    addon.Diag.Collect = collect
    t.ok(hasLine(empty, F.NO_DIAG) and not hasLine(empty, F.DIAG_HEAD), "a snapshot that answers nothing is the same")

    t.eq(copied(c, p), good, "the next one has its diagnostics again")
    t.eq(addon.problems:count(), problemsAtStart, "and no error was raised into the add-on")
end

-- Combat ------------------------------------------------------------------------

-- Fails before: no feedback module.
tests["feedback in combat: the window is the add-on's own and opens; a lock that is on or not read is said, nothing else changes"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    c.setCombat(true)
    local p = open(t, c)
    if not p then return end
    t.ok(hasInfo(p, F.LOCK_NOTE), "in a fight the window says so")
    p.press("kind.idea")
    t.eq(write(c, p, "description", "A thought in a fight"), true)
    t.eq(lines(copied(c, p)), { ns.id.title .. " feedback: Idea", "Description: A thought in a fight" })
    t.eq(c.optionsOpened(), 0, "nothing of the game's is opened")
    -- The lock not read counts as on.
    c.setCombat(false)
    c.setLockdown(nil)
    slash(c, "feedback")
    t.ok(hasInfo(p, F.LOCK_NOTE), "not known is treated as locked")
    t.eq(p.shown(), true)
    -- Out of the fight, with the lock read.
    c.setLockdown(false)
    slash(c, "feedback")
    t.eq(hasInfo(p, F.LOCK_NOTE), false, "after the fight the line is gone")
    t.eq(addon.feedback.form().description, "A thought in a fight", "what was written is still there")
end

-- (b) Reload --------------------------------------------------------------------

-- Fails before: no feedback module.
tests["feedback reload: writing, previewing and copying save nothing; a reload keeps the one setting and no report"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local p = open(t, c)
    if not p then return end
    p.press("diag")
    local before = { copy(c.saved(ns.id.accountDB)), copy(c.saved(ns.id.charDB)) }
    p.press("kind.problem")
    write(c, p, "description", "plumtree is the word to look for")
    write(c, p, "happened", "plumtree again")
    p.press("preview")
    t.ok(type(copied(c, p)) == "string")
    t.eq({ c.saved(ns.id.accountDB), c.saved(ns.id.charDB) }, before, "nothing was saved by any of it")
    -- The reload, in the middle of writing.
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(F.SETTING), true, "the setting is kept")
    t.eq(addon2.feedback.form(), {}, "what was written is not")
    local p2 = open(t, c2)
    if not p2 then return end
    t.eq(rowOf(p2, "copy").enabled, false)
    t.eq(rowOf(p2, "diag").label, F.ATTACH .. "on")
    local function holds(v)
        if type(v) == "string" then return v:find("plumtree", 1, true) ~= nil end
        if type(v) ~= "table" then return false end
        for key, value in pairs(v) do
            if holds(key) or holds(value) then return true end
        end
        return false
    end
    t.eq(holds(c2.saved(ns.id.accountDB)) or holds(c2.saved(ns.id.charDB)), false, "no report is kept anywhere")
end

-- Destination -------------------------------------------------------------------

-- Fails before: no feedback module.
tests["feedback destination: not set up, the window says so and shows no address; set, it is one copyable line of its own"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    t.eq(F.DESTINATION, "", "the one constant is empty as shipped")
    local p = open(t, c)
    if not p then return end
    t.ok(hasInfo(p, F.NO_DESTINATION), "it says none is set up")
    t.eq(rowOf(p, "destination"), nil, "and offers no address")
    t.eq(p.press("destination"), false)
    -- With one set (made up): its own button, its own box, not in the report.
    F.DESTINATION = "the made-up board at example.invalid"
    slash(c, "feedback")
    t.eq(hasInfo(p, F.NO_DESTINATION), false)
    t.eq(p.press("destination"), true)
    t.eq(boxOf(c, "Address") and boxOf(c, "Address").text, "the made-up board at example.invalid")
    p.press("kind.idea")
    write(c, p, "description", "A thought")
    t.eq(copied(c, p):find("example.invalid", 1, true), nil, "the report is only the report")
    F.DESTINATION = ""
end

-- Wording and clients that cannot draw -------------------------------------------

-- Fails before: no feedback module.
tests["feedback wording: nothing the player can read says Sent or Submitted, in the window, the row, the help or a report"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local p = open(t, c)
    if not p then return end
    p.press("kind.problem")
    write(c, p, "description", "d")
    p.press("diag")
    local row = addon.settings:row(F.SETTING)
    local all = { row.label, row.help, F.HELP, copied(c, p), F.NO_DIAG, F.NO_WINDOW, F.NO_ENTRY, F.NO_BOX,
        F.PREVIEW_TITLE, F.COPY_TITLE, F.SHARE_AT, F.COPY_DESTINATION }
    for _, r in ipairs(p.rows) do all[#all + 1] = tostring(r.text or r.label) end
    for _, entry in ipairs(c.textEntries) do all[#all + 1] = entry.words end
    t.ok(#all >= 20, "the words were gathered: " .. #all)
    for _, text in ipairs(all) do
        local low = " " .. tostring(text):lower() .. " "
        t.eq(low:find("%Asent%A"), nil, tostring(text))
        t.eq(low:find("submitted", 1, true), nil, tostring(text))
    end
end

-- Fails before: no feedback module.
tests["feedback on a client that cannot draw: one line says so, nothing raises, and the report is printed when there is no copy box"] = function(t)
    local c, addon = boot({ before = function(cl) cl.setFrames(false) end })
    if not ready(t, c, addon) then return end
    local F = addon.Feedback
    local n, problemsAtStart = #c.printed, addon.problems:count()
    slash(c, "feedback")
    t.eq(window(c), nil)
    t.ok(tostring(c.printed[n + 1]):find(F.NO_WINDOW, 1, true) ~= nil, "said: " .. tostring(c.printed[n + 1]))
    t.eq(addon.problems:count(), problemsAtStart, "the word did not fail")
    -- A window but no box to type in.
    local c2, addon2 = boot({ before = function(cl) cl.setTextEntry(false) end })
    local p = open(t, c2)
    if not p then return end
    n = #c2.printed
    p.press("kind.idea")
    t.eq(p.press("write.description"), true)
    t.ok(tostring(c2.printed[n + 1]):find(addon2.Feedback.NO_ENTRY, 1, true) ~= nil, "said: " .. tostring(c2.printed[n + 1]))
    t.eq(rowOf(p, "copy").enabled, false)
end

return tests
