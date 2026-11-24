-- The guide window (G54, UI/HelpPages.lua), end to end on the whole add-on
-- loaded on a fake client: opened by the slash word, a page picked, the
-- search, and that every page names only commands the add-on has. Built
-- from the kit's parts only. Not tested in game.
local _, ns = ...
local tests = {}

local function H() return ns.HelpPages end

-- Words of features that are off until the player turns them on.
local OFF_HERE = { feedback = true }

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

local function open(c)
    c.slashes[ns.id.slash](H().WORD)
    return c.kitWindows()[H().ID]
end

local function texts(rec)
    local out = {}
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.text ~= nil then out[#out + 1] = tostring(p.text) end
    end
    return table.concat(out, " | ")
end

local function hasKind(rec, kind)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.kind == kind then return true end
    end
    return false
end

tests["guide: the slash word opens it on the first page, built from kit parts"] = function(t)
    local c, addon = boot()
    local rec = open(c)
    t.ok(rec ~= nil, "a kit window")
    t.eq(rec and rec.shown, true)
    t.ok(hasKind(rec, "topicList"), "the features on the left")
    t.ok(hasKind(rec, "header"), "the header with search")
    local words = texts(rec)
    t.ok(words:find("Start here", 1, true) ~= nil, words)
    t.ok(words:find(ns.id.slash .. " settings", 1, true) ~= nil, words)
    t.ok(words:find(ns.id.slash .. " guide", 1, true) ~= nil, "it names its own word: " .. words)
    for _, pr in ipairs(addon.problems:list()) do
        t.ok(pr.kind ~= H().NAME and pr.owner ~= H().NAME, "no problem of its own")
    end
end

tests["guide: a page picked shows that feature and its commands"] = function(t)
    local c = boot()
    open(c)
    t.eq(c.kitSelect(H().ID, "pages", 2), true)
    local words = texts(c.kitWindows()[H().ID])
    t.ok(words:find("The arrow points at your next quest step.", 1, true) ~= nil, words)
    t.ok(words:find(ns.id.slash .. " route skip", 1, true) ~= nil, words)
    t.ok(words:find(ns.id.slash .. " settings", 1, true) == nil, "the first page's lines are gone")
end

tests["guide: every page has a command, and names only commands the add-on has"] = function(t)
    local _, addon = boot()
    local commands, help = addon.diag.commands, addon.diag.help
    local seen = {}
    for _, p in ipairs(H().PAGES) do
        t.ok(not seen[p.id], "one page per id: " .. tostring(p.id))
        seen[p.id] = true
        t.ok(#p.about > 0, p.id .. " says what it shows")
        for _, w in ipairs(p.words) do
            t.ok(OFF_HERE[w.word] or type(commands[w.word]) == "function",
                p.id .. " names a command that is not there: " .. w.word)
            local say = w.say or w.word
            t.ok(say == w.word or say:sub(1, #w.word + 1) == w.word .. " ", "what to type starts with the word: " .. say)
        end
        local lines = H().Page(p, commands, help, ns.id.slash)
        t.ok(lines[#lines].kind == "line", p.id .. " ends in a command")
    end
end

tests["guide: a command the add-on lacks is left out; a page with none says so"] = function(t)
    local page = { id = "x", title = "X", about = { { "About." } },
        words = { { word = "here", text = "Is here" }, { word = "gone", text = "Is gone" } } }
    local lines = H().Page(page, { here = function() end }, { here = "the long help" }, "/s")
    t.eq(#lines, 4)
    t.eq(lines[1].big, true)
    t.eq(lines[4].text, "/s here")
    t.eq(lines[4].sub, "Is here")
    t.eq(lines[4].tooltip, "the long help")
    local none = H().Page(page, {}, {}, "/s")
    t.eq(none[#none].kind, "empty")
    t.eq(none[#none].text, H().NO_COMMANDS[1])
end

tests["guide: the search narrows the pages, and says when none has the word"] = function(t)
    local c = boot()
    open(c)
    t.eq(#H().Search(H().PAGES, ""), #H().PAGES)
    local found = H().Search(H().PAGES, "DUNGEON")
    t.eq(#found, 1)
    t.eq(found[1].id, "dungeons")
    t.eq(c.kitType(H().ID, "header", "dungeon"), true)
    local words = texts(c.kitWindows()[H().ID])
    t.ok(words:find(ns.id.slash .. " dungeons", 1, true) ~= nil, words)
    t.ok(words:find("Start here", 1, true) == nil, words)
    t.eq(c.kitType(H().ID, "header", "zzzz"), true)
    local rec = c.kitWindows()[H().ID]
    t.ok(hasKind(rec, "empty"), "nothing found is said")
    t.ok(not hasKind(rec, "topicList"))
end

tests["guide: its place is kept, and help lists its word"] = function(t)
    local c, addon = boot()
    t.eq(addon.diag.help[H().WORD], H().HELP)
    open(c)
    t.eq(addon.helpPages.Shown(), true)
    local at = { "TOPLEFT", "TOPLEFT", 40, -60 }
    t.eq(c.kitDrag(H().ID, at, 700, 500), true)
    t.eq(addon.store:get("account", H().PATH), { point = at, width = 700, height = 500 })
    addon.helpPages.Close()
    t.eq(addon.helpPages.Shown(), false)
end

return tests
