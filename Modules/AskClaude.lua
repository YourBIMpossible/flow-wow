-- Ask Claude from inside the game, with tools\claude-bridge.ps1 running on
-- your PC and a Claude session watching it.
--   /si              Claude connected: the chat window (your questions and
--                    the answers, a box to type in, Send, Reload). Not
--                    connected yet: how to connect, with a prompt to copy
--                    into Claude.
--   /si <message>    ask straight away (or /ai, /claude, /flow ask)
--   /si setup        the connect prompt again
--
-- Sending, without a reload: WoW never lets an add-on read or write a file
-- while the game runs (its saved data is written at a reload or logout), but
-- it writes a screenshot at once. So Send shows your message for a moment as
-- a block of black and white squares, takes a screenshot, and the bridge
-- decodes it (see "Live sending" below). Where that doesn't work, Send
-- reloads instead (the message is in Flow's saved data too, never lost).
--
-- Answers still need a reload: that's the only time WoW reads Flow's files
-- (Learned\ClaudeInbox.lua, written by the bridge). Reload in the chat
-- window when you want them, and any change Claude made to Flow with them.
-- Nothing goes anywhere but files on your own PC; the bridge only runs
-- while you start it, and deletes Flow's screenshots once it has read them.

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

-------------------------------------------------------------------------------
-- Connected? The bridge writes when it last ran into Learned\ClaudeInbox.lua
-- (ns.claudeBridge = { at = unix time }) every few minutes; WoW reads that
-- at a reload, so this is "watching as of your last reload".
-------------------------------------------------------------------------------

AC.FRESH = 30 * 60   -- seconds: the bridge writes every 10 minutes while it runs
function AC.Connected(bridge, now)
    return (type(bridge) == "table" and bridge.at and (now - bridge.at) <= AC.FRESH) and true or false
end
function AC:IsConnected() return AC.Connected(ns.claudeBridge, time()) end

-------------------------------------------------------------------------------
-- Live sending (off unless you turn it on): a screenshot. WoW never lets an
-- add-on write a file while the game runs, and WoW: Forever writes its chat
-- log only when the game closes (Yang's tests: empty through reloads and
-- /chatlog off and on, then all 40 KB at once when WoW exited). But
-- the game writes a screenshot to _forever_\Screenshots at once, and add-ons
-- may take one. So Send shows the message for a moment as black and white
-- squares in the top left of the screen (a simple barcode), takes a
-- screenshot, and hides them. The bridge decodes the squares, passes the
-- message on and deletes that screenshot. The message is in Flow's saved
-- data too, so a reload passes it on if this didn't.
-------------------------------------------------------------------------------

AC.CELL = 12     -- screen pixels per square
AC.MARGIN = 2    -- squares of white round the code
AC.MAGIC = { 1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1 }   -- "Flow's code starts here"

function AC.Who(e)
    return string.format("%s;%s;%s;%s", tostring(e.char), tostring(e.class), tostring(e.level), tostring(e.zone))
end
-- "FLOW1|<id>|<char;class;level;zone>|<text>"
function AC.ShotPayload(e)
    return string.format("FLOW1|%d|%s|%s", e.id, AC.Who(e), tostring(e.text or ""))
end

-- The squares (1 = black), read in rows of `cols`: the magic, then three
-- 16-bit numbers (most significant bit first): columns, length in bytes,
-- checksum (the bytes summed, mod 65536); then the bytes, 8 bits each.
-- (tools\claude-bridge.ps1 Read-FlowCode reads exactly this.)
local function bits16(out, n) for b = 15, 0, -1 do out[#out + 1] = math.floor(n / 2 ^ b) % 2 end end
function AC.ShotBits(payload, cols)
    local out = {}
    for _, b in ipairs(AC.MAGIC) do out[#out + 1] = b end
    local sum = 0
    for i = 1, #payload do sum = (sum + payload:byte(i)) % 65536 end
    bits16(out, cols); bits16(out, #payload); bits16(out, sum)
    for i = 1, #payload do
        local byte = payload:byte(i)
        for b = 7, 0, -1 do out[#out + 1] = math.floor(byte / 2 ^ b) % 2 end
    end
    return out
end

-- Black squares joined into runs along each row ({ row, col, length }, from
-- 0): far fewer textures than one per square.
function AC.ShotRuns(bits, cols)
    local runs, start = {}, nil
    for i = 1, #bits + 1 do
        local b, col = bits[i], (i - 1) % cols
        if start and (b ~= 1 or col == 0) then
            runs[#runs + 1] = { math.floor((start - 1) / cols), (start - 1) % cols, i - start }
            start = nil
        end
        if b == 1 and not start then start = i end
    end
    return runs
end

function AC.CanLive()
    -- Off unless you turn it on (/flow chat live on): sending by screenshot is a
    -- stopgap, not the text route you want (Sooth, 0.35.114). Off: Send reloads.
    return ns.db.chat.live == true and type(Screenshot) == "function" and type(GetPhysicalScreenSize) == "function"
end

local status   -- forward: the chat window's status line
local code     -- the frame the squares are drawn on

-- Draws `payload` as squares, 1 unit = 1 screen pixel; false if it won't fit.
function AC:ShowCode(payload)
    local pw, ph = GetPhysicalScreenSize()
    if not (pw and ph and pw > 0 and ph > 0) then return false end
    local C, M = AC.CELL, AC.MARGIN
    local cols = math.min(240, math.floor(pw / C) - 2 * M - 2)
    local bits = AC.ShotBits(payload, cols)
    local rows = math.ceil(#bits / cols)
    if (rows + 2 * M) * C > ph then return false end
    if not code then
        code = CreateFrame("Frame", nil, UIParent)
        code:SetFrameStrata("TOOLTIP")
        code:SetFrameLevel(9000)
        code.bg = code:CreateTexture(nil, "BACKGROUND")
        code.bg:SetAllPoints()
        code.bg:SetColorTexture(1, 1, 1, 1)
        code.pool = {}
    end
    code:SetScale((768 / ph) / UIParent:GetEffectiveScale())
    code:ClearAllPoints()
    code:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    code:SetSize((cols + 2 * M + 2) * C, (rows + 2 * M) * C)   -- (2 more columns: the end square and white past it)
    for _, t in ipairs(code.pool) do t:Hide() end
    -- The runs, and one black square in row 0 one column past the last (white
    -- either side): the bridge measures the square size from it (a screenshot may be scaled).
    local runs = AC.ShotRuns(bits, cols)
    runs[#runs + 1] = { 0, cols + 1, 1 }
    for k, run in ipairs(runs) do
        local t = code.pool[k] or code:CreateTexture(nil, "ARTWORK")
        code.pool[k] = t
        t:SetColorTexture(0, 0, 0, 1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", code, "TOPLEFT", (M + run[2]) * C, -(M + run[1]) * C)
        t:SetSize(run[3] * C, C)
        t:Show()
    end
    code:Show()
    return true
end
function AC.CodeShown() return code ~= nil and code:IsShown() end   -- (tests)
function AC:HideCode() if code then code:Hide() end end

local shooting   -- the message being sent: { id }
local function failed(why)
    shooting = nil
    AC:HideCode()
    status("|cffff7070Couldn't send it without a reload|r (" .. why .. "). Press Reload to send it (it's saved).")
    ns:Log("chat", "live send failed: " .. why)
end
ns:On("SCREENSHOT_SUCCEEDED", function()
    if not shooting then return end
    shooting = nil
    AC:HideCode()
    ns.db.chat.liveWorks = true
    status(AC:IsConnected() and "Sent, no reload needed: Claude reads it now. Its answer shows when you press Reload."
        or "Sent, no reload needed. Claude reads it once it's connected (/si setup); answers show when you press Reload.")
end)
ns:On("SCREENSHOT_FAILED", function() if shooting then failed("the screenshot failed") end end)

-- Sends message `e` live; false if this client can't (then Send reloads).
function AC:SendLive(e)
    if not AC.CanLive() or shooting then return false end
    if not AC:ShowCode(AC.ShotPayload(e)) then return false end
    shooting = { id = e.id }
    -- The squares are on screen from the next frame: then the screenshot.
    C_Timer.After(0.15, function()
        local ok, err = pcall(Screenshot)
        if not ok then failed(tostring(err)) end
    end)
    C_Timer.After(6, function() if shooting and shooting.id == e.id then failed("no screenshot came back") end end)
    return true
end

-- 0.35.107-0.35.110 turned WoW's chat log on for this: off again (once).
ns:On("PLAYER_LOGIN", function()
    if ns.db.chat.toldLog then
        ns.db.chat.toldLog, ns.db.chat.flushes = nil, nil
        if type(LoggingChat) == "function" and LoggingChat() then LoggingChat(false) end
    end
end)

function AC:Send(text)
    local chat = ns.db.chat
    local id = chat.nextId
    chat.nextId = id + 1
    local e = AC.Entry(id, text)
    -- In Flow's saved data too: a reload passes it on if the live send didn't.
    chat.outbox[#chat.outbox + 1] = e
    while #chat.outbox > MAX_OUTBOX do table.remove(chat.outbox, 1) end
    -- What you asked, kept (the last 20) so the chat window can show it next
    -- to Claude's answer.
    chat.sent[id] = text
    for old in pairs(chat.sent) do if old <= id - MAX_OUTBOX then chat.sent[old] = nil end end
    if AC:SendLive(e) then
        status("Sending (no reload)...")
        if AC.box and AC.box:IsShown() then AC:Open() end
        return
    end
    ns:Print("sent to Claude (reloading so it's saved where Claude can read it)...")
    ReloadUI()   -- (from your slash command or the Send button: allowed)
end

-------------------------------------------------------------------------------
-- Connecting Claude: a prompt to paste into a Claude Code session (Claude
-- desktop's Code tab, or `claude` in a terminal) on the PC you play on.
-------------------------------------------------------------------------------

AC.REPO = "https://github.com/Perpetuator-LLC/flow-wow"
function AC.SetupPrompt(char, class, level, realm)
    return table.concat({
        "Connect yourself to my WoW addon Flow's in-game chat, then watch it for me. Explain each step in plain words, and ask me before changing anything that starts with Windows.",
        "",
        string.format("I play WoW: Forever as %s (%s %s) on %s, with the Flow addon (%s).", tostring(char), tostring(class), tostring(level), tostring(realm), AC.REPO),
        "",
        "1. Find my Flow source: a git clone of that repo (often %USERPROFILE%\\projects\\flow-wow). If I have none, clone it there. If my WoW folder's _forever_\\Interface\\AddOns\\Flow isn't a link to that clone, tell me how to link it, or pass -AddonDir <that AddOns\\Flow folder> to the bridge below.",
        "2. Read CLAUDE.md (the \"Watch Flow's in-game chat\" section) and docs\\ASK-CLAUDE.md in it.",
        "3. Run: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1 -SelfTest  (it should say \"self-test OK\").",
        "4. Start: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1  with your Monitor tool, and start it again each time it expires. It finds my WoW folder by itself and reads my messages from Flow's saved data (_forever_\\WTF\\Account\\<account>\\SavedVariables\\Flow.lua) at a reload (and, if I turn it on with /flow chat live on, from Flow's coded screenshots in _forever_\\Screenshots as I send them, which it decodes and deletes).",
        "5. Each ASK line is a message from me: do what it asks in my Flow folder, then answer: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1 -Reply <id> -Text \"...\"  (at most 3 short sentences, plain text; say if I need to reload). DEATH and UPDATE lines: CLAUDE.md says what to do.",
        "6. When it prints READY, tell me to press Reload in Flow Chat (/si) and say hello.",
    }, "\n")
end
function AC:MyPrompt()
    local _, class = UnitClass("player")
    return AC.SetupPrompt(UnitName("player"), class, UnitLevel("player"), GetRealmName and GetRealmName() or "?")
end

-------------------------------------------------------------------------------
-- The chat window (/si): your questions and Claude's answers, a box to type
-- in, Send and Reload; or, not connected, the prompt to connect Claude.
-------------------------------------------------------------------------------

-- The conversation as lines, oldest first, at most `max` exchanges: answers
-- (with what you asked) and messages still waiting, in time order. (They
-- used to be ordered by two different counters, waiting ones always last:
-- five unanswered tests pushed every answer out of the window, Yang.)
function AC.History(inbox, chat, max)
    local out = {}
    for _, r in ipairs(inbox or {}) do
        local q = r.replyTo and chat.sent and chat.sent[r.replyTo]
        out[#out + 1] = { q = q, a = r.text, at = r.at or 0, n = r.id or 0 }
    end
    for _, m in ipairs(chat.outbox or {}) do
        out[#out + 1] = { q = m.text, waiting = true, at = m.at or 0, n = 1e9 + (m.id or 0) }
    end
    table.sort(out, function(x, y)
        if x.at ~= y.at then return x.at < y.at end
        return x.n < y.n   -- (same time: answers first)
    end)
    local lines = {}
    for i = math.max(1, #out - (max or 6) + 1), #out do
        local e = out[i]
        if e.q then lines[#lines + 1] = "|cff88ccffYou:|r " .. e.q end
        if e.waiting then lines[#lines + 1] = "|cff888888(waiting for Claude: Reload shows its answer)|r"
        elseif e.a then lines[#lines + 1] = "|cff" .. ORANGE .. "Claude:|r " .. e.a end
    end
    return lines
end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(text)
    return b
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
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 40); f.status:SetPoint("BOTTOMRIGHT", -12, 40)
    f.status:SetJustifyH("LEFT")
    -- Reload: when you want Claude's answers (and any change it made to Flow).
    f.reload = button(f, "Reload", 70)
    f.reload:SetPoint("BOTTOMRIGHT", -12, 10)
    f.reload:SetScript("OnClick", function()
        ns:Print("reloading to show Claude's answers (and load any change it made to Flow)...")
        ReloadUI()
    end)
    f.reload:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reload", 1, 1, 1)
        GameTooltip:AddLine("WoW only reads Flow's files at a reload: Claude's answers, and any change it made to Flow, show after one.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.reload:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Chat view.
    f.chat = CreateFrame("Frame", nil, f)
    f.chat:SetAllPoints()
    -- The conversation: newest at the bottom, the mouse wheel scrolls back.
    -- (A fixed-height text cut long answers off.)
    f.log = CreateFrame("ScrollingMessageFrame", nil, f.chat)
    f.log:SetPoint("TOPLEFT", 12, -32); f.log:SetPoint("TOPRIGHT", -12, -32)
    f.log:SetHeight(200)
    f.log:SetFontObject(GameFontHighlightSmall)
    f.log:SetJustifyH("LEFT")
    f.log:SetFading(false)
    f.log:SetMaxLines(400)
    f.log:SetSpacing(2)
    f.log:EnableMouseWheel(true)
    f.log:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    f.edit = CreateFrame("EditBox", nil, f.chat, "InputBoxTemplate")
    f.edit:SetSize(215, 22)
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
    f.send = button(f.chat, "Send", 60)
    f.send:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
    f.send:SetScript("OnClick", send)
    f.connect = button(f.chat, "Connect", 70)
    f.connect:SetPoint("LEFT", f.send, "RIGHT", 4, 0)
    f.connect:SetScript("OnClick", function() AC:OpenSetup() end)

    -- Setup view: the prompt to paste into Claude.
    f.setup = CreateFrame("Frame", nil, f)
    f.setup:SetAllPoints()
    f.setup.intro = f.setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.setup.intro:SetPoint("TOPLEFT", 12, -32); f.setup.intro:SetPoint("TOPRIGHT", -12, -32)
    f.setup.intro:SetJustifyH("LEFT")
    f.setup.intro:SetText("Claude isn't connected yet. Copy this (Ctrl+C: it's selected) into a Claude Code session on this PC (Claude desktop's Code tab). It sets Claude up to read your messages and change Flow for you. Then press Reload.")
    local sf = CreateFrame("ScrollFrame", nil, f.setup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -74); sf:SetPoint("BOTTOMRIGHT", -30, 62)
    f.prompt = CreateFrame("EditBox", nil, sf)
    f.prompt:SetMultiLine(true)
    f.prompt:SetAutoFocus(false)
    f.prompt:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    f.prompt:SetWidth(420)
    f.prompt:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: typing puts the prompt back.
    f.prompt:SetScript("OnTextChanged", function(self, user)
        if user and self.text and self:GetText() ~= self.text then self:SetText(self.text); self:HighlightText() end
    end)
    sf:SetScrollChild(f.prompt)
    f.copy = button(f.setup, "Select all", 80)
    f.copy:SetPoint("BOTTOMLEFT", 12, 10)
    f.copy:SetScript("OnClick", function() f.prompt:SetFocus(); f.prompt:HighlightText() end)
    f.toChat = button(f.setup, "Chat anyway", 100)
    f.toChat:SetPoint("LEFT", f.copy, "RIGHT", 4, 0)
    f.toChat:SetScript("OnClick", function() ns.db.chat.setupSkipped = true; AC:Open() end)

    -- Copy (chat view, in the title bar: the row below is full): the whole
    -- conversation in the Flow Copy window (select, Ctrl+C; web addresses in
    -- Claude's answers can be picked out one by one).
    f.copyLog = button(f.chat, "Copy", 50)
    f.copyLog:SetHeight(18)
    f.copyLog:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.copyLog:SetScript("OnClick", function()
        if not ns.copyBox then f.status:SetText("Type /reload to load the Flow Copy window.") return end
        local lines = AC.History(ns.claudeInbox, ns.db.chat, 20)
        if #lines == 0 then f.status:SetText("Nothing to copy yet.") return end
        ns.copyBox:Show("the Flow Chat conversation", lines)
    end)
    f:Hide()
    return f
end

function status(text)   -- (declared above)
    if box and text then box.status:SetText(text) end
end

local function liveHint()
    if not AC.CanLive() then return "Send reloads your UI for a moment so Claude can read it." end
    return "Send needs no reload (a quick screenshot carries it)."
end

-- `draft`: text to put in the box to finish (a message too long for the chat box).
function AC:Open(draft)
    box = box or buildBox()
    AC.box = box
    box.setup:Hide(); box.chat:Show()
    local chat = ns.db.chat
    local lines = AC.History(ns.claudeInbox, chat, 20)
    box.log:Clear()
    if #lines == 0 then
        box.log:AddMessage("|cff888888Ask anything about Flow or your character. A Claude session on your PC answers (docs/ASK-CLAUDE.md).|r")
    end
    for _, l in ipairs(lines) do box.log:AddMessage(l) end
    box.log:ScrollToBottom()
    box.connect:SetShown(not AC:IsConnected())
    box.status:SetText(draft and "The chat box stops at 255 letters, so the end may be cut off: finish your message here (it takes 1000) and press Enter."
        or not AC:IsConnected() and ("Claude wasn't watching at your last reload: Connect shows how. " .. liveHint())
        or #chat.outbox > 0
        and string.format("Waiting on %d message(s). Reload shows Claude's answers.", #chat.outbox)
        or (liveHint() .. " Reload shows Claude's answers."))
    box:Show()
    if draft then box.edit:SetText(draft) end
    box.edit:SetFocus()
    if draft then box.edit:SetCursorPosition(#draft) end
end

function AC:OpenSetup()
    box = box or buildBox()
    AC.box = box
    box.chat:Hide(); box.setup:Show()
    local text = AC:MyPrompt()
    box.prompt.text = text
    box.prompt:SetText(text)
    box.status:SetText(ns.claudeBridge and string.format("Claude was last watching %d min before your last reload.",
        math.floor((time() - (ns.claudeBridge.at or 0)) / 60)) or "Claude hasn't connected on this PC yet.")
    box:Show()
    box.prompt:SetFocus(); box.prompt:HighlightText()
end

-- Messages waiting more than a day: a reload passed them on long ago and no
-- answer is coming (Yang's tests): out of the outbox (what you asked stays
-- in the chat history). Returns how many went.
AC.STALE = 24 * 3600
function AC.DropStale(outbox, now)
    local n = 0
    for i = #outbox, 1, -1 do
        if (outbox[i].at or now) < now - AC.STALE then table.remove(outbox, i); n = n + 1 end
    end
    return n
end

local function check()
    local chat = ns.db.chat
    AC.DropStale(chat.outbox, time())
    local new = AC.TakeNew(ns.claudeInbox, chat)
    for _, r in ipairs(new) do show(r) end
    if #new > 0 then ns:Print("(/si opens the chat window)") end
    if #chat.outbox > 0 then
        ns:Print(string.format("waiting for Claude on %d message(s). Reload in Flow Chat (/si) looks again.%s", #chat.outbox,
            AC:IsConnected() and "" or " Claude isn't connected: /si setup shows how."))
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
    if arg == "" then   -- connected (or you chose to chat anyway): the chat; else how to connect
        if AC:IsConnected() or ns.db.chat.setupSkipped then AC:Open() else AC:OpenSetup() end
        return
    end
    if arg == "setup" or arg == "connect" then AC:OpenSetup() return end
    if arg == "check" or arg == "reload" then ns:Print("checking for Claude's answers (reloading)..."); ReloadUI() return end
    -- Too long for the chat box: finish it in the Flow Chat window instead
    -- of sending the cut-off part.
    if AC.MaybeCut(arg) then AC:Open(arg) return end
    AC:Send(arg)
end
ns.commands.ask = command

-- /flow chat live on|off: send by a screenshot (no reload) or by reloading.
-- /flow chat stamps ... is Chat.lua's (loaded earlier): passed on to it, which
-- this replacing it silently stopped (F-100).
AC._chatStamps = ns.commands.chat
ns.commands.chat = function(arg)
    if AC._chatStamps and (arg or ""):lower():match("^%s*stamps") then return AC._chatStamps(arg) end
    local on = (arg or ""):lower():match("^live%s+(o[nf]f?)$")
    if on == "on" or on == "off" then ns.db.chat.live = (on == "on") end
    ns:Print(string.format("Flow Chat sends %s. Claude connected (as of your last reload): %s. /flow chat live on|off",
        AC.CanLive() and "without a reload (a screenshot the bridge reads)" or "by reloading", AC:IsConnected() and "yes" or "no"))
end

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
    "/si (or /ai, /claude): Flow Chat with Claude; not connected yet, it shows a prompt to connect Claude.",
    "/si <message>: ask straight away (no reload: a quick screenshot carries it). Reload in the window shows answers.",
    "/si setup: the connect prompt again. /flow chat live on|off: send without or with a reload.",
} })
