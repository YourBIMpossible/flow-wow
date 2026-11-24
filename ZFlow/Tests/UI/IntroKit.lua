local _, ns = ...

-- The first-run intro drawn by the shared kit (lead sections 297 item 5
-- and 322 line 6): one kit window, "Intro", its first sentence the header
-- and the rest kit lines. A kit line stays on one line, so the long
-- sentences are cut at word ends (Intro.Wrap). The plain panel is what is
-- left when the kit or the client refuses the window. The older cases
-- (Tests/UI/Intro.lua) refuse the kit window in their setup and are the
-- plain panel cases.
-- Fake client; not tested in game.
--
-- Red before the code: the intro asks for no kit window, so c.kitWindows()
-- holds none and every test here fails its first check.

local I = ns.Intro
local tests = {}

local ID = "Intro"

-- opts: char (saved data), settingOff, kitFails (how many kit windows the
-- client refuses), noClose (a client whose plain panels cannot be closed).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local char = opts.char
    if opts.settingOff then
        char = char or {}
        char.settings = { ui = { intro = false } }
    end
    if char then c.setSaved(ns.id.charDB, char) end
    if opts.noClose then c.setCloseRoute(false) end
    if opts.kitFails and type(c.setKitFails) == "function" then c.setKitFails(opts.kitFails) end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    if opts.settingOff then
        k:Setting({ key = I.SETTING, scope = "char", type = "bool", default = true, label = "First-run intro" })
    end
    local api = I.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag
end

local function kit(c)
    if type(c.kitWindows) ~= "function" then return nil end
    return c.kitWindows()[ID]
end

local function kitShown(c)
    local w = kit(c)
    return w ~= nil and w.shown == true
end

-- The window's words: the header, then the lines joined back into text.
local function wordsOf(c)
    local w = kit(c)
    local header, rest = nil, {}
    for _, p in ipairs(w and w.parts or {}) do
        if p.kind == "header" then header = p.text end
        if p.kind == "line" then rest[#rest + 1] = p.text end
    end
    return header, table.concat(rest, " "), rest
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Intro" then return p end
    end
    return nil
end

local function hostProblems(k)
    local kind = ns.KitHost and ns.KitHost.PROBLEM or "kitHost"
    return k.problems:count(kind)
end

tests["intro kit: the first login shows one kit window with the intro's words"] = function(t)
    local k, c, api = start()
    t.eq(kitShown(c), true, "the kit window is shown")
    local lines = I.Lines(ns.id)
    local header, text, parts = wordsOf(c)
    t.eq(header, lines[1], "the welcome is the header")
    t.eq(text, table.concat(lines, " ", 2), "every other word, in order")
    t.ok(type(I.WRAP) == "number", "Intro.WRAP")
    for _, l in ipairs(parts) do
        t.ok(#l <= (I.WRAP or 0), "a kit line stays on one line: " .. l)
    end
    local p = panelOf(c)
    t.ok(p ~= nil, "the plain panel is still made, behind the kit")
    t.eq(p and p.shown, false, "and is not shown")
    t.eq(api.shows(), 1)
    t.eq(hostProblems(k), 0, "no problem")
end

tests["intro kit: closing the window marks the character; the next login shows nothing"] = function(t)
    local k, c = start()
    t.eq(k.store:get("char", I.SEEN_PATH), nil, "not marked until closed")
    t.eq(type(c.kitClose) == "function" and c.kitClose(ID), true, "the player closes it")
    t.eq(kitShown(c), false, "closed")
    t.eq(k.store:get("char", I.SEEN_PATH), true, "marked as seen")
    local _, c2, api2 = start({ char = { state = { intro = { seen = true } } } })
    t.eq(kitShown(c2), false, "a later login: not shown")
    t.eq(api2.shows(), 0)
end

tests["intro kit: the intro word shows it again, also after it was closed"] = function(t)
    local _, c, api, diag = start({ char = { state = { intro = { seen = true } } } })
    t.eq(kitShown(c), false, "seen: not shown at login")
    diag.commands[I.WORD]("")
    t.eq(kitShown(c), true, "asked for: shown")
    t.eq(api.shows(), 1)
    t.eq(type(c.kitClose) == "function" and c.kitClose(ID), true, "closed again")
    diag.commands[I.WORD]("")
    t.eq(kitShown(c), true, "and shown again")
    t.eq(api.shows(), 2)
end

tests["intro kit: ui.intro off keeps it from showing at login; the intro word still shows it"] = function(t)
    local _, c, _, diag = start({ settingOff = true })
    t.eq(kitShown(c), false, "not shown at login")
    diag.commands[I.WORD]("")
    t.eq(kitShown(c), true, "asked for, so shown")
end

tests["intro kit: the kit window has its own close, so it shows where a plain panel could not be closed"] = function(t)
    local k, c = start({ noClose = true })
    t.eq(kitShown(c), true, "shown at login")
    t.eq(type(c.kitClose) == "function" and c.kitClose(ID), true, "the player closes it")
    t.eq(k.store:get("char", I.SEEN_PATH), true, "marked as seen")
end

tests["intro kit: a refused kit window hands over to the plain panel, with one problem line"] = function(t)
    local k, c, _, diag = start({ kitFails = math.huge })
    t.eq(kit(c), nil, "no kit window")
    local p = panelOf(c)
    t.ok(p ~= nil, "the plain panel")
    if p == nil then return end
    t.eq(p.shown, true, "shown in its place")
    t.eq(p.lines, I.Lines(ns.id), "the intro's lines, uncut")
    t.eq(hostProblems(k), 1, "one line says the plain panel is used")
    p.close()
    t.eq(k.store:get("char", I.SEEN_PATH), true, "closing the plain panel marks the character")
    diag.commands[I.WORD]("")
    t.eq(p.shown, true, "the word shows the plain panel")
    t.eq(hostProblems(k), 1, "said once")
end

tests["intro kit: refused, and a plain panel that cannot be closed: nothing at login"] = function(t)
    local k, c, api, diag = start({ kitFails = math.huge, noClose = true })
    local p = panelOf(c)
    t.ok(p ~= nil, "the plain panel")
    if p == nil then return end
    t.eq(p.shown, false, "not shown at login")
    t.eq(api.shows(), 0)
    diag.commands[I.WORD]("")
    t.eq(p.shown, true, "shown when asked for")
    t.eq(k.store:get("char", I.SEEN_PATH), nil, "not marked seen")
end

tests["intro kit: the view is a window the kit takes; it closes, and has nothing else to press"] = function(t)
    t.ok(type(I.View) == "function", "Intro.View")
    if type(I.View) ~= "function" then return end
    local id = { title = "Test-Addon", slash = "/testaddon" }
    local tree, why = ns.Kit.Window(I.View(id))
    t.ok(type(tree) == "table", "the kit takes it: " .. tostring(why))
    if type(tree) ~= "table" then return end
    t.ok(tree.closable ~= false, "a close button")
    t.ok(tree.escape ~= false, "Escape closes it")
    local n, all = 0, {}
    ns.Kit.Each(tree, function(part)
        n = n + 1
        all[#all + 1] = tostring(ns.Kit.TextOf(part))
        t.ok(part.kind ~= "button" and part.onClick == nil, "nothing to press: " .. tostring(part.kind))
    end)
    t.ok(n >= #I.Lines(id), "its lines are parts")
    local text = table.concat(all, " ")
    t.ok(text:find("Test-Addon", 1, true) ~= nil, "the title from the identity")
    t.ok(text:find("/testaddon help", 1, true) ~= nil, "the help command from the identity")
    t.ok(text:find(ns.id.slash .. " ", 1, true) == nil, "nothing written in")
    local odd, whyOdd = ns.Kit.Window(I.View(nil))
    t.ok(type(odd) == "table", "no identity given is still a window: " .. tostring(whyOdd))
end

tests["intro kit: Wrap cuts at word ends and loses no word"] = function(t)
    t.ok(type(I.Wrap) == "function", "Intro.Wrap")
    if type(I.Wrap) ~= "function" then return end
    t.eq(I.Wrap("one two three", 7), { "one two", "three" })
    t.eq(I.Wrap("one two three", 100), { "one two three" })
    t.eq(I.Wrap("abcdefghij kl", 4), { "abcdefghij", "kl" }, "a word longer than the width stands alone, uncut")
    t.eq(I.Wrap("  spaced   out  ", 20), { "spaced out" })
    t.eq(I.Wrap("", 10), {}, "no words, no line")
    t.eq(I.Wrap(nil, 10), {}, "not text, no line")
    t.eq(I.Wrap("one two", 0), { "one two" }, "a width that is no width leaves the text whole")
end

return tests
