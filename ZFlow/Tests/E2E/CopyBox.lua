local _, ns = ...
-- S24 copy window, the two checks the lead lists as unverified: the copy
-- box must not open by itself (boot and many of this add-on's own chat
-- lines open nothing), and the chat window's Copy button opens it. Also
-- the copy word opens it with the last line. Whole add-on on a fake
-- client. Nothing is typed into the game's chat: the main chat window's
-- lines and the edit box are the same after the box opens, and the box
-- never takes the keyboard. Made-up lines. Not tested in game.
local tests = {}

local WINDOW = "ChatFrame1"
local SAY = "CHAT_MSG_SAY"
local MANY = 40

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setWindow(WINDOW, { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function ready(t, c, addon)
    local ok = type(addon.Chat) == "table" and type(c.pushChat) == "function"
        and type(c.chatLines) == "function" and type(c.copyBoxes) == "table"
    t.ok(ok, "the chat module is loaded and the fake client has its chat controls")
    return ok
end

-- Many lines of this add-on's own, both printed and through the chat
-- window; the last line the window shows, as plain text, is returned
-- (what the chat filters made of it, not what went in).
local function chatter(c, addon)
    local last
    for i = 1, MANY do
        c.print(ns.id.title .. ": line " .. i)
        local shown = c.pushChat(SAY, ns.id.title .. ": window line " .. i)
        if type(shown) == "string" then last = addon.Chat.Plain(shown, addon.Chat.Prefix(ns.id)) end
        c.advance(1, 2)
    end
    return last
end

local function shownBoxes(c)
    local n = 0
    for _, box in ipairs(c.copyBoxes) do
        if box.shown then n = n + 1 end
    end
    return n
end

local function myButton(c)
    for _, h in ipairs(c.windowButtons or {}) do
        if h.frame == WINDOW then return h end
    end
    return nil
end

-- What the game's chat holds that a player could have typed into.
local function typed(c)
    local edit = type(c.editBoxState) == "function" and c.editBoxState() or nil
    return { lines = c.chatLines(1, 500) or {}, edit = edit }
end

tests["copy box S24: boot and many add-on lines open no copy box"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    t.eq(shownBoxes(c), 0, "none after boot")
    chatter(c, addon)
    c.advance(30, 20)
    t.eq(shownBoxes(c), 0, "none after " .. MANY .. " of the add-on's own lines")
    for _, box in ipairs(c.copyBoxes) do
        t.eq(box.focused, false, "no box holds the keyboard")
    end
end

tests["copy box S24: the copy word opens the box with the last line, unfocused"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local last = chatter(c, addon)
    local before = typed(c)
    c.slashes[ns.id.slash]("chat copy 1")
    local box = c.copyBoxes[#c.copyBoxes]
    t.ok(box ~= nil, "a copy box")
    if not box then return end
    t.eq(box.text, last, "the last line, plain")
    t.eq(box.shown, true)
    t.eq(box.focused, false, "it does not take the keyboard")
    t.eq(shownBoxes(c), 1, "one box")
    t.eq(typed(c), before, "nothing typed into the game's chat")
end

tests["copy box S24: the chat window's Copy button opens the box"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local button = myButton(c)
    t.ok(button ~= nil, "a Copy button on the main chat window")
    if not button then return end
    t.eq(button.spec and button.spec.text, "Copy")
    t.eq(button.shown, true)
    local last = chatter(c, addon)
    t.eq(shownBoxes(c), 0, "not open before the click")
    local before = typed(c)
    button.click()
    local box = c.copyBoxes[#c.copyBoxes]
    t.ok(box ~= nil, "a copy box")
    if not box then return end
    t.eq(box.shown, true)
    t.eq(box.focused, false, "it does not take the keyboard")
    local tail = "\n" .. last
    t.eq(string.sub(box.text, -#tail), tail, "it ends with the last line")
    t.eq(typed(c), before, "nothing typed into the game's chat")
end

return tests
