-- c.optionsPage: Z-Flow's page in the game's Options > AddOns, the pattern
-- legacy Flow used on this client (Modules/Settings.lua). The real client
-- over a hand-built environment; every frame is a recording stub.
local _, ns = ...

local function gameEnv(route)
    local env = { made = {}, calls = {} }
    local function frame(kind, template)
        local f = { kind = kind, template = template, scripts = {}, shown = true, text = nil, checked = nil }
        local function note(name) env.calls[#env.calls + 1] = name end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:SetPoint() end
        function f:ClearAllPoints() end
        function f:SetSize() end
        function f:SetHeight() end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:Enable() self.enabled = true end
        function f:Disable() self.enabled = false end
        function f:SetText(s) self.text = s end
        function f:GetText() return self.text end
        function f:SetChecked(on) self.checked = on end
        function f:GetChecked() return self.checked end
        function f:SetAutoFocus() end
        function f:ClearFocus() end
        function f:SetScrollChild() end
        function f:IsVisible() return env.visible == true end
        function f:CreateFontString()
            local fs = frame("FontString")
            return fs
        end
        note("make " .. kind)
        env.made[#env.made + 1] = f
        return f
    end
    function env.CreateFrame(kind, _, _, template) return frame(kind, template) end
    if route == "settings" then
        local cat = { id = 77 }
        function cat.GetID(self) return self.id end
        env.Settings = {
            RegisterCanvasLayoutCategory = function(canvas, title) env.registered = { canvas = canvas, title = title }; return cat end,
            RegisterAddOnCategory = function(c) env.addon = c end,
            OpenToCategory = function(id) env.openedWith = id end,
        }
    elseif route == "interface" then
        env.InterfaceOptions_AddCategory = function(canvas) env.registered = { canvas = canvas } end
        env.InterfaceOptionsFrame_OpenToCategory = function() env.openCount = (env.openCount or 0) + 1 end
    end
    env.ShowUIPanel = function() env.blizzardPanel = true end
    env.HideUIPanel = function() env.blizzardPanel = true end
    return env
end

local function find(env, kind, template)
    local out = {}
    for _, f in ipairs(env.made) do
        if f.kind == kind and (template == nil or f.template == template) and f.shown then out[#out + 1] = f end
    end
    return out
end

return {
    ["optionsPage: registered through the Settings API and opened by the category's id"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        t.eq(type(h), "table")
        t.eq(env.registered.title, "Z-Flow")
        t.ok(env.addon ~= nil, "added to the add-on list")
        t.eq(h.open(), true)
        t.eq(env.openedWith, 77)
        t.eq(env.blizzardPanel, nil, "no Blizzard panel function is called")
    end,

    ["optionsPage: older clients get Interface Options, opened twice"] = function(t)
        local env = gameEnv("interface")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        t.eq(type(h), "table")
        t.eq(h.open(), true)
        t.eq(env.openCount, 2)
    end,

    ["optionsPage: no route is no page"] = function(t)
        t.eq(ns.make.client(gameEnv("none")).optionsPage({ title = "Z-Flow" }), nil)
    end,

    ["optionsPage: each row kind draws its control, and a change calls back"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        local got = {}
        local function act(key, value) got[#got + 1] = { key, value } end
        h.draw({
            { kind = "group", text = "Gear" },
            { kind = "toggle", key = "gear.tooltip", label = "Gear verdict", value = true, settable = true },
            { kind = "choice", key = "arrow.style", label = "Style", value = "modern", choices = { "modern", "flat" }, settable = true },
            { kind = "number", key = "repair.below", label = "Repair below", value = 2, min = 1, max = 3, settable = true },
            { kind = "text", key = "x.name", label = "Name", value = "a", settable = true },
            { kind = "info", key = "arrow.layout", label = "Arrows", shown = "set" },
        }, act)
        local checks = find(env, "CheckButton", "UICheckButtonTemplate")
        t.eq(#checks, 1)
        t.eq(checks[1].checked, true)
        checks[1].checked = false
        checks[1].scripts.OnClick(checks[1])
        local buttons = find(env, "Button", "UIPanelButtonTemplate")
        t.eq(#buttons, 4, "two choices, minus and plus")
        t.eq(buttons[1].text, "[modern]", "the choice in use is marked")
        buttons[2].scripts.OnClick(buttons[2])
        buttons[3].scripts.OnClick(buttons[3])
        buttons[4].scripts.OnClick(buttons[4])
        local edits = find(env, "EditBox", "InputBoxTemplate")
        t.eq(#edits, 1)
        edits[1].text = "b"
        edits[1].scripts.OnEnterPressed(edits[1])
        t.eq(got, { { "gear.tooltip", false }, { "arrow.style", "flat" }, { "repair.below", 1 },
            { "repair.below", 3 }, { "x.name", "b" } })
    end,

    ["optionsPage: a row that cannot be set is disabled; a redraw reuses the controls"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        local rows = { { kind = "toggle", key = "a", label = "A", value = false, settable = false, why = "not now" } }
        h.draw(rows, function() end)
        local before = #env.made
        t.eq(find(env, "CheckButton")[1].enabled, false)
        h.draw(rows, function() end)
        t.eq(#env.made, before, "nothing new made")
    end,

    ["optionsPage: at a limit the minus or plus button is disabled"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        h.draw({ { kind = "number", key = "n", label = "N", value = 3, min = 1, max = 3, settable = true } }, function() end)
        local buttons = find(env, "Button", "UIPanelButtonTemplate")
        t.eq({ buttons[1].enabled, buttons[2].enabled }, { true, false })
    end,

    -- Lead sections 238 and 239: topics and search on the page.
    -- Fails before: Core/Client.lua draw knows no "search", "topics",
    -- "section" or "note" row (each fell through to a plain label), takes
    -- no nav, and draws no line under a row.
    ["optionsPage: the search box, the topic buttons and a result's Open topic button tell nav, not act"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        local got, went = {}, {}
        h.draw({
            { kind = "search", label = "Search", value = "sell", clear = "Clear" },
            { kind = "topics", topics = { { id = "bags", name = "Bags", on = true }, { id = "gear", name = "Gear" } } },
            { kind = "group", text = "Found" },
            { kind = "section", text = "A section" },
            { kind = "toggle", key = "a.b", label = "A", value = true, settable = true,
              under = "Saved for account - Bags", jump = "bags", jumpText = "Open topic" },
            { kind = "note", text = "Nothing matches." },
        }, function(key, value) got[#got + 1] = { key, value } end,
            function(kind, value) went[#went + 1] = { kind, value } end)
        local edits = find(env, "EditBox", "InputBoxTemplate")
        t.eq(#edits, 1, "the search box")
        t.eq(edits[1].text, "sell", "it keeps what was searched")
        edits[1].text = "bank"
        edits[1].scripts.OnEnterPressed(edits[1])
        local buttons = find(env, "Button", "UIPanelButtonTemplate")
        t.eq(#buttons, 4)
        t.eq({ buttons[1].text, buttons[2].text, buttons[3].text, buttons[4].text },
            { "Clear", "[Bags]", "Gear", "Open topic" }, "the topic shown is marked")
        t.eq(buttons[1].enabled, true, "Clear can be pressed while a search is on")
        buttons[1].scripts.OnClick(buttons[1])
        buttons[3].scripts.OnClick(buttons[3])
        buttons[4].scripts.OnClick(buttons[4])
        t.eq(went, { { "search", "bank" }, { "search", "" }, { "topic", "gear" }, { "topic", "bags" } })
        t.eq(got, {}, "no setting was changed by any of it")
        local texts = {}
        for _, f in ipairs(find(env, "FontString")) do
            if f.text then texts[f.text] = true end
        end
        for _, text in ipairs({ "Search", "Found", "A section", "A", "Saved for account - Bags", "Nothing matches." }) do
            t.ok(texts[text], "drawn: " .. text)
        end
        -- The control of a result is the same check button, and still acts.
        local checks = find(env, "CheckButton", "UICheckButtonTemplate")
        t.eq(#checks, 1)
        checks[1].checked = false
        checks[1].scripts.OnClick(checks[1])
        t.eq(got, { { "a.b", false } })
    end,

    ["optionsPage: with no nav nothing is raised; an empty search greys Clear; a redraw reuses the controls"] = function(t)
        local env = gameEnv("settings")
        local h = ns.make.client(env).optionsPage({ title = "Z-Flow" })
        local rows = {
            { kind = "search", label = "Search", value = "", clear = "Clear" },
            { kind = "topics", topics = { { id = "bags", name = "Bags, Vendors and Bank" },
                { id = "gear", name = "Gear and Loot" }, { id = "travel", name = "Travel and Questing" },
                { id = "combat", name = "Combat and Class" }, { id = "prof", name = "Professions and Crafting" } } },
            { kind = "toggle", key = "a.b", label = "A", value = true, settable = true, under = "Saved for account" },
        }
        t.eq(h.draw(rows, function() end), true)
        local buttons = find(env, "Button", "UIPanelButtonTemplate")
        t.eq(#buttons, 6, "Clear and five topics, wrapped onto more lines")
        t.eq(buttons[1].enabled, false, "nothing to clear")
        local ok = pcall(function()
            buttons[2].scripts.OnClick(buttons[2])
            local edit = find(env, "EditBox", "InputBoxTemplate")[1]
            edit.scripts.OnEnterPressed(edit)
        end)
        t.eq(ok, true)
        local before = #env.made
        h.draw(rows, function() end)
        t.eq(#env.made, before, "nothing new made")
    end,
}
