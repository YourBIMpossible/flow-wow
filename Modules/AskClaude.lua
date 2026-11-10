-- Ask Claude from inside the game: a poor man's chat through files, with
-- tools\claude-bridge.ps1 running on your PC.
--   /claude make the arrow green      (or /flow ask ...)
--     Flow saves the message and reloads the UI: WoW only writes add-on
--     data to disk on a reload. The bridge sees it, asks Claude Code (in the
--     Flow folder, so it can change Flow itself), and writes the answer to
--     Learned\ClaudeInbox.lua.
--   /claude          the chat window: your questions and the answers, a box
--                    to type in, Send, and Check now
--   /claude check    look for answers (reloads: that's when WoW reads the
--                    answer file, and any code Claude changed)
-- Answers show in chat as "Claude: ...". Nothing goes anywhere but files on
-- your own PC; the bridge only runs while you start it.

local _, ns = ...
local AC = {}
ns.askClaude = AC

local MAX_OUTBOX = 20
local ORANGE = "d97757"

function AC.Entry(id, text, now)
    local _, class = UnitClass("player")
    return { id = id, text = text, at = now or time(), char = UnitName("player"), class = class,
             level = UnitLevel("player"), zone = GetZoneText and GetZoneText() or "?" }
end

-- Answers you haven't seen, in order; marks them seen and drops the
-- messages they answer from the outbox.
function AC.TakeNew(inbox, chat)
    local new = {}
    for _, r in ipairs(inbox or {}) do
        if r.id and not chat.seen[r.id] then
            chat.seen[r.id] = true
            new[#new + 1] = r
        end
        if r.replyTo then
            for i = #chat.outbox, 1, -1 do
                if chat.outbox[i].id == r.replyTo then table.remove(chat.outbox, i) end
            end
        end
    end
    table.sort(new, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return new
end

local function show(r)
    local first = true
    for line in tostring(r.text or ""):gmatch("[^\n]+") do
        print((first and ("|cff" .. ORANGE .. "Claude:|r ") or "  ") .. line)
        first = false
    end
end

function AC:Send(text)
    local chat = ns.db.chat
    local id = chat.nextId
    chat.nextId = id + 1
    chat.outbox[#chat.outbox + 1] = AC.Entry(id, text)
    while #chat.outbox > MAX_OUTBOX do table.remove(chat.outbox, 1) end
    -- What you asked, kept (the last 20) so the chat window can show it next
    -- to Claude's answer.
    chat.sent[id] = text
    for old in pairs(chat.sent) do if old <= id - MAX_OUTBOX then chat.sent[old] = nil end end
    ns:Print("sent to Claude (reloading so it's saved where Claude can read it)...")
    ReloadUI()   -- (from your slash command or the Send button: allowed)
end

-------------------------------------------------------------------------------
-- The chat window (/claude on its own): your questions and Claude's answers,
-- a box to type in, Send and "Check now". Sending and checking reload the UI
-- for a moment: WoW only writes and reads add-on files on a reload.
-- (/claude used to just reload, which looked like it did nothing.)
-------------------------------------------------------------------------------

-- The conversation as lines, oldest first, at most `max` exchanges:
-- answers (with what you asked), then messages still waiting.
function AC.History(inbox, chat, max)
    local out = {}
    for _, r in ipairs(inbox or {}) do
        local q = r.replyTo and chat.sent and chat.sent[r.replyTo]
        out[#out + 1] = { q = q, a = r.text, id = r.id or 0 }
    end
    table.sort(out, function(x, y) return x.id < y.id end)
    for _, m in ipairs(chat.outbox or {}) do out[#out + 1] = { q = m.text, waiting = true, id = 1e9 + (m.id or 0) } end
    local lines = {}
    for i = math.max(1, #out - (max or 6) + 1), #out do
        local e = out[i]
        if e.q then lines[#lines + 1] = "|cff88ccffYou:|r " .. e.q end
        if e.waiting then lines[#lines + 1] = "|cff888888(waiting for Claude...)|r"
        elseif e.a then lines[#lines + 1] = "|cff" .. ORANGE .. "Claude:|r " .. e.a end
    end
    return lines
end

local box
local function buildBox()
    local f = CreateFrame("Frame", "FlowAskClaude", UIParent)
    f:SetSize(480, 320)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Chat", "Interface\\Icons\\INV_Misc_Book_09")
    ns:MakeMovable(f, ns.db.chat, true)
    tinsert(UISpecialFrames, "FlowAskClaude")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    f.log = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.log:SetPoint("TOPLEFT", 12, -32); f.log:SetPoint("TOPRIGHT", -12, -32)
    f.log:SetHeight(200)
    f.log:SetJustifyH("LEFT"); f.log:SetJustifyV("BOTTOM")
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 40); f.status:SetPoint("BOTTOMRIGHT", -12, 40)
    f.status:SetJustifyH("LEFT")
    f.edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.edit:SetSize(236, 22)   -- (room for Send, Check now and Copy)
    f.edit:SetPoint("BOTTOMLEFT", 18, 10)
    f.edit:SetAutoFocus(false)
    f.edit:SetMaxLetters(1000)   -- (the game's chat box stops at 255)
    local function send()
        local text = (f.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then f.status:SetText("Type a message first.") return end
        f.edit:SetText(""); f.edit:ClearFocus()
        AC:Send(text)
    end
    f.edit:SetScript("OnEnterPressed", send)
    f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.send:SetSize(60, 22); f.send:SetText("Send")
    f.send:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
    f.send:SetScript("OnClick", send)
    f.check = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.check:SetSize(80, 22); f.check:SetText("Check now")
    f.check:SetPoint("LEFT", f.send, "RIGHT", 4, 0)
    f.check:SetScript("OnClick", function()
        ns:Print("checking for Claude's answers (reloading)...")
        ReloadUI()
    end)
    -- Copy: the whole conversation in the copy window (select, Ctrl+C; web
    -- addresses in Claude's answers can be picked out one by one).
    f.copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copy:SetSize(56, 22); f.copy:SetText("Copy")
    f.copy:SetPoint("LEFT", f.check, "RIGHT", 4, 0)
    f.copy:SetScript("OnClick", function()
        local lines = AC.History(ns.claudeInbox, ns.db.chat, 20)
        if #lines == 0 then f.status:SetText("Nothing to copy yet.") return end
        ns.copyBox:Show("Flow Chat: the conversation", lines)
    end)
    f:Hide()
    return f
end

-- `draft`: text to put in the box to finish (a message too long for the chat box).
function AC:Open(draft)
    box = box or buildBox()
    local chat = ns.db.chat
    local lines = AC.History(ns.claudeInbox, chat, 6)
    box.log:SetText(#lines > 0 and table.concat(lines, "\n")
        or "|cff888888Ask anything about Flow or your character. A Claude session on your PC answers (docs/ASK-CLAUDE.md).|r")
    box.status:SetText(draft and "The chat box stops at 255 letters, so the end may be cut off: finish your message here (it takes 1000) and press Enter."
        or #chat.outbox > 0
        and string.format("Waiting on %d message(s). Answers arrive when you click Check now (it reloads), or at your next reload.", #chat.outbox)
        or "Send reloads your UI for a moment so Claude can read it. Claude answers while its session is watching.")
    box:Show()
    if draft then box.edit:SetText(draft) end
    box.edit:SetFocus()
    if draft then box.edit:SetCursorPosition(#draft) end
end

function AC.Frame() return box end   -- (tests)

local function check()
    local chat = ns.db.chat
    local new = AC.TakeNew(ns.claudeInbox, chat)
    for _, r in ipairs(new) do show(r) end
    if #new > 0 then ns:Print("(/claude opens the chat window)") end
    if #chat.outbox > 0 then
        ns:Print(string.format("waiting for Claude on %d message(s). /claude check looks again (it reloads). Is Claude watching (docs/ASK-CLAUDE.md)?", #chat.outbox))
    end
end
ns:On("PLAYER_LOGIN", function() C_Timer.After(3, function() pcall(check) end) end)

ns:OnLoad(function(saved)
    saved.chat = saved.chat or {}
    saved.chat.outbox = saved.chat.outbox or {}
    saved.chat.seen = saved.chat.seen or {}
    saved.chat.nextId = saved.chat.nextId or 1
    saved.chat.sent = saved.chat.sent or {}
end)

-- The game's chat box stops at 255 letters ("/claude " included), so a
-- message this long was probably cut off as you typed (Yang's was).
AC.CHAT_BOX_FULL = 240
function AC.MaybeCut(text) return #(text or "") >= AC.CHAT_BOX_FULL end

local function command(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then AC:Open() return end   -- the chat window
    if arg == "check" then ns:Print("checking for Claude's answers (reloading)..."); ReloadUI() return end
    -- Too long for the chat box: finish it in the Flow Chat window instead
    -- of sending the cut-off part.
    if AC.MaybeCut(arg) then AC:Open(arg) return end
    AC:Send(arg)
end
ns.commands.ask = command

-- /claude, and the short /ai and /si, unless another add-on already owns them.
AC.SLASHES = { "/claude", "/ai", "/si" }
ns:On("PLAYER_LOGIN", function()
    if not SlashCmdList then return end
    local n = 0
    for _, cmd in ipairs(AC.SLASHES) do
        if not (hash_SlashCmdList and hash_SlashCmdList[cmd:upper()]) then
            n = n + 1
            _G["SLASH_FLOWCLAUDE" .. n] = cmd
        end
    end
    if n > 0 then SlashCmdList.FLOWCLAUDE = command end
end)

ns:Register("help", "claude", { order = 90, title = "Ask Claude", lines = {
    "/claude (or /ai, /si): the chat window (your questions, Claude's answers, a box to type in).",
    "/ai <message>: ask straight away (it reloads to send). /ai check: look for answers (reloads).",
    "Long messages: type them in the window (the chat box stops at 255 letters).",
} })
