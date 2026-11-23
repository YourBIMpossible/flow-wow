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

return tests
