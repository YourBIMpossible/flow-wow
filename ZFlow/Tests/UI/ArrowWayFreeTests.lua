-- "/way" is claimed only when no other addon owns it (legacy
-- Modules/Nav/Waypoint.lua:260-262), over the fake client and over a
-- hand-built environment for the real boundary. The addon's own command
-- followed by "way" works either way. No game client is involved. Not seen
-- in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav
local W = N.Waypoint

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.takenAtLoad and type(c.setSlashTaken) == "function" then c.setSlashTaken("/way", true) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    if opts.takenAtLogin and type(c.setSlashTaken) == "function" then c.setSlashTaken("/way", true) end
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function last(c) return c.printed[#c.printed] or "" end
local function saved(k)
    local nav = k.store:get(W.SCOPE, W.PATH)
    return type(nav) == "table" and nav.waypoint or nil
end
local function has(text, part) return text:find(part, 1, true) ~= nil end

-- The client's slash globals, hand-written.
local function slashEnv()
    return { SlashCmdList = {} }
end

return {
    ["way free: nobody else has it, so it is claimed"] = function(t)
        local k, c = start()
        t.ok(type(c.slashes["/way"]) == "function", "the command is there")
        if type(c.slashes["/way"]) ~= "function" then return end
        c.slashes["/way"]("50 30")
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 })
    end,

    ["way free: another addon had it when the file loaded, so it is left alone"] = function(t)
        local k, c = start({ takenAtLoad = true })
        t.ok(type(c.setSlashTaken) == "function", "the fake can say a command is taken")
        t.eq(c.slashes["/way"], nil, "not claimed")
        t.eq(k.problems:count(), 0, "being second is no problem")
    end,

    ["way free: the addon's own command still sets one when /way is taken"] = function(t)
        local k, c = start({ takenAtLoad = true })
        t.eq(c.slashes["/way"], nil)
        c.slashes[ns.id.slash]("way 50 30")
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 })
        t.ok(has(last(c), "waypoint set: 50.0, 30.0"), last(c))
    end,

    ["way free: with /way taken, how to set one names the addon's own command"] = function(t)
        local _, c = start({ takenAtLoad = true })
        c.slashes[ns.id.slash]("way")
        t.ok(has(last(c), ns.id.slash .. " way x y"), last(c))
        t.ok(not has(last(c), " /way x y"), last(c))
    end,

    ["way free: another addon claims it by the login, so it is given back"] = function(t)
        local k, c = start({ takenAtLogin = true })
        t.ok(type(c.setSlashTaken) == "function", "the fake can say a command is taken")
        t.eq(c.slashes["/way"], nil, "given back")
        c.slashes[ns.id.slash]("way 50 30")
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 }, "the own command still works")
    end,

    ["way free: the real boundary sees a command another tag owns"] = function(t)
        local env = slashEnv()
        local c = ns.make.client(env)
        t.ok(type(c.slashTaken) == "function", "the read is there")
        if type(c.slashTaken) ~= "function" then return end
        t.eq(c.slashTaken("/way", "MINEWAY"), false, "free")
        env.SlashCmdList.OTHER_WAY = function() end
        env.SLASH_OTHER_WAY1 = "/otherway"
        env.SLASH_OTHER_WAY2 = "/WAY"
        t.eq(c.slashTaken("/way", "MINEWAY"), true, "the second spelling, any case")
        t.eq(c.slashTaken("/elsewhere", "MINEWAY"), false)
    end,

    ["way free: the real boundary does not count its own tag"] = function(t)
        local env = slashEnv()
        local c = ns.make.client(env)
        if type(c.slashTaken) ~= "function" then t.ok(false, "no read") return end
        local got
        t.eq(c.slash("MINEWAY", "/way", function(rest) got = rest end), true)
        t.eq(c.slashTaken("/way", "MINEWAY"), false, "held by the asker")
        t.eq(c.slashTaken("/way", "SOMEONE"), true, "held by another")
        env.SlashCmdList.MINEWAY("1 2")
        t.eq(got, "1 2")
    end,

    ["way free: the real boundary sees a command the client has already looked up"] = function(t)
        local env = slashEnv()
        local c = ns.make.client(env)
        if type(c.slashTaken) ~= "function" then t.ok(false, "no read") return end
        env.hash_SlashCmdList = { ["/WAY"] = function() end }
        t.eq(c.slashTaken("/way", "MINEWAY"), true)
    end,

    ["way free: with no slash table the answer is unknown, not free"] = function(t)
        local c = ns.make.client({})
        if type(c.slashTaken) ~= "function" then t.ok(false, "no read") return end
        t.eq(c.slashTaken("/way", "MINEWAY"), nil)
        t.eq(c.slashTaken(nil, "MINEWAY"), nil)
    end,

    ["way free: giving a command back clears the tag, its text and the looked-up entry"] = function(t)
        local env = slashEnv()
        local c = ns.make.client(env)
        t.ok(type(c.unslash) == "function", "the release is there")
        if type(c.unslash) ~= "function" then return end
        c.slash("MINEWAY", "/way", function() end)
        local other = function() end
        env.hash_SlashCmdList = { ["/WAY"] = env.SlashCmdList.MINEWAY, ["/KEEP"] = other }
        t.eq(c.unslash("MINEWAY"), true)
        t.eq(env.SlashCmdList.MINEWAY, nil)
        t.eq(env.SLASH_MINEWAY1, nil)
        t.eq(env.hash_SlashCmdList["/WAY"], nil)
        t.eq(env.hash_SlashCmdList["/KEEP"], other, "another command is not touched")
        t.eq(c.unslash("MINEWAY"), false, "nothing held, nothing done")
    end,
}
