-- A short, still login intro for players who want less motion on screen
-- (F-new-3). Flow had it as splash.short (commit 5ae28de5,
-- Modules/Splash.lua:16-22): off unless ticked; on, nothing turns, the
-- title shows for 1.0 s and fades over 0.6 s.
--
-- DATA AND RULE ONLY. The intro this applies to is the arrow's (UI/Arrow.lua,
-- Arrow.INTRO_SECONDS), which is drawn by another lane.
--
--   IntroStill.Spec(on) -> { animate, seconds, show, fade }
--       on must be a plain true; anything else is the normal intro.
--   IntroStill.For(k) -> spec   the same, from the setting on kernel k
--
-- MUSE NEED (UI/Arrow.lua, the arrow's intro clock): read
-- ns.IntroStill.For(k) when the intro starts; set introUntil to
-- now + spec.seconds instead of now + Arrow.INTRO_SECONDS, and when
-- spec.animate is false draw nothing that moves (title at full alpha for
-- spec.show seconds, then a fade over spec.fade seconds). Until then the
-- setting is saved and read but the intro looks the same.
--
-- Setting: "splash.short" (bool, account, off), stored at
-- settings.splash.short, where the import from Flow already writes it
-- (Import/FromFlow.lua). The row is in Settings/Rows.lua.
local _, ns = ...

local S = ns.IntroStill or {}
ns.IntroStill = S

S.SETTING = "splash.short"
-- The still intro's two phases, in seconds: Flow's lengths.
S.SHOW, S.FADE = 1.0, 0.6

-- The normal intro's length: the arrow's own, read late so the load order
-- does not matter.
local function fullSeconds()
    local A = ns.Arrow
    if type(A) == "table" and type(A.INTRO_SECONDS) == "number" then return A.INTRO_SECONDS end
    return 3
end

function S.Spec(on)
    if on == true then
        return { animate = false, seconds = S.SHOW + S.FADE, show = S.SHOW, fade = S.FADE }
    end
    local full = fullSeconds()
    return { animate = true, seconds = full, show = full, fade = 0 }
end

-- A missing kernel or a failing read is the normal intro.
function S.For(k)
    local s
    if type(k) == "table" then s = k.settings end
    if type(s) ~= "table" or type(s.get) ~= "function" then return S.Spec(false) end
    local ok, v = pcall(s.get, s, S.SETTING)
    if not ok then return S.Spec(false) end
    return S.Spec(v)
end
