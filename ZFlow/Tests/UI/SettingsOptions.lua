-- The settings page with controls in the game's Options (UI/SettingsOptions.lua;
-- WoW/from-plexy/RESEARCH-settings-controls.md). Through the fake client's
-- optionsPage and a real kernel; hand-made rows only.
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
    ["settings options: opening the page draws the search, the topics, then a control for each row of the topic"] = function(t)
        local _, c, api = start()
        t.eq(api.open(), true)
        local rows = c.optionsRows()
        t.eq(rows[1].kind, "search")
        t.eq(rows[2].kind, "topics")
        t.eq(rows[3], { kind = "group", text = ns.Settings.Topics.Find("advanced").name })
        t.eq(row(c, "test.flag").kind, "toggle")
        t.eq(row(c, "test.flag").value, true)
        t.eq(row(c, "test.mode").kind, "choice")
        t.eq(row(c, "test.mode").choices, { "low", "high" })
        t.eq(row(c, "test.count").kind, "number")
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
}
