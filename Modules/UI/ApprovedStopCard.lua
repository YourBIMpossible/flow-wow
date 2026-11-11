-- The approved glossy card, implemented with ordinary WoW frames and textures.
-- It owns its layout and fonts. It does not cast, route, or alter protected UI.
local addonName, ns = ...
local UI = {}
ns.approvedStopCard = UI

local media = "Interface\\AddOns\\" .. addonName .. "\\Media\\FlowCard\\"
local P = { text = { .969, .941, .890 }, muted = { .773, .773, .702 }, gold = { .922, .796, .549 },
    border = { .710, .604, .380 }, dark = { .065, .057, .041 } }
UI.palette = P
UI.media = media
local PROF = {
    Fishing = "Trade_Fishing", Mining = "Trade_Mining", Blacksmithing = "Trade_BlackSmithing",
    Herbalism = "Trade_Herbalism", Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice",
    Alchemy = "Trade_Alchemy", Enchanting = "Trade_Engraving", Engineering = "Trade_Engineering",
    Tailoring = "Trade_Tailoring", Leatherworking = "Trade_LeatherWorking", Skinning = "INV_Misc_Pelt_Wolf_01",
}

function UI.ResolveIcon(model)
    if model.icon then return model.icon end
    local name = PROF[model.profession]
    return name and ("Interface\\Icons\\" .. name) or "Interface\\Icons\\INV_Misc_Map_01"
end

local function color(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or 1) end
local function fill(parent, path, level)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, level or 0)
    t:SetAllPoints(parent); t:SetTexture(path)
    return t
end
local function border(parent, c, alpha, inset)
    inset = inset or 0
    local function edge(a, b, horizontal)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint(a, parent, a, a:find("LEFT") and inset or -inset, a:find("TOP") and -inset or inset)
        t:SetPoint(b, parent, b, b:find("LEFT") and inset or -inset, b:find("TOP") and -inset or inset)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        color(t, c, alpha)
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
end
local function setFont(s, size, medium)
    local font = UI.media .. "Fonts\\FlowSans-" .. (medium and "Medium" or "Regular") .. ".ttf"
    local ok, success = pcall(s.SetFont, s, font, size, "")
    if not ok or success == false then
        s:SetFont("Fonts\\ARIALN.TTF", size, "")
        UI.fontFallback = true
    end
end
local function text(parent, size, medium, c)
    local s = parent:CreateFontString(nil, "OVERLAY")
    setFont(s, size, medium)
    s:SetTextColor(c[1], c[2], c[3], 1)
    s:SetJustifyH("LEFT"); s:SetJustifyV("TOP"); s:SetWordWrap(true)
    if s.SetNonSpaceWrap then s:SetNonSpaceWrap(true) end
    s:SetShadowColor(0, 0, 0, .40); s:SetShadowOffset(0, -1)
    return s
end
local function measure(s, width, value)
    s:ClearAllPoints(); s:SetWidth(math.max(1, width)); s:SetHeight(0); s:SetText(value or "")
    return math.ceil(s:GetStringHeight() or 0)
end
local function put(s, parent, x, y, width, value)
    local h = measure(s, width, value)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    s:SetHeight(math.max(1, h)); s:Show()
    return h
end
local function clearTip() if GameTooltip then GameTooltip:Hide() end end
local function safeClick(card, fn)
    if not fn then return end
    local ok, err = pcall(fn)
    if not ok then
        card.lastError = tostring(err)
        if card.options.onError then card.options.onError(card.lastError) end
    end
end

local function newButton(parent, card)
    local b = CreateFrame("Button", nil, parent)
    b.normal = fill(b, UI.media .. "Textures\\button-secondary.tga")
    b.hover = fill(b, UI.media .. "Textures\\button-hover.tga", 1); b.hover:Hide()
    b.pressed = fill(b, UI.media .. "Textures\\button-pressed.tga", 2); b.pressed:Hide()
    border(b, P.border, 1); border(b, P.dark, .8, 1)
    b.label = text(b, 13, true, P.gold); b.label:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self) if self.allowed then self.hover:Show() end end)
    b:SetScript("OnLeave", function(self) self.hover:Hide(); self.pressed:Hide() end)
    b:SetScript("OnMouseDown", function(self) if self.allowed then self.pressed:Show() end end)
    b:SetScript("OnMouseUp", function(self) self.pressed:Hide() end)
    b:SetScript("OnClick", function(self) if self.allowed then safeClick(card, self.callback) end end)
    return b
end

function UI.Create(parent, options)
    options = options or {}
    parent = parent or UIParent
    local f = CreateFrame("Frame", options.name, parent)
    f.options = options; f.model = {}; f.expanded = false; f.rows = {}; f.buttons = {}
    f:SetFrameStrata(options.strata or "FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:SetSize(380, 240)
    fill(f, UI.media .. "Textures\\frame-material.tga")
    border(f, P.border, 1); border(f, P.dark, 1, 1); border(f, { .42, .35, .22 }, 1, 2)

    f.chrome = CreateFrame("Frame", nil, f)
    f.chrome:SetPoint("TOPLEFT", 4, -4); f.chrome:SetPoint("TOPRIGHT", -4, -4); f.chrome:SetHeight(38)
    fill(f.chrome, UI.media .. "Textures\\header-glass.tga")
    f.brand = text(f.chrome, 12, true, P.text)
    f.brand:SetPoint("LEFT", 12, 0); f.brand:SetText("Flow Stop")
    f.brand:SetWidth(180); f.brand:SetHeight(18)
    f.chrome:EnableMouse(true); f.chrome:RegisterForDrag("LeftButton")
    f.chrome:SetScript("OnDragStart", function() f:StartMoving(); f.moving = true end)
    f.chrome:SetScript("OnDragStop", function()
        f:StopMovingOrSizing(); f.moving = false
        if options.savePoint then
            local a, _, b, x, y = f:GetPoint()
            options.savePoint({ a, b, x, y })
        end
    end)

    f.close = newButton(f.chrome, f)
    f.close:SetPoint("RIGHT", -8, 0); f.close:SetSize(24, 24)
    f.close.label:SetText("×"); f.close.label:SetAllPoints(f.close)
    f.close.allowed = true; f.close.callback = function() f:Hide() end

    f.hero = CreateFrame("Frame", nil, f)
    f.hero:SetPoint("TOPLEFT", f.chrome, "BOTTOMLEFT", 7, -8)
    fill(f.hero, UI.media .. "Textures\\heading-glass.tga")
    border(f.hero, { .60, .52, .36 }, .45)
    f.icon = f.hero:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36); f.icon:SetPoint("TOPLEFT", 14, -14)
    f.icon:SetTexCoord(.04, .96, .04, .96)
    f.category = text(f.hero, 12, false, P.muted)
    f.title = text(f.hero, 19, true, P.text)
    f.titleHit = CreateFrame("Frame", nil, f.hero)
    f.titleHit:EnableMouse(true)
    f.titleHit:SetScript("OnEnter", function(self)
        if not (f.titleTruncated and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(f.model.fullTitle or f.model.title or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.titleHit:SetScript("OnLeave", clearTip)
    f.subtitle = text(f.hero, 12, false, P.muted)
    f.distance = text(f.hero, 12, false, P.gold)

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.body = CreateFrame("Frame", nil, f.scroll)
    f.scroll:SetScrollChild(f.body)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(_, delta)
        local value = math.max(0, math.min(f.scrollRange or 0, (f.scroll:GetVerticalScroll() or 0) - delta * 30))
        f.scroll:SetVerticalScroll(value); f.scrollbar:SetValue(value)
    end)
    f.scrollbar = CreateFrame("Slider", nil, f)
    f.scrollbar:SetWidth(8); f.scrollbar:SetOrientation("VERTICAL")
    f.scrollbar:SetMinMaxValues(0, 0); f.scrollbar:SetValueStep(1)
    f.scrollbar:SetThumbTexture(UI.media .. "Textures\\scroll-thumb.tga")
    if f.scrollbar.GetThumbTexture then
        local thumb = f.scrollbar:GetThumbTexture()
        if thumb then thumb:SetSize(6, 28) end
    end
    f.scrollbar:SetScript("OnValueChanged", function(_, value) f.scroll:SetVerticalScroll(value) end)

    f.more = CreateFrame("Button", nil, f.body)
    f.more.label = text(f.more, 12, true, P.gold)
    f.more.label:SetAllPoints(f.more)
    f.more:SetScript("OnClick", function()
        f.expanded = not f.expanded; f:Layout()
    end)
    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetPoint("BOTTOMLEFT", 14, 10); f.footer:SetPoint("BOTTOMRIGHT", -14, 10)

    local function row(index, c, medium, size)
        local s = f.rows[index]
        if not s then s = text(f.body, size, medium, c); f.rows[index] = s
        else setFont(s, size, medium) end
        s:SetTextColor(c[1], c[2], c[3], 1)
        return s
    end

    function f:Layout()
        if self.layingOut then return end
        self.layingOut = true
        local m, o = self.model, self.options
        local available = (parent:GetWidth() or 1024) - 24
        local w = math.min(o.width or 380, math.max(160, available))
        self:SetWidth(w)
        local inner = w - 22
        self.hero:SetWidth(inner)
        local tw = inner - 80
        local categoryH = put(self.category, self.hero, 64, 13, tw, m.category or "Next stop")
        if self.title.SetMaxLines then self.title:SetMaxLines(0) end
        local titleH = measure(self.title, tw, m.title or "Next stop")
        self.titleTruncated = titleH > 52
        if self.title.SetMaxLines then self.title:SetMaxLines(2) end
        self.title:SetPoint("TOPLEFT", self.hero, "TOPLEFT", 64, -(17 + categoryH))
        self.title:SetHeight(math.min(titleH, 52)); self.title:Show()
        self.titleHit:ClearAllPoints(); self.titleHit:SetAllPoints(self.title)
        local heroContent = categoryH + 4 + math.min(titleH, 52)
        if m.subtitle and m.subtitle ~= "" then
            local h = put(self.subtitle, self.hero, 64, 17 + heroContent, tw, m.subtitle)
            heroContent = heroContent + h + 5
        else self.subtitle:Hide() end
        local heroH = math.max(40, heroContent) + 28
        self.hero:SetHeight(heroH)
        if m.distance then
            self.distance:SetText(m.distance); self.distance:SetWidth(70); self.distance:SetHeight(18)
            self.distance:ClearAllPoints(); self.distance:SetPoint("RIGHT", self.chrome, "RIGHT", -42, 0); self.distance:Show()
        else self.distance:Hide() end

        -- Actions wrap into new rows. Their actual labels are measured first.
        local actions, fw, x, y, rowH = m.actions or {}, w - 28, 0, 0, 36
        local footerH = 0
        for i, action in ipairs(actions) do
            local b = self.buttons[i]
            if not b then b = newButton(self.footer, self); self.buttons[i] = b end
            b.label:SetText(action.label or "Action")
            local share = #actions <= 2 and (fw - 8 * (#actions - 1)) / #actions or 0
            local desired = math.min(fw, math.max(112, share, math.ceil(b.label:GetStringWidth()) + 24))
            if x > 0 and x + desired > fw then x, y = 0, y + rowH + 8; rowH = 36 end
            local labelH = measure(b.label, desired - 20, action.label or "Action")
            local bh = math.max(36, labelH + 14)
            b:SetSize(desired, bh); b.label:SetHeight(labelH)
            b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", self.footer, "TOPLEFT", x, -y)
            b.allowed = action.enabled ~= false
            b.callback = action.callback
            b.normal:SetTexture(UI.media .. "Textures\\button-" .. (action.primary and "primary" or "secondary") .. ".tga")
            b:SetAlpha(b.allowed and 1 or .48)
            if b.allowed then b:Enable() else b:Disable(); b.hover:Hide(); b.pressed:Hide() end
            b:Show(); x = x + desired + 8; rowH = math.max(rowH, bh); footerH = y + rowH
        end
        for i = #actions + 1, #self.buttons do self.buttons[i]:Hide(); self.buttons[i].callback = nil end
        self.footer:SetHeight(math.max(1, footerH))
        if footerH > 0 then self.footer:Show() else self.footer:Hide() end

        local maxH = math.min(o.maxHeight or 620, (parent:GetHeight() or 768) - 24)
        local top = 4 + 38 + 8 + heroH + 12
        local bottom = footerH > 0 and (footerH + 24) or 12
        local bw = w - 44
        local function bodyLayout(width)
            local n, cy = 0, 0
            local function add(value, c, medium, size)
                if not value or value == "" then return end
                n = n + 1
                local s = row(n, c, medium, size or 14)
                cy = cy + put(s, self.body, 0, cy, width, value) + 7
            end
            add(m.blocked and ("Blocked: " .. m.blocked), { 1, .55, .48 }, false, 13)
            add(m.destination, P.gold, true)
            add(m.note, P.muted, false, 12)
            for _, line in ipairs(m.details or {}) do add(line, P.text, false) end
            if #(m.alternatives or {}) > 0 then
                if cy > 0 then cy = cy + 3 end
                self.more:ClearAllPoints(); self.more:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -cy)
                self.more:SetSize(width, 24)
                self.more.label:SetText((self.expanded and "− " or "+ ") .. "Other trainers (" .. #m.alternatives .. ")")
                self.more:Show(); cy = cy + 30
                if self.expanded then for _, name in ipairs(m.alternatives) do add(name, P.text, false, 13) end end
            else self.more:Hide() end
            for i = n + 1, #self.rows do self.rows[i]:Hide() end
            return math.max(1, cy - 7)
        end
        local natural = bodyLayout(bw)
        local bodyH = math.min(natural, math.max(32, maxH - top - bottom))
        self.scrollRange = math.max(0, natural - bodyH)
        if self.scrollRange > 0 then bw = bw - 12; natural = bodyLayout(bw); self.scrollRange = math.max(0, natural - bodyH) end
        self.body:SetWidth(bw); self.body:SetHeight(natural)
        self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 22, -top)
        self.scroll:SetSize(bw, bodyH)
        self.scrollbar:ClearAllPoints(); self.scrollbar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -15, -top)
        self.scrollbar:SetHeight(bodyH); self.scrollbar:SetMinMaxValues(0, self.scrollRange)
        self.scrollbar:SetShown(self.scrollRange > 0)
        local value = math.min(self.scrollRange, self.scroll:GetVerticalScroll() or 0)
        self.scroll:SetVerticalScroll(value); self.scrollbar:SetValue(value)
        self:SetHeight(top + bodyH + bottom)
        self.layingOut = false
    end

    function f:SetModel(model)
        if self.modelKey ~= model.key then self.expanded = false; self.scroll:SetVerticalScroll(0) end
        self.modelKey = model.key
        self.model = model
        local atlasOK = false
        if model.iconAtlas and self.icon.SetAtlas then atlasOK = pcall(self.icon.SetAtlas, self.icon, model.iconAtlas, false) end
        if not atlasOK then self.icon:SetTexture(UI.ResolveIcon(model)) end
        self:Layout()
    end
    f:SetScript("OnSizeChanged", function() if not f.layingOut then f:Layout() end end)
    f:SetScript("OnHide", function() f:StopMovingOrSizing(); f.moving = false; clearTip() end)
    f:Hide()
    f.flowApprovedCard = true
    return f
end
