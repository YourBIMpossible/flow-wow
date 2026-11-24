-- The party invite line (G58, Nav/InvitePrompt.lua), end to end on the
-- whole add-on loaded on a fake client: off until the setting is on, a
-- friend named as one to accept, anyone else left to the player, and the
-- line gone when the invite is. It accepts nothing. The names are made up.
-- Not tested in game.
local _, ns = ...
local tests = {}

local function P() return ns.Nav.InvitePrompt end

local function boot(on)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    local key = P().SETTING
    if on then addon.settings:set(key, true) end
    return c, addon
end

local function line(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == P().PROMPT then return p.text end
    end
    return nil
end

local function invite(c, name, guid)
    c.fire("PARTY_INVITE_REQUEST", name, false, false, false, false, false, guid)
end

tests["invite line: off until the setting is on"] = function(t)
    local c, addon = boot(false)
    local key = P().SETTING
    t.eq(addon.settings:get(key), false)
    c.setFriend("Player-1-0000000A", true)
    invite(c, "Friendname", "Player-1-0000000A")
    t.eq(line(addon), nil)
end

tests["invite line: a friend is named as one to accept; nothing is accepted"] = function(t)
    local c, addon = boot(true)
    c.setFriend("Player-1-0000000A", true)
    invite(c, "Friendname", "Player-1-0000000A")
    t.eq(line(addon), "Friendname invited you and is a friend: accept the invite.")
    t.eq(c.grouped(), nil, "it joined no group")
end

tests["invite line: a stranger, or no answer about the friends list, is up to you"] = function(t)
    local c, addon = boot(true)
    c.setFriend("Player-1-0000000B", false)
    invite(c, "Othername", "Player-1-0000000B")
    t.eq(line(addon), "Othername invited you: up to you.")
    invite(c, "Thirdname", nil)
    t.eq(line(addon), "Thirdname invited you: up to you.")
    invite(c, "Fourthname", "Player-1-0000000C")
    t.eq(line(addon), "Fourthname invited you: up to you.")
end

tests["invite line: gone when you join, when it is taken back, and after a while"] = function(t)
    local c, addon = boot(true)
    invite(c, "Othername", nil)
    t.ok(line(addon) ~= nil)
    c.fire("GROUP_ROSTER_UPDATE")
    t.eq(line(addon), nil, "joined")
    invite(c, "Othername", nil)
    c.fire("PARTY_INVITE_CANCEL")
    t.eq(line(addon), nil, "taken back")
    invite(c, "Othername", nil)
    c.advance(P().KEEP - 5, 5)
    t.ok(line(addon) ~= nil, "still there")
    c.advance(10, 10)
    t.eq(line(addon), nil, "the invite ran out")
end

tests["invite line: the setting turned off takes the line away at once"] = function(t)
    local c, addon = boot(true)
    invite(c, "Othername", nil)
    t.ok(line(addon) ~= nil)
    local key = P().SETTING
    addon.settings:set(key, false)
    t.eq(line(addon), nil)
    invite(c, "Othername", nil)
    t.eq(line(addon), nil)
end

return tests
