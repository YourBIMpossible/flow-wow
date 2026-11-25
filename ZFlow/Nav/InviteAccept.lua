local _, ns = ...

-- Parity row F-28 (lead sections 738 and 740): a group invite from a
-- friend is accepted for you. As Flow's Modules/Invites.lua (:1-3,
-- on by default; :78-87: on PARTY_INVITE_REQUEST, not when already in a
-- group, only someone you count as a friend, then AcceptGroup and one line
-- in chat). Friends only, as Flow (the WoW friends list and Battle.net;
-- lead section 740: not guild members). Z-Flow adds three guards the row
-- asks for:
-- never in a fight, never while queued, and never on an answer that is not
-- known (a fight, a queue, a group or a friend not read is never yes).
--
-- Nav/InvitePrompt.lua's advice line stays as it was (its own setting).
-- Flow also closed the game's invite popup by hand (StaticPopup_Hide);
-- that is a Blizzard frame, so it is left to the game here.
--
--   IA.Decide(r) -> "accept" | why not: "off", "combat", "grouped",
--     "queued", "stranger". r = { on, inCombat, grouped, queued, friend };
--     each must be a plain true or false to count.
-- Setting IA.SETTING (bool, account), on as made (Flow's default).
-- "<slash> invites on|off" switches it and says the state.
-- Reads: client.inCombat, client.grouped, client.isFriend(guid) (as
-- InvitePrompt), and one CLIENT NEED stubbed in Core/ClientFake.lua
-- ("§ F-28"): client.queued() (a dungeon finder or battleground queue).
-- Action: client.acceptGroup(), the second CLIENT NEED (AcceptGroup()).
-- The inviter's name is said, never saved.
-- Not tested in game.
local IA = {}
ns.Nav.InviteAccept = IA

IA.NAME = "inviteAccept"
IA.SETTING = "invites.accept"
IA.WORD = "invites"
IA.HELP = "accept group invites from friends for you: invites on|off"
IA.JOINED = "joined %s's group (a friend's invite, accepted for you; %s %s off to stop)."

function IA.Decide(r)
    if type(r) ~= "table" or r.on ~= true then return "off" end
    if r.inCombat ~= false then return "combat" end
    if r.grouped ~= false then return "grouped" end
    if r.queued ~= false then return "queued" end
    if r.friend ~= true then return "stranger" end
    return "accept"
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok and type(v) == "boolean" then return v end
    return nil
end

function IA.Declare(k, diag)
    local api = {}
    local ctx

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    function api.Invited(name, guid)
        if not ctx then return "off" end
        local client = ctx.client
        local id = nil
        if type(guid) == "string" and guid ~= "" then id = guid end
        local r = {
            on = ctx.settings:get(IA.SETTING) ~= false,
            inCombat = ask(client, "inCombat"),
            grouped = ask(client, "grouped"),
            queued = ask(client, "queued"),
        }
        if id then r.friend = ask(client, "isFriend", id) end
        local verdict = IA.Decide(r)
        if verdict ~= "accept" then return verdict end
        if type(client.acceptGroup) ~= "function" then return "noAction" end
        local ok = pcall(client.acceptGroup)
        if not ok then return "refused" end
        local who = "your friend"
        if type(name) == "string" and name ~= "" then who = name end
        say(IA.JOINED:format(who, ns.id.slash, IA.WORD))
        return "accept"
    end

    k:Module({
        name = IA.NAME,
        needs = { "client", "bus", "settings" },
        settings = { {
            -- A new row, on as made (as Flow's): a changed behaviour,
            -- reviewed from another lane (lead section 557).
            key = IA.SETTING, scope = "account", type = "bool", default = true,
            label = "Accept group invites from friends",
            help = "A friend who invites you to a group is accepted for you, out of a fight "
                .. "and when you are not queued or in a group. Anyone else gets the game's own window.",
            group = "party",
            synonyms = { "invite", "invites", "accept", "party", "group", "friend" },
        } },
        start = function(c)
            ctx = c
            c.bus:on(IA.NAME, "PARTY_INVITE_REQUEST", function(name, _, _, _, _, _, guid)
                api.Invited(name, guid)
            end)
        end,
        stop = function() ctx = nil end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[IA.WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then ctx.settings:set(IA.SETTING, word == "on") end
            local state = "on"
            if ctx.settings:get(IA.SETTING) == false then state = "off" end
            say("accept group invites from friends: " .. state
                .. " (" .. ns.id.slash .. " " .. IA.WORD .. " on|off).")
        end
        if type(diag.help) == "table" then diag.help[IA.WORD] = IA.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.inviteAccept = IA.Declare(ns, ns.diag)
