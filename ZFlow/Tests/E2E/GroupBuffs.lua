local _, ns = ...
-- P-PARTY (lead section 233): the whole add-on on a fake client, a caster
-- druid with her own buffs up and no enemy targeted, out of a fight, in a
-- party. A member missing Mark of the Wild, or carrying a poison she can
-- remove, is named on the rotation icon's caption with the spell; the diag
-- word names the party unit, never the member. Look only: the key's
-- attributes are exactly what they are with no suggestion, so nothing is
-- ever cast on the member. Made-up names and spell ids. Not tested in game.
local tests = {}

local D = ns.RotationDriver
local MOTW, THORNS, ABOLISH = "Mark of the Wild", "Thorns", "Abolish Poison"
local IDS = {
    [MOTW] = 1126, [THORNS] = 467, ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603,
    ["Remove Curse"] = 2782, [ABOLISH] = 2893, ["Cure Poison"] = 8946,
}
local BUFFED = { [MOTW] = true, [THORNS] = true }
local NAME = "Bramblewick"   -- made up
local MEMBER = { unit = "party1", name = NAME, class = "WARRIOR", role = "NONE", power = 1, dead = false, connected = true }

-- opts.member: fields over MEMBER ("nil" leaves one out); opts.buffs: the
-- member's buff rows (nil: not read); opts.reach: false or "unread" for
-- every spell; opts.debuffs: the member's debuff types; opts.party =
-- "unread": the group is not read yet; opts.account, opts.char: the saved
-- data a reload starts from.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("DRUID"); c.setFaction("Alliance"); c.setLevel(30); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local m = {}
    for k, v in pairs(MEMBER) do m[k] = v end
    for k, v in pairs(opts.member or {}) do
        if v == "nil" then m[k] = nil else m[k] = v end
    end
    if opts.party ~= "unread" then c.setParty({ m }) end
    for _, id in pairs(IDS) do
        if opts.reach == false then c.setReach("party1", id, false)
        elseif opts.reach ~= "unread" then c.setReach("party1", id, true) end
    end
    if opts.buffs ~= "unread" then c.setUnitBuffs("party1", opts.buffs or { { name = THORNS, left = 500 } }) end
    if opts.debuffs then c.setUnitDebuffs("party1", opts.debuffs) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    addon.settings:set(D.SETTING, true)
    c.setFormName(nil, true); c.setPlayerBuffs(BUFFED); c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(2, 10)
    return c, addon, icon
end

local function view(addon)
    local use = addon.use(D.NAME)
    return type(use) == "table" and use.View() or nil
end

local function picked(addon)
    local v = view(addon)
    local s = type(v) == "table" and v.suggestion or nil
    return type(s) == "table" and s or nil
end

local function member(over)
    local m = {}
    for k, v in pairs(MEMBER) do m[k] = v end
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

-- How many of the driver's ticks failed.
local function errors(addon) return addon.use(D.NAME).Errors() end

local function said(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("rotation:", 1, true) then out[#out + 1] = line end
    end
    return table.concat(out, " / ")
end

-- Does any string inside v hold `text`?
local function holds(v, text, depth)
    depth = depth or 0
    if depth > 30 then return false end
    if type(v) == "string" then return v:find(text, 1, true) ~= nil end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if holds(key, text, depth + 1) or holds(value, text, depth + 1) then return true end
    end
    return false
end

tests["group e2e: a member missing Mark of the Wild: named on the caption, the key unchanged"] = function(t)
    local _, addon, icon = start()
    local s = picked(addon)
    t.ok(s ~= nil, "a suggestion")
    if not s then return end
    t.eq({ s.step, s.spell, s.unit, s.member, s.look }, { "group", MOTW, "party1", NAME, true })
    t.ok(icon ~= nil and icon.shown, "the icon is up")
    t.eq(icon and icon.texture, "tex:" .. MOTW, "the spell's picture")
    t.eq(icon and icon.captionText, MOTW .. " on " .. NAME, "the caption names the member, live")
    -- Look only: the key holds what it holds with no suggestion at all.
    local v = view(addon)
    local plan = addon.KeyPlan(addon.Packs.DRUID, nil)
    t.eq(v.attrs, addon.cast.Attributes(nil, plan, nil, v.lockdown, nil), "the key's attributes are the no-suggestion ones")
    t.eq(v.attrs.source, "plan", "the key's spell comes from the plan")
    for _, row in ipairs(v.attrs.button or {}) do
        t.ok(row.value ~= MOTW, "Mark of the Wild is on no attribute: " .. tostring(row.attr))
        t.ok(row.value ~= "party1", "the member is on no attribute: " .. tostring(row.attr))
    end
end

tests["group e2e: the diag word names the unit and never the member; nothing saved holds the name"] = function(t)
    local c = start()
    local line = said(c)
    t.ok(line:find("suggesting " .. MOTW .. " for party1 (group; look only, nothing cast)", 1, true) ~= nil,
        "the diag line: " .. line)
    for _, printed in ipairs(c.printed) do
        t.ok(not tostring(printed):find(NAME, 1, true), "no printed line holds the name")
    end
    t.ok(not holds(c.saved(ns.id.accountDB), NAME), "the account's saved data holds no name")
    t.ok(not holds(c.saved(ns.id.charDB), NAME), "the character's saved data holds no name")
end

tests["group e2e: everyone covered: nothing for the group"] = function(t)
    local _, addon, icon = start({ buffs = { { name = "Gift of the Wild", left = 3000 }, { name = THORNS, left = 500 } } })
    t.eq(picked(addon), nil, "Gift of the Wild counts; Thorns up")
    t.ok(icon ~= nil and not icon.shown, "the icon is down")
    t.eq(icon and icon.captionText, nil, "no caption")
end

tests["group e2e: dead, offline, out of reach, or reach not read: skipped"] = function(t)
    for _, case in ipairs({
        { "dead", { member = { dead = true } } },
        { "dead not read", { member = { dead = "nil" } } },
        { "offline", { member = { connected = false } } },
        { "out of reach", { reach = false } },
        { "reach not read", { reach = "unread" } },
        { "buffs not read", { buffs = "unread" } },
    }) do
        local _, addon = start(case[2])
        t.eq(picked(addon), nil, case[1])
    end
end

tests["group e2e: in a fight: nothing; out again: back"] = function(t)
    local c, addon = start()
    t.ok(picked(addon) ~= nil, "out of a fight: suggested, so this test can fail")
    c.setCombat(true); c.advance(2, 10)
    local s = picked(addon)
    t.ok(s == nil or s.step ~= "group", "in a fight: nothing for the group")
    c.setCombat(false); c.advance(2, 10)
    s = picked(addon)
    t.eq(s and s.step, "group", "out again")
end

tests["group e2e: the setting switches it off and on"] = function(t)
    local c, addon = start()
    t.ok(picked(addon) ~= nil, "on by default")
    t.eq(addon.settings:set(addon.PartyGroup.SETTING, false), true, "the row is there and takes off")
    c.advance(2, 10)
    t.eq(picked(addon), nil, "off: nothing")
    addon.settings:set(addon.PartyGroup.SETTING, true); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).step, "group", "on again")
end

tests["group e2e: a poison on the member: the cure, look only"] = function(t)
    local c, addon, icon = start({ buffs = { { name = MOTW, left = 1000 }, { name = THORNS, left = 500 } },
        debuffs = { Poison = "Made-up Venom" } })
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit, s.look } or nil, { "group", ABOLISH, "party1", true })
    t.eq(icon and icon.captionText, ABOLISH .. " on " .. NAME)
    local v = view(addon)
    t.eq(v and v.attrs and v.attrs.source, "plan", "the key is the plan's")
    t.ok(not said(c):find(NAME, 1, true), "no name in the diag word")
end

-- Flag (a): the curses and poisons on you are read now, so the dispel step
-- that was always "nothing to remove" in the game can fire.
tests["group e2e: a curse on you: Remove Curse on yourself, out of a fight"] = function(t)
    local c, addon = start({ buffs = { { name = MOTW, left = 1000 }, { name = THORNS, left = 500 } } })
    c.setUnitDebuffs("player", { Curse = "Made-up Hex" }); c.advance(2, 10)
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit } or nil, { "dispel", "Remove Curse", "player" })
    local v = view(addon)
    t.eq(v and v.snapshot and v.snapshot.debuffTypes, { Curse = "Made-up Hex" }, "the read reached the snapshot")
end

-- Lead section 236 (a): data arriving late and in parts. The group is not
-- read on the first ticks; then the roster comes (the client's own
-- GROUP_ROSTER_UPDATE), but the member's buffs are not read yet; then they
-- are. Nothing is suggested until both are known: never a guess between.
tests["group e2e 236(a): the roster, then the member's buffs, arrive late: nothing until both are known"] = function(t)
    local c, addon, icon = start({ party = "unread", buffs = "unread" })
    t.eq(picked(addon), nil, "the group not read: nothing")
    t.eq(icon and icon.captionText, nil, "no caption")
    c.setParty({ member() }); c.fire("GROUP_ROSTER_UPDATE"); c.advance(2, 10)
    t.eq(picked(addon), nil, "the roster in, the buffs not read: nothing, never a guess")
    t.eq(icon and icon.captionText, nil, "still no caption")
    c.setUnitBuffs("party1", { { name = THORNS, left = 500 } }); c.advance(2, 10)
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit } or nil, { "group", MOTW, "party1" }, "both known: Mark of the Wild")
    t.eq(icon and icon.captionText, MOTW .. " on " .. NAME)
    c.setParty({}); c.fire("GROUP_ROSTER_UPDATE"); c.advance(2, 10)
    t.eq(picked(addon), nil, "the member left the group: nothing")
    t.eq(icon and icon.captionText, nil, "and the caption is gone")
end

-- Lead section 236 (b): a reload in the middle. The setting off is kept in
-- the saved data; a second add-on built from it still has it off, and on
-- again brings the suggestion back.
tests["group e2e 236(b): the setting off survives a reload; on again restores it"] = function(t)
    local c, addon = start()
    t.eq(picked(addon) and picked(addon).step, "group", "on by default: suggested")
    t.eq(addon.settings:set(addon.PartyGroup.SETTING, false), true, "switched off")
    c.advance(2, 10)
    t.eq(picked(addon), nil, "off: nothing")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(addon2.PartyGroup.SETTING), false, "still off after the reload")
    t.eq(picked(addon2), nil, "and nothing for the group")
    addon2.settings:set(addon2.PartyGroup.SETTING, true); c2.advance(2, 10)
    t.eq(picked(addon2) and picked(addon2).step, "group", "on again: suggested")
end

-- Lead section 236 (c): a read that fails, then recovers. The group read
-- (and then the reach read) raises on some ticks: nothing is suggested, no
-- error escapes the tick, the view stays a fresh one; once the client
-- answers again the suggestion comes back.
tests["group e2e 236(c): the group read raises, then answers: nothing, no error, then the suggestion"] = function(t)
    local c, addon = start()
    t.eq(picked(addon) and picked(addon).step, "group", "suggested, so this test can fail")
    local before = errors(addon)
    c.setPartyFails(true); c.advance(2, 10)
    t.eq(picked(addon), nil, "the group read raises: nothing")
    t.eq(errors(addon), before, "no error escaped the tick")
    t.ok(view(addon) ~= nil and view(addon).stale ~= true, "the view is fresh, not a kept one")
    c.setPartyFails(false); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).step, "group", "the read answers again: suggested")
    c.setReachFails(true); c.advance(2, 10)
    t.eq(picked(addon), nil, "the reach read raises: not known, nothing")
    t.eq(errors(addon), before, "no error escaped the tick")
    c.setReachFails(false); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).step, "group", "the reach answers again: suggested")
end

-- ---------------------------------------------- lead section 243 item 1

local K = ns.KeyFrame
local OTHER = "Quillaby"   -- made up

-- The rotation key's secure button on the fake client, or nil.
local function keyButton(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h end
    end
    return nil
end

-- The key on: the secure button is set out of a fight.
local function keyOn(c, addon)
    addon.settings:set(K.SETTING, true)
    c.advance(2, 10)
    return keyButton(c)
end

-- No attribute of the button holds the group spell, the unit or the name.
local function keyClean(t, b, label)
    t.ok(b ~= nil, label .. ": the key's button was made")
    for attr, value in pairs(b and b.attrs or {}) do
        t.ok(value ~= MOTW and value ~= ABOLISH and value ~= "party1" and value ~= NAME,
            label .. ": nothing of the group suggestion on " .. tostring(attr))
    end
end

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- 243 item 3: the look-only check on the key's actual attributes.
tests["group e2e 243: a group suggestion leaves the key's secure button as the plan has it"] = function(t)
    local c, addon = start()
    local b = keyOn(c, addon)
    t.eq(picked(addon) and picked(addon).step, "group", "the group step picked")
    t.eq(b and { b.attrs.type, b.attrs.spell, b.attrs.unit }, { "spell", "Wrath", "target" },
        "the key casts the caster key's spell on your target")
    keyClean(t, b, "out of a fight")
end

-- 243 item 1 (MED): the icon shows the key will not cast it.
tests["group e2e 243: the icon is marked look-only for a group suggestion, and only then"] = function(t)
    local c, addon, icon = start()
    t.eq(picked(addon) and picked(addon).step, "group")
    t.eq(icon and icon.marked, "look", "a group suggestion: the look-only mark")
    c.setPlayerBuffs({ [THORNS] = true }); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).step, "list", "your own Mark is missing: the list's own buff")
    t.eq(icon and icon.marked, nil, "your own buff: no mark, the key casts it")
    c.setPlayerBuffs(BUFFED); c.setUnitBuffs("party1", { { name = MOTW, left = 1000 }, { name = THORNS, left = 500 } })
    c.advance(2, 10)
    t.eq(picked(addon), nil, "nothing")
    t.eq(icon and icon.marked, nil, "nothing shown: no mark")
end

-- 243 item 4 (section 236): the roster changes in a fight.
tests["group e2e 243: the roster changes mid-fight: nothing in the fight, the new member after"] = function(t)
    local c, addon = start({ buffs = { { name = MOTW, left = 1000 }, { name = THORNS, left = 500 } } })
    t.eq(picked(addon), nil, "party1 has both: nothing")
    c.setCombat(true); c.advance(1, 5)
    c.setParty({ member({ unit = "party2", name = OTHER }) })
    for _, id in pairs(IDS) do c.setReach("party2", id, true) end
    c.setUnitBuffs("party2", { { name = THORNS, left = 500 } })
    c.fire("GROUP_ROSTER_UPDATE"); c.advance(2, 10)
    local s = picked(addon)
    t.ok(s == nil or s.step ~= "group", "in the fight: nothing for the group")
    c.setCombat(false); c.advance(2, 10)
    s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit, s.member } or nil, { "group", MOTW, "party2", OTHER },
        "out of the fight: the new member, read again")
end

-- 243 item 4: lockdown not known while a group suggestion is up.
tests["group e2e 243: lockdown not known: still look only, the key untouched"] = function(t)
    local c, addon, icon = start()
    local b = keyOn(c, addon)
    local before = copy(b and b.attrs)
    c.setLockdown(nil); c.advance(2, 10)
    local s = picked(addon)
    t.eq(s and { s.step, s.look } or nil, { "group", true }, "still suggested, look only")
    t.eq(icon and icon.marked, "look", "still marked")
    t.eq(b and copy(b.attrs), before, "the key's attributes are as they were")
    keyClean(t, b, "lockdown not known")
end

-- 243 item 4: the aura read raises for one member, then recovers.
tests["group e2e 243: the buff read raises for one member: skipped, no error, then back"] = function(t)
    local c, addon = start()
    c.setParty({ member(), member({ unit = "party2", name = OTHER }) })
    for _, id in pairs(IDS) do c.setReach("party2", id, true) end
    c.setUnitBuffs("party2", { { name = THORNS, left = 500 } })
    c.fire("GROUP_ROSTER_UPDATE"); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).unit, "party1", "both missing Mark: party1 first")
    local before = errors(addon)
    c.setUnitBuffFails("party1", true); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).unit, "party2", "party1's buffs raise: skipped, party2")
    t.eq(errors(addon), before, "no error escaped the tick")
    c.setUnitBuffFails("party1", false); c.advance(2, 10)
    t.eq(picked(addon) and picked(addon).unit, "party1", "party1 read again")
end

-- 243 item 5: buff memory. The game hides the member's buffs; what you
-- cast on them is remembered (Flow's E.buffMemory, Engine.lua:1399-1410),
-- so Mark of the Wild is not asked for again until it runs out.
tests["group e2e 243: buffs hidden: what you cast on them is remembered until it runs out"] = function(t)
    local c, addon = start({ buffs = { { name = false } } })
    t.eq(picked(addon), nil, "their buffs hidden, nothing remembered: not known, nothing")
    c.fire("UNIT_SPELLCAST_SENT", "player", OTHER, "cast-0", IDS[MOTW])
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", IDS[MOTW])
    c.advance(2, 10)
    t.eq(picked(addon), nil, "cast on someone else: still nothing for party1")
    c.fire("UNIT_SPELLCAST_SENT", "player", NAME, "cast-1", IDS[MOTW])
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", IDS[MOTW])
    c.advance(2, 10)
    t.eq(picked(addon), nil, "cast on them: covered for its 30 minutes")
    c.advance(1750, 50)
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit } or nil, { "group", MOTW, "party1" }, "under a minute left: running out")
    t.ok(s == nil or not tostring(s.reason):find(NAME, 1, true), "no name in the reason")
end

-- 243 item 5: "a more powerful spell is already active" (Flow's
-- E.BOUNCE_SECONDS, Engine.lua:1084, 1412-1420): the game's refusal is
-- remembered for that member and spell for five minutes.
tests["group e2e 243: the game refuses a weaker buff: not asked for again for five minutes"] = function(t)
    local c, addon = start()
    t.eq(picked(addon) and picked(addon).spell, MOTW, "Mark missing: suggested")
    c.fire("UNIT_SPELLCAST_SENT", "player", NAME, "cast-2", IDS[MOTW])
    c.fire("UI_ERROR_MESSAGE", 51, "A more powerful spell is already active")
    c.advance(2, 10)
    t.eq(picked(addon), nil, "a stronger one is on them: not asked for")
    c.advance(300, 30)
    t.eq(picked(addon) and picked(addon).spell, MOTW, "five minutes on: asked again")
end

return tests
