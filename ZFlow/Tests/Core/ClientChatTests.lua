-- N60a chat: the client's chat reads and hooks (Core/Client.lua chatLines,
-- chatFilter, onLinkClick, pratModule). The real client over a hand-built
-- environment (`env` stands in for the game's globals), then the fake.
-- Every call read here is a first guess, not seen in game on 16001.
-- Fails before: the client has none of the four (c.chatLines is nil).
local _, ns = ...

local tests = {}

local SECRET = {}
local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_GUILD" }

local function chatFrame(lines)
    local f = { lines = lines }
    function f:GetNumMessages() return #self.lines end
    function f:GetMessageInfo(i)
        if self.lines[i] == "raise" then error("no such line") end
        return self.lines[i], 1, 1, 1
    end
    return f
end

-- A filter table as ChatFrameUtil keeps it: event -> list of functions.
local function filterEnv()
    local env = { filters = {}, hooks = {}, hookCalls = 0 }
    local function add(event, fn)
        env.filters[event] = env.filters[event] or {}
        table.insert(env.filters[event], fn)
    end
    local function remove(event, fn)
        local list = env.filters[event] or {}
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end
    env.ChatFrameUtil = { AddMessageEventFilter = add, RemoveMessageEventFilter = remove }
    env.issecretvalue = function(v) return v == SECRET end
    env.SetItemRef = function() end
    env.hooksecurefunc = function(name, hook)
        env.hookCalls = env.hookCalls + 1
        env.hooks[name] = hook
    end
    return env
end

local function has(t, c)
    local ok = type(c.chatLines) == "function" and type(c.chatFilter) == "function"
        and type(c.onLinkClick) == "function" and type(c.pratModule) == "function"
    t.ok(ok, "the client has chatLines, chatFilter, onLinkClick and pratModule")
    return ok
end

-- ------------------------------------------------------------- chatLines

tests["client chat: the last lines of a chat window, oldest first"] = function(t)
    local env = { ChatFrame1 = chatFrame({ "one", "two", "three", "four" }) }
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq(c.chatLines(1, 10), { "one", "two", "three", "four" })
    t.eq(c.chatLines(1, 2), { "three", "four" })
    t.eq(c.chatLines(1), { "one", "two", "three", "four" })
    t.eq(c.chatLines(2, 10), nil, "a window that is not there is not known")
    t.eq(c.chatLines("1", 10), nil)
    t.eq(c.chatLines(0, 10), nil)
end

tests["client chat: never more than 500 lines"] = function(t)
    local lines = {}
    for i = 1, 600 do lines[i] = "line " .. i end
    local c = ns.make.client({ ChatFrame1 = chatFrame(lines) })
    if not has(t, c) then return end
    local got = c.chatLines(1, 5000)
    t.eq(#got, 500)
    t.eq(got[1], "line 101")
    t.eq(got[500], "line 600")
end

tests["client chat: a line that raises, is hidden or is no text is left out; a count that is no number is not known"] = function(t)
    local env = { ChatFrame1 = chatFrame({ "one", "raise", SECRET, 7, "five" }) }
    env.issecretvalue = function(v) return v == SECRET end
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq(c.chatLines(1, 10), { "one", "five" })
    env.ChatFrame1.GetNumMessages = function() return "many" end
    t.eq(c.chatLines(1, 10), nil)
    env.ChatFrame1.GetNumMessages = function() error("no count") end
    t.eq(c.chatLines(1, 10), nil)
    env.ChatFrame1 = {}
    t.eq(c.chatLines(1, 10), nil, "a window with no such read")
end

-- ------------------------------------------------------------ chatFilter

tests["client chat: one filter for each event, through ChatFrameUtil; the cancel takes it away"] = function(t)
    local env = filterEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local cancel = c.chatFilter(EVENTS, function(text) return text .. "!" end)
    t.eq(type(cancel), "function")
    t.eq(#(env.filters.CHAT_MSG_SAY or {}), 1)
    t.eq(#(env.filters.CHAT_MSG_GUILD or {}), 1)
    local filter = env.filters.CHAT_MSG_SAY[1]
    -- The game's contract: false, then every argument again when one changed.
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall", 3) }, { false, "hi!", "Thrall", 3 })
    cancel()
    t.eq(#env.filters.CHAT_MSG_SAY, 0)
    t.eq(#env.filters.CHAT_MSG_GUILD, 0)
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall") }, { false }, "a cancelled filter changes nothing")
end

tests["client chat: a filter that changes nothing, raises or sees a hidden text passes the line on"] = function(t)
    local env = filterEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local calls, answer = 0, nil
    c.chatFilter(EVENTS, function(text)
        calls = calls + 1
        if answer == "raise" then error("filter failed") end
        if answer == "same" then return text end
        return answer
    end)
    local filter = env.filters.CHAT_MSG_SAY[1]
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall") }, { false }, "no answer")
    answer = "same"
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall") }, { false }, "the same text")
    answer = 7
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall") }, { false }, "an answer that is no text")
    answer = "raise"
    t.eq({ filter({}, "CHAT_MSG_SAY", "hi", "Thrall") }, { false }, "an error stays inside")
    t.eq(calls, 4)
    answer = "changed"
    t.eq({ filter({}, "CHAT_MSG_SAY", SECRET, "Thrall") }, { false }, "a hidden text is not read")
    t.eq({ filter({}, "CHAT_MSG_SAY", nil, "Thrall") }, { false })
    t.eq({ filter({}, "CHAT_MSG_SAY", 12, "Thrall") }, { false })
    t.eq(calls, 4, "and the filter was not asked about them")
end

tests["client chat: the older global is used when ChatFrameUtil is not there; neither is no filter"] = function(t)
    local added, removed = {}, {}
    local env = {
        ChatFrame_AddMessageEventFilter = function(event) added[#added + 1] = event end,
        ChatFrame_RemoveMessageEventFilter = function(event) removed[#removed + 1] = event end,
    }
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local cancel = c.chatFilter(EVENTS, function() end)
    t.eq(added, EVENTS)
    t.eq(type(cancel), "function")
    cancel()
    t.eq(removed, EVENTS)
    t.eq(ns.make.client({}).chatFilter(EVENTS, function() end), nil)
    t.eq(c.chatFilter(EVENTS, nil), nil)
    t.eq(c.chatFilter(nil, function() end), nil)
    env.ChatFrame_AddMessageEventFilter = function() error("refused") end
    t.eq(c.chatFilter(EVENTS, function() end), nil, "an event the client refuses is not a filter")
end

-- ----------------------------------------------------------- onLinkClick

tests["client chat: a click on a link of the asked kind is told; any other link is not"] = function(t)
    local env = filterEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local got, other = {}, {}
    local cancel = c.onLinkClick("addon:Mine:url", function(rest) got[#got + 1] = rest end)
    c.onLinkClick("addon:Mine:note", function(rest) other[#other + 1] = rest end)
    t.eq(type(cancel), "function")
    t.eq(env.hookCalls, 1, "the game's link click is followed once, whatever the number of kinds")
    local hook = env.hooks.SetItemRef
    t.eq(type(hook), "function")
    hook("addon:Mine:url:http://example.com/a:b", "[x]", "LeftButton", {})
    hook("item:2589::::::::10:::::", "[Linen Cloth]", "LeftButton", {})
    hook("player:Thrall", "[Thrall]", "LeftButton", {})
    hook("addon:Mine:urlx:nope", "[x]", "LeftButton", {})
    hook("addon:Mine:url", "[x]", "LeftButton", {})
    hook(SECRET, "[x]", "LeftButton", {})
    hook(nil)
    t.eq(got, { "http://example.com/a:b" })
    t.eq(other, {})
    cancel()
    hook("addon:Mine:url:http://example.com", "[x]", "LeftButton", {})
    t.eq(#got, 1, "nothing after the cancel")
end

tests["client chat: an error in the told function stays inside; no hook is no follow"] = function(t)
    local env = filterEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    c.onLinkClick("addon:Mine:url", function() error("click failed") end)
    t.eq(pcall(env.hooks.SetItemRef, "addon:Mine:url:x"), true)
    local bare = ns.make.client({ SetItemRef = function() end })
    t.eq(bare.onLinkClick("addon:Mine:url", function() end), nil, "no hooksecurefunc")
    local none = ns.make.client({ hooksecurefunc = function() end })
    t.eq(none.onLinkClick("addon:Mine:url", function() end), nil, "no SetItemRef")
    t.eq(c.onLinkClick("", function() end), nil)
    t.eq(c.onLinkClick("addon:Mine:url", nil), nil)
end

-- ------------------------------------------------------------ pratModule

tests["client chat: whether a Prat module is on - yes, no, or not known"] = function(t)
    local mods = {
        UrlCopy = { IsEnabled = function() return true end },
        CopyChat = { IsEnabled = function() return false end },
        Odd = { IsEnabled = function() return "yes" end },
        Raises = { IsEnabled = function() error("not yet") end },
    }
    local env = { Prat = { GetModule = function(_, name) return mods[name] end } }
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq(c.pratModule("UrlCopy"), true)
    t.eq(c.pratModule("CopyChat"), false)
    t.eq(c.pratModule("Odd"), nil)
    t.eq(c.pratModule("Raises"), nil)
    t.eq(c.pratModule("Missing"), nil)
    t.eq(c.pratModule(nil), nil)
    env.Prat = { Addon = { GetModule = function(_, name) return mods[name] end } }
    t.eq(c.pratModule("UrlCopy"), true, "through Prat.Addon")
    env.Prat = { GetModule = function() error("no such module") end }
    t.eq(c.pratModule("UrlCopy"), nil)
    env.Prat = nil
    t.eq(c.pratModule("UrlCopy"), nil, "Prat is not there")
end

-- ------------------------------------------------------------------ fake

tests["fake client chat: a pushed line goes through the filters to the window; a click is told by kind"] = function(t)
    local c = ns.make.fakeClient()
    if not has(t, c) then return end
    t.eq(c.chatLines(1, 10), nil, "no window lines until one is pushed or set")
    t.eq(c.chatFilterCount("CHAT_MSG_SAY"), 0)
    local cancel = c.chatFilter(EVENTS, function(text) return text .. "!" end)
    t.eq(c.chatFilterCount("CHAT_MSG_SAY"), 1)
    t.eq(c.pushChat("CHAT_MSG_SAY", "hi"), "hi!")
    t.eq(c.pushChat("CHAT_MSG_WHISPER", "psst"), "psst", "an event with no filter")
    t.eq(c.pushChat("CHAT_MSG_SAY", SECRET), SECRET, "what is no text passes untouched")
    cancel()
    t.eq(c.chatFilterCount("CHAT_MSG_SAY"), 0)
    t.eq(c.pushChat("CHAT_MSG_SAY", "bye"), "bye")
    t.eq(c.chatLines(1, 10), { "hi!", "psst", "bye" })
    t.eq(c.chatLines(1, 2), { "psst", "bye" })
    c.setChatLines(2, { "a", "b" })
    t.eq(c.chatLines(2, 1), { "b" })

    local got = {}
    c.onLinkClick("addon:Mine:url", function(rest) got[#got + 1] = rest end)
    t.eq(c.clickLink("addon:Mine:url:http://example.com"), 1)
    t.eq(c.clickLink("item:2589"), 0)
    t.eq(got, { "http://example.com" })
    t.eq(c.linkClicks, { "addon:Mine:url:http://example.com", "item:2589" }, "the game handles every click itself")

    t.eq(c.pratModule("UrlCopy"), nil)
    c.setPratModule("UrlCopy", true)
    t.eq(c.pratModule("UrlCopy"), true)
    c.setChatFilters(false)
    t.eq(c.chatFilter(EVENTS, function() end), nil, "a client with no chat filter")
    c.setLinkHook(false)
    t.eq(c.onLinkClick("addon:Mine:other", function() end), nil, "a client with no link hook")
end

-- ----------------------------------------------------------------- names

tests["client chat: the names these reads ask are in Diag.NAMES"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({
        "ChatFrameUtil.AddMessageEventFilter", "ChatFrameUtil.RemoveMessageEventFilter",
        "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter",
        "SetItemRef", "hooksecurefunc", "ChatFrame1", "ChatFrame1.GetNumMessages", "ChatFrame1.GetMessageInfo",
        "Prat", "Prat.GetModule", "Prat.Addon",
    }) do
        t.ok(listed[name], "listed: " .. name)
    end
end

return tests
