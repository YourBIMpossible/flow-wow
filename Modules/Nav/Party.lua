-- Party routes. Your own route and the party route are always separate:
-- you can follow the party route or your own, switch any time (toggle under
-- the arrow, or /flow party mine|follow), and the party never changes your
-- own route.
--
-- How it starts:
--   * Joining a group: Flow asks the party for its route; if there is one you
--     get a popup: "Follow party route" or "Keep my route".
--   * Forming a group: if you're the leader and nobody shares a route within
--     a few seconds, Flow shares one: objectives and turn-ins of quests party
--     members have in common first (the best guess at what the party is
--     doing), otherwise your current route. Members exchange quest lists so
--     that guess can be made.
--   * /flow party share shares your route by hand.
--
-- Editing: anyone following the party route can choose stops (map
-- checkpoints, trip list, advice rows), add waypoints, and clears a stop by
-- reaching it. Every edit is numbered and sent to everyone; the newest edit
-- wins (ties: the later name), so nobody owns it.

local _, ns = ...
local P = {}
ns.party = P

local PREFIX = "FlowWoW"
local MAX_STOPS = 15

local state = { joined = false, following = false, clock = 0, editor = "", stops = {} }
local offer          -- latest route shared by someone while you're not joined
local incoming = {}  -- sender -> { clock, total, stops }
local members = {}   -- name -> { quests = { [id] = true } }
local counter = 0
local inGroup = false

local function me() return UnitName("player") or "?" end

-- Is this addon-message sender you? The game echoes your own party messages
-- back, and on WoW: Forever the sender carries your realm ("Name-Realm")
-- even after Ambiguate, so comparing with your plain name let your own
-- quest progress through ("Help <yourself>?").
local function myRealm()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    return (r:gsub("[%s%-']", ""))
end
function P.IsMe(sender, myName, realm)
    if type(sender) ~= "string" then return false end
    myName, realm = myName or me(), realm or myRealm()
    if sender == myName then return true end
    local name, senderRealm = sender:match("^([^%-]+)%-(.+)$")
    if name ~= myName then return false end
    return realm == "" or (senderRealm:gsub("[%s%-']", "")) == realm
end

local function channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end


local function send(msg)
    local ch = channel()
    if not ch then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, ch)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, ch)
    end
end

local function clean(s) return (tostring(s or ""):gsub("[|~]", "")) end

local function encode(s)
    return table.concat({ s.id, s.map, string.format("%.4f", s.x), string.format("%.4f", s.y),
        s.level or "", s.kind or "", clean(s.label):sub(1, 60) }, "~")
end

local function decode(str)
    local f = {}
    for part in (str .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
    if #f < 7 then return nil end
    return { id = f[1], map = tonumber(f[2]), x = tonumber(f[3]), y = tonumber(f[4]),
             level = tonumber(f[5]), kind = f[6] ~= "" and f[6] or nil, label = f[7] }
end

local function newId()
    counter = counter + 1
    return me() .. counter .. "-" .. (state.clock + 1)
end

local function changed()
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
    if P.RefreshToggle then P:RefreshToggle() end
end

-------------------------------------------------------------------------------
-- Messages
--   B|clock|n  S|clock|i|stop  E|clock   whole route (begin / stop / end)
--   Q|0                                  "send me your route" (just joined)
--   L|part|parts|id,id,...               my quest log (for the party guess)
-------------------------------------------------------------------------------

function P:Broadcast()
    send(string.format("B|%d|%d", state.clock, #state.stops))
    for i, s in ipairs(state.stops) do
        send(string.format("S|%d|%d|%s", state.clock, i, encode(s)))
    end
    send(string.format("E|%d", state.clock))
end

local lastQuestSend = 0
function P:SendQuests()
    if not channel() or GetTime() - lastQuestSend < 2 then return end
    lastQuestSend = GetTime()
    local ids = {}
    for id in pairs(ns.quests:LogIds()) do ids[#ids + 1] = tostring(id) end
    -- Split into parts that fit an addon message.
    local parts, cur = {}, {}
    for _, id in ipairs(ids) do
        cur[#cur + 1] = id
        if #table.concat(cur, ",") > 200 then parts[#parts + 1] = table.concat(cur, ","); cur = {} end
    end
    parts[#parts + 1] = table.concat(cur, ",")
    for i, p in ipairs(parts) do send(string.format("L|%d|%d|%s", i, #parts, p)) end
end

local function newer(clock, editor)
    return clock > state.clock or (clock == state.clock and editor > state.editor)
end

local function received(sender, msg)
    local kind, rest = msg:match("^(%a)|(.*)$")
    if kind == "B" then
        local clock, total = rest:match("^(%d+)|(%d+)$")
        incoming[sender] = { clock = tonumber(clock), total = tonumber(total), stops = {} }
    elseif kind == "S" then
        local clock, i, body = rest:match("^(%d+)|(%d+)|(.*)$")
        local inc = incoming[sender]
        if inc and inc.clock == tonumber(clock) then inc.stops[tonumber(i)] = decode(body) end
    elseif kind == "E" then
        local inc = incoming[sender]
        incoming[sender] = nil
        if not inc or inc.clock ~= tonumber(rest) then return end
        local stops = {}
        for i = 1, inc.total do if inc.stops[i] then stops[#stops + 1] = inc.stops[i] end end
        if state.joined then
            if newer(inc.clock, sender) then
                state.stops, state.clock, state.editor = stops, inc.clock, sender
                changed()
                if state.following then
                    ns:Print(sender .. " updated the party route (" .. #stops .. " stops)")
                end
            end
        else
            offer = { clock = inc.clock, editor = sender, stops = stops }
            P:ShowPrompt(sender, #stops)
        end
    elseif kind == "Q" then
        if state.joined then P:Broadcast() end
        P:SendQuests()
    elseif kind == "L" then
        local part, _, list = rest:match("^(%d+)|(%d+)|(.*)$")
        members[sender] = members[sender] or { quests = {} }
        if tonumber(part) == 1 then members[sender].quests = {} end
        for id in (list or ""):gmatch("%d+") do members[sender].quests[tonumber(id)] = true end
    elseif kind and P.handlers[kind] then
        P.handlers[kind](sender, rest)   -- other modules' messages (PartyHelp.lua: quest progress)
    end
end

-- Other modules can use the same addon channel: P.handlers[letter] =
-- function(sender, rest) receives "letter|rest"; P.Send(msg) sends one.
P.handlers = {}
P.Send = function(msg) send(msg) end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

function P:Active() return state.joined end
function P:InGroup() return channel() ~= nil end
-- True when the arrow and plan should use the party route.
function P:Following() return state.joined and state.following end
function P:Stops() return state.stops end
function P:Editor() return state.editor ~= "" and state.editor or nil end

function P:SetFollowing(on)
    if not state.joined then return end
    state.following = on and true or false
    changed()
    ns:Print(on and "following the party route" or "following your own route (the party route is kept; switch back any time)")
end

local function edit(fn)
    fn(state.stops)
    while #state.stops > MAX_STOPS do table.remove(state.stops) end
    state.clock = state.clock + 1
    state.editor = me()
    P:Broadcast()
    changed()
end

function P:MoveFirst(id)
    edit(function(stops)
        for i, s in ipairs(stops) do
            if s.id == id then table.insert(stops, 1, table.remove(stops, i)) return end
        end
    end)
end

function P:AddFront(map, x, y, label, level, kind)
    edit(function(stops)
        table.insert(stops, 1, { id = newId(), map = map, x = x, y = y, label = label, level = level, kind = kind })
    end)
end

function P:AddGoal(goal)
    local p = ns.nav:PlayerPos()
    local best, bd
    for _, pt in ipairs(goal.points or {}) do
        if pt.map and pt.wx and p and pt.cont == p.cont then
            local d = (pt.wx - p.wx) ^ 2 + (pt.wy - p.wy) ^ 2
            if not bd or d < bd then best, bd = pt, d end
        end
    end
    if best then self:AddFront(best.map, best.x, best.y, goal.text or goal.title, goal.level, "shared") end
end

function P:Done(id)
    edit(function(stops)
        for i, s in ipairs(stops) do if s.id == id then table.remove(stops, i) return end end
    end)
end

-------------------------------------------------------------------------------
-- Building a party route
-------------------------------------------------------------------------------

local function questOf(key) return tonumber(key:match("^(%d+):")) end

-- Stops for a party route, and why: quests party members share come first.
function P:EstimateStops()
    local p = ns.nav:PlayerPos()
    if not p then return {}, "no position" end
    local goals = {}
    for _, g in ipairs(ns.nav:Goals()) do
        -- (not party stops, and not a friend's quests you're helping with: only your own)
        if not g.key:find("^party:") and not g.key:find("^help:") and g.key ~= "user:wp" then goals[#goals + 1] = g end
    end
    local counts = {}
    for id in pairs(ns.quests:LogIds()) do counts[id] = 1 end
    for _, m in pairs(members) do
        for id in pairs(m.quests) do counts[id] = (counts[id] or 0) + 1 end
    end
    local common, shared = {}, {}
    for _, g in ipairs(goals) do
        local q = questOf(g.key)
        if q and (counts[q] or 0) >= 2 then common[g.key] = true; shared[q] = true end
    end
    local plan, why
    if next(common) then
        local n = 0
        for _ in pairs(shared) do n = n + 1 end
        plan = ns.planner:Plan(p, goals, { tour = common, air = ns.nav.TravelYards })
        why = n .. " quest(s) you share come first"
    else
        plan = ns.planner:Plan(p, goals, { air = ns.nav.TravelYards })
        why = "your current route (no shared quests yet)"
    end
    local stops = {}
    for _, s in ipairs(plan or {}) do
        local pt = s.point
        if pt and pt.map and pt.x and #stops < MAX_STOPS then
            stops[#stops + 1] = { id = newId(), map = pt.map, x = pt.x, y = pt.y,
                label = s.goal.text or s.goal.title, level = s.goal.level, kind = "shared" }
        end
    end
    return stops, why
end

function P:Share(auto)
    if not channel() then ns:Print("you're not in a group") return end
    local stops, why = self:EstimateStops()
    if #stops == 0 then
        if not auto then ns:Print("nothing to share yet") end
        return
    end
    state.joined, state.following = true, true
    edit(function(st)
        wipe(st)
        for _, s in ipairs(stops) do st[#st + 1] = s end
    end)
    ns:Print(string.format("%s the party route: %d stops; %s. Anyone can edit it.",
        auto and "made" or "shared", #stops, why))
end

function P:Join(follow)
    if not offer then ns:Print("no party route to join yet") return end
    state.joined = true
    state.following = follow ~= false
    state.stops, state.clock, state.editor = offer.stops, offer.clock, offer.editor
    offer = nil
    if self.prompt then self.prompt:Hide() end
    changed()
    ns:Print(state.following and "following the party route. Switch back to yours any time (under the arrow)."
        or "kept your own route. The party route is there if you want it (under the arrow).")
end

function P:Leave(quiet)
    state.joined, state.following = false, false
    wipe(state.stops)
    changed()
    if not quiet then ns:Print("left the party route; back to your own") end
end

-------------------------------------------------------------------------------
-- Navigation: party stops are goals only while you follow the party route.
-------------------------------------------------------------------------------

ns:Register("navGoal", "party", {
    collect = function()
        if not P:Following() then return nil end
        local out, prev = {}, nil
        for i, s in ipairs(state.stops) do
            local key = "party:" .. s.id
            out[#out + 1] = {
                key = key, weight = 0.5, level = s.level,
                points = { { map = s.map, x = s.x, y = s.y } },
                title = s.label, text = "Party: " .. (s.label or "stop " .. i),
                details = { "Party route stop " .. i .. " of " .. #state.stops .. ".",
                            "Anyone following it can move it, add stops, or reach it to clear it." },
                deps = prev and { prev } or nil,
            }
            prev = key
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- UI: join prompt and the party/mine toggle under the arrow
-------------------------------------------------------------------------------

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

function P:ShowPrompt(sender, n)
    if not self.prompt then
        local f = CreateFrame("Frame", "FlowPartyPrompt", UIParent)
        f:SetSize(340, 78)
        f:SetPoint("TOP", 0, -200)
        f:SetFrameStrata("DIALOG")
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        local top = f:CreateTexture(nil, "BORDER")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
        local c = ns.theme.user
        top:SetColorTexture(c[1], c[2], c[3], 0.9)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOP", 0, -10)
        f.text:SetWidth(320)
        local follow = button(f, "Follow party route", 140)
        follow:SetPoint("BOTTOMLEFT", 20, 10)
        follow:SetScript("OnClick", function() P:Join(true) end)
        local mine = button(f, "Keep my route", 140)
        mine:SetPoint("BOTTOMRIGHT", -20, 10)
        mine:SetScript("OnClick", function() P:Join(false) end)
        self.prompt = f
    end
    self.prompt.text:SetText(string.format("%s's party route: %d stops.\nFollow it? You can switch back to your own any time.", sender, n))
    self.prompt:Show()
end

function P:RefreshToggle()
    local arrow = _G.FlowNavArrow
    if not arrow then return end
    if not self.toggle then
        local t = CreateFrame("Button", nil, arrow)
        t:SetSize(140, 16)
        t:SetPoint("TOP", arrow, "BOTTOM", 0, -34)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetAllPoints()
        t:SetScript("OnClick", function() P:SetFollowing(not state.following) end)
        self.toggle = t
    end
    if not state.joined then self.toggle:Hide() return end
    local c = ns.theme.user
    self.toggle.text:SetText(state.following
        and string.format("|cff%sParty route|r  (click: my route)", c.hex)
        or "My route  |cff888888(click: party route)|r")
    self.toggle:Show()
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

ns:OnLoad(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end)

ns:On("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= PREFIX or not msg or not sender then return end
    if P.IsMe(sender) then return end   -- your own message, echoed back
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    if P.IsMe(name) then return end
    received(name, msg)
end)

local lastRoster = 0
local function onRoster()
    local nowIn = channel() ~= nil
    if not nowIn then
        if state.joined then P:Leave(true); ns:Print("left the group, so the party route ended") end
        inGroup = false
        wipe(members)
        offer = nil
        return
    end
    if not inGroup then
        -- Just joined or formed a group: ask for a route and share our quests.
        -- Never switch you onto a party route by itself: as leader you get a
        -- one-line hint; others get the usual prompt when a route is shared.
        inGroup = true
        send("Q|0")
        P:SendQuests()
        -- (Flow players in the group are asked about the party route by
        -- PartyHelp.lua when their quest progress arrives.)
        return
    end
    -- Someone else joined: re-share (throttled) so they get the prompt.
    if GetTime() - lastRoster < 5 then return end
    lastRoster = GetTime()
    if state.joined then P:Broadcast() end
    P:SendQuests()
end

ns:On("GROUP_ROSTER_UPDATE", onRoster)
ns:On("PARTY_MEMBERS_CHANGED", onRoster)  -- older clients
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, onRoster) end)
ns:On("QUEST_ACCEPTED", function() P:SendQuests() end)
ns:On("QUEST_TURNED_IN", function() P:SendQuests() end)

ns.commands.party = function(arg)
    arg = (arg or ""):lower()
    if arg == "share" then P:Share(false)
    elseif arg == "join" or arg == "follow" then
        -- The party route (PartyHelp.lua); a hand-made one someone shared
        -- with /flow party share is joined if that's what's on offer.
        if offer and not state.joined then P:Join(true)
        elseif ns.partyHelp then ns.partyHelp:Join() end
    elseif arg == "mine" or arg == "leave" then
        if state.joined then P:Leave(true) end
        if ns.partyHelp then ns.partyHelp:Stop() end
    elseif arg:find("^help") then
        if ns.partyHelp then ns.partyHelp:Command(arg:match("^help%s*(.*)$")) end
    elseif arg:find("^quests") then
        if ns.partyHelp then ns.partyHelp:Command(arg:match("^quests%s*(.*)$")) end
    elseif arg:find("^follow%s+%S") then
        if ns.follow then ns.follow:Command(arg:match("^follow%s+(.*)$")) end
    else
        if state.joined then
            ns:Print(string.format("party route: %d stops, last edit by %s. You're following %s.",
                #state.stops, state.editor, state.following and "the party route" or "your own route"))
        elseif offer then
            ns:Print(offer.editor .. " shared a party route: /flow party join")
        else
            ns:Print("no party route.")
        end
        if ns.partyHelp then ns.partyHelp:Status() end
        if ns.follow then print("  " .. ns.follow:Status()) end
        print("  /flow party join|leave, /flow party quests mine|<name>, /flow follow <name>|off")
    end
end

ns:Register("help", "party", { order = 45, title = "Party route", lines = {
    "Flow players in a group share how far they are on each quest (only what changed, a few bytes at a time).",
    "Join the party route: everyone on it gets one route for all their quests, the same route and the same next stop for all of you (one of you plans it).",
    "Or keep your own route, or do just one member's quests. Choose under the arrow or in the route menu (right-click the arrow).",
    "Follow a party member: the arrow points at them (route menu, or /flow follow <name>).",
    "/flow party join|leave, /flow party quests mine|<name>",
} })
