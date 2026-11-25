local _, ns = ...
-- Z-Flow party route (G48, lead dispatch P-TRIP). The player who planned a
-- route (Nav/TripRoute.lua, the route word) can share it with the party;
-- party members who run the add-on are offered it in one locally printed
-- line and can follow it on their own arrow.
--
-- SAFETY: the only outward call of the add-on. It sends add-on messages
-- (never chat text, never whispers, never a public channel) on the "PARTY"
-- channel only, to the player's own party, only when the player types
-- `route share` or `route ask` (or, once per ANSWER_EVERY seconds, to
-- answer a party member's ask for the route this player shared), and only
-- while the setting party.routeShare is on (off by default). It never
-- shares by itself on plan. Party route edits (B-39) and joining or
-- leaving the party route (B-45) send one message each, only on the
-- player's own word or link click, under the same setting. Nothing else here acts: it prints locally and
-- hands a taken route to the trip route's own Run.
--
-- Words (added to the route word): route share, route ask, route take,
-- route keep (FLOW-PARITY B-38: keep your own route, drop the offer).
-- Any send the client does not answer as a success is "not shared"; each
-- client keeps walking its own route.
--
-- Messages (prefix ns.id.commPrefix, version ns.id.commVersion), each at
-- most MAX_BYTES:
--   "<ver>|R|<sid>|<seq>|<count>|<data>"   one chunk of a shared route
--   "<ver>|Q|<nonce>"                       a late joiner's ask
-- The route payload (chunks joined in order): "Z1,<title>;" then one
-- "<label>,<detail>,<map>,<x>,<y>" per stop, ";" between them; every
-- separator, "%", control and non-ASCII byte is written %XX. A missing or
-- out-of-order chunk says "incomplete; ask again". A malformed or
-- unknown-version message is ignored with one diag problem line.
--
-- Pure:
--   P.Encode(route) -> payload
--   P.Decode(payload) -> run (for the trip route's Run) or nil, why
--   P.Chunks(sid, payload, ver) -> messages or nil, why
--   P.Ask(nonce, ver) -> message
--   P.Parse(message, ver) -> { type = "R", sid, seq, count, data }
--                            | { type = "Q", nonce } or nil, why
-- FLOW-PARITY B-40 (lead section 471): one line under the quest arrow says
-- which route it walks and how to switch: an offer not taken yet, or the
-- party route being followed. Local only: the line sends nothing; route
-- keep while following drops the party route.
--   P.Line(offerFrom, followFrom, slash) -> line or nil
-- Module "partyRoute" provides Share, Ask, Take, Keep, Line, Edit, First, Done, Add,
-- SetScope, Scope, Filter, Progress, RouteLeader.
-- Not tested in game: the two-client game test is an owner item.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local P = {}
N.PartyRoute = P

P.NAME = "partyRoute"
P.WORD = "route"
P.HELP = "route share: send your route to your party; route ask: ask the party for theirs; route take: follow it; route keep: keep your own;"
    .. " route first <n>, route done <n>, route add: change the party route for everyone on it;"
    .. " route join: one route for the party; route just <name>: just their quests; route mine: your own"
P.SETTING = "party.routeShare"
P.CHANNEL = "PARTY"
P.MAX_BYTES = 255
P.MAX_CHUNKS = 8
P.MAX_STOPS = 12
P.ANSWER_EVERY = 10      -- seconds between answers to asks

P.SHARED = "Route shared with your party: %d stops."
P.NOT_SHARED = "Route not shared: %s. You keep your own route."
P.ASKED = "Asked your party for their route."
P.NOT_ASKED = "Not asked: %s."
P.OFFER = "%s shared a route (%d stops); type %s route take to follow it."
P.INCOMPLETE = "The route from %s came incomplete; ask again with %s route ask."
P.NO_OFFER = "No party route to take."
P.TAKEN = "Following the route from %s: %s"
-- FLOW-PARITY B-36: the offer carries two chat links, the player clicks one;
-- nothing is taken until then. Kind "addon:<addon>:party", rest take|keep.
P.FOLLOW = "Follow party route"
P.KEEP = "Keep my route"
P.KEPT = "Keeping your own route; the route from %s is not taken."
function P.Kind(addon) return "addon:" .. tostring(addon) .. ":party" end
function P.Choices(addon)
    local kind = P.Kind(addon)
    return "|H" .. kind .. ":take|h[" .. P.FOLLOW .. "]|h |H" .. kind .. ":keep|h[" .. P.KEEP .. "]|h"
end
P.LINE_OFFER = "Party route from %s: %s route take to follow it."
P.LINE_FOLLOW = "Following %s's route: %s route keep for your own."
P.DROPPED = "Dropped the route from %s; type the route word to plan your own."
P.WHY_OFF = "sharing is off in the settings (Share your route with your party)"
P.WHY_ALONE = "you are not in a party"
P.WHY_PREFIX = "the client did not take the add-on message prefix"
P.WHY_NO_ROUTE = "no route planned; type the route word first"
P.WHY_NO_TRIP = "the trip route is off"

local HEAD = "Z1"

function P.Line(offerFrom, followFrom, slash)
    slash = tostring(slash or "")
    if type(followFrom) == "string" then return P.LINE_FOLLOW:format(followFrom, slash) end
    if type(offerFrom) == "string" then return P.LINE_OFFER:format(offerFrom, slash) end
    return nil
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function esc(s)
    return (tostring(s or ""):gsub("[%%|;,%c\128-\255]", function(ch) return ("%%%02X"):format(ch:byte()) end))
end

local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Every field between seps, empty ones kept.
local function split(s, sep)
    local out, from = {}, 1
    while true do
        local i = s:find(sep, from, true)
        if not i then
            out[#out + 1] = s:sub(from)
            return out
        end
        out[#out + 1] = s:sub(from, i - 1)
        from = i + 1
    end
end

local function num(v)
    return tostring(tonumber(("%.4f"):format(v)))
end

function P.Encode(route)
    local parts = { HEAD .. "," .. esc(type(route) == "table" and route.label or "") }
    local stops = type(route) == "table" and type(route.stops) == "table" and route.stops or {}
    for _, s in ipairs(stops) do
        if #parts > P.MAX_STOPS then break end
        local p = type(s) == "table" and s.place
        if type(p) == "table" and finite(p.map) and finite(p.x) and finite(p.y) then
            parts[#parts + 1] = esc(s.label) .. "," .. esc(s.detail) .. "," .. tostring(math.floor(p.map)) .. ","
                .. num(p.x) .. "," .. num(p.y)
        end
    end
    return table.concat(parts, ";")
end

function P.Decode(payload)
    if type(payload) ~= "string" or payload == "" then return nil, "empty route" end
    local records = split(payload, ";")
    local head = split(records[1], ",")
    if #head ~= 2 or head[1] ~= HEAD then return nil, "not a route" end
    local steps = {}
    for i = 2, #records do
        local f = split(records[i], ",")
        if #f ~= 5 then return nil, "stop " .. (i - 1) .. " has " .. #f .. " fields" end
        local map, x, y = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        if not (finite(map) and finite(x) and finite(y)) then return nil, "stop " .. (i - 1) .. " has no place" end
        local detail = unesc(f[2])
        steps[#steps + 1] = { kind = "party", label = unesc(f[1]), detail = detail ~= "" and detail or nil,
                              place = { map = map, x = x, y = y } }
    end
    if #steps == 0 then return nil, "no stops" end
    return { title = unesc(head[2]), steps = steps }
end

-- FLOW-PARITY B-43: a taken route's steps say whose they are ("<name>:
-- <label>") and "(done for you)" when that quest is complete in this
-- player's own log (log rows as client.questLog gives them: title,
-- complete, objectives { text, done }). Read from the local log only:
-- nothing is sent. A label that would be over N.Waypoint.LABEL_MAX keeps
-- its own text and the words go to the step's detail (never cut).
P.DONE = " (done for you)"

local function labelMax()
    return ns.Nav and ns.Nav.Waypoint and ns.Nav.Waypoint.LABEL_MAX or 40
end

local function doneFor(step, log)
    if type(log) ~= "table" then return false end
    for _, q in ipairs(log) do
        if type(q) == "table" and q.title == step.label then
            if q.complete == true then return true end
            for _, o in ipairs(type(q.objectives) == "table" and q.objectives or {}) do
                if type(o) == "table" and o.done == true and step.detail ~= nil and o.text == step.detail then return true end
            end
            return false
        end
    end
    return false
end

function P.Label(from, step, log)
    if type(step) ~= "table" or type(step.label) ~= "string" then return step end
    local who
    if type(from) == "string" then who = from:match("^([^%-]+)") end
    local out = {}
    for key, v in pairs(step) do out[key] = v end
    local extra = {}
    local label = step.label
    if who and #(who .. ": " .. label) <= labelMax() then label = who .. ": " .. label
    elseif who then extra[#extra + 1] = who .. "'s step" end
    if doneFor(step, log) then
        if #(label .. P.DONE) <= labelMax() then label = label .. P.DONE else extra[#extra + 1] = "done for you" end
    end
    out.label = label
    if #extra > 0 then
        local more = table.concat(extra, ", ")
        out.detail = step.detail and (step.detail .. " (" .. more .. ")") or more
    end
    return out
end

function P.Chunks(sid, payload, ver)
    if type(payload) ~= "string" or payload == "" then return nil, "nothing to send" end
    local fixed = tostring(ver) .. "|R|" .. tostring(sid) .. "|"
    local room = P.MAX_BYTES - #fixed - #(tostring(P.MAX_CHUNKS) .. "|" .. tostring(P.MAX_CHUNKS) .. "|")
    local count = math.ceil(#payload / room)
    if count > P.MAX_CHUNKS then return nil, "the route is too long to send" end
    local out = {}
    for i = 1, count do
        out[i] = fixed .. i .. "|" .. count .. "|" .. payload:sub((i - 1) * room + 1, i * room)
    end
    return out
end

function P.Ask(nonce, ver)
    return tostring(ver) .. "|Q|" .. tostring(nonce)
end

function P.Parse(msg, ver)
    if type(msg) ~= "string" then return nil, "not text" end
    local v, kind, rest = msg:match("^(%d+)|(%u)|(.*)$")
    if not v then return nil, "not a route message" end
    if tonumber(v) ~= ver then return nil, "unknown version " .. v end
    if kind == "Q" then
        if not rest:match("^%w+$") then return nil, "an ask without a nonce" end
        return { type = "Q", nonce = rest }
    end
    if kind == "J" then
        if rest == "1" then return { type = "J", on = true } end
        if rest == "0" then return { type = "J", on = false } end
        return nil, "a join out of form"
    end
    if kind == "E" then
        local esid, clockText, op, arg = rest:match("^(%w+)|(%d+)|(%u)|(.*)$")
        if not esid then return nil, "an edit out of form" end
        return { type = "E", sid = esid, clock = tonumber(clockText), op = op, arg = arg }
    end
    if kind ~= "R" then return nil, "unknown kind " .. kind end
    local sid, seqText, countText, data = rest:match("^(%w+)|(%d+)|(%d+)|(.+)$")
    if not sid then return nil, "a route chunk out of form" end
    local seq, count = tonumber(seqText), tonumber(countText)
    if count < 1 or count > P.MAX_CHUNKS or seq < 1 or seq > count then
        return nil, "a route chunk out of form"
    end
    return { type = "R", sid = sid, seq = seq, count = count, data = data }
end

-- FLOW-PARITY B-39 (Flow Modules/Nav/Party.lua:226-252): shared edits. Anyone
-- on a shared route moves a stop first, adds a stop in front or marks one
-- done for all; the edit goes to the party as one message with a clock, and
-- every client on that route applies it to its own copy. Stops are counted
-- from 1 in the route as it stands; a later clock wins.
--   "<ver>|E|<sid>|<clock>|<op>|<arg>"  op F (first, arg n), D (done, arg n),
--                                        A (add in front, arg a stop record)
P.EDITED = "%s changed the party route: %s"
P.EDIT_SAID = { F = "stop %s moved first", D = "stop %s done for everyone", A = "a stop added in front" }
P.NO_PARTY_ROUTE = "No party route to change: share one or take one first."
P.NOT_EDITED = "Not changed: %s."

function P.StopRecord(s)
    local p = type(s) == "table" and s.place
    if type(p) ~= "table" or not (finite(p.map) and finite(p.x) and finite(p.y)) then return nil end
    return esc(s.label) .. "," .. esc(s.detail) .. "," .. tostring(math.floor(p.map)) .. "," .. num(p.x) .. "," .. num(p.y)
end

local function copySteps(steps)
    local out = {}
    for i, st in ipairs(steps) do
        local c = {}
        for key, v in pairs(st) do c[key] = v end
        out[i] = c
    end
    return out
end

function P.ApplyEdit(steps, op, arg)
    if type(steps) ~= "table" then return nil, "no route" end
    local out = copySteps(steps)
    if op == "A" then
        local run = P.Decode(HEAD .. ",;" .. tostring(arg or ""))
        if not run then return nil, "a stop out of form" end
        table.insert(out, 1, run.steps[1])
        while #out > P.MAX_STOPS do table.remove(out) end
        return out
    end
    local n = tonumber(arg)
    if n == nil or n ~= math.floor(n) or n < 1 or n > #out then return nil, "no stop " .. tostring(arg) end
    if op == "F" then table.insert(out, 1, table.remove(out, n)); return out end
    if op == "D" then table.remove(out, n); return out end
    return nil, "unknown edit " .. tostring(op)
end

function P.EditMsg(sid, clock, op, arg, ver)
    return tostring(ver) .. "|E|" .. tostring(sid) .. "|" .. tostring(clock) .. "|" .. tostring(op) .. "|" .. tostring(arg or "")
end

-- FLOW-PARITY B-45 (Flow PartyHelp.lua:431-523): one shared order. On the
-- party route (scope "combined") one member plans: the group leader if on
-- it, else the first name in A to Z order (realm and case ignored). The
-- planner's route goes to the others when they join and at each edit, and
-- each follows it at once; a route from anyone else stays an offer.
--   "<ver>|J|1" joined the party route, "<ver>|J|0" left it.
local function plain(n)
    if type(n) ~= "string" then return "" end
    return (n:match("^([^%-]+)") or n):lower()
end
P.Plain = plain
function P.Unesc(s) return unesc(tostring(s or "")) end

function P.Leader(me, others, groupLeader)
    local all = { me }
    for _, n in ipairs(type(others) == "table" and others or {}) do all[#all + 1] = n end
    if groupLeader then
        for _, n in ipairs(all) do
            if plain(n) == plain(groupLeader) then return n end
        end
    end
    table.sort(all, function(a, b) return plain(a) < plain(b) end)
    return all[1]
end

function P.JoinMsg(on, ver)
    if on then return tostring(ver) .. "|J|1" end
    return tostring(ver) .. "|J|0"
end

-- FLOW-PARITY B-42 and B-44 (Flow PartyHelp.lua:206-236, :311): whose quests
-- the route covers. "mine" (default), "theirs" (one member's: "Just <name>'s
-- quests") or "combined" (everyone on the party route). Progress per member
-- is B-41's (Nav/PartyProgress.lua): { [quest id] = { complete, objectives =
-- { { have, need } } } }, fed in from the partyProgress module on this
-- module's own tick (FEED_EVERY; lead section 843.2), and through
-- Progress(name, rows).
P.FEED_EVERY = 2
function P.ToDo(rows)
    local n = 0
    if type(rows) ~= "table" then return 0 end
    for _, q in pairs(rows) do
        if type(q) == "table" and q.complete ~= true then n = n + 1 end
    end
    return n
end

function P.Covered(scope, who, progress, joined)
    if type(progress) ~= "table" then return nil end
    if scope == "theirs" then
        if who == nil or progress[who] == nil then return nil end
        return { [who] = progress[who] }
    end
    if scope ~= "combined" then return nil end
    local out
    for name, rows in pairs(progress) do
        if type(joined) == "table" and joined[name] then
            out = out or {}
            out[name] = rows
        end
    end
    return out
end

-- The steps for the covered members' quests, as Flow's PartyHelp.lua H.Keep
-- (:381-399) and H.QuestsOnly (:404-411; lead section 843.2): a step of a
-- quest someone covered has, by quest id; an objective step only while
-- their objective is not finished (have < need); a turn-in when they have
-- the quest; the party route's own steps (kind "party"). Any other step is
-- left out. Every step when nobody else is covered.
local function objectiveOpen(e, i)
    if e.complete == true then return false end
    local o = nil
    if type(e.objectives) == "table" then o = e.objectives[i] end
    if type(o) ~= "table" then return false end
    return type(o.have) == "number" and type(o.need) == "number" and o.have < o.need
end

function P.KeepFor(steps, covered)
    if type(covered) ~= "table" then return steps end
    local out = {}
    local list = {}
    if type(steps) == "table" then list = steps end
    for _, st in ipairs(list) do
        local keep = false
        if type(st) == "table" then
            if st.party == true or st.kind == "party" then keep = true end
            if not keep and st.quest ~= nil then
                for _, rows in pairs(covered) do
                    local e = nil
                    if type(rows) == "table" then e = rows[st.quest] end
                    if type(e) == "table" then
                        if st.turnIn == true or st.objective == nil then
                            keep = true
                        elseif objectiveOpen(e, st.objective) then
                            keep = true
                        end
                    end
                    if keep then break end
                end
            end
        end
        if keep then out[#out + 1] = st end
    end
    return out
end

-- B-44: ask once per member per group, only with quests to do, only while
-- the route is your own.
function P.AskWho(name, progress, asked, scope, me)
    if scope ~= "mine" or type(name) ~= "string" then return nil end
    if plain(name) == plain(me) then return nil end
    if type(asked) == "table" and asked[name] then return nil end
    if type(progress) ~= "table" or P.ToDo(progress[name]) == 0 then return nil end
    return name
end
P.HELP_ASK = "%s is in your group with quests to do (%d). Join the party route, or help with just theirs?"
P.JOIN = "Join the party route"
P.JUST = "Just %s's"
P.NOT_NOW = "Not now"
P.SCOPE_SAID = {
    mine = "Route: your own quests.",
    theirs = "Route: just %s's quests (%d to do).",
    combined = "Joined the party route: one route for everyone on it.",
}
P.NO_PROGRESS = "No quest progress from %s yet."
function P.HelpChoices(addon, name)
    local kind = P.Kind(addon)
    return "|H" .. kind .. ":join|h[" .. P.JOIN .. "]|h |H" .. kind .. ":just:" .. esc(name) .. "|h["
        .. P.JUST:format(name) .. "]|h |H" .. kind .. ":notnow|h[" .. P.NOT_NOW .. "]|h"
end

function P.Declare(k, diag)
    local api = {}
    local ctx
    local cancel
    local prefixOk = false
    local mine = {}          -- sids and nonces this client sent
    local shared             -- the messages of the route this client shared
    local answeredAt
    local bufs = {}          -- sender -> { sid, count, n, parts }
    local offer              -- { from, run }
    local following          -- B-40: who sent the route being followed
    local offered, warned = {}, {}
    local made = 0
    local cancelClick
    -- B-39: the party route this client is on (shared or taken), its sid,
    -- its stops as sent (before names are added) and the last edit's clock.
    local party                 -- { sid, from, title, steps, clock }
    -- B-42, B-44, B-45: whose quests, who joined, whom we asked.
    local scope, focus = "mine", nil
    local progress, joined, asked = {}, {}, {}
    local feed

    local function client() return ctx and ctx.client or k.client end
    local function id() return k.id or ns.id end

    local function say(text)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        c.print(id().title .. ": " .. tostring(text))
    end

    local function problem(why)
        k.problems:add(P.NAME, "message", tostring(why))
    end

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, P.SETTING)
        return ok and v == true
    end

    local function newId()
        made = made + 1
        local v = ("%x%x"):format(math.random(0, 65535), made)
        mine[v] = true
        return v
    end

    local function now()
        local c = client()
        local ok, t = pcall(c.now)
        return ok and finite(t) and t or nil
    end

    -- Every message on the party channel, or nil and why at the first the
    -- client does not answer as sent.
    local function send(msgs)
        if not on() then return nil, P.WHY_OFF end
        local c = client()
        if type(c) ~= "table" or type(c.addonSend) ~= "function" then return nil, P.WHY_PREFIX end
        local okG, grouped = pcall(c.grouped)
        if not okG or grouped ~= true then return nil, P.WHY_ALONE end
        if not prefixOk then return nil, P.WHY_PREFIX end
        for _, m in ipairs(msgs) do
            local ok, sent, why = pcall(c.addonSend, id().commPrefix, m, P.CHANNEL)
            if not ok then return nil, tostring(sent) end
            if sent ~= true then return nil, tostring(why or "the client did not send it") end
        end
        return true
    end

    function api.Share()
        local tr = k.use and k.use("tripRoute")
        if not tr then return say(P.NOT_SHARED:format(P.WHY_NO_TRIP)) end
        local cur = type(tr.Current) == "function" and tr.Current() or nil
        if not cur then return say(P.NOT_SHARED:format(P.WHY_NO_ROUTE)) end
        local msgs, why = P.Chunks(newId(), P.Encode(cur), id().commVersion)
        if not msgs then return say(P.NOT_SHARED:format(why)) end
        local ok, sendWhy = send(msgs)
        if not ok then return say(P.NOT_SHARED:format(sendWhy)) end
        shared = msgs
        local run = P.Decode(P.Encode(cur))
        if run then
            party = { sid = msgs[1]:match("|R|(%w+)|"), title = run.title, steps = run.steps, clock = 0 }
        end
        say(P.SHARED:format(math.min(#cur.stops, P.MAX_STOPS)))
    end

    function api.Ask()
        local ok, why = send({ P.Ask(newId(), id().commVersion) })
        say(ok and P.ASKED or P.NOT_ASKED:format(why))
    end

    function api.Take()
        if not offer then return say(P.NO_OFFER) end
        local tr = k.use and k.use("tripRoute")
        if not tr then return say(P.NOT_SHARED:format(P.WHY_NO_TRIP)) end
        local c = client()
        local okLog, log = false, nil
        if type(c) == "table" and type(c.questLog) == "function" then okLog, log = pcall(c.questLog) end
        local run = {}
        for key, v in pairs(offer.run) do run[key] = v end
        run.steps = {}
        local own
        if okLog then own = log end
        for i, st in ipairs(offer.run.steps or {}) do run.steps[i] = P.Label(offer.from, st, own) end
        following = offer.from
        party = { sid = offer.sid, from = offer.from, title = offer.run.title, steps = offer.run.steps, clock = 0 }
        say(P.TAKEN:format(following, tostring(tr.Run(run))))
    end

    -- B-40: the arrow's line; the followed route ended clears it.
    function api.Line()
        if following then
            local tr = k.use and k.use("tripRoute")
            local cur
            if tr and type(tr.Current) == "function" then
                local ok, v = pcall(tr.Current)
                if ok then cur = v end
            end
            if not cur then following = nil end
        end
        local offerFrom
        if offer then offerFrom = offer.from end
        return P.Line(offerFrom, following, id().slash)
    end

    local function chunk(p, sender)
        local buf = bufs[sender]
        if p.seq == 1 then
            buf = { sid = p.sid, count = p.count, n = 0, parts = {} }
            bufs[sender] = buf
        end
        if not buf or buf.sid ~= p.sid or buf.count ~= p.count or p.seq ~= buf.n + 1 then
            bufs[sender] = nil
            local key = sender .. "|" .. p.sid
            if not warned[key] then
                warned[key] = true
                say(P.INCOMPLETE:format(sender, id().slash))
            end
            return
        end
        buf.n = buf.n + 1
        buf.parts[buf.n] = p.data
        if buf.n < buf.count then return end
        bufs[sender] = nil
        local run, why = P.Decode(table.concat(buf.parts))
        if not run then return problem(why) end
        offer = { from = sender, run = run, sid = p.sid }
        -- B-45: on the party route, the planner's route is followed at once.
        if scope == "combined" and api.IsLeader(sender) then
            api.Take()
            local arrowNow = k.use and k.use("arrow")
            if type(arrowNow) == "table" and type(arrowNow.Redraw) == "function" then pcall(arrowNow.Redraw) end
            return
        end
        -- The offer line is under the arrow at once (B-40): redraw it.
        local arrow = k.use and k.use("arrow")
        if type(arrow) == "table" and type(arrow.Redraw) == "function" then pcall(arrow.Redraw) end
        local key = sender .. "|" .. p.sid
        if not offered[key] then
            offered[key] = true
            say(P.OFFER:format(sender, #run.steps, id().slash) .. " " .. P.Choices(id().addon))
        end
    end

    -- B-39: the party route again on this client's own trip route, names on.
    local function rerun()
        local tr = k.use and k.use("tripRoute")
        if not tr or not party then return end
        local c = client()
        local log
        if type(c) == "table" and type(c.questLog) == "function" then
            local okLog, rows = pcall(c.questLog)
            if okLog then log = rows end
        end
        local steps = {}
        for i, st in ipairs(party.steps) do steps[i] = P.Label(party.from, st, log) end
        pcall(tr.Run, { title = party.title, steps = steps })
        if party.from == nil then
            local msgs = P.Chunks(party.sid, P.Encode({ label = party.title, stops = party.steps }), id().commVersion)
            if msgs then shared = msgs end
        end
    end

    function api.Edit(op, arg)
        if not party then return say(P.NO_PARTY_ROUTE) end
        local steps, why = P.ApplyEdit(party.steps, op, arg)
        if not steps then return say(P.NOT_EDITED:format(why)) end
        local clock = party.clock + 1
        local ok, sendWhy = send({ P.EditMsg(party.sid, clock, op, arg, id().commVersion) })
        if not ok then return say(P.NOT_EDITED:format(sendWhy)) end
        party.steps, party.clock = steps, clock
        rerun()
        say(P.EDIT_SAID[op]:format(tostring(arg)))
    end

    function api.First(n) return api.Edit("F", tostring(n)) end
    function api.Done(n) return api.Edit("D", tostring(n)) end
    function api.Add(label)
        local c = client()
        local okPos, pos = false, nil
        if type(c) == "table" and type(c.position) == "function" then okPos, pos = pcall(c.position) end
        local rec
        if okPos then rec = P.StopRecord({ label = label or "Meet here", place = pos }) end
        if not rec then return say(P.NOT_EDITED:format("your place is not known")) end
        return api.Edit("A", rec)
    end

    local function edited(p, sender)
        if not party or p.sid ~= party.sid or p.clock <= party.clock then return end
        local steps, why = P.ApplyEdit(party.steps, p.op, p.arg)
        if not steps then return problem(why) end
        party.steps, party.clock = steps, p.clock
        rerun()
        local said = P.EDIT_SAID[p.op] or "?"
        say(P.EDITED:format(sender, said:format(p.arg)))
    end

    -- B-45: names of the others on the party route; the group leader's name.
    local function onRoute()
        local out = {}
        for name, isOn in pairs(joined) do
            if isOn then out[#out + 1] = name end
        end
        table.sort(out)
        return out
    end

    local function me()
        local c = client()
        if type(c) ~= "table" or type(c.playerName) ~= "function" then return nil end
        local ok, name = pcall(c.playerName)
        if ok then return name end
        return nil
    end

    local function leaderName()
        local c = client()
        if type(c) ~= "table" or type(c.groupLeader) ~= "function" then return nil end
        local ok, unit = pcall(c.groupLeader)
        if not ok or type(unit) ~= "string" then return nil end
        if unit == "player" then return me() end
        if type(c.party) ~= "function" then return nil end
        local okRows, rows = pcall(c.party)
        if not okRows or type(rows) ~= "table" then return nil end
        for _, r in ipairs(rows) do
            if type(r) == "table" and r.unit == unit then return r.name end
        end
        return nil
    end

    function api.RouteLeader()
        if scope ~= "combined" then return nil end
        return P.Leader(me(), onRoute(), leaderName())
    end

    function api.IsLeader(name)
        local l = api.RouteLeader()
        return l ~= nil and P.Plain(l) == P.Plain(name)
    end

    -- B-42: whose quests the route covers. "theirs" needs that member's
    -- progress (B-41). Joining or leaving the party route tells the party.
    function api.SetScope(sc, name)
        if sc == "theirs" and progress[name] == nil then return say(P.NO_PROGRESS:format(tostring(name))) end
        local was = scope
        scope = sc
        focus = nil
        if sc == "theirs" then focus = name end
        if (sc == "combined") ~= (was == "combined") then send({ P.JoinMsg(sc == "combined", id().commVersion) }) end
        if sc == "theirs" then
            say(P.SCOPE_SAID.theirs:format(name, P.ToDo(progress[name])))
        else
            say(P.SCOPE_SAID[sc])
        end
        if sc == "combined" and api.IsLeader(me()) then api.Share() end
    end

    function api.Scope() return scope, focus end

    -- B-42: the trip route's steps cut to the covered members' quests.
    function api.Filter(steps)
        return P.KeepFor(steps, P.Covered(scope, focus, progress, joined))
    end

    -- B-44: a member's quest progress (B-41 feeds it); asks once whether to
    -- help, with chat links for the choices.
    function api.Progress(name, rows)
        if type(name) ~= "string" then return end
        progress[name] = rows
        local who = P.AskWho(name, progress, asked, scope, me())
        if not who then return end
        asked[who] = true
        say(P.HELP_ASK:format(who, P.ToDo(rows)) .. " " .. P.HelpChoices(id().addon, who))
    end

    -- Lead section 843.2: each member's progress from the partyProgress
    -- module (B-41), given to Progress (which asks once, B-44).
    function feed()
        local pp = k.use and k.use("partyProgress")
        if type(pp) ~= "table" or type(pp.Names) ~= "function" or type(pp.Progress) ~= "function" then return end
        local okN, names = pcall(pp.Names)
        if not okN or type(names) ~= "table" then return end
        for _, name in ipairs(names) do
            local okP, rows = pcall(pp.Progress, name)
            if okP and type(rows) == "table" then api.Progress(name, rows) end
        end
    end

    function api.Keep()
        if following then
            local tr = k.use and k.use("tripRoute")
            if tr and type(tr.Off) == "function" then pcall(tr.Off) end
            local from = following
            following, offer = nil, nil
            return say(P.DROPPED:format(from))
        end
        if not offer then return say(P.NO_OFFER) end
        local from = offer.from
        offer = nil
        say(P.KEPT:format(from))
    end

    -- A click redraws the arrow at once, as the slash word's own pass
    -- does (lead section 466): the player clicks and sees the route.
    local function redraw()
        local arrow = k.use and k.use("arrow")
        if type(arrow) == "table" and type(arrow.Redraw) == "function" then pcall(arrow.Redraw) end
    end

    local function clicked(rest)
        if rest == "take" then api.Take(); return redraw() end
        if rest == "keep" then api.Keep(); return redraw() end
        if rest == "join" then api.SetScope("combined"); return redraw() end
        local name = type(rest) == "string" and rest:match("^just:(.+)$")
        if name then
            api.SetScope("theirs", P.Unesc(name))
            return redraw()
        end
    end

    local function receive(prefix, text, channel, sender)
        if prefix ~= id().commPrefix or channel ~= P.CHANNEL then return end
        local p, why = P.Parse(text, id().commVersion)
        if not p then return problem(why) end
        if p.type == "Q" then
            if mine[p.nonce] or not shared then return end
            local t = now()
            if answeredAt and t and t - answeredAt < P.ANSWER_EVERY then return end
            answeredAt = t
            local ok, sendWhy = send(shared)
            if not ok then problem("answer not sent: " .. tostring(sendWhy)) end
            return
        end
        if p.type == "J" then
            joined[tostring(sender)] = p.on
            return
        end
        if p.type == "E" then return edited(p, tostring(sender)) end
        if mine[p.sid] then return end
        chunk(p, tostring(sender))
    end

    if diag and type(diag.commands) == "table" then
        local prior = diag.commands[P.WORD]
        diag.commands[P.WORD] = function(rest)
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "share" then return api.Share() end
            if word == "ask" then return api.Ask() end
            if word == "take" then return api.Take() end
            if word == "keep" then return api.Keep() end
            local arg = tostring(rest or ""):match("^%s*%S+%s+(.-)%s*$")
            if word == "first" then return api.First(arg) end
            if word == "done" then return api.Done(arg) end
            if word == "add" then return api.Add() end
            if word == "join" then return api.SetScope("combined") end
            if word == "mine" then return api.SetScope("mine") end
            if word == "just" then return api.SetScope("theirs", arg) end
            if type(prior) == "function" then return prior(rest) end
        end
        if type(diag.help) == "table" then
            local before = diag.help[P.WORD]
            diag.help[P.WORD] = (type(before) == "string" and (before .. "; ") or "") .. P.HELP
        end
    end

    k:Setting({ key = P.SETTING, scope = "account", type = "bool", default = false,
        label = "Share your route with your party", group = "travel.route",
        help = "Acts only when you type a route word (share, ask, first, done, add, join), click a party route link,"
            .. " or a party member asks for the route you shared:"
            .. " sends the route to your party as add-on data, never to chat or anyone else.",
        synonyms = { "party", "share", "route", "group" } })

    k:Module({
        name = P.NAME,
        needs = { "client", "settings" },
        provides = { Share = api.Share, Ask = api.Ask, Take = api.Take, Keep = api.Keep,
                     Edit = api.Edit, First = api.First, Done = api.Done, Add = api.Add,
                     SetScope = api.SetScope, Scope = api.Scope, Filter = api.Filter, Progress = api.Progress,
                     RouteLeader = api.RouteLeader,
                     Line = function() return api.Line() end },
        -- Lead section 843.2: B-41's progress, read on our own tick.
        ticks = { { every = P.FEED_EVERY, when = "always", run = function() feed() end } },
        start = function(c)
            ctx = c
            local cl = c.client
            if type(cl.addonPrefix) == "function" then
                local ok, v = pcall(cl.addonPrefix, id().commPrefix)
                prefixOk = ok and v == true
            end
            cancel = cl.listen("CHAT_MSG_ADDON", function(...)
                local ok, err = pcall(receive, ...)
                if not ok then problem(err) end
            end)
            if type(cl.onLinkClick) == "function" then
                local ok, got = pcall(cl.onLinkClick, P.Kind(id().addon), clicked)
                if ok and type(got) == "function" then cancelClick = got end
            end
        end,
        stop = function()
            if type(cancel) == "function" then pcall(cancel) end
            if type(cancelClick) == "function" then pcall(cancelClick) end
            cancel, cancelClick = nil, nil
            bufs, offer = {}, nil
            party, scope, focus = nil, "mine", nil
            progress, joined, asked = {}, {}, {}
        end,
    })
    return api
end

ns.partyRoute = P.Declare(ns, ns.diag)
