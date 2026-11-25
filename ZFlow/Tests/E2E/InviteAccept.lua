-- Parity row F-28 (lead sections 738 and 740): a group invite from a
-- friend is accepted for you (friends only, as Flow; not guild members),
-- as Flow's Modules/Invites.lua (:1-3
-- "accepted for you", on by default; :78-87 the event, not when already
-- in a group, only a friend). Never in a fight, never from a stranger,
-- never while queued, never in a group already, never with the setting
-- off. The whole add-on on a fake client; the names are made up. Not
-- tested in game. Fails before: nothing was ever accepted.
local _, ns = ...
local tests = {}

local function IA() return ns.Nav.InviteAccept end

local FRIEND, GUILDIE, STRANGER = "Player-1-0000000A", "Player-1-0000000B", "Player-1-0000000C"

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.setFriend(FRIEND, true)
    c.setFriend(STRANGER, false)
    c.setFriend(GUILDIE, false)
    c.setGrouped(false)
    c.setQueued(false)
    c.setCombat(false)
    return c, addon
end

local function invite(c, name, guid)
    c.fire("PARTY_INVITE_REQUEST", name, false, false, false, false, false, guid)
end

tests["invite accept: names and the default, on as Flow's"] = function(t)
    t.eq(type(IA()), "table", "loaded")
    if type(IA()) ~= "table" then return end
    t.eq({ IA().NAME, IA().SETTING, IA().WORD }, { "inviteAccept", "invites.accept", "invites" })
    local _, addon = boot()
    t.eq(addon.settings:get(IA().SETTING), true, "on as made (Flow: on by default)")
end

tests["invite accept: a friend's invite is accepted"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 1, "the friend")
end

-- Lead section 740: Flow accepts friends only.
tests["invite accept: a guild member who is not a friend is not accepted"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    invite(c, "Guildname", GUILDIE)
    t.eq(c.groupAccepts, 0, "a guild member, not a friend")
    t.eq(IA().Decide({ on = true, inCombat = false, grouped = false, queued = false, friend = false, guild = true }),
        "stranger", "a guild answer counts for nothing")
end

tests["invite accept: never from a stranger, or one whose standing is not known"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    invite(c, "Stranger", STRANGER)
    t.eq(c.groupAccepts, 0, "a stranger")
    invite(c, "Noid", nil)
    t.eq(c.groupAccepts, 0, "no id: not known, not accepted")
    invite(c, "Unknown", "Player-1-0000000D")
    t.eq(c.groupAccepts, 0, "neither list answers: not accepted")
end

tests["invite accept: never in a fight, or a fight not known"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    c.setCombat(true)
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 0, "in a fight")
    t.eq(IA().Decide({ on = true, inCombat = nil, grouped = false, queued = false, friend = true }), "combat",
        "a fight not known")
end

tests["invite accept: never while queued, or in a group already"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    c.setQueued(true)
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 0, "queued")
    c.setQueued(nil)
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 0, "a queue not known")
    c.setQueued(false)
    c.setGrouped(true)
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 0, "in a group already")
end

tests["invite accept: off by the setting or the word, nothing accepted"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c, addon = boot()
    addon.settings:set(IA().SETTING, false)
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 0, "the setting off")
    c.slashes[ns.id.slash](IA().WORD .. " on")
    t.eq(addon.settings:get(IA().SETTING), true, "the word turns it on")
    invite(c, "Friendname", FRIEND)
    t.eq(c.groupAccepts, 1)
end

tests["invite accept: says so in one line, and saves no name"] = function(t)
    if type(IA()) ~= "table" then return t.ok(false, "not loaded") end
    local c = boot()
    local before = #c.printed
    invite(c, "Friendname", FRIEND)
    local said = table.concat(c.printed, "\n", before + 1)
    t.ok(said:find("Friendname", 1, true) ~= nil, "names who: " .. said)
    local function holds(v)
        if type(v) == "string" then return v:find("Friendname", 1, true) ~= nil end
        if type(v) ~= "table" then return false end
        for key, value in pairs(v) do if holds(key) or holds(value) then return true end end
        return false
    end
    t.ok(not holds(c.saved(ns.id.accountDB)) and not holds(c.saved(ns.id.charDB)), "no name saved")
end

return tests
