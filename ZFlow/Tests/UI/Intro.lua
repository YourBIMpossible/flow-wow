local _, ns = ...

-- Tests for ZFlow/UI/Intro.lua (U-D, G55): the first-run intro. On a
-- character's first login with Z-Flow a panel says in plain words what
-- Z-Flow shows and names /zflow help. Its close button or Escape hides it,
-- and then it is not shown again (char state.intro.seen). /zflow intro
-- shows it again. The row "ui.intro" (on by default) turns the first-login
-- showing off. It changes no setting. Fake client; not tested in game.
--
-- The close button and the Escape route are a CLIENT NEED: client.panel(spec)
-- with spec.closable = true, and the handle's h.onClose(fn), fn() when the
-- player closes it. The fake has both: h.close() is the player closing it,
-- and c.setCloseRoute(false) is a client without them.

local I = ns.Intro
local tests = {}

-- opts: setting (true / false / nil: no row declared), char (saved data),
-- noFrames, countSettings, noClose (a client whose panels cannot be closed).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local char = opts.char
    if opts.setting == false then
        -- Off before the first login: the store opens at PLAYER_LOGIN, so
        -- the player's choice is in the saved data the client hands over.
        char = char or {}
        char.settings = { ui = { intro = false } }
    end
    if char then c.setSaved(ns.id.charDB, char) end
    if opts.noFrames then c.setFrames(false) end
    if opts.noClose then c.setCloseRoute(false) end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = I.SETTING, scope = "char", type = "bool", default = true, label = "First-run intro" })
    end
    local writes = { n = 0 }
    if opts.countSettings then
        for _, name in ipairs({ "set", "reset" }) do
            local real = k.settings[name]
            k.settings[name] = function(...)
                writes.n = writes.n + 1
                return real(...)
            end
        end
    end
    local api = I.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag, writes
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Intro" then return p end
    end
    return nil
end

local function has(lines, pattern)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(pattern, 1, true) then return true end
    end
    return false
end

tests["intro: shown on a character's first login, in plain words, naming /zflow help"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(I.NAME)), "started")
    local p = panelOf(c)
    t.ok(p ~= nil, "the panel is made")
    t.eq(p.shown, true, "shown at the first login")
    t.eq(p.lines, I.Lines(ns.id), "the intro's lines")
    t.ok(has(p.lines, "/zflow help"), "names /zflow help")
    t.ok(has(p.lines, "/zflow intro"), "says how to see it again")
    t.ok(has(p.lines, "arrow"), "the arrows")
    t.ok(has(p.lines, "merchant"), "the vendor sell list")
    t.ok(has(p.lines, "tooltip"), "the gear tooltip lines")
    t.eq(api.shows(), 1)
    t.ok(type(ns.intro) == "table", "the addon's own is declared")
end

tests["intro: the lines are plain text"] = function(t)
    for _, l in ipairs(I.Lines(ns.id)) do
        t.ok(type(l) == "string" and l ~= "", "a line")
        t.ok(not l:find("|c", 1, true) and not l:find("|r", 1, true) and not l:find("|T", 1, true), "no markup: " .. l)
    end
end

tests["intro: the panel can be closed with its button or Escape"] = function(t)
    local _, c = start()
    local p = panelOf(c)
    t.eq(p.spec.closable, true, "asks the client for a close button and the Escape route")
    t.ok(type(p.spec.name) == "string" and p.spec.name ~= "", "a global name, which the Escape route needs")
end

tests["intro: closing it hides it and marks the character; the next login does not show it"] = function(t)
    local k, c = start()
    panelOf(c).close()
    t.eq(panelOf(c).shown, false, "hidden")
    t.eq(k.store:get("char", I.SEEN_PATH), true, "marked as seen")
    local _, c2, api2 = start({ char = { state = { intro = { seen = true } } } })
    t.eq(panelOf(c2).shown, false, "a later login: not shown")
    t.eq(api2.shows(), 0)
end

tests["intro: not closed (a reload before closing) shows it again at the next login"] = function(t)
    local k = start()
    t.eq(k.store:get("char", I.SEEN_PATH), nil, "not marked until closed")
end

tests["intro: /zflow intro shows it again, also after it was seen"] = function(t)
    local k, c, api, diag = start({ char = { state = { intro = { seen = true } } } })
    t.eq(panelOf(c).shown, false)
    t.ok(type(diag.commands[I.WORD]) == "function", "the word is added to the slash command")
    diag.commands[I.WORD]("")
    t.eq(panelOf(c).shown, true, "shown again")
    t.eq(api.shows(), 1)
    panelOf(c).close()
    t.eq(k.store:get("char", I.SEEN_PATH), true, "still seen")
    t.eq(I.WORD, "intro")
end

tests["intro: ui.intro off keeps it from showing at login; /zflow intro still shows it"] = function(t)
    local _, c, _, diag = start({ setting = false })
    t.eq(panelOf(c).shown, false, "not shown at login")
    diag.commands[I.WORD]("")
    t.eq(panelOf(c).shown, true, "asked for, so shown")
end

tests["intro: on by default, also before the lead's settings row exists"] = function(t)
    local _, c = start({ setting = true })
    t.eq(panelOf(c).shown, true, "row declared, default on: shown")
    local _, c2 = start()
    t.eq(panelOf(c2).shown, true, "no row yet: shown")
    t.eq(I.SETTING, "ui.intro", "the settings row's name")
end

tests["intro: it changes no setting"] = function(t)
    local _, c, _, diag, writes = start({ countSettings = true })
    panelOf(c).close()
    diag.commands[I.WORD]("")
    panelOf(c).close()
    t.eq(writes.n, 0, "no settings:set or settings:reset")
end

tests["intro: a client that cannot draw prints the lines when asked"] = function(t)
    local k, c, api, diag = start({ noFrames = true })
    t.eq((k:ModuleState(I.NAME)), "started", "still started")
    t.eq(#c.panels, 0, "no panel")
    t.eq(k.store:get("char", I.SEEN_PATH), nil, "nothing shown, so not seen")
    local before = #c.printed
    diag.commands[I.WORD]("")
    t.eq(#c.printed - before, #I.Lines(ns.id), "the lines in chat")
    t.eq(api.shows(), 1)
end

tests["intro: look only - no secure frame, no acting functions"] = function(t)
    local _, c, api = start()
    local p = panelOf(c)
    for field in pairs(p.spec) do
        local f = tostring(field):lower()
        t.ok(not (f:find("secure") or f:find("macro") or f:find("spell")), "no acting field on the panel: " .. f)
    end
    for _, tbl in ipairs({ I, api }) do
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            t.ok(not (n:find("sell") or n:find("buy") or n:find("cast") or n:find("secure") or n:find("^set$")),
                "no acting function: " .. n)
        end
    end
end

tests["intro: a panel the player cannot close is not shown at login; /zflow intro still shows it"] = function(t)
    local k, c, api, diag = start({ noClose = true })
    local p = panelOf(c)
    t.ok(p ~= nil, "the panel is made")
    t.eq(p.shown, false, "not shown at login without a close route")
    t.eq(api.shows(), 0)
    diag.commands[I.WORD]("")
    t.eq(p.shown, true, "shown when asked for")
    t.eq(k.store:get("char", I.SEEN_PATH), nil, "not marked seen")
end

tests["intro: the profession arrow is described as it looks in every mode"] = function(t)
    for _, l in ipairs(I.Lines(ns.id)) do
        t.ok(not l:lower():find("see-through", 1, true) and not l:lower():find("faint", 1, true)
            and not l:lower():find("translucent", 1, true), "no look that holds only in one mode: " .. l)
    end
    t.ok(has(I.Lines(ns.id), "a second arrow points to your next profession step"), "the profession arrow, plainly")
end

tests["intro: the addon's name and slash word come from ns.id"] = function(t)
    local id = { title = "Test-Addon", slash = "/testaddon" }
    local lines = I.Lines(id)
    t.ok(has(lines, "Test-Addon"), "the title from the identity")
    t.ok(has(lines, "/testaddon help"), "the help command from the identity")
    t.ok(has(lines, "/testaddon intro"), "the intro command from the identity")
    t.ok(not has(lines, ns.id.title) and not has(lines, ns.id.slash), "nothing written in")
end

return tests
