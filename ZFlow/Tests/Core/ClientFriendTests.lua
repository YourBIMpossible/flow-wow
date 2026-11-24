-- c.isFriend(guid) (G58): is this player on the friends list? The real
-- client over a hand-built environment; ClientFake's own version at the
-- end. Unknown stays unknown: no id, no friends list, a failed read or an
-- answer of the wrong shape gives nil, never "not a friend".
local _, ns = ...

local tests = {}

local ID = "Player-1-0000000A"

tests["isFriend: true and false as the game says, asked with the id"] = function(t)
    local asked
    local c = ns.make.client({ C_FriendList = { IsFriend = function(guid) asked = guid; return guid == ID end } })
    t.eq(c.isFriend(ID), true)
    t.eq(asked, ID)
    t.eq(c.isFriend("Player-1-0000000B"), false)
end

tests["isFriend: nil with no id, no friends list, a failed read or a wrong answer"] = function(t)
    local c = ns.make.client({ C_FriendList = { IsFriend = function() return true end } })
    t.eq(c.isFriend(nil), nil)
    t.eq(c.isFriend(""), nil)
    t.eq(c.isFriend(7), nil)
    t.eq(ns.make.client({}).isFriend(ID), nil)
    t.eq(ns.make.client({ C_FriendList = {} }).isFriend(ID), nil)
    t.eq(ns.make.client({ C_FriendList = { IsFriend = function() error("no") end } }).isFriend(ID), nil)
    t.eq(ns.make.client({ C_FriendList = { IsFriend = function() return 1 end } }).isFriend(ID), nil)
end

tests["isFriend: the fake answers what it was set, and nil until then"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.isFriend(ID), nil)
    c.setFriend(ID, true)
    t.eq(c.isFriend(ID), true)
end

return tests
