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
}
