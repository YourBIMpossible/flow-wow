local _, ns = ...

-- F-new-3: a short, still login intro for players who want less motion.
-- Flow (commit 5ae28de5, Modules/Splash.lua:16-22) keeps splash.short, off
-- unless ticked; on, nothing turns and the intro lasts 1.0 s shown plus a
-- 0.6 s fade instead of the full one. Here: the row, its default and group,
-- the pure rule, and what the arrow's intro is handed for each value.
-- Fake client; not tested in game.
--
-- Red before the code: ns.IntroStill does not exist and no row is called
-- splash.short.

local tests = {}

local function boot(saved)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, saved or {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return addon, c
end

tests["intro still: the row exists, off by default, with the windows"] = function(t)
    local addon = boot()
    local S = addon.IntroStill
    t.ok(type(S) == "table", "the rule is loaded")
    if type(S) ~= "table" then return end
    t.eq(S.SETTING, "splash.short", "the key, as Flow's import writes it")
    local row = addon.settings:row(S.SETTING)
    t.ok(row ~= nil, "the row is declared")
    if row == nil then return end
    t.eq(row.type, "bool", "a switch")
    t.eq(row.default, false, "off unless the player ticks it, as in Flow")
    t.eq(row.group, "general.windows", "with what is on the screen")
    t.ok(type(row.label) == "string" and row.label ~= "", "a label")
    t.ok(type(row.help) == "string" and row.help ~= "", "a help line")
    t.eq(addon.settings:get(S.SETTING), false, "a fresh install reads off")
end

tests["intro still: the pure rule for off and on"] = function(t)
    local S = ns.IntroStill
    t.ok(type(S) == "table", "the rule is loaded")
    if type(S) ~= "table" then return end
    local off = S.Spec(false)
    t.eq(off.animate, true, "off: the intro moves as before")
    t.eq(off.seconds, ns.Arrow.INTRO_SECONDS, "off: the full length")
    local on = S.Spec(true)
    t.eq(on.animate, false, "on: nothing turns")
    t.eq(on.show, 1.0, "on: shown for a second")
    t.ok(math.abs(on.fade - 0.6) < 1e-9, "on: then fades")
    t.ok(math.abs(on.seconds - 1.6) < 1e-9, "on: 1.6 seconds in all")
    t.ok(on.seconds < off.seconds, "on is shorter")
    -- Anything but a plain true is off, so a broken saved value never
    -- changes the intro.
    t.eq(S.Spec(nil).animate, true, "nil: off")
    t.eq(S.Spec("yes").animate, true, "a string: off")
end

tests["intro still: what the intro is handed with each value"] = function(t)
    local addon = boot()
    local S = addon.IntroStill
    if type(S) ~= "table" then t.ok(false, "the rule is loaded"); return end
    local spec = S.For(addon)
    t.eq(spec.animate, true, "default: the moving intro")
    t.eq(spec.seconds, addon.Arrow.INTRO_SECONDS, "default: full length")
    local ok = addon.settings:set(S.SETTING, true)
    t.ok(ok, "the player can tick it")
    spec = S.For(addon)
    t.eq(spec.animate, false, "ticked: still")
    t.ok(math.abs(spec.seconds - 1.6) < 1e-9, "ticked: short")
    addon.settings:set(S.SETTING, false)
    t.eq(S.For(addon).animate, true, "unticked again: moving")
    -- No settings at all: the default.
    t.eq(S.For(nil).animate, true, "no kernel: off")
end

tests["intro still: a value imported from Flow is read"] = function(t)
    local addon = boot({ settings = { splash = { short = true } } })
    local S = addon.IntroStill
    if type(S) ~= "table" then t.ok(false, "the rule is loaded"); return end
    t.eq(addon.settings:get(S.SETTING), true, "saved at settings.splash.short")
    t.eq(S.For(addon).animate, false, "and the intro is still")
end

return tests
