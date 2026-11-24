local _, ns = ...
-- The settings window follows the game's own Settings window (owner,
-- 2026-11-23: "The settings look alright, but they look dated. I'd rather
-- match the current WoW Settings window."). Topics at the left, rows that
-- scroll at the right, the search at the top, and now: a choice is one box
-- that opens its list (a dropdown), a number with two limits is a slider
-- with its value beside it, and Close stands at the foot.
-- Two halves. The whole add-on on a fake client, through the player's two
-- entries (the minimap button's menu and the slash word): open, scroll,
-- switch one setting, search one word, Close. And the real client's kit
-- over a hand-built game environment drawing the dropdown and the slider,
-- with and without the game's slider. Look only: every setting and its key
-- are as before. No game client is involved. Not tested in game.
local tests = {}

local K = ns.Kit
local W = ns.SettingsWindow

local TEMPLATES = { "ButtonFrameTemplate", "UIPanelCloseButton", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate", "UIPanelScrollFrameTemplate",
    "PanelTabButtonTemplate" }

-- As ClientKitMouseTests' gameEnv, plus the strata and, when sliders is
-- "template" or "plain", a Slider's own calls ("template": the stock slider
-- template exists too). With sliders nil a Slider frame has none of them.
local function gameEnv(sliders)
    local env = { made = {}, UIParent = { level = 0 }, UISpecialFrames = {} }
    local has = {}
    for _, name in ipairs(TEMPLATES) do has[name] = true end
    if sliders == "template" then has.OptionsSliderTemplate = true end
    local function region(kind, parent, template, name)
        local r = { kind = kind, parent = parent, template = template, name = name, scripts = {}, shown = true,
            vscroll = 0 }
        r.level = ((type(parent) == "table" and parent.level) or 0) + 1
        function r:SetScript(script, fn) self.scripts[script] = fn end
        function r:GetScript(script) return self.scripts[script] end
        function r:Show() self.shown = true end
        function r:Hide()
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function r:IsShown() return self.shown end
        function r:SetText(s) self.text = s end
        function r:GetText() return self.text end
        function r:SetTextColor(...) self.textColor = { ... } end
        function r:SetChecked(on) self.checked = on end
        function r:GetChecked() return self.checked end
        function r:Enable() self.enabled = true end
        function r:Disable() self.enabled = false end
        function r:SetTexture(v) self.texture = v return true end
        function r:GetTexture() return self.texture end
        function r:SetColorTexture(...) self.color = { ... } end
        function r:SetSize(w, h) self.width, self.height = w, h end
        function r:SetWidth(w) self.width = w end
        function r:SetHeight(h) self.height = h end
        function r:GetWidth() return self.width end
        function r:GetHeight() return self.height end
        function r:SetPoint() end
        function r:ClearAllPoints() end
        function r:GetPoint() return "TOPLEFT", env.UIParent, "TOPLEFT", 30, -40 end
        function r:CreateTexture() return region("Texture", self) end
        function r:CreateFontString(_, _, font)
            local fs = region("FontString", self)
            fs.font = font
            return fs
        end
        function r:EnableMouse(on) self.mouse = on and true or false end
        function r:IsMouseEnabled() return self.mouse == true end
        function r:EnableMouseWheel(on) self.wheel = on and true or false end
        function r:SetFrameLevel(n) self.level = n end
        function r:GetFrameLevel() return self.level end
        function r:SetFrameStrata(s) self.strata = s end
        function r:GetName() return self.name end
        function r:GetObjectType() return self.kind end
        function r:GetParent() return self.parent end
        function r:SetScrollChild(child)
            self.child = child
            self.vscroll = 0
        end
        function r:GetVerticalScroll() return self.vscroll end
        function r:SetVerticalScroll(v) self.vscroll = v end
        function r:GetVerticalScrollRange()
            local ch = (self.child and self.child.height) or 0
            local mine = self.height or 0
            if ch - mine < 0 then return 0 end
            return ch - mine
        end
        if kind == "Slider" and sliders ~= nil then
            function r:SetOrientation(o) self.orientation = o end
            function r:SetThumbTexture(v) self.thumb = region("Texture", self) self.thumb.texture = v end
            function r:GetThumbTexture() return self.thumb end
            function r:SetMinMaxValues(a, b) self.min, self.max = a, b end
            function r:SetValueStep(s) self.step = s end
            function r:SetValue(v)
                self.value = v
                if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
            end
            function r:GetValue() return self.value end
        end
        env.made[#env.made + 1] = r
        return r
    end
    function env.CreateFrame(kind, name, parent, template)
        if template ~= nil and not has[template] then error("no template " .. tostring(template)) end
        local f = region(kind, parent, template, name)
        if name ~= nil and env[name] == nil then env[name] = f end
        return f
    end
    function env.InCombatLockdown() return false end
    function env.GetMouseFocus() return env.focus end
    return env
end

local function shown(env, kind)
    local out = {}
    for _, r in ipairs(env.made) do
        if r.kind == kind and r.shown then out[#out + 1] = r end
    end
    return out
end

-- Shown, and so is everything it stands on (as the game draws it).
local function visible(r)
    local n = 0
    while type(r) == "table" and r.kind ~= nil and n < 20 do
        if not r.shown then return false end
        r, n = r.parent, n + 1
    end
    return true
end

-- The visible region of that kind saying that text, itself or on a font
-- string of its own.
local function saying(env, kind, text)
    for _, r in ipairs(env.made) do
        if r.kind == kind and visible(r) then
            if r.text == text then return r end
            for _, fs in ipairs(env.made) do
                if fs.kind == "FontString" and fs.parent == r and fs.shown and fs.text == text then return r end
            end
        end
    end
    return nil
end

-- The loaded add-on, its settings window not yet asked for, and the tree
-- it last asked the client to draw: -> c, addon, tree().
local function boot()
    local c = ns.make.fakeClient()
    c.setScreen(1024, 768)
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setLockdown(false)
    if type(c.setBindings) == "function" then c.setBindings({}) end
    local last
    local kit = c.kitWindow
    function c.kitWindow(id, tree, extra)
        local h = kit(id, tree, extra)
        if id ~= W.ID or type(h) ~= "table" then return h end
        last = tree
        local update = h.update
        function h.update(now)
            local ok = update(now)
            if ok then last = now end
            return ok
        end
        return h
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, function() return last end
end

local function window(c) return (c.kitWindows() or {})[W.ID] end

local function parts(tree, kind)
    local out = {}
    K.Each(tree, function(p) if p.kind == kind then out[#out + 1] = p end end)
    return out
end

-- Shows each topic in turn until pick(tree) answers something: -> that.
local function topicWhere(c, tree, pick)
    for i = 1, #ns.Settings.Topics.LIST do
        local topics = parts(tree(), "topicList")[1]
        if topics == nil then return nil end
        topics.onSelect(i)
        c.advance(1, 4)
        local got = pick(tree())
        if got ~= nil then return got end
    end
    return nil
end

local function switches(tree)
    local rows = {}
    K.Each(tree, function(p)
        if p.kind == "row" and p.enabled and type(p.control) == "table" and p.control.kind == "checkbox" then
            rows[#rows + 1] = p
        end
    end)
    return rows
end

-- The real client's kit drawing that tree: -> env, handle.
local function draw(tree, sliders)
    local env = gameEnv(sliders)
    local real = ns.make.client(env)
    local h = real.kitWindow("E2ELook", tree, { name = "E2ELookFrame" })
    if type(h) == "table" then h.show(true) end
    return env, h
end

-- A made-up window of one choice row and one number row.
local function controlsTree(got, drop, low, high)
    return K.Window({ id = "KitLook", title = "Settings", width = 760, height = 520, children = {
        { kind = "header", title = "1 topic", search = { onText = function() end, text = "" } },
        { kind = "topicList", items = { "General" }, selected = 1, onSelect = function() end },
        { kind = "scroll", children = {
            { kind = "row", label = "A mode", description = "One of three.",
                control = { kind = "choice", items = { "Low", "Middle", "High" }, selected = 2, drop = drop,
                    onSelect = function(i) got[#got + 1] = "mode " .. i end } },
            { kind = "row", label = "A count", description = "From low to high.",
                control = { kind = "number", value = 4, min = low, max = high, step = 2,
                    onChange = function(v) got[#got + 1] = "count " .. v end } },
        } },
        { kind = "footer", buttons = { { kind = "button", text = "Close", onClick = function() got[#got + 1] = "close" end } } },
    } })
end

tests["settings look: the minimap menu opens the window; Close at its foot closes it; the slash word opens it again"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    local b = type(c.minimapButtons) == "table" and c.minimapButtons[1] or nil
    t.ok(b ~= nil, "the minimap button")
    if b == nil then return end
    b.click("right")
    b.choose("settings")
    c.advance(1, 4)
    local w = window(c)
    t.ok(w ~= nil and w.shown == true, "the menu's settings row shows the window")
    if w == nil then return end
    t.eq({ w.parts[1].kind, w.parts[2].kind, w.parts[3].kind }, { "header", "topicList", "scroll" },
        "the search at the top, the topics at the left, the rows that scroll")
    local foot, close = 0, nil
    for _, p in ipairs(w.parts) do
        if p.kind == "footer" then foot = foot + 1 end
        if p.kind == "button" and p.text == W.CLOSE_TEXT then close = p end
    end
    t.eq(foot, 1, "one foot")
    t.ok(close ~= nil, "with Close on it")
    t.eq(c.kitClick(W.ID, W.CLOSE), true, "Close takes a click")
    c.advance(1, 4)
    t.eq(window(c).shown, false, "and the window is closed")
    c.slashes[ns.id.slash]("settings")
    c.advance(1, 4)
    t.eq(window(c).shown, true, "the slash word opens it again")
    t.eq(addon.problems:count(), before)
end

tests["settings look: opened by the slash word - the rows scroll, a switch is switched, a word is searched"] = function(t)
    local c, addon, tree = boot()
    local before = addon.problems:count()
    c.slashes[ns.id.slash]("settings")
    c.advance(1, 4)
    t.ok(type(tree()) == "table" and window(c) ~= nil and window(c).shown, "the slash word shows the window")
    if type(tree()) ~= "table" then return end
    -- Scroll: the game's kit draws the add-on's rows; the wheel moves them.
    local many = topicWhere(c, tree, function(now)
        local rows = switches(now)
        if #rows >= 12 then return rows end
        return nil
    end)
    t.ok(many ~= nil, "a topic of twelve switches or more")
    local env, h = draw(tree())
    t.ok(type(h) == "table", "the real kit draws the add-on's tree")
    if type(h) ~= "table" then return end
    local list = shown(env, "ScrollFrame")[2]
    t.ok(list ~= nil and type(list.scripts.OnMouseWheel) == "function", "the rows take the wheel")
    if list == nil or type(list.scripts.OnMouseWheel) ~= "function" then return end
    list.scripts.OnMouseWheel(list, -1)
    t.ok(list.vscroll > 0, "one notch down moves the rows")
    t.ok(saying(env, "Button", W.CLOSE_TEXT) ~= nil, "Close is drawn at the foot")
    -- Switch one setting.
    local row = many and many[1]
    if row == nil then return end
    local key, was = row.control.key, row.control.checked
    t.eq(addon.settings:get(key), was, "the box shows what is set")
    t.eq(c.kitClick(W.ID, key), true, "the box takes a click")
    t.eq(addon.settings:get(key), not was, key .. " is switched")
    t.eq(c.kitClick(W.ID, key), true)
    t.eq(addon.settings:get(key), was, "and back")
    -- Search one word: the first word of that row's label.
    local word = tostring(row.label):match("%a+")
    t.ok(type(word) == "string" and #word > 0, "a word to search")
    t.eq(c.kitType(W.ID, W.HEADER, word), true, "the search box takes the word")
    c.advance(1, 4)
    local found = false
    for _, p in ipairs(parts(tree(), "row")) do
        if p.label == row.label then found = true end
    end
    t.ok(found, "the row with that word is among what is found")
    t.eq(addon.problems:count(), before)
end

tests["settings look: every setting keeps its key; every choice is a dropdown"] = function(t)
    local c, addon, tree = boot()
    c.slashes[ns.id.slash]("settings")
    c.advance(1, 4)
    if type(tree()) ~= "table" then t.ok(false, "a drawn window") return end
    local keys, choices = 0, 0
    topicWhere(c, tree, function(now)
        for _, row in ipairs(parts(now, "row")) do
            local ctl = row.control
            if type(ctl) == "table" and (ctl.kind == "checkbox" or ctl.kind == "choice" or ctl.kind == "number") then
                keys = keys + 1
                local ok = pcall(function() return addon.settings:get(ctl.key) end)
                t.ok(ok, "the control's key is a setting: " .. tostring(ctl.key))
                if ctl.kind == "choice" then
                    choices = choices + 1
                    t.eq(ctl.drop, true, tostring(ctl.key) .. " is a dropdown")
                end
            end
        end
        return nil
    end)
    t.ok(keys > 0, "the window has settings to set")
end

tests["settings look: a dropdown shows the item in use; a press opens its list; a press on an item picks it"] = function(t)
    local got = {}
    local env, h = draw(controlsTree(got, true, 0, 10), "template")
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    local box = saying(env, "Button", "Middle")
    t.ok(box ~= nil and type(box.scripts.OnClick) == "function", "one box showing the item in use")
    if box == nil then return end
    t.ok(saying(env, "Button", "Low") == nil, "the list is shut at first")
    box.scripts.OnClick(box, "LeftButton")
    local low, high = saying(env, "Button", "Low"), saying(env, "Button", "High")
    t.ok(low ~= nil and high ~= nil, "a press opens the list of items")
    if low == nil or high == nil then return end
    t.eq(low.parent.strata, "DIALOG", "the list stands above the rows")
    box.scripts.OnClick(box, "LeftButton")
    t.eq(low.parent.shown, false, "a second press shuts it")
    box.scripts.OnClick(box, "LeftButton")
    high.scripts.OnClick(high, "LeftButton")
    t.eq(got, { "mode 3" }, "a press on an item tells the part")
    t.eq(high.parent.shown, false, "and shuts the list")
    box.scripts.OnClick(box, "LeftButton")
    local middle
    for _, r in ipairs(env.made) do
        if r.kind == "Button" and r.parent == low.parent then
            for _, fs in ipairs(env.made) do
                if fs.parent == r and fs.text == "Middle" then middle = r end
            end
        end
    end
    t.ok(middle ~= nil, "the item in use is on the list")
    if middle ~= nil then middle.scripts.OnClick(middle, "LeftButton") end
    t.eq(got, { "mode 3" }, "a press on the item in use changes nothing")
    box.scripts.OnClick(box, "LeftButton")
    t.eq(low.parent.shown, true)
    local list = shown(env, "ScrollFrame")[2]
    if list ~= nil and type(list.scripts.OnMouseWheel) == "function" then
        list.scripts.OnMouseWheel(list, -1)
        t.eq(low.parent.shown, false, "a turn of the wheel shuts the list")
    end
    box.scripts.OnClick(box, "LeftButton")
    h.show(false)
    t.eq(low.parent.shown, false, "hiding the window shuts the list")
end

tests["settings look: a choice without drop is still a row of buttons"] = function(t)
    local got = {}
    local env, h = draw(controlsTree(got, nil, 0, 10), "template")
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    t.ok(saying(env, "Button", "Low") ~= nil and saying(env, "Button", "High") ~= nil, "every item is a button")
end

for _, how in ipairs({ "template", "plain" }) do
    local name = how == "template" and "the game's slider template" or "a plain slider when the template is missing"
    tests["settings look: a number with two limits is a slider - " .. name] = function(t)
        local got = {}
        local env, h = draw(controlsTree(got, true, 0, 10), how)
        if type(h) ~= "table" then t.ok(false, "a handle") return end
        local s = shown(env, "Slider")[1]
        t.ok(s ~= nil, "a slider is drawn")
        if s == nil then return end
        t.eq(s.template, how == "template" and "OptionsSliderTemplate" or nil)
        t.eq({ s.min, s.max, s.step, s.value }, { 0, 10, 2, 4 }, "its limits, step and value")
        t.ok(saying(env, "FontString", "4") ~= nil or saying(env, "Frame", "4") ~= nil, "the value stands beside it")
        t.eq(saying(env, "Button", "+"), nil, "no stepper")
        s:SetValue(7.2)
        t.eq(got, {}, "dragging tells nothing yet")
        local value
        for _, r in ipairs(env.made) do
            if r.kind == "FontString" and r.shown and r.text == "8" then value = r end
        end
        t.ok(value ~= nil, "the value shown follows the drag, on a step")
        t.ok(type(s.scripts.OnMouseUp) == "function", "letting go is heard")
        if type(s.scripts.OnMouseUp) ~= "function" then return end
        s.scripts.OnMouseUp(s, "LeftButton")
        t.eq(got, { "count 8" }, "letting go tells the part once, the stepped value")
        s:SetValue(99)
        s.scripts.OnMouseUp(s, "LeftButton")
        t.eq(got[#got], "count 10", "never past the limit")
    end
end

tests["settings look: no slider on this client - the number keeps its stepper"] = function(t)
    local got = {}
    local env, h = draw(controlsTree(got, true, 0, 10), nil)
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    t.eq(#shown(env, "Slider"), 0, "no slider is left showing")
    t.ok(saying(env, "Button", "+") ~= nil and saying(env, "Button", "-") ~= nil, "the stepper is drawn")
end

tests["settings look: a number without both limits keeps its stepper"] = function(t)
    local got = {}
    local env, h = draw(controlsTree(got, true, 0, nil), "template")
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    t.eq(#shown(env, "Slider"), 0, "no slider")
    t.ok(saying(env, "Button", "+") ~= nil, "the stepper is drawn")
end

return tests
