local _, ns = ...

-- P-INVITES (FEATURE-PLAN G58), advice text only: a friend's or guild
-- member's invite is named as one Flow would accept with the setting on;
-- anyone else is left to the player. Nothing is accepted or declined.

local tests = {}

tests["invite advice: a friend or guild member is named as one to accept"] = function(t)
    local I = ns.InviteAdvice
    local a = I.Advise({ inviter = "Anna", friend = true }, { friends = true })
    t.eq(type(a) == "table" and a.accept, true, "friend")
    t.ok(type(a) == "table" and a.text:find("Anna", 1, true) ~= nil, "names the inviter")
    t.eq(I.Advise({ inviter = "Bo", guild = true }, { friends = true }).accept, true, "guild member")
    t.eq(type(a) == "table" and a.look, true, "look only")
end

tests["invite advice: anyone else, or the setting off, is left to the player"] = function(t)
    local I = ns.InviteAdvice
    local a = I.Advise({ inviter = "Cy", friend = false, guild = false }, { friends = true })
    t.eq(a.accept, false, "stranger")
    t.ok(a.text:find("up to you", 1, true) ~= nil, "left to you")
    t.eq(I.Advise({ inviter = "Anna", friend = true }, { friends = false }).accept, false, "setting off")
    t.eq(I.Advise({ inviter = "Anna", friend = true }, nil).accept, false, "setting not set: off by default")
    t.eq(I.Advise(nil, { friends = true }), nil, "no invite")
end

return tests
