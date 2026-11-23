-- The settings window took no clicks and did not scroll in game (lead
-- section 340): redraws at most once a frame, the scroll kept across a
-- redraw, no decorative kit frame over a control taking the mouse, a
-- control always above its row, and one diagnostics line naming the frame
-- under the mouse. The real client over a hand-built environment that
-- records frame levels, the mouse flag and the vertical scroll; no game
-- client is involved.
-- Fails before the fix: three draws in one frame draw three times; the
-- scroll is back at 0 after a redraw; a row frame under its checkbox has
-- the mouse; c.kitFocus is nil.
local _, ns = ...

local K = ns.Kit

local TEMPLATES = { "ButtonFrameTemplate", "UIPanelCloseButton", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate", "UIPanelScrollFrameTemplate",
    "PanelTabButtonTemplate" }

-- Like ClientKitTests' gameEnv, plus: frame levels (a child made one above
-- its parent), EnableMouse / IsMouseEnabled, GetName, GetObjectType,
-- GetParent, and a scroll frame whose SetScrollChild puts the scroll back
-- at 0 (the worst a client may do). env.focus: what GetMouseFocus answers.
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

-- Runs one drawn frame: every OnUpdate the client set.
local function frame(env)
    for _, r in ipairs(env.made) do
        if type(r.scripts.OnUpdate) == "function" then pcall(r.scripts.OnUpdate, r, 0.016) end
    end
end

local function shown(env, kind, template)
    local out = {}
    for _, r in ipairs(env.made) do
        if r.kind == kind and (template == nil or r.template == template) and r.shown then out[#out + 1] = r end
    end
    return out
end

local function saying(env, kind, text)
    for _, r in ipairs(env.made) do
        if r.kind == kind and r.shown and r.text == text then return r end
    end
    return nil
end

-- A window of n rows with a checkbox each, in one scroll, beside topics.
local function rowsTree(n, label, onToggle)
    local list = {}
    for i = 1, n do
        list[i] = { kind = "row", label = label .. " " .. i, description = "Row " .. i .. ".",
            control = { kind = "checkbox", checked = false, onToggle = onToggle or function() end } }
    end
    return K.Window({ id = "KitMouse", title = "Settings", width = 760, height = 520, children = {
        { kind = "header", title = "2 topics", search = { onText = function() end, text = "" } },
        { kind = "topicList", items = { "General", "Bags" }, selected = 1, onSelect = function() end },
        { kind = "scroll", children = list },
    } })
end

local tests = {}

tests["settingsWindow: three draws in one frame draw once; the last is drawn at the next frame"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    local draws = 0
    c.onKitDrawn(function() draws = draws + 1 end)
    local page = c.settingsWindow({ id = "KitMouse", name = "KitMouseFrame",
        build = function(label) return rowsTree(3, label) end })
    t.ok(type(page) == "table", "a page")
    if type(page) ~= "table" then return end
    t.eq(page.draw("First"), true, "the first draw")
    t.eq(draws, 1, "the window is made and drawn once")
    frame(env)
    draws = 0
    page.draw("A")
    page.draw("B")
    page.draw("C")
    t.eq(draws, 1, "three draws in one frame: one draw")
    frame(env)
    t.eq(draws, 2, "the one held back is drawn at the next frame")
    t.ok(saying(env, "FontString", "C 1") ~= nil, "what was asked last is what shows")
    frame(env)
    t.eq(draws, 2, "a frame with nothing asked draws nothing")
    page.draw("C")
    frame(env)
    t.eq(draws, 2, "the same tree again draws nothing")
end

tests["kitWindow: the scroll stays where the player left it across a redraw"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    local h = c.kitWindow("KitMouse", rowsTree(40, "Row"), { name = "KitMouseFrame" })
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local scrolls = shown(env, "ScrollFrame")
    t.eq(#scrolls, 2, "the topic list and the rows each scroll")
    local list = scrolls[2]
    if list == nil then return end
    list:SetVerticalScroll(50)
    t.eq(h.update(rowsTree(40, "Row")), true, "drawn again")
    t.eq(list.vscroll, 50, "still 50 down")
    -- Fewer rows: kept, but never past the end.
    t.eq(h.update(rowsTree(2, "Row")), true, "drawn with two rows")
    t.eq(list.vscroll, 0, "two rows fit: back at the top")
end

tests["kitWindow: no decorative frame over a row takes the mouse; the control stands above its row"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    local h = c.kitWindow("KitMouse", rowsTree(3, "Row"), { name = "KitMouseFrame" })
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local checks = shown(env, "CheckButton")
    t.eq(#checks, 3, "three checkboxes")
    for i, b in ipairs(checks) do
        local row = b.parent
        t.ok(row.mouse ~= true, "row " .. i .. " under its checkbox takes no mouse")
        t.ok(b.level > row.level, "checkbox " .. i .. " stands above its row")
        -- Nothing between the checkbox and the window takes the mouse but a
        -- scroll frame.
        local up, n = row, 0
        while up ~= nil and up.kind ~= nil and n < 12 do
            if up.mouse == true and up.kind ~= "ScrollFrame" and up.name ~= "KitMouseFrame" then
                t.ok(false, "a frame above checkbox " .. i .. "'s window takes the mouse: " .. tostring(up.kind))
            end
            up, n = up.parent, n + 1
        end
    end
end

tests["kitWindow: a click on a checkbox after a redraw still reaches its part"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    local got = {}
    local function toggled(on) got[#got + 1] = on end
    local h = c.kitWindow("KitMouse", rowsTree(2, "Row", toggled), { name = "KitMouseFrame" })
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    t.eq(h.update(rowsTree(2, "Again", toggled)), true, "drawn again")
    local b = shown(env, "CheckButton")[1]
    t.ok(b ~= nil and type(b.scripts.OnClick) == "function", "a checkbox with a click")
    if b == nil then return end
    b.checked = true
    t.ok(pcall(b.scripts.OnClick, b, "LeftButton"), "the click raises nothing")
    t.eq(got, { true }, "the part was told")
end

tests["kitFocus: one line names the frame under the mouse and whether it is the kit's"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    t.eq(type(c.kitFocus), "function", "the client answers kitFocus")
    if type(c.kitFocus) ~= "function" then return end
    local h = c.kitWindow("KitMouse", rowsTree(1, "Row"), { name = "KitMouseFrame" })
    if type(h) ~= "table" then t.ok(false, "a handle") return end
    env.focus = shown(env, "CheckButton")[1]
    local line = c.kitFocus()
    t.eq(type(line), "string", "a line")
    if type(line) ~= "string" then return end
    t.ok(line:find("CheckButton", 1, true) ~= nil, "names its type: " .. line)
    t.ok(line:find("kit KitMouse", 1, true) ~= nil, "says it is the kit's: " .. line)
    t.ok(line:find("(kit)", 1, true) ~= nil, "its parents are marked as the kit's: " .. line)
    env.focus = { kind = "Frame", name = "WorldFrame", GetName = function() return "WorldFrame" end,
        GetObjectType = function() return "Frame" end }
    t.ok(c.kitFocus():find("not the kit's", 1, true) ~= nil, "a game frame is not the kit's")
    env.focus = nil
    t.ok(c.kitFocus():find("nothing", 1, true) ~= nil, "nothing under the mouse says so")
end

return tests
