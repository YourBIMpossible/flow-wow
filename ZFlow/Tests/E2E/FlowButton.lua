local _, ns = ...
-- Lead section 285 item 2b: the Flow button and the self button, on the
-- whole add-on loaded on a fake client and entered the way the player
-- enters (boot, events, the settings page). Both are secure buttons the
-- player clicks, or binds a key to on the settings page with a button the
-- player presses; the add-on clicks, binds and casts nothing. Set only
-- while the lock is a plain false; a change in a fight waits for its end.
-- Size and place come from the imported layout; a grip beside each
-- button moves it (lead section 305 item 1: no drag on the secure button).
-- N15: seals, shouts and forms stay on the Flow button, never on the self
-- button. Section 236: late data, a reload, a lock read that fails, then
-- recovers. No macro type anywhere. Section 294 item 1: both buttons are
-- on screen at a default profile, out of combat, holding nothing new: no
-- key bound, no type or spell written; with nothing to cast each still
-- shows a plain face and a one-line tooltip saying what is missing.
-- Section 297 item 5: no art path named; the empty face is a plain panel.
--
-- What the fake client cannot express: the click, the key press reaching
-- the button, the drag on screen. Spell ids are made up; not tested in game.
local tests = {}

local FB = ns.FlowButton
local D = ns.RotationDriver
local PRIEST = {
    ["Flash Heal"] = 2061, ["Lesser Heal"] = 2050, ["Renew"] = 139, ["Dispel Magic"] = 527,
    ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, ["Smite"] = 585,
}
local PALADIN = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local AURA = { ["Devotion Aura"] = true }
local READY = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200 }
local FLOW = ns.id.framePrefix .. "FlowButton"
local SELF = ns.id.framePrefix .. "SelfButton"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if type(c.setBindings) == "function" then c.setBindings(opts.binds or {}) end
    local paladin = opts.class == "PALADIN"
    c.setClass(opts.class or "PRIEST"); c.setFaction("Alliance")
    c.setLevel(paladin and 10 or 20)
    c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 768)
    c.setPlayerBuffs(opts.buffs or {})
    for name, id in pairs(paladin and PALADIN or PRIEST) do
        if name ~= opts.late then c.setSpellId(name, id) end
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then
        addon.settings:set(D.SETTING, true)
        c.advance(3, 5)
    end
    return c, addon
end

local function rowOf(c, name)
    for _, h in ipairs(c.clickRows or {}) do
        if h.spec and h.spec.name == name then return h end
    end
    return nil
end

local function held(h)
    if not h then return nil end
    local a = h.slots[1].attrs
    return a.spell or a.item
end

local function noBindsNoMacros(t, c)
    if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, "the add-on bound nothing") end
    t.eq(#c.secureMacros(), 0, "no macro type on any button")
    for _, g in ipairs(c.secureGiven or {}) do
        local name = tostring(g.name)
        if name:find(FLOW, 1, true) or name:find(SELF, 1, true) then
            local attr = tostring(g.attr)
            if attr:find("type", 1, true) and g.value ~= nil then
                t.ok(g.value == "spell" or g.value == "item", "type is spell or item only: " .. tostring(g.value))
            end
        end
    end
end

local function tip(c, name)
    if type(c.hoverTipText) ~= "function" then return nil end
    return c.hoverTipText(name .. "1")
end

local function empty(c, name)
    if type(c.buttonFaces) ~= "table" or type(c.buttonFaces[name .. "1"]) ~= "table" then return nil end
    return c.buttonFaces[name .. "1"].empty
end

local function castGiven(c)
    local n = 0
    for _, g in ipairs(c.secureGiven or {}) do
        local name = tostring(g.name)
        if (name:find(FLOW, 1, true) or name:find(SELF, 1, true)) and g.value ~= nil then
            local attr = tostring(g.attr)
            if attr:find("type", 1, true) or attr:find("spell", 1, true) or attr:find("item", 1, true) then n = n + 1 end
        end
    end
    return n
end

local function reload(c, opts)
    opts = opts or {}
    local binds = {}
    local saved = c.savedBindingMap()
    local keys = {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do binds[#binds + 1] = { key, saved[key] } end
    opts.account = c.saved(ns.id.accountDB)
    opts.char = c.saved(ns.id.charDB)
    opts.binds = binds
    return start(opts)
end

-- The rotation is on by default (lead sections 293 and 294). A profile the
-- player switched off: boot once, switch it off, then start again from what
-- was saved, so nothing from the first boot is counted.
local function startOff(opts)
    local c, addon = start(opts)
    addon.settings:set(D.SETTING, false)
    c.advance(3, 5)
    return reload(c, opts)
end

-- The settings page, as the player uses it.
local function open(c)
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
end
local function pageRow(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end
local function press(c, key, label)
    local r = pageRow(c, key)
    if type(r) ~= "table" then return false end
    for _, b in ipairs(r.actions or {}) do
        if b.label == label and b.enabled == true then
            c.optionsNav("action", b.key)
            return true
        end
    end
    return false
end

-- Flow button ---------------------------------------------------------------

tests["flow button: made and shown at a default boot, its setting on by default"] = function(t)
    t.ok(type(FB) == "table", "the module is there")
    if type(FB) ~= "table" then return end
    do
        -- Default boot: the rotation is on by default, so the button
        -- already holds the planned spell and shows its icon.
        local c0, addon0 = start()
        t.eq(addon0.settings:get(D.SETTING), true, "the rotation is on by default")
        local h0 = rowOf(c0, FLOW)
        t.ok(h0 ~= nil, "default boot: the Flow button was made")
        if h0 then
            t.eq(h0.shown, true, "default boot: on screen")
            t.eq({ h0.slots[1].attrs.type, h0.slots[1].attrs.spell }, { "spell", "Power Word: Fortitude" }, "default boot: the click casts the planned spell")
            t.eq(empty(c0, FLOW), false, "default boot: the face shows the icon")
        end
        noBindsNoMacros(t, c0)
    end
    local c, addon = startOff()
    local row = addon.settings:row(FB.SETTING)
    t.ok(row ~= nil, "a settings row")
    if row then t.eq({ row.scope, row.type, row.default }, { "char", "bool", true }) end
    t.eq(FB.SETTING, "rotation.keyFrame", "the existing one-button setting")
    t.eq(addon.settings:get(FB.SETTING), true, "on by default")
    local h = rowOf(c, FLOW)
    t.ok(h ~= nil, "the Flow button was made at boot")
    if not h then return end
    t.eq(h.spec.count, 1)
    t.eq(h.spec.size, FB.SIZE, "Flow's size")
    t.eq(h.shown, true, "on screen")
    t.eq(h.slots[1].shown, true, "its button is shown")
    t.eq(h.slots[1].attrs.type, nil, "the rotation off: it casts nothing")
    t.eq(h.slots[1].icon, nil, "no art path named")
    t.eq(empty(c, FLOW), true, "the plain empty face")
    local line = tip(c, FLOW)
    t.ok(type(line) == "string" and line:find("rotation is off", 1, true) ~= nil, "the tooltip says what is missing: " .. tostring(line))
    t.eq(h.point, FB.DEFAULT_POINT, "the default place")
    local s = rowOf(c, SELF)
    t.ok(s ~= nil, "the self button was made at boot")
    t.eq(s and s.shown, true, "and is on screen")
    t.eq(empty(c, SELF), true, "the plain empty face")
    local selfLine = tip(c, SELF)
    t.ok(type(selfLine) == "string" and selfLine:find("rotation is off", 1, true) ~= nil, "its tooltip says what is missing: " .. tostring(selfLine))
    t.eq(castGiven(c), 0, "no type, spell or item written while the rotation is off")
    noBindsNoMacros(t, c)
end

tests["flow button: holds the planned spell, its icon that spell's"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    local a = h.slots[1].attrs
    t.eq({ a.type, a.spell }, { "spell", "Power Word: Fortitude" }, "the click casts the planned spell")
    t.eq(h.slots[1].icon, "tex:Power Word: Fortitude")
    t.eq(empty(c, FLOW), false, "the face shows the icon")
    t.eq(tip(c, FLOW), "Flow button. Casts Power Word: Fortitude when you click it. " .. FB.SizeLine(1),
        "F-34: ends with its size")
    t.eq(h.shown, true)
    noBindsNoMacros(t, c)
end

tests["flow button: a change in a fight waits, set after it ends"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    c.setCombat(true); c.advance(1, 5)
    local given = #h.given
    c.setPlayerBuffs({ ["Power Word: Fortitude"] = 1800 }); c.advance(5, 10)
    t.eq(#h.given, given, "nothing written to the button in the fight")
    t.eq(held(h), "Power Word: Fortitude", "it keeps what it had")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(3, 5)
    t.eq(held(h), "Inner Fire", "set after the fight")
    t.eq(h.slots[1].icon, "tex:Inner Fire")
    noBindsNoMacros(t, c)
end

tests["flow button: the grip moves it out of a fight only, the place kept"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    local to = { "CENTER", "CENTER", 100, -100 }
    t.eq(h.point, FB.DEFAULT_POINT)
    c.setCombat(true); c.advance(1, 5)
    t.eq(c.dragHandle(FLOW, to), false, "no move in a fight")
    c.setCombat(false); c.advance(1, 5)
    t.eq(c.dragHandle(FLOW, to), true, "the grip, out of a fight: moved")
    t.eq(h.point, to, "placed there")
    t.eq(addon.settings:get(FB.LAYOUT), to, "kept in the add-on's layout")
end

-- F2 (lead section 447 item 3): Ctrl + mouse wheel over the Flow button
-- resizes it, half to double size, and the size is saved (Flow:
-- Modules/MoveHandle.lua at b657e6e5, Cast.lua:457-461). The self button is
-- not wired to this, same as Flow had it. Not tested in game: the fake
-- client's c.wheelHandle stands in for the real OnMouseWheel + Ctrl check.
tests["flow button: Ctrl + wheel resizes it out of a fight only, half to double, saved"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    t.eq(addon.settings:get(FB.SCALE), 1, "no saved size yet: the default, full size")

    c.setCombat(true); c.advance(1, 5)
    t.eq(c.wheelHandle(FLOW, 1), false, "no resize in a fight")
    t.eq(h.size, FB.SIZE, "nothing applied")
    c.setCombat(false); c.advance(1, 5)

    t.eq(c.wheelHandle(FLOW, 1, false), false, "no Ctrl: refused")
    t.eq(h.size, FB.SIZE, "nothing applied without Ctrl")

    t.eq(c.wheelHandle(FLOW, 1), true, "Ctrl + wheel up, out of a fight: resized")
    t.eq(h.size, math.floor(FB.SIZE * 1.1 + 0.5), "a tenth bigger")
    t.eq(addon.settings:get(FB.SCALE), 1.1, "kept in the add-on's settings")

    for _ = 1, 12 do c.wheelHandle(FLOW, 1) end
    t.eq(h.size, FB.SIZE * 2, "wheeling up past double: clamped to double size")
    t.eq(addon.settings:get(FB.SCALE), 2, "the clamp is what was saved")

    for _ = 1, 20 do c.wheelHandle(FLOW, -1) end
    t.eq(h.size, FB.SIZE / 2, "wheeling down past half: clamped to half size")
    t.eq(addon.settings:get(FB.SCALE), 0.5, "the clamp is what was saved")

    -- The self button accepts the same gesture (the client cannot tell the
    -- two apart) but is not wired to a size setting, same as Flow: nothing
    -- happens to it.
    local hs = rowOf(c, SELF)
    local before = hs and hs.size
    c.wheelHandle(SELF, 1)
    if hs then t.eq(hs.size, before, "the self button is not resized") end
    noBindsNoMacros(t, c)
end

-- Lazy F2 (lead section 551): one way to size. The wheel resizes the row
-- to the rounded pixel size; nothing scales it on top, so the size on
-- screen is 52 * scale once, never 52 * scale * scale.
tests["flow button: the wheel sets the size on screen once, no scale on top"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true, account = { layout = { rotation = { scale = 1.5 } } } })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    t.eq(h.size, math.floor(FB.SIZE * 1.5 + 0.5), "made at the saved size")
    t.eq(c.wheelHandle(FLOW, 1), true)
    t.eq(addon.settings:get(FB.SCALE), 1.6)
    t.eq(h.size, math.floor(FB.SIZE * 1.6 + 0.5), "the row is the new size on screen")
    t.eq(h.scale, nil, "no scale on top of the size")
end

tests["flow button: a reload keeps the size the player chose"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    t.eq(c.wheelHandle(FLOW, 1), true)
    t.eq(addon.settings:get(FB.SCALE), 1.1)

    local c2, addon2 = start({ on = true, account = c.saved(ns.id.accountDB) })
    local h2 = rowOf(c2, FLOW)
    t.ok(h2 ~= nil, "the Flow button made again after a reload")
    t.eq(addon2.settings:get(FB.SCALE), 1.1, "the chosen size carried over")
    if h2 then t.eq(h2.spec.size, math.floor(FB.SIZE * 1.1 + 0.5), "made at the saved size") end
end

-- Lead section 305 item 1: a drag never casts. The buttons act on the
-- press down (Core/Client.lua clickRow registers AnyUp and AnyDown), so a
-- drag that starts on the secure button would also press it. Each button
-- moves only by the grip beside it (client.moveHandle, as ClickSlots S29),
-- and nothing drags the secure button itself. No modifier attribute is
-- written either: a Ctrl click is a plain click.
tests["flow and self buttons: moved by a grip only, never a drag on the secure button"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    for _, name in ipairs({ FLOW, SELF }) do
        local h = rowOf(c, name)
        t.ok(h ~= nil, name .. " made")
        if h then
            t.eq(h.slots[1].attrs.type, "spell", name .. ": a plain click casts")
            t.eq(h.slots[1].attrs["ctrl-type1"], nil, name .. ": no modifier attribute")
        end
        t.eq(c.ctrlDrags[name], nil, name .. ": no drag on the secure button")
        t.ok(c.moveHandles[name] ~= nil, name .. ": a grip moves it")
    end
    noBindsNoMacros(t, c)
    local d = startOff()
    t.eq(castGiven(d), 0, "a profile with the rotation off writes no cast")
    t.ok(d.moveHandles[FLOW] ~= nil, "the rotation off: the grip is there too")
end

tests["flow button: a reload keeps its place and the key the player bound"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    if type(c.pressKey) ~= "function" then t.ok(false, "fake client"); return end
    local to = { "CENTER", "CENTER", 120, -80 }
    t.eq(c.dragHandle(FLOW, to), true)
    open(c)
    t.ok(pageRow(c, "keys.flow") ~= nil, "a key row for the Flow button")
    t.eq(c.bindingCalls(), {}, "nothing bound before the player presses")
    t.eq(press(c, "keys.flow", "Set key"), true, "the player presses Set key")
    t.eq(c.pressKey("F"), true, "and a key")
    local action = "CLICK " .. FLOW .. "1:LeftButton"
    t.eq(c.savedBindingMap()["F"], action, "the key clicks the Flow button")
    local c2 = reload(c, { on = true })
    local h = rowOf(c2, FLOW)
    if not h then t.ok(false, "no Flow button after the reload"); return end
    t.eq(h.point, to, "the place read back")
    t.eq(c2.bindingMap()["F"], action, "the key read back")
    t.eq(held(h), "Power Word: Fortitude", "set again after the reload")
    t.eq(c2.bindingCalls(), {}, "the reload bound nothing")
end

tests["flow button: switched off, it is cleared and hidden"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    addon.settings:set(FB.SETTING, false); c.advance(3, 5)
    t.eq(h.shown, false, "hidden")
    t.eq(h.slots[1].attrs.spell, nil, "holds nothing")
    t.eq(h.slots[1].attrs.type, nil)
end

tests["flow button: size and place from the imported layout"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local frame = { "CENTER", "BOTTOMLEFT", 500, 300 }
    local c = start({ account = { layout = { rotation = { frame = frame, scale = 1.5 } } } })
    local h = rowOf(c, FLOW)
    if not h then t.ok(false, "no Flow button"); return end
    t.eq(h.spec.size, 78, "52 at Flow's 1.5")
    t.eq(h.point, frame, "where Flow had it")
end

-- Self button ---------------------------------------------------------------

tests["self button: shown by default holding a missing buff on you"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    local row = addon.settings:row(FB.SELF_SETTING)
    t.ok(row ~= nil, "a settings row")
    if row then t.eq({ row.scope, row.type, row.default }, { "account", "bool", true }) end
    t.eq(FB.SELF_SETTING, "buffButton.enabled", "where the Flow import keeps it")
    local h = rowOf(c, SELF)
    t.ok(h ~= nil, "the self button was made")
    if not h then return end
    local a = h.slots[1].attrs
    t.eq({ a.type, a.spell, a.unit }, { "spell", "Inner Fire", "player" },
        "the buff, on you: the next one, the Flow button shows Fortitude")
    t.eq(h.shown, true, "shown: it has something")
    t.eq(h.slots[1].icon, "tex:Inner Fire")
    t.eq(tip(c, SELF), "Buff button, for your self buffs. Casts Inner Fire on you when you click it.")
    noBindsNoMacros(t, c)
end

tests["self button: nothing to cast, it still shows, its tooltip says why"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true, buffs = { ["Power Word: Fortitude"] = 1800, ["Inner Fire"] = 600 } })
    local h = rowOf(c, SELF)
    t.ok(h ~= nil, "made")
    if not h then return end
    t.eq(h.shown, true, "every buff up: still on screen")
    t.eq(h.slots[1].attrs.spell, nil, "holding nothing")
    t.eq(empty(c, SELF), true, "the plain empty face")
    local line = tip(c, SELF)
    t.ok(type(line) == "string" and line:find("every self buff", 1, true) ~= nil, "says what is missing: " .. tostring(line))
end

-- Lead section 305 item 2: the two buttons never show the same buff. The
-- self button passes by what the Flow button holds; the Flow button's
-- suggestion stays as the rotation made it.
tests["self button: never the buff the Flow button shows"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    t.eq(held(rowOf(c, FLOW)), "Power Word: Fortitude", "the Flow button keeps the rotation's suggestion")
    t.eq(held(rowOf(c, SELF)), "Inner Fire", "the self button the next missing buff")
    c.setPlayerBuffs({ ["Inner Fire"] = 600 }); c.advance(3, 5)
    t.eq(held(rowOf(c, FLOW)), "Power Word: Fortitude")
    t.eq(held(rowOf(c, SELF)), nil, "only the Flow button's buff missing: the self button holds nothing")
    t.ok((tip(c, SELF) or ""):find("every self buff you know is up or on the Flow button", 1, true) ~= nil, "its tooltip says why: " .. tostring(tip(c, SELF)))
    addon.settings:set(FB.SETTING, false); c.advance(3, 5)
    t.eq(held(rowOf(c, SELF)), "Power Word: Fortitude", "the Flow button off: the self button takes it")
    noBindsNoMacros(t, c)
end

tests["self button: docked under the Flow button when set to dock"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true, account = { settings = { buffButton = { dock = true } } } })
    local h = rowOf(c, SELF)
    if not h then t.ok(false, "no self button"); return end
    local p = FB.DEFAULT_POINT
    t.eq(h.point, { p[1], p[2], p[3], p[4] - 26 - FB.DOCK_GAP - 26 }, "17 under Flow's bottom edge")
    t.eq(h.spec.size, FB.SIZE)
end

tests["self button: undocked and sized from the imported layout"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local frame = { "CENTER", "BOTTOMLEFT", 640, 220 }
    local c = start({ on = true, account = {
        layout = { buffButton = { frame = frame, scale = 1.1 } },
        settings = { buffButton = { dock = false } } } })
    local h = rowOf(c, SELF)
    if not h then t.ok(false, "no self button"); return end
    t.eq(h.point, frame, "where Flow had it")
    t.eq(h.spec.size, 57, "52 at 1.1, rounded")
end

tests["self button: N15 the seal stays on the Flow button"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true, class = "PALADIN", buffs = READY })
    local flow, self = rowOf(c, FLOW), rowOf(c, SELF)
    t.eq(held(flow), "Seal of Righteousness", "the seal is on the Flow button")
    t.ok(self == nil or held(self) ~= "Seal of Righteousness", "never on the self button")
    t.eq(self and self.shown, true, "nothing else to cast: still shown")
    t.eq(self and self.slots[1].attrs.spell, nil, "holding nothing")
    c.setPlayerBuffs(AURA); c.advance(3, 5)
    self = rowOf(c, SELF)
    -- Lead section 305 item 2: the Flow button now holds the blessing, so
    -- the self button does not show it too.
    t.eq(held(rowOf(c, FLOW)), "Blessing of Might", "the Flow button holds the blessing")
    t.eq(held(self), nil, "never the same buff on the self button")
    t.eq(self and self.shown, true)
    for _, name in ipairs({ "Seal of Light", "Battle Shout", "Lightning Shield", "Hunter" .. string.char(39) .. "s Mark",
                            "Bear Form", "Dire Bear Form", "Cat Form", "Moonkin Form" }) do
        t.eq(FB.OnAction(name), true, name .. " stays on the Flow button")
    end
    for _, name in ipairs({ "Blessing of Might", "Devotion Aura", "Mark of the Wild", "Travel Form", "Aspect of the Hawk" }) do
        t.eq(FB.OnAction(name), false, name .. " goes on the self button")
    end
    noBindsNoMacros(t, c)
end

tests["self button: a change in a fight waits, set after it ends"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    local h = rowOf(c, SELF)
    if not h then t.ok(false, "no self button"); return end
    c.setCombat(true); c.advance(1, 5)
    local given = #h.given
    c.setPlayerBuffs({ ["Inner Fire"] = 600 }); c.advance(5, 10)
    t.eq(#h.given, given, "nothing written in the fight")
    t.eq(held(h), "Inner Fire", "it keeps what it had")
    c.setCombat(false); c.fire("PLAYER_REGEN_ENABLED"); c.advance(3, 5)
    t.eq(held(h), nil, "set after the fight: Fortitude is on the Flow button, nothing else is missing")
    t.eq(h.shown, true, "still shown")
    noBindsNoMacros(t, c)
end

tests["self button: a reload keeps its place and the key the player bound"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true })
    if type(c.pressKey) ~= "function" then t.ok(false, "fake client"); return end
    local to = { "CENTER", "CENTER", -200, -50 }
    t.eq(c.dragHandle(SELF, to), true, "the grip moves it")
    open(c)
    t.eq(press(c, "keys.self", "Set key"), true, "the player presses Set key")
    t.eq(c.pressKey("G"), true)
    local action = "CLICK " .. SELF .. "1:LeftButton"
    t.eq(c.savedBindingMap()["G"], action)
    local c2 = reload(c, { on = true })
    local h = rowOf(c2, SELF)
    if not h then t.ok(false, "no self button after the reload"); return end
    t.eq(h.point, to, "the place read back")
    t.eq(c2.bindingMap()["G"], action, "the key read back")
    t.eq(held(h), "Inner Fire")
    t.eq(c2.bindingCalls(), {}, "the reload bound nothing")
end

-- Lead section 305 item 3: the setting's help names the visible Flow
-- button, not a hidden one.
tests["flow button: the setting's help names the Flow button, not a hidden button"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local _, addon = start()
    local row = addon.settings:row(FB.SETTING)
    t.ok(row ~= nil, "a settings row")
    local help = ""
    if type(row) == "table" and type(row.help) == "string" then help = row.help end
    t.eq(help:find("hidden", 1, true), nil, "no hidden button: " .. help)
    t.ok(help:find("Flow button", 1, true) ~= nil, "names the Flow button: " .. help)
    t.ok(help:find("presses nothing for you", 1, true) ~= nil, "still presses nothing: " .. help)
end

-- Lead section 305 item 4: the imported legacy key, key2 and always are
-- kept but not applied: nothing is bound at load, and the self button is
-- shown either way.
tests["self button: imported legacy key, key2 and always are not applied"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    for _, always in ipairs({ false, true }) do
        local c = start({ account = { settings = { buffButton = { key = "F", key2 = "SHIFT-G", always = always } } } })
        local tag = "always " .. tostring(always) .. ": "
        if type(c.bindingCalls) == "function" then t.eq(c.bindingCalls(), {}, tag .. "nothing bound at load") end
        if type(c.bindingMap) == "function" then
            t.eq(c.bindingMap()["F"], nil, tag .. "key not bound")
            t.eq(c.bindingMap()["SHIFT-G"], nil, tag .. "key2 not bound")
        end
        local h = rowOf(c, SELF)
        t.eq(h and h.shown, true, tag .. "the self button is shown")
    end
end

tests["self button: a saved choice is kept, only the unset default is on"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ char = { settings = { rotation = { keyFrame = false } } },
                             account = { settings = { buffButton = { enabled = false } } } })
    t.eq(addon.settings:get(FB.SETTING), false, "the saved Flow choice kept")
    t.eq(addon.settings:get(FB.SELF_SETTING), false, "the saved self choice kept")
    t.eq(rowOf(c, FLOW), nil, "not made")
    t.eq(rowOf(c, SELF), nil, "not made")
end

tests["self button: switched off, it is cleared and hidden"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true })
    local h = rowOf(c, SELF)
    if not h then t.ok(false, "no self button"); return end
    addon.settings:set(FB.SELF_SETTING, false); c.advance(3, 5)
    t.eq(h.shown, false, "hidden")
    t.eq(h.slots[1].attrs.spell, nil, "holds nothing")
end

tests["flow button: switched off, its key row cannot be set"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ char = { settings = { rotation = { keyFrame = false } } } })
    open(c)
    t.ok(pageRow(c, "keys.flow") ~= nil, "the key row is drawn")
    t.eq(press(c, "keys.flow", "Set key"), false, "greyed: no key for a button not made")
    t.eq(c.bindingCalls(), {})
end

-- Section 236 scenarios ------------------------------------------------------

tests["flow and self buttons: late spell data fills them once it comes"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ on = true, late = "Power Word: Fortitude" })
    t.ok(held(rowOf(c, FLOW)) ~= "Power Word: Fortitude", "no id yet: not planned")
    c.setSpellId("Power Word: Fortitude", PRIEST["Power Word: Fortitude"]); c.advance(3, 5)
    t.eq(held(rowOf(c, FLOW)), "Power Word: Fortitude", "the Flow button once the id comes")
    t.eq(held(rowOf(c, SELF)), "Inner Fire", "the self button the next one, not the same")
end

tests["flow and self buttons: a lock read that fails, then recovers"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c, addon = start({ on = true, char = { settings = { rotation = { keyFrame = false } } },
                             account = { settings = { buffButton = { enabled = false } } } })
    t.eq(rowOf(c, FLOW), nil, "off: not made")
    local real = c.combatLockdown
    local failing = true
    c.combatLockdown = function()
        if failing then error("lock read failed (test)") end
        return real()
    end
    addon.settings:set(FB.SETTING, true)
    addon.settings:set(FB.SELF_SETTING, true)
    t.eq(pcall(c.advance, 3, 5), true, "no error escapes")
    t.eq(rowOf(c, FLOW), nil, "not made while the lock cannot be read")
    failing = false
    c.advance(3, 5)
    local h = rowOf(c, FLOW)
    t.ok(h ~= nil, "made once the lock reads a plain false")
    t.eq(held(h), "Power Word: Fortitude")
    t.eq(held(rowOf(c, SELF)), "Inner Fire")
end

tests["flow and self buttons: the lock not known waits, then sets"] = function(t)
    if type(FB) ~= "table" then t.ok(false, "no module"); return end
    local c = start({ before = function(cl) cl.setLockdown(nil) end })
    t.eq(rowOf(c, FLOW), nil, "not made while the lock is not known")
    c.setLockdown(false); c.advance(3, 5)
    local h = rowOf(c, FLOW)
    t.ok(h ~= nil, "made once it is a plain false")
    t.eq(h and h.shown, true)
end

-- Parity row D-11 (lead section 712), as Flow's Modules/Rotation/
-- BuffButton.lua (:580-607 scale, ns.ClampScale in MoveHandle.lua:10-19):
-- the self button's size, one step of a tenth a notch, kept between 0.5
-- and 2 to the nearest twentieth, saved where the Flow import keeps it
-- (layout.buffButton.scale, or dockScale while docked). Out of a fight
-- only. The wheel and the drawing are the drawing lane's. Fails before:
-- the size could only come from the import.
tests["self button size: a step, kept in range, saved docked or apart"] = function(t)
    local FB = ns.FlowButton
    t.eq(FB.ScaleStep(1, 1), 1.1)
    t.eq(FB.ScaleStep(1, -1), 0.9)
    t.eq(FB.ScaleStep(2, 1), 2, "no more than 2")
    t.eq(FB.ScaleStep(0.5, -1), 0.5, "no less than 0.5")
    t.eq(FB.ScaleStep(nil, 1), 1.1, "no size yet: from 1")
    t.eq(FB.ScaleStep(1.03, 0), 1.05, "to the nearest twentieth")
end

tests["self button size: the resize is saved and refused in a fight"] = function(t)
    local c, addon = start()
    local api = addon.flowButton
    t.eq(type(api.resizeSelf), "function")
    if type(api.resizeSelf) ~= "function" then return end
    t.eq(api.resizeSelf(1), true, "docked as made")
    local layout = addon.store:get("account", "layout")
    t.eq(layout and layout.buffButton and layout.buffButton.dockScale, 1.1, "the docked size")
    addon.settings:set(ns.FlowButton.DOCK, false)
    c.advance(1, 2)
    t.eq(api.resizeSelf(-1), true, "apart")
    layout = addon.store:get("account", "layout")
    t.eq(layout.buffButton.scale, 0.9, "its own size")
    c.setLockdown(true)
    t.eq(api.resizeSelf(1), false, "in a fight: refused")
    t.eq(addon.store:get("account", "layout").buffButton.scale, 0.9, "unchanged")
end

return tests
