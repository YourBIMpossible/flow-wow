-- c.kitWindow and c.kitProbe (lead sections 287, 291 item 1 and 292): the
-- drawer of the shared window kit, and the login probe of the stock names it
-- would like to use. The real client over a hand-built environment; every
-- frame, texture and text is a recording stub. No game client is involved.
-- Fails before the drawer: c.kitWindow is nil, so every window test fails
-- its first check ("the client answers kitWindow", got nil); c.kitProbe is
-- nil, so every probe test fails "the client answers kitProbe".
local _, ns = ...

local K = ns.Kit

local TEMPLATES = { "ButtonFrameTemplate", "UIPanelCloseButton", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate", "UIPanelScrollFrameTemplate",
    "PanelTabButtonTemplate" }

-- Every stub made of that kind and template, shown or not.
local function madeOf(env, kind, template)
    local out = {}
    for _, r in ipairs(env.made) do
        if r.kind == kind and r.template == template then out[#out + 1] = r end
    end
    return out
end

-- opts.templates: the templates this client has (default: all of them).
-- opts.noFrames: it has no CreateFrame. opts.combat: what InCombatLockdown
-- answers (default false). opts.noTexture: a path SetTexture raises on.
local function gameEnv(opts)
    opts = opts or {}
    local env = { made = {}, UIParent = {}, UISpecialFrames = { "SomeoneElse" } }
    local has = {}
    for _, name in ipairs(opts.templates or TEMPLATES) do has[name] = true end
    local function region(kind, parent, template, name)
        local r = { kind = kind, parent = parent, template = template, name = name, scripts = {}, shown = true }
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
        function r:SetTexture(v)
            if v == opts.noTexture then error("no such texture") end
            self.texture = v
            return true
        end
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
        env.made[#env.made + 1] = r
        return r
    end
    if not opts.noFrames then
        function env.CreateFrame(kind, name, parent, template)
            if template ~= nil and not has[template] then error("no template " .. tostring(template)) end
            local f = region(kind, parent, template, name)
            if name ~= nil and env[name] == nil then env[name] = f end
            return f
        end
    end
    function env.InCombatLockdown()
        if opts.combat == nil then return false end
        return opts.combat
    end
    return env
end

-- The stubs that are shown, of that kind (and template, when given).
local function find(env, kind, template)
    local out = {}
    for _, r in ipairs(env.made) do
        if r.kind == kind and (template == nil or r.template == template) and r.shown then out[#out + 1] = r end
    end
    return out
end

-- The first shown stub of that kind saying exactly that text, or nil.
local function saying(env, kind, text)
    for _, r in ipairs(env.made) do
        if r.kind == kind and r.shown and r.text == text then return r end
    end
    return nil
end

local function listed(env, name)
    local n = 0
    for i = 1, #env.UISpecialFrames do
        if env.UISpecialFrames[i] == name then n = n + 1 end
    end
    return n
end

local function nop() end

-- One of every part. `fns` gives the caller functions by name; one not
-- given does nothing.
local function everyPart(fns)
    fns = fns or {}
    local function fn(name) return fns[name] or nop end
    return {
        id = "KitDemo", title = "Demo window",
        children = {
            { kind = "header", title = "14 things", search = { onText = fn("search"), text = "" } },
            { kind = "tabs", items = { "One", "Two" }, onSelect = fn("tab") },
            { kind = "topicList", items = { "Bags", "Bank" }, selected = 2, onSelect = fn("topic") },
            { kind = "section", text = "General" },
            { kind = "row", label = "Sell grey items", description = "Sells them at a vendor.",
              control = { kind = "checkbox", checked = true, onToggle = fn("toggle") } },
            { kind = "row", label = "Helper key", control = { kind = "bind", onClick = fn("bind") } },
            { kind = "row", label = "Style", control = { kind = "choice", items = { "Plain", "Fancy" }, onSelect = fn("choice") } },
            { kind = "row", label = "Icon size",
              control = { kind = "number", value = 48, min = 16, max = 49, step = 1, onChange = fn("number") } },
            { kind = "row", label = "Name", control = { kind = "text", text = "abc", onText = fn("text") } },
            { kind = "button", text = "Press me", onClick = fn("button") },
            { kind = "button", text = "Not now", onClick = fn("off"), enabled = false, tooltip = "Why not" },
            { kind = "scroll", height = 120, children = {
                { kind = "itemLine", name = "Linen Cloth", quality = 2, count = 4, money = 120005, item = 2589 },
                { kind = "itemLine", name = "Worn Sword", note = "kept: best weapon", tone = "good" },
                { kind = "empty", text = "Nothing to sell.", how = "Loot something grey first." },
            } },
            { kind = "footer", text = "Total", money = 11660, slot = "sellAction",
              buttons = { { kind = "button", text = "Refresh", onClick = fn("refresh") } } },
        },
    }
end

-- The client, a window of every part on it, and what its caller functions
-- were told: got[name] = the list of first arguments (true for none).
local function open(t, envOpts, extra)
    local env = gameEnv(envOpts)
    local c = ns.make.client(env)
    t.eq(type(c.kitWindow), "function", "the client answers kitWindow")
    if type(c.kitWindow) ~= "function" then return nil end
    local got, fns = {}, {}
    for _, name in ipairs({ "search", "tab", "topic", "toggle", "bind", "choice", "number", "text", "button", "off", "refresh" }) do
        got[name] = {}
        fns[name] = function(v)
            if v == nil then v = true end
            got[name][#got[name] + 1] = v
        end
    end
    local tree, why = K.Window(everyPart(fns))
    t.ok(type(tree) == "table", "the tree: " .. tostring(why))
    local x = { name = "KitDemoFrame" }
    for key, value in pairs(extra or {}) do x[key] = value end
    local h = c.kitWindow("KitDemo", tree, x)
    return h, env, got, c, tree
end

local function click(r)
    return pcall(r.scripts.OnClick, r, "LeftButton")
end

local tests = {}

tests["kitWindow: one of every part builds, and the handle answers"] = function(t)
    local h, env = open(t)
    if h == nil then t.ok(false, "a handle") return end
    for _, name in ipairs({ "update", "show", "shown", "close", "art", "slot" }) do
        t.eq(type(h[name]), "function", "handle." .. name)
    end
    t.eq(h.shown(), false, "a new window is hidden")
    h.show(true)
    t.eq(h.shown(), true)
    t.eq(env.made[1].shown, true, "the frame is shown")
    for _, text in ipairs({ "Demo window", "14 things", "General", "Sell grey items", "Sells them at a vendor.",
        "Helper key", "Icon size", "48", "Linen Cloth", "x4", "Worn Sword", "kept: best weapon",
        "Nothing to sell.", "Loot something grey first.", "Total" }) do
        t.ok(saying(env, "FontString", text) ~= nil, "drawn: " .. text)
    end
    for _, text in ipairs({ "Press me", "Not now", "Refresh", "Plain", "Fancy", K.NOT_BOUND, "One", "Two", "Bags", "Bank" }) do
        t.ok(saying(env, "Button", text) ~= nil, "a button: " .. text)
    end
    h.close()
    t.eq(h.shown(), false, "close() hides it")
end

-- Lead section 297 item 4: each part is the game's own when a protected
-- create makes it, else the kit's plain panel. Both paths, part by part.
tests["kitWindow: with the game's templates there, each part is the game's own"] = function(t)
    local h, env = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local art = h.art()
    t.eq({ art.frame, art.search, art.tab }, { "first", "first", "first" }, "frame, search box, tabs")
    t.eq({ art.close, art.button, art.check, art.input, art.scroll }, { "first", "first", "first", "first", "first" },
        "close, button, checkbox, text box, scroll")
    t.eq(#madeOf(env, "Frame", "ButtonFrameTemplate"), 1, "the window frame is asked for by name, once")
    t.ok(#madeOf(env, "EditBox", "SearchBoxTemplate") >= 1, "the search box template")
    t.ok(#madeOf(env, "Button", "PanelTabButtonTemplate") >= 1, "the tab template")
    t.eq({ art.rowHighlight, art.topicHighlight, art.iconBorder, art.grip },
        { "fallback", "fallback", "fallback", "fallback" }, "pictures not yet seen on 16001 stay plain")
    t.eq({ art.gold, art.iconMissing }, { "first", "first" }, "coin icons and the missing-item icon")
end

tests["kitWindow: one template missing leaves only that part plain"] = function(t)
    for _, case in ipairs({ { "ButtonFrameTemplate", "frame" }, { "SearchBoxTemplate", "search" },
        { "PanelTabButtonTemplate", "tab" }, { "UIPanelButtonTemplate", "button" },
        { "UICheckButtonTemplate", "check" }, { "UIPanelScrollFrameTemplate", "scroll" },
        { "UIPanelCloseButton", "close" } }) do
        local have = {}
        for _, name in ipairs(TEMPLATES) do
            if name ~= case[1] then have[#have + 1] = name end
        end
        local h = open(t, { templates = have })
        t.ok(type(h) == "table", "without " .. case[1] .. " the window still opens")
        if type(h) == "table" then
            local art = h.art()
            t.eq(art[case[2]], "fallback", "without " .. case[1] .. ": " .. case[2] .. " is the plain one")
            local other = "button"
            if case[2] == "button" then other = "check" end
            t.eq(art[other], "first", "without " .. case[1] .. ": " .. other .. " is still the game's own")
        end
    end
end

tests["kitWindow: a picture taken out of Kit.look.unproven is drawn"] = function(t)
    local unproven = type(K.look) == "table" and K.look.unproven
    t.eq(type(unproven), "table", "Kit.look.unproven is a table")
    if type(unproven) ~= "table" then return end
    local was = unproven.rowHighlight
    unproven.rowHighlight = nil
    local ok, err = pcall(function()
        local h = open(t)
        if h == nil then t.ok(false, "a handle") return end
        t.eq(h.art().rowHighlight, "first")
    end)
    unproven.rowHighlight = was
    t.ok(ok, "no raise: " .. tostring(err))
end

tests["kitWindow: a client with no template at all still builds, all of it the fallback"] = function(t)
    local h, env = open(t, { templates = {} })
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local art = h.art()
    t.eq({ art.frame, art.close, art.button, art.check, art.input, art.search, art.scroll, art.tab },
        { "fallback", "fallback", "fallback", "fallback", "fallback", "fallback", "fallback", "fallback" })
    t.ok(saying(env, "Button", "Press me") ~= nil, "the button is still drawn")
    t.ok(saying(env, "FontString", "Linen Cloth") ~= nil, "and the item line")
end

tests["kitWindow: a coin icon the client will not set is drawn as its letter"] = function(t)
    local h, env = open(t, { noTexture = K.look.art.gold })
    if h == nil then t.ok(false, "a handle") return end
    t.eq(h.art().gold, "fallback")
    t.eq(h.art().silver, "first")
    local letter = type(K.look.coinLetter) == "table" and K.look.coinLetter.gold
    t.ok(letter ~= nil and saying(env, "FontString", letter) ~= nil, "the gold letter is drawn")
end

tests["kitWindow: a click on a drawn button runs its onClick once; a disabled one runs nothing"] = function(t)
    local h, env, got = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local b, off = saying(env, "Button", "Press me"), saying(env, "Button", "Not now")
    t.ok(b ~= nil and off ~= nil, "both buttons drawn")
    if b == nil or off == nil then return end
    t.eq(b.enabled, true)
    t.eq(off.enabled, false, "the disabled button is disabled")
    t.ok(click(b))
    t.eq(#got.button, 1, "onClick ran once")
    t.ok(click(off))
    t.eq(#got.off, 0, "the disabled button's onClick did not run")
    t.ok(click(saying(env, "Button", "Refresh")))
    t.eq(#got.refresh, 1, "the footer button")
end

tests["kitWindow: every control tells its own function what the player did"] = function(t)
    local h, env, got = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local check = find(env, "CheckButton", "UICheckButtonTemplate")[1]
    t.ok(check ~= nil, "the check box")
    if check == nil then return end
    t.eq(check.checked, true, "it shows the part's value")
    check.checked = false
    click(check)
    click(saying(env, "Button", K.NOT_BOUND))
    click(saying(env, "Button", "Fancy"))
    click(saying(env, "Button", "Two"))
    click(saying(env, "Button", "Bags"))
    click(saying(env, "Button", "+"))
    click(saying(env, "Button", "-"))
    local edits = find(env, "EditBox", "InputBoxTemplate")
    t.eq(#edits, 2, "the search box (its fallback) and the text box")
    local search, box
    for _, e in ipairs(edits) do
        if e.text == "abc" then box = e else search = e end
    end
    t.ok(search ~= nil and box ~= nil, "both found")
    if search == nil or box == nil then return end
    search.text = "lin"
    pcall(search.scripts.OnTextChanged, search, true)
    pcall(search.scripts.OnTextChanged, search, true)
    box.text = "abcd"
    pcall(box.scripts.OnEnterPressed, box)
    t.eq(got.toggle, { false })
    t.eq(#got.bind, 1)
    t.eq(got.choice, { 2 })
    t.eq(got.tab, { 2 })
    t.eq(got.topic, { 1 })
    t.eq(got.number, { 49, 47 }, "plus then minus, each from the part's own value")
    t.eq(got.search, { "lin" }, "the same text again is not told twice")
    t.eq(got.text, { "abcd" })
end

tests["kitWindow: at its limit a number's plus is disabled and tells nothing"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    t.eq(type(c.kitWindow), "function", "the client answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local told = 0
    local tree = K.Window({ id = "KitLimit", title = "Limit", children = {
        { kind = "row", label = "N", control = { kind = "number", value = 3, min = 1, max = 3, onChange = function() told = told + 1 end } },
    } })
    t.ok(c.kitWindow("KitLimit", tree, { name = "KitLimitFrame" }) ~= nil, "a handle")
    local plus, minus = saying(env, "Button", "+"), saying(env, "Button", "-")
    t.ok(plus ~= nil and minus ~= nil, "both drawn")
    if plus == nil or minus == nil then return end
    t.eq({ plus.enabled, minus.enabled }, { false, true })
    click(plus)
    t.eq(told, 0)
end

tests["kitWindow: a caller function that raises goes to failed and does not escape"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    t.eq(type(c.kitWindow), "function", "the client answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local errs = {}
    local tree = K.Window({ id = "KitBoom", title = "Boom", children = {
        { kind = "button", text = "Boom", onClick = function() error("boom-click") end },
    } })
    local h = c.kitWindow("KitBoom", tree, { name = "KitBoomFrame", failed = function(err) errs[#errs + 1] = tostring(err) end,
        onClose = function() error("boom-close") end })
    t.ok(h ~= nil, "a handle")
    if h == nil then return end
    h.show(true)
    local b = saying(env, "Button", "Boom")
    t.ok(b ~= nil, "the button")
    if b == nil then return end
    t.ok(click(b), "the click does not raise")
    t.eq(#errs, 1, "failed was told once")
    t.ok(errs[1] ~= nil and errs[1]:find("boom-click", 1, true) ~= nil, "with the error: " .. tostring(errs[1]))
    local close = find(env, "Button", "UIPanelCloseButton")[1]
    t.ok(close ~= nil and click(close), "the close click does not raise")
    t.ok(errs[2] ~= nil and errs[2]:find("boom-close", 1, true) ~= nil, "onClose's error too: " .. tostring(errs[2]))
end

tests["kitWindow: the frame's name is in the Escape list once, however often the window is asked for"] = function(t)
    local h, env, _, c, tree = open(t)
    if h == nil then t.ok(false, "a handle") return end
    t.eq(listed(env, "KitDemoFrame"), 1)
    t.eq(env.UISpecialFrames[1], "SomeoneElse", "the list is added to, not replaced")
    local again = c.kitWindow("KitDemo", tree, { name = "KitDemoFrame" })
    t.ok(again ~= nil, "asked again: a handle")
    t.eq(listed(env, "KitDemoFrame"), 1, "still once")
end

tests["kitWindow: a window that Escape does not close is not in the list"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    t.eq(type(c.kitWindow), "function", "the client answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local tree = K.Window({ id = "KitStay", title = "Stay", escape = false, children = {} })
    t.ok(c.kitWindow("KitStay", tree, { name = "KitStayFrame" }) ~= nil, "a handle")
    t.eq(listed(env, "KitStayFrame"), 0)
end

tests["kitWindow: the close button closes it and tells onClose once"] = function(t)
    local closed = 0
    local h, env = open(t, nil, { onClose = function() closed = closed + 1 end })
    if h == nil then t.ok(false, "a handle") return end
    h.show(true)
    local close = find(env, "Button", "UIPanelCloseButton")[1]
    t.ok(close ~= nil, "a close button")
    if close == nil then return end
    click(close)
    t.eq(closed, 1)
    t.eq(h.shown(), false)
    t.eq(env.made[1].shown, false, "the frame is hidden")
    click(close)
    t.eq(closed, 1, "a second click on a closed window tells nothing")
    h.show(true)
    h.show(false)
    t.eq(closed, 1, "the add-on hiding it is not the player closing it")
    h.show(true)
    env.made[1]:Hide()
    t.eq(closed, 2, "Escape (the client hides the frame) is the player closing it")
end

tests["kitWindow: a client that cannot make frames answers nil, and says why"] = function(t)
    local c = ns.make.client(gameEnv({ noFrames = true }))
    t.eq(type(c.kitWindow), "function", "the client answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local errs = 0
    local tree = K.Window(everyPart())
    t.eq(c.kitWindow("KitDemo", tree, { name = "KitDemoFrame", failed = function() errs = errs + 1 end }), nil)
    t.eq(errs, 1, "failed was told")
    t.eq(c.kitWindow("KitDemo", nil, nil), nil, "no tree is no window, and nothing is raised")
end

tests["kitWindow: a drag of the title tells onMoved where it stands and how big it is"] = function(t)
    local moves = {}
    local h, env = open(t, nil, { onMoved = function(point, w, ht) moves[#moves + 1] = { point, w, ht } end })
    if h == nil then t.ok(false, "a handle") return end
    local bar
    for _, r in ipairs(env.made) do
        if r.kind == "Frame" and r.scripts.OnDragStop then bar = r end
    end
    t.ok(bar ~= nil, "a part of the window takes the drag")
    if bar == nil then return end
    t.ok(bar ~= env.made[1], "the title area, not the whole window")
    pcall(bar.scripts.OnDragStart, bar)
    pcall(bar.scripts.OnDragStop, bar)
    t.eq(moves, { { { "TOPLEFT", "TOPLEFT", 30, -40 }, K.WIDTH, K.HEIGHT } })
end

tests["kitWindow: the size, the place and the colours are the kit's own"] = function(t)
    local h, env = open(t, nil, { point = { "TOPLEFT", "TOPLEFT", 5, -6 }, width = 500, height = 400 })
    if h == nil then t.ok(false, "a handle") return end
    t.eq({ env.made[1].width, env.made[1].height }, { 500, 400 }, "the size asked for")
    local look = K.look
    t.eq(saying(env, "FontString", "General").textColor, look.color.accent, "a section heading is the accent colour")
    t.eq(saying(env, "FontString", "General").font, look.font.heading)
    local q = K.Quality(2)
    local name = saying(env, "FontString", "Linen Cloth")
    t.eq({ name.textColor[1], name.textColor[2], name.textColor[3] }, { q.r, q.g, q.b }, "an item's name is its quality colour")
    t.eq(saying(env, "FontString", "kept: best weapon").textColor, look.color.good, "a note is its tone colour")
    t.eq(saying(env, "FontString", "Nothing to sell.").font, look.font.big)
    local icons = 0
    for _, r in ipairs(find(env, "Texture")) do
        if r.texture == look.art.iconMissing then icons = icons + 1 end
    end
    t.eq(icons, 2, "an item with no icon shows the question mark")
end

tests["kitWindow: the footer's slot is a frame another lane can fill; an unknown slot is nil"] = function(t)
    local h = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local slot = h.slot("sellAction")
    t.ok(type(slot) == "table" and slot.kind == "Frame", "a frame")
    t.eq(h.slot("nothing"), nil)
end

tests["kitWindow: update draws a new tree and makes nothing new for the same one"] = function(t)
    local h, env, _, _, tree = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local before = #env.made
    t.eq(h.update(tree), true)
    t.eq(#env.made, before, "nothing new made")
    local small = K.Window({ id = "KitDemo", title = "Smaller", children = {
        { kind = "empty", text = "No bank data yet.", how = "Open your bank once." },
    } })
    t.eq(h.update(small), true)
    t.ok(saying(env, "FontString", "No bank data yet.") ~= nil, "the new part")
    t.ok(saying(env, "FontString", "Smaller") ~= nil, "the new title")
    t.eq(saying(env, "Button", "Press me"), nil, "the old button is hidden")
    t.eq(saying(env, "FontString", "Linen Cloth"), nil, "and the old item line")
    t.eq(h.update(nil), false, "no tree: nothing drawn, nothing raised")
end

return tests
