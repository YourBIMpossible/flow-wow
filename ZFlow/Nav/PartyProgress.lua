local _, ns = ...
-- Party quest progress (FLOW-PARITY B-41, lead section 825.1; Flow
-- PartyHelp.lua:1-160 and Party.lua:72-90). Party members who run the
-- add-on tell each other how far they are on every quest in their log:
-- each objective's count and whether the quest is ready to hand in. The
-- data half only: B-42 and B-44 read it through Progress(name) and All().
--
-- SAFETY: sends add-on messages (never chat text, never whispers, never a
-- public channel) on the "PARTY" channel only, only while the player is in
-- a party (not alone, not in a raid), at most once per EVERY seconds and
-- only when the progress changed since the last send (or a new member
-- joined), and only while the setting party.progressShare is on. As in
-- Flow, it is on by default (Flow sends with no setting at all).
-- Everything received is checked by P.Decode before it is kept; nothing
-- received is run, printed or used as a format.
--
-- Messages (prefix P.Prefix(): ns.id.commPrefix and "P", so the party
-- route's own parser never sees them; version ns.id.commVersion), each at
-- most MAX_BYTES:
--   "<ver>|G|<seq>|<count>|<entries>"
-- entries joined by ",": "83=c" ready to hand in, "86=2/4.0/1" objective
-- counts (have/need, "." between objectives), "90=" no objectives. One
-- send is count messages, seq 1..count in order; seq 1 starts a member's
-- progress again.
--
-- Pure:
--   P.Mine(questLogRows) -> { [id] = { complete, objectives = { { have, need } } } }
--   P.Encode(progress, ver) -> messages
--   P.Decode(message, ver) -> { seq, count, quests } or nil, why
-- Module "partyProgress" provides Progress(name), All(), Names().
-- Not tested in game: the two-client game test is an owner item.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local P = {}
N.PartyProgress = P

P.NAME = "partyProgress"
P.SETTING = "party.progressShare"
P.CHANNEL = "PARTY"
P.KIND = "G"
P.MAX_BYTES = 255
P.MAX_PARTS = 4
P.MAX_QUESTS = 40
P.MAX_OBJECTIVES = 8
P.MAX_COUNT = 999
P.MAX_ID_DIGITS = 7
P.MAX_NAME = 48
P.EVERY = 5          -- seconds between checks of your own progress

function P.Prefix()
    return tostring(ns.id.commPrefix) .. "P"
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- One objective's have and need, from the quest log's text ("Boar slain:
-- 2/4"); an objective with no count is 1/1 done or 0/1 not.
local function counts(o)
    local have, need
    local text
    if type(o) == "table" then text = o.text end
    if type(text) == "string" then
        local h, n = text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(h), tonumber(n)
    end
    if not need or need < 1 then
        need = 1
        if type(o) == "table" and o.done == true then have = 1 else have = 0 end
    end
    need = clamp(need, 1, P.MAX_COUNT)
    have = clamp(have or 0, 0, need)
    return have, need
end

function P.Mine(rows)
    local out, n = {}, 0
    if type(rows) ~= "table" then return out end
    for _, q in ipairs(rows) do
        if n >= P.MAX_QUESTS then break end
        if type(q) == "table" and type(q.id) == "number" and q.id > 0 and q.id == math.floor(q.id)
            and #tostring(q.id) <= P.MAX_ID_DIGITS and out[q.id] == nil then
            local e = { complete = q.complete == true, objectives = {} }
            if not e.complete then
                local list = q.objectives
                if type(list) ~= "table" then list = {} end
                for i, o in ipairs(list) do
                    if i > P.MAX_OBJECTIVES then break end
                    local have, need = counts(o)
                    e.objectives[i] = { have = have, need = need }
                end
            end
            out[q.id] = e
            n = n + 1
        end
    end
    return out
end

local function entry(id, e)
    if e.complete then return tostring(id) .. "=c" end
    local objs = {}
    for i, o in ipairs(e.objectives or {}) do
        objs[i] = ("%d/%d"):format(o.have, o.need)
    end
    return tostring(id) .. "=" .. table.concat(objs, ".")
end

function P.Encode(progress, ver)
    local ids = {}
    if type(progress) ~= "table" then progress = {} end
    for id in pairs(progress) do ids[#ids + 1] = id end
    table.sort(ids)
    -- Room for the header with the largest seq and count.
    local room = P.MAX_BYTES - #(("%s|%s|%d|%d|"):format(tostring(ver), P.KIND, P.MAX_PARTS, P.MAX_PARTS))
    local bodies, cur = {}, ""
    for _, id in ipairs(ids) do
        local en = entry(id, progress[id])
        if cur ~= "" and #cur + 1 + #en > room then
            if #bodies + 1 >= P.MAX_PARTS then break end
            bodies[#bodies + 1] = cur
            cur = ""
        end
        if cur == "" then cur = en else cur = cur .. "," .. en end
    end
    bodies[#bodies + 1] = cur
    local msgs = {}
    for i, b in ipairs(bodies) do
        msgs[i] = ("%s|%s|%d|%d|%s"):format(tostring(ver), P.KIND, i, #bodies, b)
    end
    return msgs
end

local function number(s, digits)
    if type(s) ~= "string" or s == "" or #s > digits or s:find("^%d+$") == nil then return nil end
    return tonumber(s)
end

local function decodeEntry(text)
    local idText, rest = text:match("^(%d+)=([^=]*)$")
    local id = number(idText, P.MAX_ID_DIGITS)
    if not id or id < 1 then return nil end
    if rest == "c" then return id, { complete = true, objectives = {} } end
    local e = { complete = false, objectives = {} }
    if rest == "" then return id, e end
    for part in (rest .. "."):gmatch("([^%.]*)%.") do
        local h, n = part:match("^(%d+)/(%d+)$")
        local have, need = number(h, 3), number(n, 3)
        if not have or not need or need < 1 or have > need then return nil end
        if #e.objectives >= P.MAX_OBJECTIVES then return nil end
        e.objectives[#e.objectives + 1] = { have = have, need = need }
    end
    return id, e
end

function P.Decode(msg, ver)
    if type(msg) ~= "string" then return nil, "not text" end
    if #msg > P.MAX_BYTES then return nil, "too long" end
    local v, kind, seqText, countText, body = msg:match("^(%d+)|(%a)|(%d+)|(%d+)|(.*)$")
    if not v then return nil, "malformed" end
    if tonumber(v) ~= tonumber(ver) then return nil, "unknown version" end
    if kind ~= P.KIND then return nil, "unknown kind" end
    local seq, count = number(seqText, 2), number(countText, 2)
    if not seq or not count or seq < 1 or count < 1 or count > P.MAX_PARTS or seq > count then
        return nil, "bad part number"
    end
    local quests, n = {}, 0
    if body ~= "" then
        for text in (body .. ","):gmatch("([^,]*),") do
            local id, e = decodeEntry(text)
            if not id then return nil, "bad entry" end
            if quests[id] then return nil, "quest twice" end
            n = n + 1
            if n > P.MAX_QUESTS then return nil, "too many quests" end
            quests[id] = e
        end
    end
    return { seq = seq, count = count, quests = quests }
end

-- A sender's name without its realm, capped; nil when not a name.
local function plain(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^([^%-]+)")
    if not base or #base > P.MAX_NAME then return nil end
    return base
end

function P.Declare(k)
    local ctx
    local cancels = {}
    local progress, buffers, members = {}, {}, nil
    local dirty, lastKey, checkedAt = true, nil, nil
    local prefixOk = false

    local function client()
        if not ctx then return nil end
        return ctx.client
    end

    local function on()
        if not ctx then return false end
        local s = ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, P.SETTING)
        return ok and v == true
    end

    local function me()
        local c = client()
        if type(c) ~= "table" or type(c.playerName) ~= "function" then return nil end
        local ok, name = pcall(c.playerName)
        if not ok then return nil end
        return plain(name)
    end

    -- The other party members' names, or nil when not in a party (alone, a
    -- raid, or not known).
    local function party()
        local c = client()
        if type(c) ~= "table" then return nil end
        local okG, grouped = pcall(c.grouped)
        if not okG or grouped ~= true then return nil end
        local okP, rows = pcall(c.party)
        if not okP or type(rows) ~= "table" then return nil end
        local names = {}
        for _, r in ipairs(rows) do
            if type(r) == "table" and type(r.unit) == "string" and r.unit:find("^raid") then return nil end
            if type(r) == "table" then
                local n = plain(r.name)
                if n then names[n] = true end
            end
        end
        return names
    end

    local function now()
        local c = client()
        local ok, t = pcall(c.now)
        if ok and type(t) == "number" then return t end
        return nil
    end

    local function check()
        if not dirty or not on() then return end
        local t = now()
        if not t then return end
        if checkedAt and t - checkedAt < P.EVERY then return end
        checkedAt = t
        dirty = false
        if not party() or not prefixOk then return end
        local c = client()
        local okL, rows = pcall(c.questLog)
        if not okL or type(rows) ~= "table" then return end
        local msgs = P.Encode(P.Mine(rows), ns.id.commVersion)
        local key = table.concat(msgs, "\n")
        if key == lastKey then return end
        for _, m in ipairs(msgs) do
            local ok, sent = pcall(c.addonSend, P.Prefix(), m, P.CHANNEL)
            if not ok or sent ~= true then return end
        end
        lastKey = key
    end

    local function roster()
        local names = party()
        if not names then
            progress, buffers, members, lastKey = {}, {}, nil, nil
            return
        end
        for who in pairs(progress) do
            if not names[who] then progress[who] = nil end
        end
        for who in pairs(buffers) do
            if not names[who] then buffers[who] = nil end
        end
        -- Someone new: send again (throttled) so they have your progress.
        for who in pairs(names) do
            if not members or not members[who] then
                lastKey = nil
                dirty = true
            end
        end
        members = names
    end

    local function receive(prefix, text, channel, sender)
        if prefix ~= P.Prefix() or channel ~= P.CHANNEL then return end
        local who = plain(sender)
        if not who or who == me() then return end
        local names = party()
        if names and not names[who] then return end
        local d = P.Decode(text, ns.id.commVersion)
        if not d then return end
        if d.seq == 1 then
            buffers[who] = { count = d.count, nextSeq = 1, quests = {} }
        end
        local buf = buffers[who]
        if not buf or buf.count ~= d.count or buf.nextSeq ~= d.seq then
            buffers[who] = nil
            return
        end
        for id, e in pairs(d.quests) do buf.quests[id] = e end
        buf.nextSeq = d.seq + 1
        if d.seq == d.count then
            progress[who] = buf.quests
            buffers[who] = nil
        end
    end

    local api = {}
    function api.Progress(name)
        local who = plain(name)
        if not who then return nil end
        return progress[who]
    end
    function api.All()
        local out = {}
        for who, q in pairs(progress) do out[who] = q end
        return out
    end
    function api.Names()
        local out = {}
        for who in pairs(progress) do out[#out + 1] = who end
        table.sort(out)
        return out
    end

    k:Setting({ key = P.SETTING, scope = "account", type = "bool", default = true,
        label = "Share quest progress with your party", group = "travel.route",
        help = "While you are in a party, tells party members who use this add-on how far you are on each quest"
            .. " in your log, as add-on data at most every few seconds and only when it changed;"
            .. " never to chat, a raid or anyone else.",
        synonyms = { "party", "share", "quest", "progress", "group" } })

    k:Module({
        name = P.NAME,
        needs = { "client", "settings" },
        provides = { Progress = api.Progress, All = api.All, Names = api.Names },
        start = function(c)
            ctx = c
            local cl = c.client
            if type(cl.addonPrefix) == "function" then
                local ok, v = pcall(cl.addonPrefix, P.Prefix())
                prefixOk = ok and v == true
            end
            local function mark() dirty = true end
            cancels[#cancels + 1] = cl.listen("QUEST_LOG_UPDATE", mark)
            cancels[#cancels + 1] = cl.listen("UNIT_QUEST_LOG_CHANGED", function(unit)
                if unit == "player" then dirty = true end
            end)
            cancels[#cancels + 1] = cl.listen("PLAYER_ENTERING_WORLD", mark)
            cancels[#cancels + 1] = cl.listen("GROUP_ROSTER_UPDATE", function() pcall(roster) end)
            cancels[#cancels + 1] = cl.listen("CHAT_MSG_ADDON", function(...) pcall(receive, ...) end)
            cancels[#cancels + 1] = cl.onFrame(function() pcall(check) end)
        end,
        stop = function()
            for _, cancel in ipairs(cancels) do
                if type(cancel) == "function" then pcall(cancel) end
            end
            cancels = {}
            ctx = nil
            progress, buffers, members = {}, {}, nil
            dirty, lastKey, checkedAt = true, nil, nil
        end,
    })
    return api
end

P.Declare(ns)
