local _, ns = ...
-- Lead section 294 item 5 (zflow-prof-arrow): with no step the quest arrow
-- no longer hides without a word. Its frame stays up with one line that
-- says why: no quest tracked, or no route known to this objective. Not
-- when the player hid the quest arrow or turned the quest arrow setting
-- off: those choices are kept as saved and nothing is shown. Whole add-on
-- loaded the way the game loads it (ns.offline.addon) on a fake client,
-- made-up places and names only. Look only. Not tested in game.
local tests = {}
local Arrow = ns.Arrow

-- opts: log (the quest log rows; nil: not known), account, charSettings,
-- professions (client.professions names).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    account.layout = account.layout or {}
    account.layout.arrowIntroSeen = true
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, { settings = opts.charSettings })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.log then c.setQuestLog(opts.log) end
    if opts.professions then c.setProfessions(opts.professions) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The quest frame is up with exactly these lines and no needle.
local function whyOnly(t, c, lines, what)
    local q = c.arrows and c.arrows[1]
    t.eq(q and q.shown, true, what .. ": the quest frame is up")
    t.eq(q and q.lines, lines, what .. ": its words")
    c.advance(0.1, 2)
    t.eq(q and type(q.drawn) == "table" and q.drawn.body, 0, what .. ": no needle")
end

-- A quest in the log that gives no step: no objective left to do and not
-- complete, so there is nowhere known to send the player.
local LOG = { { id = 101, title = "A Made-up Errand", objectives = {} } }

-- Fails before: the quest arrow hides with no word.
tests["quest arrow why: a default profile with no quest tracked says so"] = function(t)
    t.ok(Arrow ~= nil and Arrow.NO_QUEST ~= nil, "the line exists")
    local c = start({ log = {} })
    whyOnly(t, c, { Arrow and Arrow.NO_QUEST }, "empty quest log")
    local c2 = start({})
    whyOnly(t, c2, { Arrow and Arrow.NO_QUEST }, "quest log not known")
end

-- Fails before: a tracked quest with no known place hides the arrow.
tests["quest arrow why: a quest with no known route to its objective says so"] = function(t)
    t.ok(Arrow ~= nil and Arrow.NO_ROUTE ~= nil, "the line exists")
    local c = start({ log = LOG })
    whyOnly(t, c, { Arrow and Arrow.NO_ROUTE }, "no step known")
end

tests["quest arrow why: an arrow the player hid stays hidden and the choice stays saved"] = function(t)
    local c = start({ log = {} })
    c.slashes[ns.id.slash]("arrow hide quest")
    c.advance(1, 4)
    t.eq(c.arrows[1].shown, false, "hidden by the player: nothing shown")
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    t.eq(c.arrows[1].shown, false, "still hidden after a new layout")
    local acc = c.saved(ns.id.accountDB)
    local arrows = acc and acc.layout and acc.layout.arrows
    t.eq(arrows and arrows.hidden and arrows.hidden.quest, true, "the saved choice is unchanged")
end

tests["quest arrow why: the quest arrow setting off is kept and nothing is said"] = function(t)
    local c = start({ log = {}, charSettings = { quest = { arrow = false } },
        account = { settings = { quest = { arrow = false } } } })
    t.eq(c.arrows[1].shown, false, "quest arrow off: nothing shown")
    local acc, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    t.eq(acc.settings and acc.settings.quest and acc.settings.quest.arrow, false, "the saved choice is unchanged (account)")
    t.eq(char.settings and char.settings.quest and char.settings.quest.arrow, false, "the saved choice is unchanged (character)")
end

-- A profession step with no quest step. Stacked (the default), the
-- profession step takes the stack's place and the stack is not silent, so
-- no why line is put over it. Apart, the quest arrow has its own frame and
-- says why, and the profession frame keeps its line.
tests["quest arrow why: stacked, a profession step takes the stack and no why line is put over it"] = function(t)
    local N = ns.Nav
    local c = start({ log = {}, professions = { "Mining" } })
    local q, p = c.arrows[1], c.arrows[2]
    t.eq(q and q.shown, false, "no quest frame over the profession step")
    t.eq(p and p.shown, true, "the profession frame is up")
    t.eq(p and p.lines, { N.PROF_WHY_GM_ABSENT:format("Mining") }, "its words")
end

tests["quest arrow why: separate, the quest arrow says why and the profession frame keeps its line"] = function(t)
    local N = ns.Nav
    local c = start({ log = {}, professions = { "Mining" },
        account = { layout = { arrows = { mode = "separate" } } } })
    whyOnly(t, c, { Arrow.NO_QUEST }, "separate")
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "separate: the profession frame is up")
    t.eq(p and p.lines, { N.PROF_WHY_GM_ABSENT:format("Mining") }, "separate: its words")
end

return tests
