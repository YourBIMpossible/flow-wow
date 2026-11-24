-- Lead section 410: the settings as the game's own rows in its Options
-- (UI/SettingsNative.lua, UI/SettingsOptions.lua). Over the fake client's
-- optionsNative and a real kernel; hand-made rows only. Offline: nothing
-- here was seen in the game.
local _, ns = ...

local O = ns.SettingsOptions
local N = ns.SettingsNative

local LONG = "A long explanation of what the flag does, long enough that a row would have cut it."

-- opts: native = false for a client with no such rows.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setOptionsNative(opts.native ~= false)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Setting({ key = "test.flag", scope = "account", type = "bool", default = true, label = "A flag",
        help = LONG, group = "advanced", synonyms = { "banner" } })
    k:Setting({ key = "test.mode", scope = "char", type = "choice", choices = { "low", "high" }, default = "low",
        label = "A mode", group = "advanced" })
    k:Setting({ key = "test.count", scope = "account", type = "number", min = 1, max = 3, default = 2,
        label = "A count", group = "advanced" })
    k:Setting({ key = "test.free", scope = "account", type = "number", default = 7, label = "A free number",
        group = "advanced" })
    k:Setting({ key = "test.note", scope = "account", type = "string", default = "hello", label = "A note",
        group = "advanced" })
    k:Setting({ key = "test.place", scope = "account", type = "table", path = "layout.testPlace",
        label = "A place", group = "advanced" })
    k:Setting({ key = "test.other", scope = "account", type = "bool", default = false, label = "Another flag",
        group = "general" })
    ns.SettingsPanel.Declare(k, d)
    local api = O.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function topic(c, id)
    for _, tp in ipairs(c.nativeOptions().topics) do
        if tp.id == id then return tp end
    end
    return nil
end

local function button(tp, label)
    for _, r in ipairs(tp.rows) do
        if r.kind == "button" and r.label == label then return r end
    end
    return nil
end

return {
    ["settings native: each topic with a setting is an entry, named as the topic is"] = function(t)
        local _, c = start()
        local native = c.nativeOptions()
        t.ok(native ~= nil)
        t.eq(native.title, ns.id.title)
        t.eq(#native.topics, 2)
        t.eq(topic(c, "advanced").name, ns.Settings.Topics.Find("advanced").name)
        t.eq(topic(c, "general").name, ns.Settings.Topics.Find("general").name)
        t.eq(c.optionsEntry and c.optionsEntry() or nil, nil, "no second, one-button entry beside it")
    end,

    ["settings native: the short name is the label and the whole explanation is the tooltip"] = function(t)
        local _, c = start()
        local r = c.nativeRow("test.flag")
        t.eq(r.kind, "toggle")
        t.eq(r.label, "A flag")
        t.ok(r.tip:find(LONG, 1, true) ~= nil, "nothing cut")
        t.ok(r.tip:find(N.SAVED_FOR, 1, true) ~= nil, "and who it is saved for")
        t.eq(r.default, true)
        t.eq(r.tags, { "banner" })
    end,

    ["settings native: a tick, a slider and a dropdown, each with the model's own default and limits"] = function(t)
        local _, c = start()
        local count = c.nativeRow("test.count")
        t.eq({ count.kind, count.min, count.max, count.default }, { "number", 1, 3, 2 })
        local mode = c.nativeRow("test.mode")
        t.eq(mode.kind, "choice")
        t.eq(mode.choices, { { value = "low", label = "low" }, { value = "high", label = "high" } })
        t.eq(mode.default, "low")
        t.eq(c.nativeRow("test.place"), nil, "a place has no row")
    end,

    ["settings native: a change in the game's row goes through the settings model"] = function(t)
        local k, c = start()
        t.eq((c.nativeSet("test.flag", false)), true)
        t.eq(k.settings:get("test.flag"), false)
        t.eq(c.nativeRow("test.flag").get(), false)
        c.nativeSet("test.mode", "high")
        t.eq(k.settings:get("test.mode"), "high")
        c.nativeSet("test.count", 3)
        t.eq(k.settings:get("test.count"), 3)
    end,

    ["settings native: a value that does not fit changes nothing and is said in chat"] = function(t)
        local k, c = start()
        local from = #c.printed
        t.eq((c.nativeSet("test.mode", "sideways")), false)
        t.eq(k.settings:get("test.mode"), "low")
        t.ok(#c.printed > from)
        t.ok(c.printed[#c.printed]:find("A mode", 1, true) ~= nil)
    end,

    ["settings native: nothing changes in combat, and chat says so"] = function(t)
        local k, c = start()
        c.setLockdown(true)
        local ok, why = c.nativeSet("test.flag", false)
        t.eq(ok, false)
        t.eq(why, O.IN_COMBAT)
        t.eq(k.settings:get("test.flag"), true)
        t.ok(c.printed[#c.printed]:find(O.IN_COMBAT, 1, true) ~= nil)
    end,

    ["settings native: the open the minimap button and the slash word use opens the game's Options"] = function(t)
        local k, c, api = start()
        t.eq(api.open(), true)
        t.eq(c.nativeOptions().opened, { false }, "at the add-on's own entry")
        t.eq(c.optionsRows(), nil, "our own window was not drawn")
        t.eq(api.open({ topic = "advanced" }), true)
        t.eq(c.nativeOptions().opened, { false, "advanced" })
        t.eq(k.use(O.NAME).Open, api.open, "the one the panel asks for")
    end,

    ["settings native: the open is refused in combat and opens nothing"] = function(t)
        local _, c, api = start()
        c.setLockdown(true)
        local ok, why = api.open()
        t.eq(ok, false)
        t.eq(why, O.LOCKED)
        t.eq(c.nativeOptions().opened, {})
    end,

    ["settings native: a search opens our own window, which has the search"] = function(t)
        local _, c, api = start()
        t.eq(api.open({ query = "flag" }), true)
        t.eq(c.nativeOptions().opened, {})
        t.ok(c.optionsRows() ~= nil)
        t.ok(c.optionsStatus() ~= O.FALLBACK, "it is not the fallback here")
    end,

    ["settings native: the game's Options not opening falls back to our own window"] = function(t)
        local _, c, api = start()
        c.setNativeOpenFails(true)
        t.eq(api.open(), true)
        t.ok(c.optionsRows() ~= nil)
    end,

    ["settings native: text and a number without limits get a button that opens our window at the topic"] = function(t)
        local _, c = start()
        local advanced = topic(c, "advanced")
        t.eq(c.nativeRow("test.note"), nil)
        t.eq(c.nativeRow("test.free"), nil)
        local note = button(advanced, "A note")
        t.eq(note.text, N.CHANGE)
        t.ok(note.tip:find(N.IN_WINDOW, 1, true) ~= nil)
        t.ok(button(advanced, "A free number") ~= nil)
        note.run()
        t.ok(c.optionsRows() ~= nil, "our own window is up")
    end,

    ["settings native: the page's two buttons are on the add-on's own entry and run"] = function(t)
        local k, c = start()
        local actions = ns.SettingsPage.Actions(k)
        local rows = c.nativeOptions().rows
        t.eq(#rows, #actions)
        for i = 1, #actions do
            t.eq({ rows[i].kind, rows[i].label }, { "button", actions[i].label })
        end
        local from = #c.printed
        t.eq(c.nativePress(actions[1].label), true)
        t.ok(#c.printed > from, "what it did is said in chat")
    end,

    ["settings native: a client without the game's rows keeps our window, which says nothing else changed"] = function(t)
        local _, c, api = start({ native = false })
        t.eq(c.nativeOptions(), nil)
        t.eq(api.open(), true)
        t.ok(c.optionsRows() ~= nil)
        t.eq(c.optionsStatus(), O.FALLBACK)
        t.ok(O.FALLBACK:find("Nothing else changed", 1, true) ~= nil)
        t.ok(O.ENTRY_LINE:find("Nothing else changed", 1, true) ~= nil)
        t.eq((c.optionsAct("test.flag", false)), true)
        t.eq(c.optionsStatus(), O.SAVED .. "test.flag", "said once, not on every draw")
    end,
}
