local _, ns = ...

-- Party invites (G58, WHITE-QUEUE C6): when someone invites you, one line
-- in the advice panel says who asked and whether they are on your friends
-- list, from Core/InviteAdvice.lua:
--   "<name> invited you and is a friend: accept the invite."
--   "<name> invited you: up to you."
-- The line goes when you join a group, when the invite is taken back, and
-- after P.KEEP seconds.
--
-- TEXT ONLY. Nothing here accepts or declines: the game's own popup is the
-- player's to answer. (Old Flow accepted a friend's invite for the player;
-- that half is not built here.)
--
-- Setting "invites.friends" (bool, account), off by default: off, no line.
-- Reads: client.isFriend(guid) (the game's friends list). Writes: none.
-- The inviter's name is shown, never saved.
-- Not seen in game: whether the invite carries the inviter's id here; with
-- none, or no answer about the friends list, the line is "up to you".

local P = {}
ns.Nav.InvitePrompt = P

P.NAME = "invitePrompt"
P.SETTING = "invites.friends"
P.PROMPT = "party.invite"
P.PRIORITY = 60
P.KEEP = 60   -- seconds: the game takes an unanswered invite back after about this long
P.EVERY = 1

function P.Declare(k)
    local api = {}

    k:Module({
        name = P.NAME,
        needs = { "client", "bus", "settings", "store", "advisor" },
        settings = { {
            key = P.SETTING, scope = "account", type = "bool", default = false,
            label = "Party invites: say if a friend is asking",
            help = "When someone invites you to a group, one line says who asked and whether they are on "
                .. "your friends list. It accepts and declines nothing: you answer the game's own window.",
            group = "party",
            synonyms = { "invite", "invites", "party", "group", "friend", "friends", "accept" },
        } },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(advisor) ~= "table" then return end
            local shownAt, cancel

            local function now()
                local c = ctx.client
                if type(c.now) ~= "function" then return nil end
                local ok, v = pcall(c.now)
                return ok and type(v) == "number" and v or nil
            end

            local function clear()
                if shownAt == nil then return end
                shownAt = nil
                advisor.Remove(P.PROMPT)
            end

            function api.Invited(name, guid)
                if ctx.settings:get(P.SETTING) ~= true then return clear() end
                local friend
                local c = ctx.client
                if type(guid) == "string" and guid ~= "" and type(c.isFriend) == "function" then
                    local ok, v = pcall(c.isFriend, guid)
                    if ok and v == true then friend = true end
                end
                local advice = ns.InviteAdvice.Advise({ inviter = name, friend = friend }, { friends = true })
                if not advice then return end
                advisor.Add(P.PROMPT, advice.text, P.PRIORITY)
                shownAt = now() or 0
            end

            ctx.bus:on(P.NAME, "PARTY_INVITE_REQUEST", function(name, _, _, _, _, _, guid)
                api.Invited(name, guid)
            end)
            ctx.bus:on(P.NAME, "PARTY_INVITE_CANCEL", clear)
            ctx.bus:on(P.NAME, "GROUP_ROSTER_UPDATE", clear)
            -- Turned off while a line is up: the line goes at once.
            local row = ctx.settings:row(P.SETTING)
            if type(row) == "table" then
                cancel = ctx.store:watch(row.scope, row.path or ("settings." .. P.SETTING), function()
                    if ctx.settings:get(P.SETTING) ~= true then clear() end
                end)
            end
            api.Stop = function()
                if type(cancel) == "function" then cancel() end
                cancel = nil
            end
            api.Tick = function()
                if shownAt == nil then return end
                local t = now()
                if t == nil or t - shownAt >= P.KEEP then clear() end
            end
        end,
        ticks = { { every = P.EVERY, when = "always", run = function() if api.Tick then api.Tick() end end } },
        stop = function()
            if api.Stop then api.Stop() end
            api.Tick, api.Invited, api.Stop = nil, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.invitePrompt = P.Declare(ns)
