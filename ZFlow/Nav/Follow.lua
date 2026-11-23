local _, ns = ...
-- Z-Flow: point the arrow at a party member (G47, lead dispatch P-NAV).
-- The player picks one (the word, or the arrow menu's row); the quest
-- arrow points at them until the player stops it or they leave the group.
-- Where they are comes only from the game's own read of a party unit's
-- position (client.unitPosition); nothing is sent, shared or asked of
-- another add-on. When that position is not known (another map, an
-- instance) it is said once and the arrow shows its normal step.
--
-- LOOK ONLY. Nothing follows, targets, moves, invites or speaks for the
-- player: the arrow only points.
--
--   F.Declare(k, diag) -> api
--     api.Pick(which)   which: a party unit ("party2"), a number in the
--                       party list, or a name (any case). true or nil, why
--     api.Stop()        true when one was chosen
--     api.Step()        the step for the arrow, or nil
--     api.Members()     { { unit, name } } of the party now, or nil
-- The chosen member is kept in memory only: no name is saved.
-- Not tested in game: client.unitPosition is a first guess.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local F = {}
N.Follow = F

F.NAME = "follow"
F.WORD = "follow"
F.HELP = "follow [name | number | stop]: point the arrow at a party member (it never moves you)"
F.RADIUS = 5     -- yards: the step's radius

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function F.Declare(k, diag)
    local api = {}
    local ctx
    -- chosen = { unit, name }; unknownSaid: the "not known" line was said
    -- for the present stretch of not knowing.
    local chosen, unknownSaid = nil, false

    local function ask(name, ...)
        local client = ctx and ctx.client or k.client
        if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
        local ok, v = pcall(client[name], ...)
        if ok then return v end
        return nil
    end

    local function say(line)
        local client = ctx and ctx.client or k.client
        if type(client) == "table" and type(client.print) == "function" then
            client.print((k.id or ns.id).title .. ": " .. line)
        end
    end

    function api.Members()
        local party = ask("party")
        if type(party) ~= "table" then return nil end
        local out = {}
        for _, row in ipairs(party) do
            if type(row) == "table" and type(row.unit) == "string" then
                out[#out + 1] = { unit = row.unit, name = type(row.name) == "string" and row.name or nil }
            end
        end
        return out
    end

    local function nameOf(m) return m.name or m.unit end

    function api.Pick(which)
        local members = api.Members()
        if not members or #members == 0 then return nil, "you are not in a group." end
        local pick
        local n = tonumber(which)
        if n then
            pick = members[n]
        elseif type(which) == "string" then
            local want = which:lower()
            for _, m in ipairs(members) do
                if m.unit == which or (m.name and m.name:lower() == want) then
                    pick = m
                    break
                end
            end
        end
        if not pick then return nil, "no party member " .. tostring(which) .. "." end
        chosen, unknownSaid = { unit = pick.unit, name = pick.name }, false
        say("the arrow points at " .. nameOf(pick) .. " until you stop it (" .. F.WORD .. " stop).")
        return true
    end

    function api.Stop()
        if not chosen then return false end
        chosen, unknownSaid = nil, false
        say("the arrow no longer points at a party member.")
        return true
    end

    function api.Step()
        if not chosen then return nil end
        local members = api.Members()
        if members == nil then return nil end
        local now
        for _, m in ipairs(members) do
            local same = chosen.name ~= nil and m.name == chosen.name
                or chosen.name == nil and m.unit == chosen.unit
            if same then
                now = m
                break
            end
        end
        if not now then
            local name = nameOf(chosen)
            chosen, unknownSaid = nil, false
            say(name .. " is no longer in your group; the arrow no longer points at them.")
            return nil
        end
        chosen.unit = now.unit
        local at = ask("unitPosition", now.unit)
        if type(at) ~= "table" or at.map == nil or not finite(at.x) or not finite(at.y) then
            if not unknownSaid then
                unknownSaid = true
                say("where " .. nameOf(now) .. " is is not known (another map or an instance); the arrow shows your own step.")
            end
            return nil
        end
        unknownSaid = false
        local cont
        local here = ask("position")
        if type(here) == "table" and here.map == at.map then
            local zone = ask("zone")
            cont = type(zone) == "table" and zone.cont or nil
        end
        return { label = nameOf(now), place = { cont = cont, map = at.map, x = at.x, y = at.y }, radius = F.RADIUS }
    end

    k:Module({
        name = F.NAME,
        needs = { "client" },
        provides = {
            Pick = function(which) return api.Pick(which) end,
            Stop = function() return api.Stop() end,
            Step = function() return api.Step() end,
            Members = function() return api.Members() end,
        },
        start = function(c) ctx = c end,
        stop = function() chosen, unknownSaid = nil, false end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[F.WORD] = function(rest)
            rest = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
            if rest == "stop" or rest == "off" then
                if not api.Stop() then say("the arrow is not pointing at a party member.") end
                return
            end
            if rest == "" then
                local members = api.Members()
                if not members or #members == 0 then
                    say("you are not in a group.")
                    return
                end
                local names = {}
                for i, m in ipairs(members) do names[i] = i .. ". " .. nameOf(m) end
                say("point the arrow at: " .. table.concat(names, ", ") .. " (" .. F.WORD .. " <name or number>).")
                if chosen then say("now pointing at " .. nameOf(chosen) .. ".") end
                return
            end
            local ok, why = api.Pick(rest)
            if not ok then say(why) end
        end
        if type(diag.help) == "table" then diag.help[F.WORD] = F.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.follow = F.Declare(ns, ns.diag)
