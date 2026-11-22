-- The settings page on the shared panel (UI/SettingsPanel.lua, G52 part 2,
-- F9): the word shows and hides it, the close button and Escape close it,
-- a change typed after the word is kept and the open page shows it. Fake
-- client; not tested in game.
local _, ns = ...

local SP = ns.SettingsPanel

-- opts: saved (account data), noFrames, noClose, rows (false: none),
-- noLogin.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    if opts.noFrames then c.setFrames(false) end
    if opts.noClose then c.setCloseRoute(false) end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    if opts.rows ~= false then
        k:Setting({ key = "test.sound", scope = "account", type = "bool", default = true,
            label = "Play a sound", group = "Sounds" })
        k:Setting({ key = "test.quiet", scope = "char", type = "bool", default = false,
            label = "Stay quiet", group = "Sounds" })
    end
    local api = SP.Declare(k, diag)
    k:Boot()
    if not opts.noLogin then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c, api, diag
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Settings" then return p end
    end
    return nil
end

local function find(lines, text)
    for i, l in ipairs(lines or {}) do
        if tostring(l):find(text, 1, true) then return i, l end
    end
    return nil
end

return {
    ["settings panel: made at login on the shared panel, closable, and hidden"] = function(t)
        local k, c, api = start()
        t.eq((k:ModuleState(SP.NAME)), "started")
        local p = panelOf(c)
        t.ok(p ~= nil, "the panel is made")
        if not p then return end
        t.eq(p.spec.closable, true)
        t.eq(p.shown, false, "not shown until asked")
        t.eq(api.open(), false)
        t.eq(p.point, SP.DEFAULT_POINT)
    end,

    ["settings panel: the word shows it and the word hides it"] = function(t)
        local _, c, api, diag = start()
        local p = panelOf(c)
        t.eq(type(diag.commands[SP.WORD]), "function")
        t.eq(diag.help[SP.WORD], SP.HELP)
        diag.commands[SP.WORD]("")
        t.eq(p.shown, true)
        t.eq(api.open(), true)
        diag.commands[SP.WORD]("  ")
        t.eq(p.shown, false)
        t.eq(api.open(), false)
    end,

    ["settings panel: the page lists every row under its group, with value and key"] = function(t)
        local k, c, api = start()
        api.toggle()
        local lines = panelOf(c).lines
        t.eq(lines, SP.Lines(k))
        t.eq(lines[1], SP.TITLE)
        local g = find(lines, "Sounds")
        local a = find(lines, "Play a sound")
        local b = find(lines, "Stay quiet")
        t.ok(g and a and b and g < a and g < b, "the group stands above its rows")
        local _, line = find(lines, "Play a sound")
        t.ok(tostring(line):find("[test.sound]", 1, true) ~= nil, "the key: " .. tostring(line))
        t.ok(find(lines, ns.id.slash .. " setting <key> <value>") ~= nil, "how to change one")
    end,

    ["settings panel: the lines are plain text and never spell the old name"] = function(t)
        local k = start()
        for _, l in ipairs(SP.Lines(k)) do
            t.ok(type(l) == "string", "a line")
            t.ok(not l:find("|c", 1, true) and not l:find("|T", 1, true), "no markup: " .. l)
            t.ok(not l:find("Flow", 1, true), "no name spelled out: " .. l)
        end
        t.ok(not SP.TITLE:find("Flow", 1, true), "the title")
        t.ok(not SP.HELP:find("Flow", 1, true), "the help")
    end,

    ["settings panel: the close button or Escape closes it, and the word shows it again"] = function(t)
        local _, c, api = start()
        local p = panelOf(c)
        api.toggle()
        t.eq(type(p.close), "function")
        p.close()
        t.eq(p.shown, false)
        t.eq(api.open(), false, "it knows the player closed it")
        t.eq(api.toggle(), true, "one word shows it again")
        t.eq(p.shown, true)
    end,

    ["settings panel: a change typed after the word is kept, and the open page shows it"] = function(t)
        local k, c, api, diag = start()
        local p = panelOf(c)
        api.toggle()
        local _, before = find(p.lines, "Play a sound")
        diag.commands[SP.WORD]("test.sound off")
        t.eq(k.settings:get("test.sound"), false)
        t.eq(c.saved(ns.id.accountDB).settings.test.sound, false, "in the saved data: kept across a reload")
        local _, after = find(p.lines, "Play a sound")
        t.ok(before ~= after, "the page changed: " .. tostring(after))
        t.eq(p.shown, true, "still open")
    end,

    ["settings panel: a saved change is there after a reload"] = function(t)
        local _, _, _, diag = start()
        diag.commands[SP.WORD]("test.sound off")
        local k2, c2, api2 = start({ saved = { settings = { test = { sound = false } } } })
        t.eq(k2.settings:get("test.sound"), false)
        api2.toggle()
        local _, line = find(panelOf(c2).lines, "Play a sound")
        local k3, c3, api3 = start()
        api3.toggle()
        local _, fresh = find(panelOf(c3).lines, "Play a sound")
        t.ok(k3 ~= nil and line ~= fresh, "the page shows the saved value: " .. tostring(line))
    end,

    ["settings panel: an open page follows a change made another way"] = function(t)
        local k, c, api = start()
        local p = panelOf(c)
        api.toggle()
        local _, before = find(p.lines, "Stay quiet")
        k.settings:set("test.quiet", true)
        local _, after = find(p.lines, "Stay quiet")
        t.ok(before ~= after, "drawn again: " .. tostring(after))
    end,

    ["settings panel: a closed page is not drawn again by a change"] = function(t)
        local k, c = start()
        local p = panelOf(c)
        local was = p.lines
        k.settings:set("test.quiet", true)
        t.eq(p.lines, was)
        t.eq(p.shown, false)
    end,

    ["settings panel: a client with no frames gets the lines in the chat window"] = function(t)
        local _, c, api = start({ noFrames = true })
        t.eq(panelOf(c), nil)
        local n = #c.printed
        api.toggle()
        t.eq(api.open(), false, "nothing is open")
        t.ok(#c.printed > n, "lines were printed")
        t.ok(find(c.printed, "Play a sound") ~= nil, "the rows")
        t.ok(find(c.printed, SP.TITLE) ~= nil, "the title")
    end,

    ["settings panel: a panel that cannot be closed is still shown and hidden by the word"] = function(t)
        local _, c, api = start({ noClose = true })
        local p = panelOf(c)
        t.ok(p ~= nil, "the panel is made")
        if not p then return end
        t.eq(api.toggle(), true)
        t.eq(p.shown, true)
        t.eq(api.toggle(), false)
        t.eq(p.shown, false)
    end,

    ["settings panel: before login the word says it is not ready"] = function(t)
        local _, c, api, diag = start({ noLogin = true })
        local n = #c.printed
        diag.commands[SP.WORD]("")
        t.eq(api.open(), false)
        t.eq(#c.panels, 0, "nothing is made")
        t.ok(find({ c.printed[n + 1] }, SP.NOT_READY) ~= nil, "said: " .. tostring(c.printed[n + 1]))
    end,

    ["settings panel: with no rows the page says so"] = function(t)
        local k, c, api = start({ rows = false })
        t.eq(SP.Lines(k), { SP.TITLE, SP.NONE })
        api.toggle()
        t.eq(panelOf(c).lines, { SP.TITLE, SP.NONE })
    end,

    ["settings panel: switched off, it is hidden and stops following changes"] = function(t)
        local k, c, api = start()
        local p = panelOf(c)
        api.toggle()
        k:SwitchOff(SP.NAME, "switched off by the test")
        t.eq(p.shown, false)
        t.eq(api.open(), false)
        local was = p.lines
        k.settings:set("test.quiet", true)
        t.eq(p.lines, was)
    end,

    ["settings panel: the height follows the number of lines"] = function(t)
        t.ok(SP.Height(0) >= SP.MIN_HEIGHT, "never under the least height")
        t.ok(SP.Height(30) > SP.Height(10), "more lines, taller")
        t.eq(SP.Height(nil), SP.Height(0))
    end,

    ["settings panel: the addon's own is declared"] = function(t)
        t.eq(type(ns.settingsPanel), "table")
        t.eq(type(ns.settingsPanel.toggle), "function")
    end,
}
