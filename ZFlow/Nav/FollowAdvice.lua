local _, ns = ...

-- Follow advice (G47, lead section 397 item 15): in a group, when your
-- leader is far away, one advisor prompt says how far and which way:
-- "Your leader Ander is 300 yd away to the E: catch up." It goes when the
-- leader is near again, you leave the group, or the setting is off.
-- No line when you lead, are alone, or where either of you is is not
-- known (another map, an instance, no map size).
--
-- TEXT ONLY. Nothing here follows, targets, assists, casts, moves or
-- binds a key for the player: the player walks.
--
-- Pure part:
--   FA.Text(name, me, at, size) -> the line, or nil
--     me, at: { map, x = 0..1, y = 0..1 } (you and the leader); size:
--     { w, h } yards of that map. nil when anything is not known, the maps
--     differ, or the leader is within FA.FAR yards.
--
-- Reads: client.groupLeader(), client.party(), client.unitPosition(unit),
-- client.position(), client.mapSize(map). Writes: none.
-- Not seen in game: whether the client answers unitPosition and
-- UnitIsGroupLeader on 16001; where it does not, there is no line.
-- Setting (char, on by default): nav.followAdvice.

ns.Nav = ns.Nav or {}
local N = ns.Nav

local FA = {}
N.FollowAdvice = FA

FA.NAME = "followAdvice"
FA.SETTING = "nav.followAdvice"
FA.PROMPT = "party.followLeader"
FA.PRIORITY = 1
FA.FAR = 100      -- yards: farther than this gets the line (a first guess)
FA.EVERY = 2      -- seconds between looks
FA.LINE = "Your leader %s is %d yd away to the %s: catch up."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function spot(p)
    return type(p) == "table" and p.map ~= nil and finite(p.x) and finite(p.y)
end

function FA.Text(name, me, at, size)
    if type(name) ~= "string" or name == "" then return nil end
    if not spot(me) or not spot(at) or me.map ~= at.map then return nil end
    if type(size) ~= "table" or not finite(size.w) or not finite(size.h) or size.w <= 0 or size.h <= 0 then
        return nil
    end
    local b = N.Bearing({ x = me.x * size.w, y = me.y * size.h }, { x = at.x * size.w, y = at.y * size.h })
    if type(b) ~= "table" or not b.known or not finite(b.distance) or b.distance <= FA.FAR then return nil end
    local word = N.Compass(b.bearing)
    if not word then return nil end
    return string.format(FA.LINE, name, math.floor(b.distance + 0.5), word)
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

-- The leader's name from the party list, or nil.
local function nameOf(client, unit)
    local party = ask(client, "party")
    if type(party) ~= "table" then return nil end
    for _, row in ipairs(party) do
        if type(row) == "table" and row.unit == unit and type(row.name) == "string" then return row.name end
    end
    return nil
end

function FA.Declare(k)
    local api = {}
    local look = function() end

    k:Module({
        name = FA.NAME,
        needs = { "client", "bus", "settings", "sched", "advisor" },
        settings = { {
            key = FA.SETTING, scope = "char", type = "bool", default = true,
            label = "Your leader is far away",
            help = "In a group, says when your leader is far away, how far and which way, so you can catch up. "
                .. "It only reads where they are: nothing follows or targets them for you.",
            group = "party",
            synonyms = { "follow", "leader", "group", "party", "catch up", "advice" },
        } },
        ticks = { { every = FA.EVERY, when = "always", run = function() look() end } },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(advisor) ~= "table" then return end
            local client = ctx.client
            local shown

            local function show(text)
                if text == shown then return end
                if text then advisor.Add(FA.PROMPT, text, FA.PRIORITY) else advisor.Remove(FA.PROMPT) end
                shown = text
            end

            look = function()
                local text
                if ctx.settings:get(FA.SETTING) ~= false then
                    local leader = ask(client, "groupLeader")
                    if type(leader) == "string" and leader ~= "player" then
                        local at = ask(client, "unitPosition", leader)
                        local me = ask(client, "position")
                        local size = spot(me) and ask(client, "mapSize", me.map) or nil
                        text = FA.Text(nameOf(client, leader), me, at, size)
                    end
                end
                show(text)
            end

            ctx.bus:on(FA.NAME, "GROUP_ROSTER_UPDATE", look)
            ctx.bus:on(FA.NAME, "PLAYER_ENTERING_WORLD", look)
            look()
        end,
        stop = function() look = function() end end,
    })
    api.Look = function() look() end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.followAdvice = FA.Declare(ns)
