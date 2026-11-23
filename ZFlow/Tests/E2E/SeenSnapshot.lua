local _, ns = ...

-- Lead section 188, Zen: the seen-result snapshot (tools/offline/
-- zflow-seen.lua, reached as ns.offline.seen). The whole add-on loaded the
-- way the game loads it (ns.offline.addon) on a fake client; the snapshot
-- is one text block of what the player sees, in a fixed order, with no
-- character, realm, guild or account name in it. Every name and place here
-- is made up; nothing is from a capture. Not tested in game. Look only:
-- the snapshot takes no flight, casts nothing and clicks nothing.

local tests = {}
local seen, seenDiff, parts = ns.offline.seen, ns.offline.seenDiff, ns.offline.seenParts
local D, TM, MF, Travel = ns.RotationDriver, ns.TaxiMark, ns.MapFlights, ns.Nav.Travel

-- Made-up state has no character in it: the snapshot is told so, or it
-- refuses (see "refuses" below).
local MADE_UP = { madeUp = true }

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

local function anyFinds(lines, piece)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(piece, 1, true) then return true end
    end
    return false
end

-- The lines of one section of a snapshot text.
local function section(text, name)
    local by = parts.sections(text)
    return by[name]
end

-- ------------------------------------------------------------ flight setup
-- As FlightWay.lua and FlightMarks.lua: map 1411 is x 0..1000, y 0..500;
-- map 1420 (the wolves) is x 5000..6000, y 0..1000; the continent's world
-- map 1414 spans x 0..10000, y 0..1000. The player stands at 1411
-- (0.5, 0.5), world (500, 250).
local HOME_POST, FAR_POST = "Home Post", "Far Post"

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1420 })[area] end
    return db, zones
end

-- opts.homeX: the boarding point's world x (700 as FlightWay.lua, 200 yd
-- from the player; 520 as FlightMarks.lua). opts.far: the landing's name.
-- opts.title: the quest's title. opts.env: what the client's own name
-- reads answer. opts.account / opts.char: saved tables (a reload).
local function flying(opts)
    opts = opts or {}
    local far = opts.far or FAR_POST
    local c = ns.make.fakeClient({ env = opts.env })
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or { learned = { flights = { nodes = {
        [HOME_POST] = { cont = 1, wx = opts.homeX or 700, wy = 250 },
        [far] = { cont = 1, wx = 5480, wy = 500 },
    } } } })
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 1)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1420, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setMapCorners(1414, { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 1000 })
    c.setClass("WARRIOR"); c.setFaction("Horde")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = opts.title or "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- What the arrows section must say for the client's arrows as they are.
local function arrowsWanted(c)
    local want = {}
    for i, a in ipairs(c.arrows) do
        local head = "arrow " .. i .. " (" .. tostring(a.spec.name) .. "): "
        if a.shown then
            want[#want + 1] = head .. "shown"
            if #a.lines == 0 then want[#want + 1] = "  no lines" end
            for n, line in ipairs(a.lines) do
                want[#want + 1] = "  line " .. n .. ": " .. (line ~= "" and line or parts.UNKNOWN)
            end
        else
            want[#want + 1] = head .. "hidden"
        end
    end
    return want
end

-- ---------------------------------------------------------- paladin setup
-- As PaladinRotation.lua.
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local ENEMY = { exists = true, hostile = true, dead = false }

local function paladin()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    return c, addon, icon
end

-- Switched on, the seal up, an enemy targeted and in range, swinging.
local function fighting(c, addon)
    addon.settings:set(D.SETTING, true)
    c.setPlayerBuffs(SEALED); c.setTarget(ENEMY); c.setStealthed(false)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Judgement"], true)
    c.setCurrentSpell(IDS["Attack"], true); c.setCombat(true)
    c.advance(1, 5)
end

-- The rotation lines the diag word prints now, without the title in front.
local function rotationSaid(c)
    local from, head = #c.printed + 1, ns.id.title .. ": "
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #head) == head and line:find("rotation:", 1, true) then
            out[#out + 1] = line:sub(#head + 1)
        end
    end
    return out
end

-- ------------------------------------------------------------------ tests

tests["seen: the sections come in the fixed order, each once, and the text is the lines joined"] = function(t)
    local c, addon = flying()
    local text, lines = seen(c, addon, MADE_UP)
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(text, table.concat(lines, "\n"))
    t.eq(lines[1], parts.HEAD, "the first line names the format")
    local _, order = parts.sections(text)
    local want = { "head" }
    for i, name in ipairs(parts.SECTIONS) do want[i + 1] = name end
    t.eq(order, want)
    t.eq(parts.SECTIONS, { "arrows", "rotation icon", "flight marks", "map pins", "minimap pins",
        "nameplate labels", "combo bars", "slot icons", "panels", "chat", "diag" })
end

tests["seen: a far quest with known flight masters, the arrow's lines exactly as the arrow shows them"] = function(t)
    local c, addon = flying()
    local a = c.arrows[1]
    t.eq(a.shown, true, "the quest arrow is shown")
    local got = section(seen(c, addon, MADE_UP), "arrows")
    t.eq(got, arrowsWanted(c))
    t.eq(got and got[2], "  line 1: " .. ns.Nav.Flights.LABEL:format(FAR_POST), "Fly to ...")
    t.eq(got and got[3], "  line 2: " .. Travel.THEN:format("Wolves"), "Then: ...")
end

tests["seen: a hidden arrow says hidden and none of its old lines"] = function(t)
    local c, addon = flying()
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.ok(#a.lines > 0, "it had lines")
    -- The fake's own handle: hidden, and it keeps the lines it last drew.
    a.show(false)
    t.ok(#a.lines > 0, "a hidden arrow keeps its old lines")
    local got = section(seen(c, addon, MADE_UP), "arrows")
    t.eq(got and got[1], "arrow 1 (" .. tostring(a.spec.name) .. "): hidden")
    t.ok(not anyFinds(got, "Fly to"), "no stale line")
    t.ok(not anyFinds(got, "Wolves"), "no stale line")
    t.eq(got, arrowsWanted(c))
end

tests["seen: the paladin's icon with its picture and the reason, then hidden when switched off"] = function(t)
    local c, addon, icon = paladin()
    t.ok(icon ~= nil, "the icon was made at login")
    fighting(c, addon)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Judgement")
    local got = section(seen(c, addon, MADE_UP), "rotation icon")
    local said = rotationSaid(c)
    t.ok(#said > 0, "the diag word has rotation lines")
    local want = { "icon (" .. icon.spec.name .. "): shown", "  texture: tex:Judgement", "  mark: none" }
    for _, line in ipairs(said) do want[#want + 1] = "  reason: " .. line end
    t.eq(got, want)
    t.ok(anyFinds(got, "suggesting Judgement"), "the reason names the spell")

    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false)
    got = section(seen(c, addon, MADE_UP), "rotation icon")
    t.eq(got, { "icon (" .. icon.spec.name .. "): hidden",
        "  reason: rotation: switched off; nothing suggested." })
    t.ok(not anyFinds(got, "tex:"), "a hidden icon says no stale picture")
end

tests["seen: the flight map's ring, shown then hidden"] = function(t)
    local c, addon = flying({ homeX = 520 })
    t.eq(section(seen(c, addon, MADE_UP), "flight marks"), { "none" }, "nothing made yet")
    c.setTaxiNodes({ map = 1414, here = HOME_POST, nodes = {
        { name = HOME_POST, x = 0.052, y = 0.25, state = "current" },
        { name = FAR_POST, x = 0.548, y = 0.5, state = "reachable" },
    } })
    c.fire("TAXIMAP_OPENED")
    local h = c.taxiMarks[1]
    t.ok(h ~= nil and h.shown == true, "a ring was made and shown")
    t.eq(section(seen(c, addon, MADE_UP), "flight marks"),
        { "mark 1: shown", "  node: Far Post at 0.548, 0.500", "  label: " .. TM.Label(nil) })
    c.setTaxiNodes(nil)
    c.fire("TAXIMAP_CLOSED")
    t.eq(h and h.shown, false)
    t.eq(section(seen(c, addon, MADE_UP), "flight marks"), { "mark 1: hidden" })
end

tests["seen: the world map's flight pins, by name, and the flight's line"] = function(t)
    local c, addon = flying({ homeX = 520 })
    t.ok((addon.settings:set(MF.SETTING, true)), "set on")
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.ok(h ~= nil and h.shown == true, "pins made and shown")
    t.eq(section(seen(c, addon, MADE_UP), "map pins"), {
        "pins 1: shown",
        "  pin: Far Post, have, to, at 0.548, 0.500",
        "  pin: Home Post, have, from, at 0.052, 0.250",
        "  line: Home Post to Far Post, 0.052, 0.250 to 0.548, 0.500",
    })
    c.setWorldMap(nil)
    c.advance(2, 8)
    t.eq(h and h.shown, false)
    t.eq(section(seen(c, addon, MADE_UP), "map pins"), { "pins 1: hidden" })
end

-- No add-on: the fake client's records alone. Pins handed over out of
-- order come out sorted; what is missing is said, never left out.
tests["seen: pins are sorted whatever order they were drawn in; what is not known is said"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.mapPins()
    h.draw({
        { name = "Zulu", kind = "have", x = 0.9, y = 0.1 },
        { name = "Alpha", kind = "new", role = "to", x = 1 / 3 },
        { name = "Mike", kind = "have", role = "from", x = 0.25, y = 0.75 },
    }, {
        { from = "Mike", to = "Alpha", ax = 0.25, ay = 0.75, bx = 1 / 3 },
    })
    local text, lines = seen(c, nil, MADE_UP)
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "map pins"), {
        "pins 1: shown",
        "  pin: Alpha, new, to, at 0.333, not known",
        "  pin: Mike, have, from, at 0.250, 0.750",
        "  pin: Zulu, have, not known, at 0.900, 0.100",
        "  line: Mike to Alpha, 0.250, 0.750 to 0.333, not known",
    })
    t.eq(section(text, "arrows"), { "none" })
    t.eq(section(text, "rotation icon"), { "icon: not made", "  reason: not known" })
    t.eq(section(text, "diag"), { "not known" }, "no add-on: the diag word cannot be asked")
    t.eq(section(text, "chat"), { "none" })
end

tests["seen: two snapshots of the same state are the same text, byte for byte"] = function(t)
    local c, addon = flying({ homeX = 520 })
    addon.settings:set(MF.SETTING, true)
    c.setWorldMap(1414)
    c.advance(2, 8)
    local one = seen(c, addon, MADE_UP)
    local two = seen(c, addon, MADE_UP)
    t.ok(type(one) == "string" and #one > 0, "a text came back")
    t.eq(two, one)
    t.eq(#seenDiff(one, two), 0, "and the compare finds nothing")
    local p, i = paladin()
    fighting(p, i)
    t.eq(seen(p, i, MADE_UP), seen(p, i, MADE_UP), "the same for a rotation state")
end

-- Section 187 item 4: a reload is a second client given the first one's
-- saved tables. What the player sees of the same state is the same. Chat
-- and panels are left out: a first login may say and show what a later one
-- does not.
tests["seen: after a reload into the same state, the same arrows, icon, marks, pins and diag lines"] = function(t)
    local c, addon = flying()
    local one = seen(c, addon, MADE_UP)
    local c2, addon2 = flying({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    local two = seen(c2, addon2, MADE_UP)
    t.ok(type(one) == "string" and type(two) == "string", "both came back")
    local same = { ["arrows"] = true, ["rotation icon"] = true, ["flight marks"] = true,
        ["map pins"] = true, ["diag"] = true }
    local found = {}
    for _, d in ipairs(seenDiff(one, two)) do
        if same[d.section] then found[#found + 1] = d.text end
    end
    t.eq(found, {})
    t.ok(anyFinds(section(two, "arrows"), "Fly to " .. FAR_POST), "the flight is still on the arrow")
end

tests["seen: the diag word's lines are in the block, and asking changes nothing the player sees"] = function(t)
    local c, addon, icon = paladin()
    fighting(c, addon)
    local account = c.saved(ns.id.accountDB)
    local count, snaps = account.diag.count, #account.diag.snaps
    local printed = {}
    for i, line in ipairs(c.printed) do printed[i] = line end
    local arrowsBefore = arrowsWanted(c)
    local shown, texture, places = icon.shown, icon.texture, icon.places

    local text = seen(c, addon, MADE_UP)
    local diag = section(text, "diag")
    t.ok(diag ~= nil and #diag > 1, "the diag lines are there")
    t.eq(diag and diag[1], "  " .. ns.id.title .. ": snapshot <n> kept. Reload or log out to write it to disk.",
        "the count is not a thing the player's state decides: it is said as <n>")
    t.ok(anyFinds(diag, "rotation: "), "the rotation's line among them")

    t.eq(c.printed, printed, "nothing was said in chat")
    t.eq(account.diag.count, count, "the diag word's own count is as it was")
    t.eq(#account.diag.snaps, snaps, "and no snapshot was kept")
    t.eq(arrowsWanted(c), arrowsBefore, "the arrows are as they were")
    t.eq(icon.shown, shown); t.eq(icon.texture, texture); t.eq(icon.places, places)
    c.print("after")
    t.eq(c.printed[#c.printed], "after", "the client's print is its own again")
    t.eq(#c.printed, #printed + 1)

    -- Lines handed in are used as they are; false asks for none.
    local handed = section(seen(c, addon, { madeUp = true, diag = { "one", "two" } }), "diag")
    t.eq(handed, { "  one", "  two" })
    t.eq(section(seen(c, addon, { madeUp = true, diag = false }), "diag"), { "not asked" })
    t.eq(c.printed[#c.printed], "after", "still nothing said")
end

-- The guard (lead section 188 section 3): no character, realm, guild or
-- account name leaves in a snapshot. All four names are made up.
tests["seen: no names: character, realm, guild and account are replaced in arrow, chat and diag lines"] = function(t)
    local CHARACTER, REALM, GUILD, ACCOUNT = "Zzyxmade", "Quell Made", "Vortexmade", "Wobblemade"
    local c, addon = flying({
        far = "Camp " .. GUILD,
        title = "Help " .. CHARACTER .. " of " .. REALM,
        env = {
            UnitName = function() return CHARACTER end,
            GetRealmName = function() return REALM end,
            GetGuildInfo = function() return GUILD, "Member", 3 end,
        },
    })
    local a = c.arrows[1]
    t.eq(a.shown, true)
    -- The names are really on screen: the guard is not passing on nothing.
    t.ok(anyFinds(a.lines, CHARACTER) and anyFinds(a.lines, GUILD) and anyFinds(a.lines, REALM),
        "the arrow shows the names: " .. table.concat(a.lines, " / "))
    c.print(ns.id.title .. ": welcome back " .. CHARACTER .. "-QuellMade, account " .. ACCOUNT:upper())
    c.setEventFault("ZZYXMADE_SEEN", true)

    local text, lines = seen(c, addon, { names = { account = ACCOUNT } })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    local low = tostring(text):lower()
    for _, name in ipairs({ CHARACTER, REALM, "QuellMade", GUILD, ACCOUNT }) do
        t.ok(not low:find(name:lower(), 1, true), name .. " is not in the snapshot")
    end
    local arrows = section(text, "arrows")
    t.ok(has(arrows, "  line 1: Fly to Camp <guild>"), "the guild's place: " .. table.concat(arrows or {}, " / "))
    t.ok(has(arrows, "  line 2: Then: Help <character> of <realm>"), "the quest's title")
    t.ok(has(section(text, "chat"), "  " .. ns.id.title .. ": welcome back <character>-<realm>, account <account>"),
        "the chat line: " .. table.concat(section(text, "chat") or {}, " / "))
    t.ok(has(section(text, "diag"), "  " .. ns.id.title .. ": events not registered: <character>_SEEN."),
        "the diag line: " .. table.concat(section(text, "diag") or {}, " / "))
end

tests["seen: refuses when no character name is known and the state was not said to be made up"] = function(t)
    local c = ns.make.fakeClient()
    c.print("a line")
    local text, why = seen(c, nil)
    t.eq(text, nil, "no text")
    t.ok(type(why) == "string" and #why > 0, "and the reason is given")
    t.ok(type((seen(c, nil, { names = { character = "Zzyxmade" } }))) == "string", "a name handed in is enough")
    t.ok(type((seen(c, nil, MADE_UP))) == "string", "and so is saying the state is made up")
end

-- The review of section 188's guard: six gaps, a test each. No add-on is
-- loaded: a bare fake client and what it printed are enough. Every name is
-- made up.

-- Gap 1. The second check is its own: it does not ask redact what a name
-- is. With redact made to do nothing, a joined form still refuses.
tests["seen names: the second check is its own and refuses a joined form redact left in"] = function(t)
    local c = ns.make.fakeClient()
    local names = parts.names(c, nil, { realm = "Quell Made", guild = "Character" })
    t.ok(type(names) == "table", "the names came back")
    t.eq(parts.held("  at Quell_Made", names), true, "joined by an underscore")
    t.eq(parts.held("  at QUELL...made", names), true, "joined by dots, upper case")
    t.eq(parts.held("  a character sheet", names), true, "a name that is a word is still a name")
    t.eq(parts.held("  at <realm> for <character>", names), false, "a placeholder is not a name")
    t.eq(parts.held("  at Quill Made", names), false, "another word is not the name")

    c.print("at Quell_Made")
    local opts = { names = { character = "Zzyxmade", realm = "Quell Made" } }
    local own = parts.redact
    parts.redact = function(line) return line end
    local ok, text, why = pcall(seen, c, nil, opts)
    parts.redact = own
    t.ok(ok, "nothing raised: " .. tostring(text))
    t.eq(text, nil, "a line redact left alone is refused")
    t.ok(type(why) == "string" and why:find("chat", 1, true) ~= nil, "the reason names the section: " .. tostring(why))
    t.eq(section(seen(c, nil, opts), "chat"), { "  at <realm>" }, "with redact back, the line is replaced")
end

-- Gap 2. What was replaced and what was not known is said under the head;
-- a key of opts.names that is no kind of name is refused, not passed over.
tests["seen names: a line under the head says the kinds known and not known; a key that is no kind refuses"] = function(t)
    local c = ns.make.fakeClient()
    local text, lines = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made" } })
    t.ok(type(text) == "string", "no guild is no reason to refuse: " .. tostring(lines))
    lines = type(lines) == "table" and lines or {}
    t.eq(lines[1], parts.HEAD)
    t.eq(lines[2], "names: character, realm known; guild, account, guid not known")
    t.eq(lines[3], "== arrows ==", "the first section comes after it")
    local by, order = parts.sections(text)
    t.eq(order[1], "head")
    t.eq(by.head, { parts.HEAD, lines[2] }, "the compare has it in the head, in no section")

    local made = select(2, seen(c, nil, MADE_UP))
    t.eq(type(made) == "table" and made[2], "names: none known; character, realm, guild, account, guid not known")
    local all = select(2, seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made",
        guild = "Vortexmade", account = "Wobblemade", guid = "Player-1234-ABCDEF" } }))
    t.eq(type(all) == "table" and all[2], "names: character, realm, guild, account, guid known; none not known")

    local bad = {
        { "Zzyxmade" },
        { character = "Zzyxmade", guildd = "Vortexmade" },
        "Zzyxmade",
        { character = 5 },
        { character = { "Zzyxmade", 5 } },
        { character = { first = "Zzyxmade" } },
    }
    for i, given in ipairs(bad) do
        local got, why = seen(c, nil, { madeUp = true, names = given })
        t.eq(got, nil, "names " .. i .. " are refused")
        t.ok(type(why) == "string" and #why > 0, "names " .. i .. ": the reason is given")
        t.ok(not tostring(why):lower():find("made", 1, true), "names " .. i .. ": and it says no name: " .. tostring(why))
    end
end

-- Gap 3. The words of a name joined by anything that is not a letter or a
-- digit; the parts of a GUID alone; a name with a non-ASCII letter, the
-- same bytes, its ASCII letters in the other case.
tests["seen names: a name joined by any signs, a GUID's parts alone and a non-ASCII name are replaced"] = function(t)
    local c = ns.make.fakeClient()
    c.setGuid("player", "Player-1234-ABCDEF")
    c.print("at Quell-Made, Quell_Made, quell.made and QuellMade")
    c.print("guid Player-1234-ABCDEF, short 1234-ABCDEF, bare ABCDEF")
    c.print("the Player stands")
    c.print("account WOBBL\195\169_MADE")
    local text, lines = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made",
        account = "Wobbl\195\169 Made" } })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), {
        "  at <realm>, <realm>, <realm> and <realm>",
        "  guid <guid>, short <guid>, bare <guid>",
        "  the Player stands",
        "  account <account>",
    })
    t.eq(type(lines) == "table" and lines[2], "names: character, realm, account, guid known; guild not known",
        "the GUID the client answers is known")
end

-- Gap 4. Two names that overlap in a line leave no piece of either.
tests["seen names: two names that overlap in a line are one placeholder, no piece left"] = function(t)
    local c = ns.make.fakeClient()
    c.print("Zzyxmade")
    local text, lines = seen(c, nil, { names = { character = "Zzyx", guild = "Xmade" } })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), { "  <character>" })
end

-- Gap 5. The problems are texts of errors: a file path (with the name of
-- the computer's user in it) and the names are taken out of them too.
tests["seen names: the problems have no path and no name in them"] = function(t)
    local c = ns.make.fakeClient()
    local addon = { id = { slash = "/zzseen", accountDB = "ZzSeenMadeUpDB" } }
    c.slashes["/zzseen"] = function()
        error("C:\\Users\\Zzyxowner\\src\\x.lua:12: boom for Zzyxmade", 0)
    end
    local text, _, problems = seen(c, addon, { names = { character = "Zzyxmade" } })
    t.ok(type(text) == "string", "a text came back")
    t.eq(section(text, "diag"), { "failed" })
    problems = type(problems) == "table" and problems or {}
    t.eq(#problems, 1)
    t.eq(problems[1], "diag: <path>/x.lua:12: boom for <character>")
    t.ok(not tostring(problems[1]):find("Zzyxowner", 1, true), "the user's name is not in it")

    t.eq(parts.paths("chat: /home/zzyxowner/src/y.lua:3: bad"), "chat: <path>/y.lua:3: bad")
    t.eq(parts.paths("...xowner/src/y.lua:3: bad"), "<path>/y.lua:3: bad", "a file name Lua cut short")
    t.eq(parts.paths("diag: C:\\Users\\Zzyx Owner\\x.lua:5: bad"), "diag: <path>/x.lua:5: bad", "a blank in a folder")
    t.eq(parts.paths("diag: C:\\a\\b.lua:5: cannot open D:/c/d.txt"),
        "diag: <path>/b.lua:5: cannot open <path>/d.txt", "two paths")
    t.eq(parts.paths("panels: attempt to index a nil value"), "panels: attempt to index a nil value",
        "a text with no path is as it was")
end

-- Gap 6. A name of one or two characters is in ordinary words.
tests["seen names: a name under 3 characters refuses; with shortNames it is replaced as a whole word only"] = function(t)
    local c = ns.make.fakeClient()
    c.print("Al is in a small hall, AL.")
    local text, why = seen(c, nil, { names = { character = "Al" } })
    t.eq(text, nil, "refused")
    t.ok(type(why) == "string" and why:find("under 3 characters", 1, true) ~= nil, "the reason: " .. tostring(why))
    text, why = seen(c, nil, { madeUp = true, names = { guild = "A-b" } })
    t.eq(text, nil, "two letters and a hyphen are two characters")
    t.ok(type(why) == "string" and why:find("under 3 characters", 1, true) ~= nil, "the reason: " .. tostring(why))
    local short = seen(c, nil, { names = { character = "Al" }, shortNames = true })
    t.eq(section(short, "chat"), { "  <character> is in a small hall, <character>." })
end

tests["seen compare: the same text has no differences; one changed arrow line is the one reported"] = function(t)
    local c, addon = flying()
    local one = seen(c, addon, MADE_UP)
    t.eq(seenDiff(one, one), {})
    local wasLine = "  line 1: Fly to " .. FAR_POST
    local nowLine = "  line 1: Fly to Near Post"
    local at = one:find(wasLine, 1, true)
    t.ok(at ~= nil, "the arrow line is in the text")
    local two = one:sub(1, at - 1) .. nowLine .. one:sub(at + #wasLine)
    local diffs = seenDiff(one, two)
    t.eq(#diffs, 1, "exactly one line differs")
    local d = diffs[1] or {}
    t.eq(d.section, "arrows")
    t.eq(d.line, 2, "the second line of the section: the first under the arrow's own")
    t.eq(d.was, wasLine)
    t.eq(d.now, nowLine)
    t.eq(d.text, 'arrows, line 2: was "' .. wasLine .. '"; now "' .. nowLine .. '"')
    -- A line only one side has.
    local more = seenDiff(one, one .. "\n  one more")
    t.eq(#more, 1)
    t.eq(more[1] and more[1].section, "diag", "the last section got the extra line")
    t.eq(more[1] and more[1].was, nil)
    t.eq(more[1] and more[1].now, "  one more")
end

return tests
