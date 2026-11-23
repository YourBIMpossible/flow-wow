-- N72 (lead section 248 item 4): the macro icon window on the real client
-- boundary with a stand-in for the globals of the game, on the fake
-- client, and in the capture (Diag.NAMES and its fields). The window is
-- the icon selector popup of the macro editor; the search box filters
-- through the popup's own data provider so a click selects through the
-- normal editor. No game client is involved. Made-up names and icons only.
local _, ns = ...

-- A stand-in for the game globals. Every frame made is in env.made, in
-- order; a method the stand-in has no answer for is recorded in o.calls.
local function obj(kind, name, parent, template)
    local o = { kind = kind, name = name, parent = parent, template = template, scripts = {},
                hooks = {}, calls = {}, shown = true, text = "" }
    setmetatable(o, { __index = function(_, key)
        return function(_, ...) o.calls[#o.calls + 1] = { key, ... } end
    end })
    function o:SetScript(script, fn) self.scripts[script] = fn end
    function o:HookScript(script, fn)
        self.hooks[script] = self.hooks[script] or {}
        local list = self.hooks[script]
        list[#list + 1] = fn
    end
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsShown() return self.shown end
    function o:SetText(text) self.text = text end
    function o:GetText() return self.text end
    return o
end

-- The provider the popup makes each time it opens: icons by index.
local function provider(icons)
    local p = { icons = icons }
    function p:GetNumIcons() return #self.icons end
    function p:GetIconByIndex(i) return self.icons[i] end
    function p:GetIndexOfIcon(icon)
        for i, v in ipairs(self.icons) do if v == icon then return i end end
        return nil
    end
    return p
end

-- opts.without: a list of names left out; opts.noEditBox: CreateFrame
-- gives nothing for an EditBox.
local function gameEnv(opts)
    opts = opts or {}
    local env = { made = {}, UIParent = {} }
    function env.CreateFrame(kind, name, parent, template)
        if opts.noEditBox and kind == "EditBox" then return nil end
        local f = obj(kind, name, parent, template)
        function f:CreateFontString()
            local r = obj("FontString", nil, f)
            env.made[#env.made + 1] = r
            return r
        end
        env.made[#env.made + 1] = f
        return f
    end
    local popup = obj("Frame", "MacroPopupFrame")
    popup.shown = false
    popup.updates = 0
    function popup:Update() self.updates = self.updates + 1 end
    popup.IconSelector = { selections = 0 }
    function popup.IconSelector:UpdateSelections() self.selections = self.selections + 1 end
    env.MacroPopupFrame = popup
    env.IconSelectorPopupFrameTemplateMixin = { SetSelectedCallback = function() end }
    env.IconDataProviderMixin = { GetNumIcons = function() end }
    env.GetMacroIcons = function(into) into[1] = 134400; into[2] = "INV_Misc_Gem_01" end
    for _, name in ipairs(opts.without or {}) do
        if name == "MacroPopupFrame.IconSelector" then popup.IconSelector = nil else env[name] = nil end
    end
    return env
end

-- The window opening: the popup makes a fresh provider and fires OnShow.
local function open(env, icons)
    local popup = env.MacroPopupFrame
    popup.iconDataProvider = provider(icons or { 101, 102, 103 })
    popup.shown = true
    for _, fn in ipairs(popup.hooks.OnShow or {}) do fn(popup) end
end

local function close(env)
    local popup = env.MacroPopupFrame
    popup.shown = false
    for _, fn in ipairs(popup.hooks.OnHide or {}) do fn(popup) end
    popup.iconDataProvider = nil
end

local function find(env, kind)
    local out = {}
    for _, o in ipairs(env.made) do
        if o.kind == kind then out[#out + 1] = o end
    end
    return out
end

local function handle(env)
    local c = ns.make.client(env)
    if type(c.macroPopup) ~= "function" then return nil end
    return c.macroPopup()
end

local function listed(name)
    for _, n in ipairs(ns.Diag and ns.Diag.NAMES or {}) do
        if n == name then return true end
    end
    return false
end

local function shapes(e)
    return ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
end

return {
    ["macro icons client: every name it needs, the missing ones said in order"] = function(t)
        local c = ns.make.client({ UIParent = {} })
        t.ok(type(c.macroPopup) == "function", "the client has a macro popup reader")
        if type(c.macroPopup) ~= "function" then return end
        local h, missing = c.macroPopup()
        t.eq(h, nil)
        t.eq(missing, { "MacroPopupFrame", "IconSelectorPopupFrameTemplateMixin", "IconDataProviderMixin",
                        "GetMacroIcons", "MacroPopupFrame.IconSelector" })
        local h2, missing2 = handle(gameEnv({ without = { "IconDataProviderMixin" } }))
        t.eq(h2, nil)
        t.eq(missing2, { "IconDataProviderMixin" })
        local h3, missing3 = handle(gameEnv({ without = { "MacroPopupFrame.IconSelector" } }))
        t.eq(h3, nil)
        t.eq(missing3, { "MacroPopupFrame.IconSelector" })
        local h4, missing4 = handle(gameEnv())
        t.ok(type(h4) == "table", "all there: a handle")
        t.eq(missing4, nil)
    end,

    ["macro icons client: the icons read through the provider the window made, none before it opened"] = function(t)
        local env = gameEnv()
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        t.eq(h.shown(), false)
        t.eq(h.count(), nil, "no provider yet")
        t.eq(h.icon(1), nil)
        open(env, { 101, "Interface\\Icons\\INV_Misc_Gem_01" })
        t.eq(h.shown(), true)
        t.eq(h.count(), 2)
        t.eq(h.icon(1), 101)
        t.eq(h.icon(2), "Interface\\Icons\\INV_Misc_Gem_01")
        t.eq(h.icon(3), nil)
    end,

    ["macro icons client: a list shown through the provider, the full list back on nil"] = function(t)
        local env = gameEnv()
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        t.eq(h.show({ 102 }), false, "no provider before the window opens")
        open(env, { 101, 102, 103 })
        local p = env.MacroPopupFrame.iconDataProvider
        local orig = { p.GetNumIcons, p.GetIconByIndex, p.GetIndexOfIcon }
        t.eq(h.show({ 103, 101 }), true)
        t.eq(p:GetNumIcons(), 2)
        t.eq(p:GetIconByIndex(1), 103)
        t.eq(p:GetIconByIndex(2), 101)
        t.eq(p:GetIndexOfIcon(101), 2, "the editor finds the chosen icon in what it shows")
        t.ok(env.MacroPopupFrame.updates + env.MacroPopupFrame.IconSelector.selections >= 1, "the grid redrawn")
        t.eq(h.count(), 3, "the reader still sees every icon")
        t.eq(h.icon(3), 103)
        t.eq(h.show({ 102 }), true, "a second list over the first")
        t.eq(p:GetNumIcons(), 1)
        t.eq(h.show(nil), true)
        t.eq({ p.GetNumIcons, p.GetIconByIndex, p.GetIndexOfIcon }, orig, "the provider's own calls back")
        t.eq(p:GetNumIcons(), 3)
    end,

    ["macro icons client: a new provider after the window opens again is the one filtered"] = function(t)
        local env = gameEnv()
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        open(env, { 101, 102 })
        h.show({ 102 })
        h.show(nil)
        close(env)
        open(env, { 201, 202, 203 })
        local second = env.MacroPopupFrame.iconDataProvider
        t.eq(h.count(), 3)
        t.eq(h.icon(1), 201)
        t.eq(h.show({ 203 }), true)
        t.eq(second:GetNumIcons(), 1)
        t.eq(h.show(nil), true)
        t.eq(second:GetNumIcons(), 3)
    end,

    ["macro icons client: the search box and three filter buttons, plain frames, made once"] = function(t)
        local env = gameEnv()
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        local typed, chosen = {}, {}
        local b = h.addBox({ onText = function(s) typed[#typed + 1] = s end,
                             onFilter = function(kind) chosen[#chosen + 1] = kind end })
        t.ok(type(b) == "table", "a box handle")
        if type(b) ~= "table" then return end
        local boxes = find(env, "EditBox")
        t.eq(#boxes, 1)
        t.eq(boxes[1].parent, env.MacroPopupFrame)
        t.eq(boxes[1].template, "SearchBoxTemplate")
        local buttons = find(env, "Button")
        t.eq(#buttons, 3)
        for _, f in ipairs(env.made) do
            t.ok(not tostring(f.template or ""):find("Secure"), "never a secure template")
        end
        boxes[1].text = "fire"
        boxes[1].scripts.OnTextChanged(boxes[1], true)
        t.eq(typed, { "fire" })
        buttons[2].scripts.OnClick(buttons[2], "LeftButton")
        buttons[3].scripts.OnClick(buttons[3], "LeftButton")
        buttons[1].scripts.OnClick(buttons[1], "LeftButton")
        t.eq(chosen, { "spells", "items", "all" })
        b.setText("")
        t.eq(boxes[1].text, "")
        b.hint("3 matches")
        local said = false
        for _, f in ipairs(find(env, "FontString")) do if f.text == "3 matches" then said = true end end
        t.ok(said, "the hint is shown")
        t.eq(h.addBox({}), b, "a second ask gives the same box")
        t.eq(#find(env, "EditBox"), 1)
    end,

    ["macro icons client: no edit box, no search box"] = function(t)
        local env = gameEnv({ noEditBox = true })
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        t.eq(h.addBox({}), nil)
        t.eq(#find(env, "Button"), 0, "no buttons left behind")
    end,

    ["macro icons client: opening and closing told through one hook each"] = function(t)
        local env = gameEnv()
        local h = handle(env)
        if type(h) ~= "table" then t.ok(false, "a handle"); return end
        local seen = {}
        h.onShow(function() seen[#seen + 1] = "show1" end)
        h.onShow(function() seen[#seen + 1] = "show2" end)
        h.onHide(function() seen[#seen + 1] = "hide" end)
        open(env)
        close(env)
        t.eq(seen, { "show2", "hide" }, "the last one given is told")
        t.eq(#(env.MacroPopupFrame.hooks.OnShow or {}), 1, "hooked once")
        t.eq(#(env.MacroPopupFrame.hooks.OnHide or {}), 1)
        t.eq(env.MacroPopupFrame.scripts.OnShow, nil, "the window's own script is not replaced")
    end,

    ["macro icons client: spell names and icons from the spellbook, newer calls first"] = function(t)
        local env = { UIParent = {} }
        env.Enum = { SpellBookSpellBank = { Player = 0 } }
        local lines = { { itemIndexOffset = 0, numSpellBookItems = 2 }, { itemIndexOffset = 2, numSpellBookItems = 1 } }
        local items = { { name = "Fireball", iconID = 101 }, { name = "Frostbolt", iconID = 102 },
                        { name = "Fire Ward", iconID = 103 } }
        env.C_SpellBook = {
            GetNumSpellBookSkillLines = function() return #lines end,
            GetSpellBookSkillLineInfo = function(i) return lines[i] end,
            GetSpellBookItemInfo = function(i, bank) if bank == 0 then return items[i] end end,
        }
        local c = ns.make.client(env)
        t.ok(type(c.spellbookIcons) == "function", "a spellbook reader")
        if type(c.spellbookIcons) ~= "function" then return end
        t.eq(c.spellbookIcons(), { { name = "Fireball", icon = 101 }, { name = "Frostbolt", icon = 102 },
                                   { name = "Fire Ward", icon = 103 } })
        local old = { UIParent = {} }
        old.GetNumSpellTabs = function() return 1 end
        old.GetSpellTabInfo = function() return "General", "tab", 0, 2 end
        old.GetSpellBookItemName = function(i, book) if book == "spell" then return ({ "Attack", "Fireball" })[i] end end
        old.GetSpellBookItemTexture = function(i, book)
            if book == "spell" then return ({ 1, "Interface\\Icons\\Fire" })[i] end
        end
        t.eq(ns.make.client(old).spellbookIcons(), { { name = "Attack", icon = 1 },
                                                     { name = "Fireball", icon = "Interface\\Icons\\Fire" } })
        t.eq(ns.make.client({ UIParent = {} }).spellbookIcons(), nil, "neither: not known")
        old.GetSpellTabInfo = function() error("raised") end
        t.eq(ns.make.client(old).spellbookIcons(), nil, "a read that raised: not known")
    end,

    ["macro icons capture: every new read is named and has its capture field"] = function(t)
        for _, name in ipairs({ "MacroPopupFrame", "MacroPopupFrame.IconSelector",
                                "IconSelectorPopupFrameTemplateMixin", "IconDataProviderMixin", "GetMacroIcons",
                                "GetMacroItemIcons", "GetSpellBookItemTexture", "GetSpellBookItemName",
                                "GetNumSpellTabs", "GetSpellTabInfo", "C_SpellBook.GetNumSpellBookSkillLines",
                                "C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.GetSpellBookItemInfo",
                                "GetItemIcon", "C_Item.GetItemIconByID" }) do
            t.ok(listed(name), name .. " in Diag.NAMES")
        end
        local e = { IconSelectorPopupFrameTemplateMixin = { SetSelectedCallback = function() end },
                    IconDataProviderMixin = { GetNumIcons = function() end },
                    GetMacroIcons = function(into) into[1] = 134400; into[2] = 134401 end,
                    MacroPopupFrame = { IconSelector = {} } }
        local s = shapes(e)
        local function field(name)
            return type(s[name]) == "table" and s[name] or { values = {}, types = {} }
        end
        t.eq((field("iconSelectorMixin").values.v1 or {}).SetSelectedCallback, "function")
        t.eq((field("iconDataProviderMixin").values.v1 or {}).GetNumIcons, "function")
        t.eq(field("macroIcons").values.v1, 2, "how many icons the client fills in")
        t.eq(field("macroIcons").values.v2, 134400, "the first of them")
        t.eq((field("macroPopup").values.v1 or {}).IconSelector, "table")
        local none = shapes({})
        t.eq(type(none.macroPopup) == "table" and none.macroPopup.types[1], "nil", "not loaded: recorded as nothing")
        t.eq(type(none.macroIcons) == "table" and none.macroIcons.ok, false)
    end,

    ["macro icons fake: the window, its box and its controls, as the real client"] = function(t)
        local c = ns.make.fakeClient()
        t.ok(type(c.macroPopup) == "function" and type(c.setMacroPopup) == "function", "fake reader and setter")
        if type(c.macroPopup) ~= "function" or type(c.setMacroPopup) ~= "function" then return end
        local h, missing = c.macroPopup()
        t.eq(h, nil)
        t.eq(missing, { "MacroPopupFrame" }, "not loaded")
        c.setMacroPopup({ missing = { "IconDataProviderMixin" } })
        local h2, missing2 = c.macroPopup()
        t.eq(h2, nil)
        t.eq(missing2, { "IconDataProviderMixin" })
        c.setMacroPopup({ icons = { 101, 102, 103 } })
        local h3 = c.macroPopup()
        if type(h3) ~= "table" then t.ok(false, "a handle"); return end
        local p = c.macroPopups[#c.macroPopups]
        t.eq(h3.count(), nil, "closed: no provider")
        t.eq(h3.show({ 102 }), false)
        local seen, typed = {}, {}
        h3.onShow(function() seen[#seen + 1] = "show" end)
        h3.onHide(function() seen[#seen + 1] = "hide" end)
        local b = h3.addBox({ onText = function(s) typed[#typed + 1] = s end, onFilter = function() end })
        t.ok(type(b) == "table", "a box")
        t.eq(h3.addBox({}), b, "made once")
        p.open()
        t.eq(h3.count(), 3)
        t.eq(h3.icon(2), 102)
        t.eq(h3.show({ 103 }), true)
        t.eq(p.visible(), { 103 })
        p.click(1)
        t.eq(p.selected, 103)
        t.eq(p.type("fi"), true)
        t.eq(typed, { "fi" })
        t.eq(p.box.text, "fi")
        b.setText("")
        t.eq(p.box.text, "")
        t.eq(typed, { "fi", "" }, "the box changed by the add-on is told too")
        h3.show(nil)
        t.eq(p.visible(), { 101, 102, 103 })
        p.close()
        t.eq(seen, { "show", "hide" })
        c.setFrames(false)
        c.setMacroPopup({ icons = { 1 } })
        local h4 = c.macroPopup()
        t.eq(type(h4) == "table" and h4.addBox({}), nil, "no frames: no box")
        t.eq(c.spellbookIcons(), nil, "spellbook not known until set")
        c.setSpellbook({ { name = "Fireball", icon = 101 } })
        t.eq(c.spellbookIcons(), { { name = "Fireball", icon = 101 } })
        t.eq(c.spellbookReads, 2, "each read counted")
    end,
}
