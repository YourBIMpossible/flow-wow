-- F-new-3 (lead section 872.2): with the short, still login intro on
-- (UI/LoginIntro.lua, the LI.SHORT setting) the arrows' intro lasts as long
-- as that one, LI.Times(true); otherwise Arrow.INTRO_SECONDS. Over the fake
-- client; no game client is involved.
local _, ns = ...

local A = ns.Arrow
local LI = ns.LoginIntro

-- A kernel stand-in whose settings answer short for LI.SHORT.
local function kWith(short)
    return { settings = { get = function(_, key)
        if key == LI.SHORT then return short end
        return nil
    end } }
end

-- The still intro's length, from its own rule.
local function still()
    local show, tail = LI.Times(true)
    return show + tail
end

local function start()
    local c = ns.make.fakeClient()
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    return c, a, k
end

return {
    ["intro still: the short intro off gives INTRO_SECONDS"] = function(t)
        t.eq(A.IntroSeconds(kWith(false)), A.INTRO_SECONDS)
        t.eq(A.IntroSeconds(kWith(nil)), A.INTRO_SECONDS, "never set")
    end,

    ["intro still: the short intro on gives LI.Times(true), show plus fade"] = function(t)
        t.eq(A.IntroSeconds(kWith(true)), still())
        t.ok(still() < A.INTRO_SECONDS, "shorter than the full intro")
    end,

    ["intro still: settings that cannot be read give INTRO_SECONDS"] = function(t)
        t.eq(A.IntroSeconds(nil), A.INTRO_SECONDS, "no kernel")
        t.eq(A.IntroSeconds({}), A.INTRO_SECONDS, "no settings")
        t.eq(A.IntroSeconds({ settings = { get = function() error("broken") end } }), A.INTRO_SECONDS, "raises")
    end,

    ["intro still: with the short intro on, the arrows' intro ends after it"] = function(t)
        local c, a, k = start()
        local s = k.settings
        local get = s.get
        s.get = function(self, key)
            if key == LI.SHORT then return true end
            return get(self, key)
        end
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
        c.advance(0.01, 1)
        c.advance(still() - 0.3, 5)
        local during = a.state().view.quest.mode
        c.advance(0.6, 5)
        local after = a.state().view.quest.mode
        s.get = get
        t.eq(during, "intro", "still playing")
        t.ok(after ~= "intro", "ended with the short intro, before INTRO_SECONDS")
    end,
}
