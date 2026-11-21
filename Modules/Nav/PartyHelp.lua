-- Party quest progress: Flow players in a group send each other how far they
-- are on every quest in their log (each objective's count, e.g. 3/10, and
-- whether it's ready to hand in). Whose quests your route covers:
--   Your own route      your quests only (the default)
--   The party route     everyone who joined it: all their quests (objectives,
--                       quest items, turn-ins) as one optimal route, kept up
--                       to date as anyone's progress changes. Each spot is one
--                       stop saying who it's for.
--   Just <name>'s       only what they still need (kill credit is shared in a
--                       party), where they hand in, and your own steps only
--                       where they need the same thing
-- Their steps say whose they are ("Bob: ..."), and "(done for you)" when
-- you've already finished that part yourself. Flow asks when a party member
-- first shares (Join the party route / Just <name>'s / Not now) and when
-- someone joins the party route. Change it any time: the line under the
-- arrow, the route menu (right-click the arrow), or /flow party join|leave,
-- /flow party quests mine|<name>. Leaving the group goes back to your own.
--
-- Messages (on Party.lua's addon channel), sent only when something changed:
--   G|part|parts|body   everything: entries joined by ",":
--                       "83=c" ready to hand in, "86=2/4.0/1" objective counts
--   D|entries|ids       just what changed since the last send: changed or new
--                       entries, and the ids of quests that left the log
--   R|0  / R|<name>     "send me your progress" (everyone / just that player)
--   J|1  / J|0          joined / left the party route

local _, ns = ...
local H = {}
ns.partyHelp = H

local MAX_PART = 220
local progress = {}   -- name -> { [questId] = { complete, objectives = { { have, need, finished } } } }
local buffers = {}    -- name -> progress being received
local asked = {}      -- name -> true: already asked this group
local scope = "mine"  -- "mine" | "theirs" | "combined" (= the party route)
local focus           -- the party member for "theirs"
local joinedBy = {}   -- name -> true: they're on the party route
local askedJoin = {}  -- name -> true: asked "join them?" this group
local order           -- the party route's order from its planner: { leader, entries, at }
local lastOrder, lastOrderAt = nil, 0   -- (as the planner: what you last sent)

-------------------------------------------------------------------------------
-- Encoding
-------------------------------------------------------------------------------

-- One quest: "83=c" (ready to hand in) or "86=2/4.0/1" (objective counts).
function H.EncodeEntry(id, e)
    if e.complete then return id .. "=c" end
    local objs = {}
    for _, o in ipairs(e.objectives or {}) do
        objs[#objs + 1] = string.format("%d/%d", o.have or 0, o.need or 1)
    end
    return id .. "=" .. table.concat(objs, ".")
end

-- prog = { [id] = { complete, objectives = { { have, need } } } } -> parts.
function H.Encode(prog)
    local ids = {}
    for id in pairs(prog) do ids[#ids + 1] = id end
    table.sort(ids)
    local entries = {}
    for _, id in ipairs(ids) do entries[#entries + 1] = H.EncodeEntry(id, prog[id]) end
    local parts, cur = {}, ""
    for _, en in ipairs(entries) do
        if cur ~= "" and #cur + 1 + #en > MAX_PART then parts[#parts + 1] = cur; cur = "" end
        cur = cur == "" and en or (cur .. "," .. en)
    end
    parts[#parts + 1] = cur
    return parts
end

-- One part's body -> entries added to `into`.
function H.Decode(body, into)
    into = into or {}
    for id, rest in (body or ""):gmatch("(%d+)=([^,]*)") do
        local e = { complete = rest == "c", objectives = {} }
        if not e.complete then
            for have, need in rest:gmatch("(%d+)/(%d+)") do
                have, need = tonumber(have), tonumber(need)
                e.objectives[#e.objectives + 1] = { have = have, need = need, finished = have >= need }
            end
        end
        into[tonumber(id)] = e
    end
    return into
end

-------------------------------------------------------------------------------
-- Your progress, sent to the party
-------------------------------------------------------------------------------

function H.Mine()
    local out = {}
    for _, q in ipairs(ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        local e = { complete = q.complete and true or false, objectives = {} }
        local counts = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id)
        for i, o in ipairs(q.objectives) do
            local c = counts and counts[i]
            local have, need = c and c.numFulfilled, c and c.numRequired
            if not need then
                have, need = (o.text or ""):match("(%d+)%s*/%s*(%d+)")
                have, need = tonumber(have), tonumber(need)
            end
            if not need or need < 1 then have, need = o.finished and 1 or 0, 1 end
            e.objectives[#e.objectives + 1] = { have = have or 0, need = need, finished = o.finished and true or false }
        end
        out[q.id] = e
    end
    return out
end

-- What changed between two sends: changed or new entries, and gone ids.
-- last / now: { [id] = entry string }. Returns changed (list), gone (list).
function H.Diff(last, now)
    local changed, gone = {}, {}
    for id, s in pairs(now) do if last[id] ~= s then changed[#changed + 1] = s end end
    for id in pairs(last) do if not now[id] then gone[#gone + 1] = tostring(id) end end
    table.sort(changed); table.sort(gone)
    return changed, gone
end

-- Apply a "D" message to someone's progress.
function H.ApplyDiff(prog, changedText, goneText)
    H.Decode(changedText, prog)
    for id in (goneText or ""):gmatch("%d+") do prog[tonumber(id)] = nil end
    return prog
end

-- Send your progress: everything when asked (force), otherwise only what
-- changed since last time (usually one short message), nothing if nothing did.
local lastEntries, lastSentAt = nil, 0
function H.SendMine(force)
    if not (ns.party and ns.party:InGroup()) then return end
    local mine = H.Mine()
    local now = {}
    for id, e in pairs(mine) do now[id] = H.EncodeEntry(id, e) end
    if not force and lastEntries then
        local changed, gone = H.Diff(lastEntries, now)
        if #changed == 0 and #gone == 0 then return end
        local msg = "D|" .. table.concat(changed, ",") .. "|" .. table.concat(gone, ",")
        if #msg <= 240 then
            lastEntries, lastSentAt = now, GetTime()
            ns.party.Send(msg)
            return
        end
    end
    lastEntries, lastSentAt = now, GetTime()
    local parts = H.Encode(mine)
    for i, p in ipairs(parts) do ns.party.Send(string.format("G|%d|%d|%s", i, #parts, p)) end
    if scope == "combined" then ns.party.Send("J|1") end
end

-- Quest log changes come in bursts: send 2 s after the last one.
local pending = false
local function soon()
    if pending then return end
    pending = true
    C_Timer.After(2, function() pending = false; pcall(H.SendMine) end)
end

-------------------------------------------------------------------------------
-- Their progress
-------------------------------------------------------------------------------

-- Quests they still have something to do for (not ready to hand in).
function H.ToDo(prog)
    local n = 0
    for _, e in pairs(prog or {}) do
        if not e.complete then n = n + 1 end
    end
    return n
end

function H.Progress(name) return progress[name] end
-- Forget someone's progress (a name that turned out to be you).
function H.Drop(name)
    if not name then return end
    progress[name], joinedBy[name], buffers[name] = nil, nil, nil
    -- (You were following "just their quests", which were your own: back to your route.)
    if scope == "theirs" and focus == name and H.SetScope then pcall(H.SetScope, H, "mine") end
    if H.RefreshToggle then pcall(H.RefreshToggle, H) end
end
function H.All() return progress end   -- name -> progress (QuestShare.lua reads who has what)
function H:Scope() return scope, focus end
function H:Joined() return scope == "combined" end
-- Who else is on the party route (that you have progress from).
function H.OnRoute()
    local out = {}
    for name in pairs(progress) do if joinedBy[name] then out[#out + 1] = name end end
    table.sort(out)
    return out
end
-- Anyone's quests besides yours on the route? (a name for "theirs", "the party" for the party route)
function H:Helping()
    if scope == "theirs" then return focus end
    if scope == "combined" then return "the party" end
end

local function changed()
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
    if H.RefreshToggle then H:RefreshToggle() end
end

-- What the route covers: "mine", "theirs" (with a name) or "combined" (the
-- party route). Joining or leaving the party route tells the party (J).
function H:SetScope(s, name, why)
    if s == "theirs" and not progress[name] then
        ns:Print("no quest progress from " .. tostring(name) .. " yet (they need Flow too)")
        return
    end
    local was = scope
    scope, focus = s, (s == "theirs") and name or nil
    if s ~= "combined" then order, lastOrder = nil, nil end
    if self.prompt then self.prompt:Hide() end
    if (s == "combined") ~= (was == "combined") and ns.party and ns.party:InGroup() then
        ns.party.Send(s == "combined" and "J|1" or "J|0")
    end
    changed()
    if s == "theirs" then
        ns:Print(string.format("route: just %s's quests (%d to do). Change it under the arrow.", name, H.ToDo(progress[name])))
    elseif s == "combined" then
        local others = H.OnRoute()
        ns:Print("joined the party route: everyone on it gets one route for all their quests"
            .. (#others > 0 and (" (with " .. table.concat(others, ", ") .. ")") or " (others join it from their route menu)")
            .. ". Change it under the arrow.")
    elseif was ~= "mine" then
        ns:Print("route: your own quests" .. (why and (" (" .. why .. ")") or ""))
    end
end
function H:Join() self:SetScope("combined") end
function H:Help(name) self:SetScope("theirs", name) end
function H:Stop(why) if scope ~= "mine" then self:SetScope("mine", nil, why) end end

-- Ask once per person per group, when they have something left to do (not
-- when your route already covers other people's quests).
function H:MaybeAsk(name)
    if asked[name] or scope ~= "mine" or ns.party.IsMe(name) then return end
    local todo = H.ToDo(progress[name])
    if todo == 0 then return end
    asked[name] = true
    self:ShowPrompt(name, todo, joinedBy[name])
end

local function arrived(sender)
    if scope ~= "mine" then changed() else H:MaybeAsk(sender); H:RefreshToggle() end
    -- Quests you have and they don't: shared one at a time (Quests/QuestShare.lua).
    if ns.questShare then pcall(ns.questShare.ShareMissing, ns.questShare) end
end

ns.party.handlers.G = function(sender, rest)
    local part, parts, body = rest:match("^(%d+)|(%d+)|(.*)$")
    part, parts = tonumber(part), tonumber(parts)
    if not part then return end
    if ns.party.IsMe(sender) then return end   -- (never your own progress)
    if part == 1 then buffers[sender] = {} end
    local buf = buffers[sender]
    if not buf then return end
    H.Decode(body, buf)
    if part < parts then return end
    buffers[sender] = nil
    progress[sender] = buf
    arrived(sender)
end
-- Just what changed. Missed the full list? Ask that player for it.
ns.party.handlers.D = function(sender, rest)
    if ns.party.IsMe(sender) then return end
    local changedText, goneText = rest:match("^([^|]*)|?(.*)$")
    if not progress[sender] then ns.party.Send("R|" .. sender) return end
    H.ApplyDiff(progress[sender], changedText, goneText)
    arrived(sender)
end
-- "Send me your progress": everyone (R|0) or just you (R|<your name>).
ns.party.handlers.R = function(_, who)
    if who and who ~= "0" and not ns.party.IsMe(who) then return end
    if GetTime() - lastSentAt > 2 then H.SendMine(true) end
end
-- Someone joined or left the party route.
ns.party.handlers.J = function(sender, on)
    if ns.party.IsMe(sender) then return end
    local was = joinedBy[sender]
    joinedBy[sender] = (on == "1") or nil
    if was == joinedBy[sender] then return end
    if scope == "combined" then
        changed()
        ns:Print(sender .. (joinedBy[sender] and " joined the party route: their quests are on it now" or " left the party route"))
    elseif joinedBy[sender] and not askedJoin[sender] and progress[sender] then
        askedJoin[sender] = true
        H:ShowPrompt(sender, H.ToDo(progress[sender]), true)
    end
    H:RefreshToggle()
end

-------------------------------------------------------------------------------
-- Route: whose quests it covers
-------------------------------------------------------------------------------

-- Leave out what your own quests already cover: an objective you still need
-- yourself (your own step is there) and the turn-in of a quest you have too,
-- unless they're ready to hand it in and you aren't (your turn-in waits for
-- your objectives; theirs mustn't). theirs: their entry for that quest.
function H.Skip(key, mine, theirs)
    local id, rest = key:match("^help:(%d+):(.+)$")
    local own = mine[tonumber(id)]
    if not own then return false end
    if rest == "done" then return not (theirs and theirs.complete and not own.complete) end
    local o = own.objectives[tonumber(rest)]
    return o ~= nil and not o.finished
end

-- A party member's step that you've already done yourself: that objective
-- (or the whole quest) is finished in your log, or you handed the quest in
-- before. Their step then says "(done for you)".
function H.DoneForYou(key, mineE, doneBefore)
    local rest = key:match("^help:%d+:(.+)$")
    if not rest then return false end
    if mineE then
        if mineE.complete then return true end
        local o = rest ~= "done" and mineE.objectives[tonumber(rest)]
        return o and o.finished or false
    end
    return doneBefore and true or false
end

-- Whose progress the route covers now: { [name] = progress } or nil. The
-- party route: everyone else who joined it (your own quests are there anyway).
function H.Covered(sc, who, prog, joined)
    if sc == "theirs" then return who and prog[who] and { [who] = prog[who] } or nil end
    if sc == "combined" then
        local out
        for name, p in pairs(prog) do
            if joined[name] then out = out or {}; out[name] = p end
        end
        return out
    end
end
local function covered() return H.Covered(scope, focus, progress, joinedBy) end

ns:Register("navGoal", "partyhelp", {
    collect = function()
        local who = covered()
        local db = who and ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not (db and ns.quests.QuestGoals) then return nil end
        local mine = H.Mine()
        local names, byKey, out = {}, {}, {}
        for name in pairs(who) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local list = {}
            for id, e in pairs(who[name]) do
                ns.quests.QuestGoals(db, { id = id, complete = e.complete, objectives = e.objectives }, list,
                    { prefix = "help:", who = name, skip = function(key) return H.Skip(key, mine, e) end })
            end
            for _, g in ipairs(list) do
                local had = byKey[g.key]
                if had then
                    had.forNames[#had.forNames + 1] = name   -- the same spot for two of them: one step
                else
                    g.forNames = { name }
                    byKey[g.key] = g
                    out[#out + 1] = g
                end
            end
        end
        for _, g in ipairs(out) do
            local id = tonumber(g.key:match("^help:(%d+):"))
            local whoText = table.concat(g.forNames, ", ")
            g.helping = whoText
            -- QuestGoals wrote "<first name>: "; with more names, all of them.
            if #g.forNames > 1 then g.text = whoText .. g.text:sub(#g.forNames[1] + 1) end
            if H.DoneForYou(g.key, mine[id], ns.quests:IsCompleted(id)) then
                g.doneForYou = true
                g.text = g.text .. " |cff40ff40(done for you)|r"
                g.details = g.details or {}
                table.insert(g.details, 1, "You've done this part yourself: it's for " .. whoText .. ".")
            end
        end
        return out
    end,
})

-- "Just <name>'s": their steps, your own where they need the same objective
-- or you both hand in the same quest, and party-route steps. Nothing else.
function H.Keep(list, their)
    local out = {}
    for _, g in ipairs(list) do
        local k = g.key
        local keep = k:find("^help:") ~= nil or k:find("^party:") ~= nil
        if not keep then
            local id, rest = k:match("^(%d+):(.+)$")
            local e = id and their[tonumber(id)]
            if e then
                if rest == "done" then keep = true
                else
                    local o = not e.complete and e.objectives[tonumber(rest)]
                    keep = (o and not o.finished) and true or false
                end
            end
        end
        if keep then out[#out + 1] = g end
    end
    return out
end
-- The party route is quests only (objectives, quest items, turn-ins), so
-- everyone on it plans from the same kind of steps: no one's own trainers,
-- pickups or gathering. (Nav.lua, after collecting every provider's goals)
function H.QuestsOnly(list)
    local out = {}
    for _, g in ipairs(list) do
        local k = g.key
        if k:find("^%d+:") or k:find("^help:") or k:find("^party:") then out[#out + 1] = g end
    end
    return out
end
function H:FilterGoals(list)
    if scope == "combined" then return H.QuestsOnly(list) end
    if scope ~= "theirs" or not (focus and progress[focus]) then return list end
    return H.Keep(list, progress[focus])
end

-------------------------------------------------------------------------------
-- One route for everyone on the party route
--   The planner: the group leader if they're on it, otherwise whoever's name
--   comes first. They plan as usual and send the order and spots of the next
--   8 steps in one short message when it changes:
--     O|key~map~x~y,key~map~x~y,...   key: "83:1", "86:done" (whoever's quest)
--   Everyone else on the route follows that order and those spots, so you
--   all head to the same place. No order for 90 s: plan for yourself.
-------------------------------------------------------------------------------

local function plainLower(n) return (n and (n:match("^([^%-]+)") or n) or ""):lower() end

-- Who plans: the group leader if on the route, else the first name.
function H.Leader(me, others, groupLeader)
    local all = { me }
    for _, n in ipairs(others) do all[#all + 1] = n end
    if groupLeader then
        for _, n in ipairs(all) do if plainLower(n) == plainLower(groupLeader) then return n end end
    end
    table.sort(all, function(a, b) return plainLower(a) < plainLower(b) end)
    return all[1]
end

local function groupLeaderName()
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return UnitName("player") end
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and 40 or 4 do
        local u = (raid and "raid" or "party") .. i
        if UnitExists(u) and UnitIsGroupLeader and UnitIsGroupLeader(u) then return (UnitName(u)) end
    end
end

function H:RouteLeader()
    if scope ~= "combined" then return nil end
    return H.Leader(UnitName("player"), H.OnRoute(), groupLeaderName())
end
function H:IsRouteLeader()
    local l = self:RouteLeader()
    return l ~= nil and plainLower(l) == plainLower(UnitName("player"))
end

local function canon(key) return (key:gsub("^help:", "")) end
H._canon = canon

-- The leader's next steps as a message body (nil if nothing to send).
function H.OrderBody(plan, n)
    local parts = {}
    for i, s in ipairs(plan or {}) do
        if i > (n or 8) then break end
        local pt = s.point
        if pt and pt.map and pt.x and pt.y and s.goal and s.goal.key then
            parts[#parts + 1] = string.format("%s~%d~%.4f~%.4f", canon(s.goal.key), pt.map, pt.x, pt.y)
        end
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end
function H.ParseOrder(body)
    local out = {}
    for key, map, x, y in (body or ""):gmatch("([^~,]+)~(%d+)~([%d%.]+)~([%d%.]+)") do
        out[#out + 1] = { key = key, map = tonumber(map), x = tonumber(x), y = tonumber(y) }
    end
    return out
end

-- Leader: send the order when its next steps change (at most every 2 s; the
-- same order again only every 30 s, for anyone who joined since).
function H:Publish(plan)
    if not (scope == "combined" and ns.party and ns.party:InGroup() and #H.OnRoute() > 0 and self:IsRouteLeader()) then return end
    local body = H.OrderBody(plan, 8)
    if not body then return end
    local now = GetTime()
    if body == lastOrder and now - lastOrderAt < 30 then return end
    if now - lastOrderAt < 2 then
        if not H.publishSoon then
            H.publishSoon = true
            C_Timer.After(2, function() H.publishSoon = false; if ns.nav then pcall(H.Publish, H, ns.nav.plan) end end)
        end
        return
    end
    lastOrder, lastOrderAt = body, now
    ns.party.Send("O|" .. body)
end

ns.party.handlers.O = function(sender, body)
    if ns.party.IsMe(sender) or scope ~= "combined" then return end
    local leader = H:RouteLeader()
    if not (leader and plainLower(leader) == plainLower(sender)) then return end   -- only the planner's
    order = { leader = sender, entries = H.ParseOrder(body), at = GetTime() }
    if ns.nav then ns.nav.planDirty = true end
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- A step on the leader's route that isn't one of your goals (their own
-- quest you can't help with): still on your route, so you stay together.
local function routeGoal(e, leader)
    local id, part = e.key:match("^(%d+):(.+)$")
    local q = id and ns.quests:QuestieGet("GetQuest", tonumber(id))
    local name = q and q.name or "a quest"
    return { key = "route:" .. e.key, kind = part == "done" and "turnin" or "party", title = name,
             text = leader .. "'s route: " .. name .. (part == "done" and " (hand in)" or ""),
             details = { "On the party route that " .. leader .. " plans: you all head here together." } }
end

-- Follower: your plan from the leader's order. nil = plan yourself.
function H:SharedPlan(p, goals)
    if scope ~= "combined" or not order or self:IsRouteLeader() then return nil end
    if GetTime() - order.at > 90 then return nil end
    local byKey = {}
    for _, g in ipairs(goals) do byKey[g.key] = g end
    local plan, cum, x, y = { dropped = {}, sharedBy = order.leader }, 0, p.wx, p.wy
    for _, e in ipairs(order.entries) do
        local cont, wx, wy = ns.nav:ToWorld(e.map, e.x, e.y)
        if wx and cont == p.cont then
            local pt = { map = e.map, x = e.x, y = e.y, cont = cont, wx = wx, wy = wy }
            local g = byKey[e.key] or byKey["help:" .. e.key]
            if not g then g = routeGoal(e, order.leader); g.points = { pt } end
            local leg = dist(x, y, wx, wy)
            cum = cum + leg
            plan[#plan + 1] = { goal = g, point = pt, leg = leg, cum = cum }
            x, y = wx, wy
        end
    end
    return #plan > 0 and plan or nil
end

-------------------------------------------------------------------------------
-- UI: the question, the line under the arrow, the route menu
-------------------------------------------------------------------------------

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

-- The question. joined: they're on the party route already ("join them?").
function H:ShowPrompt(name, todo, joined)
    if not self.prompt then
        local f = CreateFrame("Frame", "FlowHelpPrompt", UIParent)
        f:SetSize(400, 84)
        f:SetPoint("TOP", 0, -290)
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
        f.text:SetWidth(380)
        f.join = button(f, "Join the party route", 150)
        f.join:SetPoint("BOTTOMLEFT", 12, 10)
        f.join:SetScript("OnClick", function() H:Join() end)
        f.theirs = button(f, "Just theirs", 120)
        f.theirs:SetPoint("LEFT", f.join, "RIGHT", 6, 0)
        f.theirs:SetScript("OnClick", function() H:SetScope("theirs", f.name) end)
        local no = button(f, "Not now", 90)
        no:SetPoint("BOTTOMRIGHT", -12, 10)
        no:SetScript("OnClick", function() f:Hide() end)
        self.prompt = f
    end
    local f = self.prompt
    f.name = name
    f.theirs:SetText("Just " .. name .. "'s")
    f.theirs:SetShown(not joined)
    if joined then
        f.text:SetText(string.format("%s joined the party route (%d quest(s) to do).\nJoin it? Everyone on it gets one route for all their quests.", name, todo))
    else
        f.text:SetText(string.format("%s is in your group with Flow: %d quest(s) to do.\nJoin the party route? Everyone on it gets one route for all their quests.", name, todo))
    end
    f:Show()
end

-- The choices, for the route menu ("Party") and the line under the arrow.
function H:MenuItems()
    local onRoute = H.OnRoute()
    local items = {
        { text = "Your own route", radio = true, checked = scope == "mine" and not (ns.party and ns.party:Following()),
          func = function()
              if ns.party and ns.party:Following() then ns.party:SetFollowing(false) end
              H:SetScope("mine")
          end },
        { text = "Join the party route" .. (#onRoute > 0 and (" (" .. table.concat(onRoute, ", ") .. " on it)") or ""),
          radio = true, checked = scope == "combined", func = function() H:Join() end },
    }
    local names = {}
    for name in pairs(progress) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        items[#items + 1] = { text = string.format("Just %s's quests (%d to do)", name, H.ToDo(progress[name])), radio = true,
            checked = scope == "theirs" and focus == name, func = function() H:SetScope("theirs", name) end }
    end
    return items
end

function H.ScopeText()
    if scope == "theirs" then return "Just " .. focus .. "'s quests" end
    if scope == "combined" then
        local others = H.OnRoute()
        return "Party route" .. (#others > 0 and (" (you, " .. table.concat(others, ", ") .. ")") or " (just you so far)")
    end
    return "Your own route"
end

function H:RefreshToggle()
    local arrow = _G.FlowNavArrow
    if not arrow then return end
    if not self.toggle then
        local t = CreateFrame("Button", nil, arrow)
        t:SetSize(220, 16)
        t:SetPoint("TOP", arrow, "BOTTOM", 0, -50)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetAllPoints()
        t:SetScript("OnClick", function()
            local items = { { title = true, text = "Party" } }
            for _, it in ipairs(H:MenuItems()) do items[#items + 1] = it end
            ns.menu:Open(items)
        end)
        self.toggle = t
    end
    if not next(progress) and scope ~= "combined" then self.toggle:Hide() return end
    local c = ns.theme.user
    self.toggle.text:SetText(string.format("|cff%s%s|r  |cff888888(click: change)|r",
        scope == "mine" and "ffffff" or c.hex, H.ScopeText()))
    self.toggle:Show()
end

function H:Status()
    local names = {}
    for name, prog in pairs(progress) do
        names[#names + 1] = string.format("%s (%d to do%s)", name, H.ToDo(prog), joinedBy[name] and ", on the party route" or "")
    end
    print("  quest progress from: " .. (#names > 0 and table.concat(names, ", ") or "nobody yet (they need Flow)")
        .. "; you: " .. H.ScopeText())
end

-- /flow party quests mine|party|<name>  (and the older help <name>|off)
function H:Command(arg)
    arg = (arg or ""):lower()
    if arg == "" then self:Status() return end
    if arg == "off" or arg == "stop" or arg == "mine" then self:SetScope("mine") return end
    if arg == "party" or arg == "combined" or arg == "join" or arg == "all" then self:Join() return end
    for name in pairs(progress) do
        if name:lower() == arg or name:lower():match("^([^%-]+)") == arg then self:SetScope("theirs", name) return end
    end
    ns:Print("no quest progress from " .. arg .. " (are they in your group, with Flow?)")
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

local inGroup = false
local function onRoster()
    local now = ns.party and ns.party:InGroup()
    if not now then
        H:Stop("you left the group")
        wipe(progress); wipe(buffers); wipe(asked); wipe(joinedBy); wipe(askedJoin)
        order, lastOrder = nil, nil
        lastEntries = nil   -- next group gets the full list
        inGroup = false
        H:RefreshToggle()
        return
    end
    if not inGroup then
        inGroup = true
        ns.party.Send("R|0")
        H.SendMine(true)
        return
    end
    -- Someone left: drop their progress; someone joined: they get ours.
    for name in pairs(progress) do
        if not ((UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name))) then
            progress[name], joinedBy[name] = nil, nil
            if scope == "theirs" and focus == name then H:Stop(name .. " left the group") end
            if scope == "combined" then changed() end
        end
    end
    H:RefreshToggle()
    if GetTime() - lastSentAt > 5 then H.SendMine(true) end   -- (roster updates come in bursts)
end

ns:On("GROUP_ROSTER_UPDATE", function() C_Timer.After(1, onRoster) end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, onRoster) end)
ns:On("QUEST_LOG_UPDATE", soon)
ns:On("QUEST_ACCEPTED", soon)
ns:On("QUEST_TURNED_IN", soon)
