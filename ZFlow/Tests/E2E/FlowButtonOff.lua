local _, ns = ...
-- The Flow button with the rotation off (lead section 533, gap 5; Muse's
-- agreed spec), on the whole add-on loaded on a fake client: it shows the
-- word Flow, never a question mark and never the last spell's picture, and
-- its tooltip is one exact line naming the Settings row to turn on. The
-- button is a secure button: its face changes out of a fight only. Section
-- 236: a reload; the rotation switched on later. Spell ids are made up.
-- What the fake client cannot express: the face as drawn. Not tested in
-- game.
local tests = {}

local FB = ns.FlowButton
local D = ns.RotationDriver
local PRIEST = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Smite"] = 585,
}
local FLOW = ns.id.framePrefix .. "FlowButton"
local OFF_TIP = "Rotation off \226\128\148 turn on 'Suggest the next spell' to fill this button."

-- opts: account, char (saved ahead)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 768)
    c.setPlayerBuffs({})
    for name, id in pairs(PRIEST) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function face(c)
    return type(c.buttonFaces) == "table" and c.buttonFaces[FLOW .. "1"] or {}
end

local function tip(c)
    return c.hoverTipText(FLOW .. "1")
end

-- The face says the word: the plain face, its label Flow, drawn as the word
-- (the fake keeps "word" for the plain face with no question mark).
local function saysFlow(c)
    local f = face(c)
    return f.empty == true and f.label == "Flow" and f.dimmed == "word"
end

local function off(c, addon)
    addon.settings:set(D.SETTING, false)
    c.advance(3, 5)
end

-- Red on 799a956f: the tooltip is the older sentence.
tests["flow button off: the tooltip is the one exact line, naming the Settings row as it reads"] = function(t)
    local c, addon, base = start()
    off(c, addon)
    t.eq(tip(c), OFF_TIP)
    local row = addon.settings:row(D.SETTING)
    t.ok(row ~= nil and type(row.label) == "string", "the rotation has a Settings row")
    t.eq(row and row.label, "Suggest the next spell", "its label, as it reads on the page")
    t.ok(row ~= nil and OFF_TIP:find("'" .. row.label .. "'", 1, true) ~= nil, "the tooltip quotes that label")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 799a956f: the button keeps the last spell's picture, dimmed.
tests["flow button off: it shows the word Flow, not the last spell's picture, and never a question mark"] = function(t)
    local c, addon, base = start()
    t.eq(face(c).empty, false, "the rotation on: the planned spell's picture")
    off(c, addon)
    t.ok(saysFlow(c), "switched off: the word Flow (empty " .. tostring(face(c).empty) .. ", dimmed "
        .. tostring(face(c).dimmed) .. ")")
    t.ok(face(c).dimmed ~= nil, "never the bare plain face, which draws a question mark")
    t.ok(face(c).dimmed ~= "picture", "never the last spell's picture")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- The button is a secure button. Red on 799a956f for the last check: after
-- the fight the button shows the last spell's picture, not the word.
tests["flow button off: switched off in a fight, the face changes only after the fight"] = function(t)
    local c, addon, base = start()
    c.setCombat(true); c.advance(1, 5)
    local before = { face(c).empty, face(c).dimmed }
    off(c, addon)
    t.eq({ face(c).empty, face(c).dimmed }, before, "in the fight the face is as it was")
    t.ok(not saysFlow(c), "not the word yet")
    t.ok(tip(c) ~= OFF_TIP, "and the tooltip still says what the click casts: " .. tostring(tip(c)))
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(3, 5)
    t.ok(saysFlow(c), "after the fight: the word Flow")
    t.eq(tip(c), OFF_TIP)
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a reload, then data arriving late (the rotation switched on).
tests["flow button off: a reload with the rotation off shows the word; switched on, the button fills"] = function(t)
    local c, addon = start()
    off(c, addon)
    local c2, addon2, base2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(D.SETTING), false, "off is kept over the reload")
    t.ok(saysFlow(c2), "the word Flow from the start")
    t.eq(tip(c2), OFF_TIP)
    t.eq(addon2.problems:count(), base2, "no new problem while off")
    addon2.settings:set(D.SETTING, true)
    c2.advance(3, 5)
    -- Switched on, modules the reload started off report what the fake
    -- client lacks (the icon glow); count from here.
    local on2 = addon2.problems:count()
    t.eq(face(c2).empty, false, "switched on: the planned spell's picture")
    t.eq(tip(c2), "Flow button. Casts Power Word: Fortitude when you click it.")
    off(c2, addon2)
    t.ok(saysFlow(c2), "and off again: the word")
    t.eq(addon2.problems:count(), on2, "no new problem")
end

tests["flow button off: the tooltip line, pure"] = function(t)
    t.eq(FB.OFF_TIP, OFF_TIP)
    t.eq(FB.Tip("flow", FB.OFF_TIP, nil), OFF_TIP, "exactly the line, nothing before it")
    t.eq(FB.Tip("flow", "Nothing to cast now.", nil), "Flow button. Nothing to cast now.", "any other reason is as before")
    t.eq(FB.Tip("flow", FB.OFF_TIP, { spell = "Smite" }), "Flow button. Casts Smite when you click it.",
        "holding a spell it says what the click casts")
end

return tests
