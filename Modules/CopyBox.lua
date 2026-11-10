local _, ns = ...

-- The copy window: text you can select and copy out of the game. The game's
-- chat box can't be selected, so a test failure or a web address Flow prints
-- can't be copied from there. This window shows the text in a box you can
-- select: Ctrl+A selects it all, Ctrl+C copies, then paste it anywhere (a
-- web address into your browser).
--   /flow copy          what Flow said in chat lately (the last 300 lines)
--   /flow test          opens it with the results when a test fails
--   the Copy button     on the Flow Chat window (/claude): the conversation

local C = {}
ns.copyBox = C

local MAX_LINES = 300
C.lines = {}   -- what Flow printed lately, as plain text, oldest first

-- Text without the game's colour and link codes: what you'd want to paste.
-- An item or quest link keeps its name ("[Linen Cloth]"); icons go.
function C.Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("||", "|")
    return s
end

-- Web addresses in some text (http://..., https://..., www....), in order.
function C.Links(s)
    local out = {}
    for url in tostring(s or ""):gmatch("https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+") do
        out[#out + 1] = (url:gsub("[%.,;:!%?%)]+$", ""))   -- (not the full stop after it)
    end
    for url in tostring(s or ""):gmatch("%f[%w]www%.[%w%-%._~:/%?#@!%$&'%*%+,;=%%]+") do
        url = url:gsub("[%.,;:!%?%)]+$", "")
        local dup = false
        for _, u in ipairs(out) do if u:find(url, 1, true) then dup = true end end
        if not dup then out[#out + 1] = url end
    end
    return out
end

-- Keeps one line Flow printed (ns:Print sends everything here).
function C.Add(msg)
    local l = C.lines
    l[#l + 1] = date("%H:%M:%S") .. "  " .. C.Plain(msg)
    while #l > MAX_LINES do table.remove(l, 1) end
end

-- Everything Flow prints to chat is kept for /flow copy too.
local basePrint = ns.Print
function ns:Print(msg)
    pcall(C.Add, msg)
    return basePrint(self, msg)
end

local box
local function build()
    local f = CreateFrame("Frame", "FlowCopyBox", UIParent)
    f:SetSize(600, 380)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Copy text", "Interface\\Icons\\INV_Misc_Note_01")
    ns:MakeMovable(f, {}, true)   -- Shift-drag moves it (not saved: it opens in the middle)
    tinsert(UISpecialFrames, "FlowCopyBox")   -- Esc closes it
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 12, 12); f.hint:SetPoint("BOTTOMRIGHT", -200, 12)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetText("Ctrl+A selects all, Ctrl+C copies. Esc closes.")

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 12, -(ns.theme.TITLE_H + 8))
    f.scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    f.edit = CreateFrame("EditBox", nil, f.scroll)
    f.edit:SetMultiLine(true)
    f.edit:SetAutoFocus(false)
    f.edit:SetFontObject(ChatFontNormal)
    f.edit:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 550)
    f.edit:SetMaxLetters(0)
    f.scroll:SetScrollChild(f.edit)
    f.scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then f.edit:SetWidth(w) end end)
    -- Read-only: typing puts the text back (you can still select and copy).
    f.edit:SetScript("OnTextChanged", function(self, user)
        if user and f.text and self:GetText() ~= f.text then self:SetText(f.text); self:HighlightText() end
    end)
    f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
        -- Keep the cursor in view while you select with the keyboard.
        local top, view = f.scroll:GetVerticalScroll(), f.scroll:GetHeight()
        y = -y
        if y < top then f.scroll:SetVerticalScroll(y)
        elseif y + h > top + view then f.scroll:SetVerticalScroll(y + h - view) end
    end)
    -- A click on the empty part of the box puts the cursor in it too.
    f.scroll:EnableMouse(true)
    f.scroll:SetScript("OnMouseDown", function() f.edit:SetFocus() end)

    -- The web addresses in the text, one button each: click selects just
    -- that one, ready for Ctrl+C.
    f.linkBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.linkBtn:SetSize(170, 22)
    f.linkBtn:SetPoint("BOTTOMRIGHT", -12, 9)
    f.linkBtn:SetScript("OnClick", function() C:NextLink() end)
    f.linkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Web addresses")
        GameTooltip:AddLine("Each click selects the next web address in the text. Then Ctrl+C, and paste it into your browser.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

-- Shows `lines` (a list, or one string) under `title`, all selected.
function C:Show(title, lines)
    box = box or build()
    local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
    text = C.Plain(text)
    box.text = text
    box.links, box.linkAt = C.Links(text), 0
    box.head.text:SetText(title or "Copy text")
    box.linkBtn:SetText(#box.links > 0 and string.format("Select a web address (%d)", #box.links) or "No web addresses")
    box.linkBtn:SetEnabled(#box.links > 0)
    box:Show()
    box.edit:SetText(text)
    box.edit:SetCursorPosition(0)
    box.scroll:SetVerticalScroll(0)
    box.edit:SetFocus()
    box.edit:HighlightText()
    return box
end

-- Selects the next web address in the box (after the last one picked).
function C:NextLink()
    if not (box and box.links and #box.links > 0) then return end
    box.linkAt = box.linkAt % #box.links + 1
    local s, e = box.text:find(box.links[box.linkAt], 1, true)
    if not s then return end
    box.edit:SetFocus()
    box.edit:HighlightText(s - 1, e)
    box.edit:SetCursorPosition(e)
    box.linkBtn:SetText(string.format("Web address %d of %d", box.linkAt, #box.links))
end

function C:Hide() if box then box:Hide() end end
function C.Frame() return box end   -- (tests)

ns.commands.copy = function()
    if #C.lines == 0 then ns:Print("nothing to copy yet: Flow hasn't said anything in chat since the last /reload") return end
    C:Show(string.format("What Flow said lately (%d lines)", #C.lines), C.lines)
end
