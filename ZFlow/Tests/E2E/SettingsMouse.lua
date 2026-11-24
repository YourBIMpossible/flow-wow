local _, ns = ...
-- The settings window takes the mouse, end to end (owner, 2026-11-23: "I
-- can't scroll or interact with anything in the Settings menu"). The whole
-- add-on is loaded on a fake client and the window opened by the slash
-- word; the tree the add-on then asks the client to draw (its real rows,
-- with their real controls) is drawn by the real client's kit over a
-- hand-built game environment that records frame levels, the mouse flag and
-- the scroll. What is held: the rows are taller than the window and the
-- wheel moves them, both ways and never past an end; every check box
-- stands above its row with nothing over it taking the mouse; a click on
-- one changes that setting in the loaded add-on; a click on a topic shows
-- that topic's rows. Lead section 340's tests hold this on a made-up tree;
-- this holds it on the add-on's own. No game client is involved. Not
-- tested in game.
local tests = {}

local TEMPLATES = { "ButtonFrameTemplate", "UIPanelCloseButton", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate", "UIPanelScrollFrameTemplate",
    "PanelTabButtonTemplate" }

-- As ClientKitMouseTests' gameEnv: frames that record their level, mouse
-- flag, scripts, text and vertical scroll.
local function gameEnv()
    local env = { made = {}, UIParent = { level = 0 }, UISpecialFrames = {} }
    local has = {}
    for _, name in ipairs(TEMPLATES) do has[name] = true end
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

local function saying(env, kind, text)
    for _, r in ipairs(env.made) do
        if r.kind == kind and r.shown and r.text == text then return r end
    end
    return nil
end

-- The loaded add-on with its settings window open by the slash word, and
-- the tree it last asked the client to draw: -> c, addon, tree().
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
        if id ~= ns.SettingsWindow.ID or type(h) ~= "table" then return h end
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
    c.slashes[ns.id.slash]("settings")
    c.advance(1, 4)
    return c, addon, function() return last end
end

-- The first topic with at least `least` switches a player may set, shown:
-- -> the rows (kit parts) with a check box.
local function topicWithSwitches(c, tree, least)
    local T = ns.Settings.Topics
    for i = 1, #T.LIST do
        local topics
        ns.Kit.Each(tree(), function(p) if p.kind == "topicList" then topics = p end end)
        if topics == nil then return {} end
        topics.onSelect(i)
        c.advance(1, 4)
        local rows = {}
        ns.Kit.Each(tree(), function(p)
            if p.kind == "row" and p.enabled and type(p.control) == "table" and p.control.kind == "checkbox" then
                rows[#rows + 1] = p
            end
        end)
        if #rows >= least then return rows end
    end
    return {}
end

-- The real client's kit drawing that tree: -> env, handle.
local function draw(tree)
    local env = gameEnv()
    local real = ns.make.client(env)
    return env, real.kitWindow("E2ESettings", tree, { name = "E2ESettingsFrame" })
end

tests["settings mouse: the add-on's own rows scroll with the wheel, both ways, never past an end"] = function(t)
    local c, _, tree = boot()
    t.ok(type(tree()) == "table", "the slash word has the window drawn")
    if type(tree()) ~= "table" then return end
    local rows = topicWithSwitches(c, tree, 12)
    t.ok(#rows >= 12, "a topic of twelve switches or more")
    local env, h = draw(tree())
    t.ok(type(h) == "table", "the real kit draws the add-on's tree")
    if type(h) ~= "table" then return end
    local scrolls = shown(env, "ScrollFrame")
    t.eq(#scrolls, 2, "the topic list and the rows each scroll")
    local list = scrolls[2]
    if list == nil then return end
    t.eq(list.wheel, true, "the rows' scroll takes the wheel")
    local wheel = list.scripts.OnMouseWheel
    t.eq(type(wheel), "function", "and has a wheel handler")
    if type(wheel) ~= "function" then return end
    local range = list:GetVerticalScrollRange()
    t.ok(range > 0, "the rows are taller than the window")
    wheel(list, -1)
    local one = list.vscroll
    t.ok(one > 0 and one <= range, "one notch down moves the rows")
    for _ = 1, 400 do wheel(list, -1) end
    t.eq(list.vscroll, range, "never past the last row")
    wheel(list, 1)
    t.ok(list.vscroll < range, "one notch up moves back")
    for _ = 1, 400 do wheel(list, 1) end
    t.eq(list.vscroll, 0, "never above the first")
end

tests["settings mouse: every check box stands above its row and nothing over it takes the mouse"] = function(t)
    local c, _, tree = boot()
    if type(tree()) ~= "table" then t.ok(false, "a drawn window") return end
    local rows = topicWithSwitches(c, tree, 3)
    local env, h = draw(tree())
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    local checks = shown(env, "CheckButton")
    local boxes = 0
    ns.Kit.Each(tree(), function(p)
        if p.kind == "row" and type(p.control) == "table" and p.control.kind == "checkbox" then boxes = boxes + 1 end
    end)
    t.ok(#rows >= 3, "a topic of three switches or more")
    t.eq(#checks, boxes, "a check box for each switch of the topic")
    t.ok(#checks >= 3, "three or more")
    for i, b in ipairs(checks) do
        t.eq(type(b.scripts.OnClick), "function", "check box " .. i .. " takes a click")
        local row = b.parent
        t.ok(row.mouse ~= true, "row " .. i .. " under its check box takes no mouse")
        t.ok(b.level > row.level, "check box " .. i .. " stands above its row")
        local up, n = row, 0
        while up ~= nil and up.kind ~= nil and n < 12 do
            if up.mouse == true and up.kind ~= "ScrollFrame" and up.name ~= "E2ESettingsFrame" then
                t.ok(false, "a frame over check box " .. i .. " takes the mouse: " .. tostring(up.kind))
            end
            up, n = up.parent, n + 1
        end
    end
end

tests["settings mouse: a click on a drawn check box changes that setting in the add-on, and again changes it back"] = function(t)
    local c, addon, tree = boot()
    if type(tree()) ~= "table" then t.ok(false, "a drawn window") return end
    local before = addon.problems:count()
    local rows = topicWithSwitches(c, tree, 1)
    local row = rows[1]
    t.ok(row ~= nil, "a switch to click")
    if row == nil then return end
    local key, was = row.control.key, row.control.checked
    t.eq(addon.settings:get(key), was, "the box shows what is set")
    local env, h = draw(tree())
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    local b = shown(env, "CheckButton")[1]
    if b == nil then t.ok(false, "a check box") return end
    b.checked = not was
    t.ok(pcall(b.scripts.OnClick, b, "LeftButton"), "the click raises nothing")
    t.eq(addon.settings:get(key), not was, key .. " is changed by the click")
    c.advance(1, 4)
    -- The add-on asked for a redraw; the game's kit draws it, and the box
    -- there turns the setting back.
    t.eq(h.update(tree()), true, "the redraw is drawn")
    b = shown(env, "CheckButton")[1]
    b.checked = was
    t.ok(pcall(b.scripts.OnClick, b, "LeftButton"), "the second click raises nothing")
    t.eq(addon.settings:get(key), was, "and back")
    t.eq(addon.problems:count(), before)
end

tests["settings mouse: a click on a topic in the drawn list shows that topic's rows"] = function(t)
    local c, _, tree = boot()
    if type(tree()) ~= "table" then t.ok(false, "a drawn window") return end
    local T = ns.Settings.Topics
    local env, h = draw(tree())
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    local second = T.LIST[2].name
    local button
    for _, r in ipairs(env.made) do
        if r.kind == "Button" and r.shown and type(r.scripts.OnClick) == "function" then
            local label = r.text
            if label == nil then
                for _, fs in ipairs(env.made) do
                    if fs.kind == "FontString" and fs.parent == r and fs.text == second then label = second end
                end
            end
            if label == second then button = r break end
        end
    end
    t.ok(button ~= nil, "the second topic is a button that takes a click")
    if button == nil then return end
    t.ok(pcall(button.scripts.OnClick, button, "LeftButton"), "the click raises nothing")
    c.advance(1, 4)
    local heading
    ns.Kit.Each(tree(), function(p) if p.kind == "section" and p.big and heading == nil then heading = p.text end end)
    t.eq(heading, second, "the add-on now shows the second topic")
    t.eq(h.update(tree()), true, "and the game's kit draws it")
    t.ok(saying(env, "FontString", second) ~= nil, "its name is on the window")
end

return tests
