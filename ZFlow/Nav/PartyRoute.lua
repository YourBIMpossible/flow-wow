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
-- shares by itself on plan. Nothing else here acts: it prints locally and
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
-- Module "partyRoute" provides Share, Ask, Take, Keep, Line.
-- Not tested in game: the two-client game test is an owner item.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local P = {}
N.PartyRoute = P

P.NAME = "partyRoute"
P.WORD = "route"
P.HELP = "route share: send your route to your party; route ask: ask the party for theirs; route take: follow it; route keep: keep your own"
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
P.WHY_OFF = ""sharing is off in the settings (Share your route with your party)"
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
    if kind ~= "R" then return nil, "unknown kind " .. kind end
    local sid, seqText, countText, data = rest:match("^(%w+)|(%d+)|(%d+)|(.+)$")
    if not sid then return nil, "a route chunk out of form" end
    local seq, count = tonumber(seqText), tonumber(countText)
    if count < 1 or count > P.MAX_CHUNKS or seq < 1 or seq > count then
        return nil, "a route chunk out of form"
    end
    return { type = "R", sid = sid, seq = seq, count = count, data = data }
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
        offer = { from = sender, run = run }
        local key = sender .. "|" .. p.sid
        if not offered[key] then
            offered[key] = true
            say(P.OFFER:format(sender, #run.steps, id().slash) .. " " .. P.Choices(id().addon))
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
            if type(prior) == "function" then return prior(rest) end
        end
        if type(diag.help) == "table" then
            local before = diag.help[P.WORD]
            diag.help[P.WORD] = (type(before) == "string" and (before .. "; ") or "") .. P.HELP
        end
    end

    k:Setting({ key = P.SETTING, scope = "account", type = "bool", default = false,
        label = "Share your route with your party", group = "travel.route",
        help = "Acts only when you type route share or route ask, or when a party member asks for the route you shared:"
            .. " sends the route to your party as add-on data, never to chat or anyone else.",
        synonyms = { "party", "share", "route", "group" } })

    k:Module({
        name = P.NAME,
        needs = { "client", "settings" },
        provides = { Share = api.Share, Ask = api.Ask, Take = api.Take, Keep = api.Keep,
                     Line = function() return api.Line() end },
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
        end,
    })
    return api
end

ns.partyRoute = P.Declare(ns, ns.diag)
