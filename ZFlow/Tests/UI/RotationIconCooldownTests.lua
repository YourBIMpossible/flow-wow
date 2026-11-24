-- G27: the cooldown text on the rotation icon. When the suggested spell
-- still has seconds of cooldown left (client.spellCooldownLeft, lane A's
-- read), the line under the icon says how long, "8s" or "2m"; ready, the
-- global cooldown only, or not known: no text. A look-only suggestion's
-- words (for another player) keep the line. Shows only; nothing is cast.
-- Fake client in a kernel. Not tested in game.
--
-- Red before the code: I.CooldownText and I.Caption do not exist and the
-- icon writes no cooldown in its caption.
local _, ns = ...

local I = ns.RotationIcon
local D = ns.RotationDriver
local tests = {}

local WRATH = 5176
local WRATH_TEX = 136006 -- a test value, not client data
local CLASS = "TESTCLASS"

local function pack()
    return {
        spells = { Wrath = { evidence = "test" } },
        lists = { default = { { spell = "Wrath", target = true, reason = "Wrath" } } },
        keys = { none = { key = "Wrath" } },
    }
end

local function start(before)
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setInRange(WRATH, true)
    c.setSpellTexture(WRATH, WRATH_TEX)
    c.target = function() return { exists = true, hostile = true, dead = false } end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setScreen(1024, 768)
    if before then before(c) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    D.Declare(k, { [CLASS] = pack() })
    I.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    return k, c
end

local function suggest(k, s)
    k.bus:emit(D.EVENT, { suggestion = s, trace = {} })
end

local function caption(c) return c.icons[1] and c.icons[1].captionText end

-- ------------------------------------------------------------------- pure
tests["rotation icon cooldown: the text for the seconds left"] = function(t)
    t.eq(I.CooldownText(nil), nil, "not known")
    t.eq(I.CooldownText("8"), nil, "not a number")
    t.eq(I.CooldownText(0), nil, "ready")
    t.eq(I.CooldownText(-1), nil)
    t.eq(I.CooldownText(0 / 0), nil, "not a number at all")
    t.eq(I.CooldownText(math.huge), nil)
    t.eq(I.CooldownText(1.2), nil, "the global cooldown only: no text")
    t.eq(I.CooldownText(I.MIN_LEFT), nil, "at the floor: no text")
    t.eq(I.CooldownText(7.2), "8s", "rounded up: the spell is not ready at 7")
    t.eq(I.CooldownText(59.5), "60s")
    t.eq(I.CooldownText(60), "60s")
    t.eq(I.CooldownText(61), "2m", "a minute and more in minutes, rounded up")
    t.eq(I.CooldownText(600), "10m")
end

tests["rotation icon cooldown: the look-only words keep the line"] = function(t)
    local look = { suggestion = { spell = "Renew", look = true, member = "Healer" } }
    t.eq(I.Caption(look, 30), "Renew on Healer", "the words, not the cooldown")
    t.eq(I.Caption({ suggestion = { spell = "Wrath" } }, 30), "30s")
    t.eq(I.Caption({ suggestion = { spell = "Wrath" } }, 0), nil)
    t.eq(I.Caption({ suggestion = { spell = "Wrath" } }, nil), nil)
    t.eq(I.Caption(nil, 30), nil, "no view, no line")
end

-- ----------------------------------------------------------------- module
tests["rotation icon cooldown: seconds left on the suggested spell are under the icon"] = function(t)
    local k, c = start(function(cl) cl.setSpellCooldownLeft(WRATH, 7.2) end)
    suggest(k, { spell = "Wrath" })
    t.eq(c.icons[1].shown, true)
    t.eq(caption(c), "8s")
end

tests["rotation icon cooldown: the next view with the spell ready clears the text"] = function(t)
    local k, c = start(function(cl) cl.setSpellCooldownLeft(WRATH, 12) end)
    suggest(k, { spell = "Wrath" })
    t.eq(caption(c), "12s")
    c.setSpellCooldownLeft(WRATH, 0)
    suggest(k, { spell = "Wrath" })
    t.eq(caption(c), nil, "ready: no text")
end

tests["rotation icon cooldown: not known or no read, no text and no problem"] = function(t)
    local k, c = start()
    suggest(k, { spell = "Wrath" })
    t.eq(caption(c), nil, "not known")
    local k2, c2 = start(function(cl) cl.spellCooldownLeft = nil end)
    suggest(k2, { spell = "Wrath" })
    t.eq(c2.icons[1].shown, true, "the icon still shows")
    t.eq(caption(c2), nil)
    local k3, c3 = start(function(cl) cl.spellCooldownLeft = function() error("boom", 0) end end)
    suggest(k3, { spell = "Wrath" })
    t.eq(c3.icons[1].shown, true, "a read that raises costs nothing")
    t.eq(caption(c3), nil)
    t.eq(k3:ModuleState(I.NAME), "started")
end

tests["rotation icon cooldown: the icon hidden clears the text"] = function(t)
    local k, c = start(function(cl) cl.setSpellCooldownLeft(WRATH, 20) end)
    suggest(k, { spell = "Wrath" })
    t.eq(caption(c), "20s")
    suggest(k, nil)
    t.eq(c.icons[1].shown, false)
    t.eq(caption(c), nil)
end

return tests
