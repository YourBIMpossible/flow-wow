-- The settings with controls, in the add-on's own window
-- (UI/SettingsOptions.lua; lead section 285 item 3). Through the fake
-- client's settingsWindow and a real kernel; hand-made rows only.
local _, ns = ...

local O = ns.SettingsOptions

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if opts.noPage then c.setOptionsPage(false) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Setting({ key = "test.flag", scope = "account", type = "bool", default = true, label = "A flag", group = "advanced" })
    k:Setting({ key = "test.mode", scope = "char", type = "choice", choices = { "low", "high" }, default = "low",
        label = "A mode", group = "advanced" })
    k:Setting({ key = "test.count", scope = "account", type = "number", min = 1, max = 3, default = 2,
        label = "A count", group = "advanced" })
    k:Setting({ key = "test.place", scope = "account", type = "table", path = "layout.testPlace",
        label = "A place", group = "advanced" })
    ns.SettingsPanel.Declare(k, d)
    local api = O.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function row(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

return {
    -- Changed for the window (lead section 285 item 3): the search and the
    -- topics stand beside the rows (the layout), not in them, so the
    -- topic's name is the first row. It asserted rows[1].kind "search",
    -- rows[2].kind "topics" and the name at rows[3].
    ["settings options: opening the page draws the search, the topics, then a control for each row of the topic"] = function(t)
        local _, c, api = start()
        t.eq(api.open(), true)
        local rows = c.optionsRows()
        t.eq(c.optionsLayout().search.value, "", "the search stands beside the rows")
        t.eq(#c.optionsLayout().topics, 1, "and so do the topics")
        t.eq(rows[1], { kind = "group", text = ns.Settings.Topics.Find("advanced").name })
        t.eq(row(c, "test.flag").kind, "toggle")
        t.eq(row(c, "test.flag").value, true)
        t.eq(row(c, "test.mode").kind, "choice")
        t.eq(row(c, "test.mode").choices, { "low", "high" })
        t.eq(row(c, "test.count").kind, "slider", "a number with both limits is a slider (row N57)")
        t.eq({ row(c, "test.count").min, row(c, "test.count").max }, { 1, 3 })
        t.eq(row(c, "test.place").kind, "info", "a place is shown, not changed")
        t.eq(row(c, "test.place").settable, false)
    end,

    ["settings options: a tick, a choice and a number change and are saved"] = function(t)
        local k, c, api = start()
        api.open()
        t.eq((c.optionsAct("test.flag", false)), true)
        t.eq(k.settings:get("test.flag"), false)
        t.eq(row(c, "test.flag").value, false, "redrawn")
        t.eq(c.optionsStatus(), O.SAVED .. "test.flag")
        c.optionsAct("test.mode", "high")
        t.eq(k.settings:get("test.mode"), "high")
        c.optionsAct("test.count", 3)
        t.eq(k.settings:get("test.count"), 3)
    end,

    ["settings options: a value that does not fit is refused, changes nothing and says why"] = function(t)
        local k, c, api = start()
        api.open()
        local ok = c.optionsAct("test.count", 9)
        t.eq(ok, false)
        t.eq(k.settings:get("test.count"), 2)
        t.ok(type(c.optionsStatus()) == "string" and c.optionsStatus():find("test.count", 1, true) ~= nil)
        t.eq(c.optionsAct("test.mode", "middle"), false)
        t.eq(k.settings:get("test.mode"), "low")
    end,

    ["settings options: no change during combat lockdown"] = function(t)
        local k, c, api = start()
        api.open()
        c.combatLockdown = function() return true end
        t.eq(c.optionsAct("test.flag", false), false)
        t.eq(k.settings:get("test.flag"), true)
        t.eq(c.optionsStatus(), O.IN_COMBAT)
    end,

    ["settings options: a change made elsewhere shows on the open page"] = function(t)
        local k, c, api = start()
        api.open()
        t.eq(k.settings:set("test.flag", false), true)
        t.eq(row(c, "test.flag").value, false)
    end,

    ["settings options: /zflow settings opens the Options page when there is one"] = function(t)
        local _, c = start()
        c.slashes[ns.id.slash]("settings")
        t.eq(c.optionsOpened(), 1)
    end,

    ["settings options: with no Options page, /zflow settings keeps the text page"] = function(t)
        local k, c, api = start({ noPage = true })
        t.eq(api.open(), false)
        c.slashes[ns.id.slash]("settings")
        t.eq(c.optionsOpened(), 0)
        t.eq(k.use(ns.SettingsPanel.NAME).Open(), true, "the text page is open instead")
    end,

    ["settings options: every row keeps its key; no new row is made"] = function(t)
        local k, c, api = start()
        api.open()
        local keys = {}
        for r in k.settings:each() do keys[r.key] = true end
        for _, r in ipairs(c.optionsRows()) do
            if r.key ~= nil then t.ok(keys[r.key], tostring(r.key)) end
        end
    end,

    -- Lead section 247 item 5 (MyBuddy, MED). Fails before: api.open asked
    -- the client's page to open with no lockdown check
    -- (UI/SettingsOptions.lua api.open).
    ["settings options: in combat lockdown, or with the lock not known, the page is not asked to open and open says why"] = function(t)
        local _, c, api = start()
        c.setLockdown(true)
        local ok, why = api.open()
        t.eq(ok, false)
        t.eq(why, O.LOCKED)
        t.ok(type(O.LOCKED) == "string" and O.LOCKED ~= "", "there is a line for it")
        t.eq(c.optionsOpened(), 0)
        c.setLockdown(nil)
        ok, why = api.open()
        t.eq(ok, false)
        t.eq(why, O.LOCK_UNKNOWN)
        t.ok(type(O.LOCK_UNKNOWN) == "string" and O.LOCK_UNKNOWN ~= O.LOCKED, "not known has its own line")
        t.eq(c.optionsOpened(), 0, "not known counts as locked")
        c.setLockdown(false)
        t.eq((api.open()), true)
        t.eq(c.optionsOpened(), 1, "after the fight it opens")
    end,

    ["settings options: a client with no Options page says nothing of combat"] = function(t)
        local _, c, api = start({ noPage = true })
        c.setLockdown(true)
        local ok, why = api.open()
        t.eq(ok, false)
        t.eq(why, nil)
    end,

    -- Carry-forward of the legacy slider (lead section 247 item 5). Fails
    -- before: a number row was drawn with no step, so the client stepped by
    -- 1 and a 0 to 1 row could not be moved at all.
    ["settings options: a number row carries its step; a 0 to 1 row moves in twentieths and saves a clean value"] = function(t)
        local k, c, api = start()
        k:Setting({ key = "test.share", scope = "account", type = "number", min = 0, max = 1, default = 0.2,
            label = "A share", group = "advanced" })
        k:Setting({ key = "test.half", scope = "account", type = "number", min = 0, max = 3, default = 1, step = 0.5,
            label = "By halves", group = "advanced" })
        api.open()
        t.eq(row(c, "test.count").step, 1, "a whole-number row steps by one")
        t.eq(row(c, "test.share").step, 0.05)
        t.eq(row(c, "test.half").step, 0.5, "a row's own step is used")
        t.eq((c.optionsAct("test.share", 0.2 + 0.05)), true)
        t.eq(k.settings:get("test.share"), 0.25)
        t.eq((c.optionsAct("test.share", 0.25 + 0.05)), true)
        t.eq(k.settings:get("test.share"), 0.3, "no stray digits from the adding")
        t.eq(c.optionsAct("test.share", 1.05), false, "its limits still hold")
        t.eq(k.settings:get("test.share"), 0.3)
        t.eq((c.optionsAct("test.count", 3)), true)
        t.eq(k.settings:get("test.count"), 3)
    end,

    -- SETTINGS-UX-01 item 4: help understandable. Fails before: the row the
    -- page draws carried no help.
    ["settings options: a row's description is drawn with it"] = function(t)
        local k, c, api = start()
        k:Setting({ key = "test.helped", scope = "account", type = "bool", default = true, label = "Helped",
            help = "What it does, in a sentence.", group = "advanced" })
        api.open()
        t.eq(row(c, "test.helped").help, "What it does, in a sentence.")
        t.eq(row(c, "test.flag").help, nil, "none is made up")
    end,

    -- Row N57 (lead section 249 item 2). Fails before: a number row was
    -- always kind "number", and the fake has no optionsDrag.
    ["settings options: a number with both limits is a slider; dragging it saves through the same checked set"] = function(t)
        local k, c, api = start()
        k:Setting({ key = "test.free", scope = "account", type = "number", default = 4, label = "No limits", group = "advanced" })
        k:Setting({ key = "test.share", scope = "account", type = "number", min = 0, max = 1, default = 0.2,
            label = "A share", group = "advanced" })
        api.open()
        t.eq(row(c, "test.count").kind, "slider")
        t.eq({ row(c, "test.count").min, row(c, "test.count").max, row(c, "test.count").step }, { 1, 3, 1 })
        t.eq(row(c, "test.free").kind, "number", "no limits: the stepper")
        t.ok(type(c.optionsDrag) == "function", "the fake page can be dragged")
        if type(c.optionsDrag) ~= "function" then return end
        t.eq(c.optionsDrag("test.count", 3), true)
        t.eq(k.settings:get("test.count"), 3)
        t.eq(row(c, "test.count").value, 3, "redrawn")
        t.eq(c.optionsStatus(), O.SAVED .. "test.count")
        t.eq(c.optionsDrag("test.share", 0.52), true)
        t.eq(k.settings:get("test.share"), 0.5, "on the row's step")
        t.eq(c.optionsDrag("test.share", 9), true)
        t.eq(k.settings:get("test.share"), 1, "a slider cannot go past its limit")
        t.eq(c.optionsDrag("test.free", 2), false, "not a slider")
        t.eq(c.optionsDrag("test.flag", 1), false)
        c.combatLockdown = function() return true end
        c.optionsDrag("test.count", 1)
        t.eq(k.settings:get("test.count"), 3, "no change in combat, as for every control")
        t.eq(c.optionsStatus(), O.IN_COMBAT)
    end,

    -- Fails before: the fake has no setSliders, and the page gave no slider.
    ["settings options: on a client with no slider the same row is the stepper and still changes"] = function(t)
        local k, c, api = start()
        t.ok(type(c.setSliders) == "function", "the fake can play a client with no slider")
        if type(c.setSliders) ~= "function" then return end
        c.setSliders(false)
        api.open()
        t.eq(row(c, "test.count").kind, "number")
        t.eq(c.optionsDrag("test.count", 3), false, "nothing to drag")
        t.eq((c.optionsAct("test.count", 3)), true, "plus still works")
        t.eq(k.settings:get("test.count"), 3)
    end,

    -- The legacy page's two buttons (Modules/Settings.lua :884, :900).
    -- Fails before: SettingsPage has no Actions / Act and the page no
    -- "actions" row.
    ["settings options: Use the suggestions sets each suggested value through the checked set; Keep my settings changes none"] = function(t)
        local k, c, api = start()
        local P = ns.SettingsPage
        t.ok(type(P.Actions) == "function" and type(P.Act) == "function", "the page has its actions")
        if type(P.Act) ~= "function" then return end
        k:Setting({ key = "test.home", scope = "account", type = "bool", default = true, label = "A general row",
            group = "general" })
        api.open()
        t.eq(c.optionsNav("topic", "general"), true)
        local actions
        for _, r in ipairs(c.optionsRows()) do
            if r.kind == "actions" then actions = r.actions end
        end
        t.ok(type(actions) == "table" and #actions == 2, "two buttons under the General topic")
        if type(actions) ~= "table" then return end
        t.eq({ actions[1].key, actions[2].key }, { "suggest", "keep" })
        t.eq(actions[1].label, "Use " .. ns.id.title .. "'s suggestions")
        t.eq(actions[2].label, "Keep my settings")
        c.optionsNav("topic", "advanced")
        for _, r in ipairs(c.optionsRows()) do t.ok(r.kind ~= "actions", "only under General") end

        local shipped = ns.Setup.SUGGESTIONS
        local ok, err = pcall(function()
            -- None shipped: it says so and changes nothing.
            ns.Setup.SUGGESTIONS = {}
            t.eq(c.optionsNav("action", "suggest"), true)
            t.eq(c.optionsStatus(), P.NO_SUGGESTIONS)
            t.eq(k.store:get("char", ns.Setup.OFFERED_PATH), nil, "nothing to finish yet")
            -- Some: each goes through the checked set.
            ns.Setup.SUGGESTIONS = {
                { key = "test.flag", value = false, why = "Quieter." },
                { key = "test.count", value = 3, why = "More." },
                { key = "test.count", value = 9, why = "Too many: outside its limits." },
                { key = "test.mode", value = "low", why = "Already so." },
                { key = "test.nosuch", value = true, why = "No such row." },
            }
            t.eq(c.optionsNav("action", "suggest"), true)
            t.eq({ k.settings:get("test.flag"), k.settings:get("test.count"), k.settings:get("test.mode") },
                { false, 3, "low" })
            t.ok(c.optionsStatus():find("2 ", 1, true) == 1, "it says how many changed: " .. tostring(c.optionsStatus()))
            t.ok(c.optionsStatus():find("1 ", 1, true) ~= nil, "and that one was refused: " .. tostring(c.optionsStatus()))
            t.eq(k.store:get("char", ns.Setup.OFFERED_PATH), true, "the suggestions are done with for this character")
            t.eq(c.saved(ns.id.accountDB).settings.test.count, 3, "saved where it always was")
            -- Again: nothing left to change.
            ns.Setup.SUGGESTIONS = { { key = "test.flag", value = false, why = "Quieter." } }
            c.optionsNav("action", "suggest")
            t.eq(c.optionsStatus(), P.ALREADY)
        end)
        ns.Setup.SUGGESTIONS = shipped
        t.ok(ok, tostring(err))

        -- Keep my settings: no value moves; the suggestions are done with.
        local k2, c2, api2 = start()
        api2.open()
        local before = { k2.settings:get("test.flag"), k2.settings:get("test.count"), k2.settings:get("test.mode") }
        t.eq(c2.optionsNav("action", "keep"), true)
        t.eq(c2.optionsStatus(), P.KEPT)
        t.eq({ k2.settings:get("test.flag"), k2.settings:get("test.count"), k2.settings:get("test.mode") }, before)
        t.eq(k2.store:get("char", ns.Setup.OFFERED_PATH), true)
        t.eq(c2.optionsNav("action", "nosuch"), false)
        -- In combat a press is refused, as a change is.
        local k3, c3, api3 = start()
        api3.open()
        c3.combatLockdown = function() return true end
        t.eq(c3.optionsNav("action", "keep"), false)
        t.eq(c3.optionsStatus(), O.IN_COMBAT)
        t.eq(k3.store:get("char", ns.Setup.OFFERED_PATH), nil)
    end,
}
