local _, ns = ...

-- Lead section 188, Zen: the seen-result snapshot (tools/offline/
-- zflow-seen.lua, reached as ns.offline.seen). The whole add-on loaded the
-- way the game loads it (ns.offline.addon) on a fake client; the snapshot
-- is one text block of what the player sees, in a fixed order. Since lead
-- section 199 (format 3) a line keeps only the add-on's own words, numbers
-- and compass words; every run of other text is a slot "<text:n>" (n its
-- length), and the chat is counted. Known names are replaced on top of
-- that. Every name and place here is made up; nothing is from a capture.
-- Not tested in game. Look only: the snapshot takes no flight, casts
-- nothing and clicks nothing.

local tests = {}
local seen, seenDiff, parts = ns.offline.seen, ns.offline.seenDiff, ns.offline.seenParts
local D, TM, MF, Travel = ns.RotationDriver, ns.TaxiMark, ns.MapFlights, ns.Nav.Travel

-- Made-up state has no character in it: the snapshot is told so, or it
-- refuses (see "refuses" below).
local MADE_UP = { madeUp = true }
local MADE_LINE = "names: made up; none known; none absent; character, realm, guild, account, guid not known"
-- Section 217 (N2): no add-on and no name read answered: made up is not
-- shown, so the line says not known instead.
local UNPROVEN_LINE = "names: not known; none known; none absent; character, realm, guild, account, guid not known"
local MUST = { "character", "realm", "guild", "account", "guid" }

-- Options for real state (lead section 199, N1): the names handed in, and
-- every kind of M.MUST that is not handed in marked absent. more: other
-- options (words, shortNames, ...). answered: kinds the client itself
-- answers (a GUID set on it), never marked absent.
local function named(names, more, answered)
    local opts, skip = { names = names, absent = {} }, {}
    for _, kind in ipairs(answered or {}) do skip[kind] = true end
    for _, kind in ipairs(MUST) do
        if names[kind] == nil and not skip[kind] then opts.absent[#opts.absent + 1] = kind end
    end
    for key, value in pairs(more or {}) do opts[key] = value end
    return opts
end

-- What the block says of a free value: its template under the add-on's
-- own words.
local function said(v)
    if v == nil or v == "" then return parts.UNKNOWN end
    return parts.template(tostring(v), parts.words())
end

-- The slot for a run of free text.
local function slot(text) return "<text:" .. #text .. ">" end

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
-- (0.5, 0.5), world (500, 250). The flight masters' names and the quest's
-- title are made-up words no add-on string has.
local HOME_POST, FAR_POST, TITLE = "Qorvhome Zank", "Qorvfar Zank", "Qorvwolves"

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
    c.setQuestLog({ { id = 303, title = opts.title or TITLE, objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- What the arrows section must say for the client's arrows as they are.
local function arrowsWanted(c)
    local want = {}
    for i, a in ipairs(c.arrows) do
        local head = "arrow " .. i .. " (" .. said(a.spec.name) .. "): "
        if a.shown then
            want[#want + 1] = head .. "shown"
            if #a.lines == 0 then want[#want + 1] = "  no lines" end
            for n, line in ipairs(a.lines) do
                want[#want + 1] = "  line " .. n .. ": " .. said(line)
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

tests["seen: a far quest with known flight masters, the arrow's lines as their templates"] = function(t)
    local c, addon = flying()
    local a = c.arrows[1]
    t.eq(a.shown, true, "the quest arrow is shown")
    t.eq(a.lines[1], ns.Nav.Flights.LABEL:format(FAR_POST), "the arrow itself shows the name")
    local got = section(seen(c, addon, MADE_UP), "arrows")
    t.eq(got, arrowsWanted(c))
    t.eq(got and got[2], "  line 1: Fly to " .. slot(FAR_POST), "Fly to ...: the add-on's words, the name a slot")
    t.eq(got and got[3], "  line 2: Then: " .. slot(TITLE), "Then: ...: the quest's title a slot")
    t.ok(not anyFinds(got, "Qorv"), "no free text is printed")
    t.eq(Travel.THEN:format(TITLE), "Then: " .. TITLE)
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
    t.eq(got and got[1], "arrow 1 (" .. said(a.spec.name) .. "): hidden")
    t.ok(not anyFinds(got, "Fly to"), "no stale line")
    t.ok(not anyFinds(got, "Then:"), "no stale line")
    t.eq(got, arrowsWanted(c))
end

tests["seen: the paladin's icon with its picture and the reason, then hidden when switched off"] = function(t)
    local c, addon, icon = paladin()
    t.ok(icon ~= nil, "the icon was made at login")
    fighting(c, addon)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Judgement")
    local got = section(seen(c, addon, MADE_UP), "rotation icon")
    local lines = rotationSaid(c)
    t.ok(#lines > 0, "the diag word has rotation lines")
    local want = { "icon (" .. said(icon.spec.name) .. "): shown", "  texture: " .. said(icon.texture), "  mark: none" }
    for _, line in ipairs(lines) do want[#want + 1] = "  reason: " .. said(line) end
    t.eq(got, want)
    t.ok(anyFinds(got, "suggesting Judgement"), "the reason names the spell: both are the add-on's own words")

    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false)
    got = section(seen(c, addon, MADE_UP), "rotation icon")
    t.eq(got, { "icon (" .. said(icon.spec.name) .. "): hidden",
        "  reason: rotation: switched off; nothing suggested." })
    t.ok(not anyFinds(got, "texture:"), "a hidden icon says no stale picture")
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
        { "mark 1: shown", "  node: " .. slot(FAR_POST) .. " at 0.548, 0.500", "  label: " .. said(TM.Label(nil)) })
    c.setTaxiNodes(nil)
    c.fire("TAXIMAP_CLOSED")
    t.eq(h and h.shown, false)
    t.eq(section(seen(c, addon, MADE_UP), "flight marks"), { "mark 1: hidden" })
end

tests["seen: the world map's flight pins, the names slotted, and the flight's line"] = function(t)
    local c, addon = flying({ homeX = 520 })
    t.ok((addon.settings:set(MF.SETTING, true)), "set on")
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.ok(h ~= nil and h.shown == true, "pins made and shown")
    -- Sorted as the lines they make: <text:12> (the far post) before <text:13>.
    t.eq(section(seen(c, addon, MADE_UP), "map pins"), {
        "pins 1: shown",
        "  pin: " .. slot(FAR_POST) .. ", have, to, at 0.548, 0.500",
        "  pin: " .. slot(HOME_POST) .. ", have, from, at 0.052, 0.250",
        "  line: " .. slot(HOME_POST) .. " to " .. slot(FAR_POST) .. ", 0.052, 0.250 to 0.548, 0.500",
    })
    c.setWorldMap(nil)
    c.advance(2, 8)
    t.eq(h and h.shown, false)
    t.eq(section(seen(c, addon, MADE_UP), "map pins"), { "pins 1: hidden" })
end

-- No add-on: the fake client's records alone. Pins handed over out of
-- order come out sorted (as the lines they make); what is missing is
-- said, never left out.
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
    local text, lines = seen(c, nil, { madeUp = true, words = { "have new to from" } })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "map pins"), {
        "pins 1: shown",
        "  pin: <text:4>, have, from, at 0.250, 0.750",
        "  pin: <text:4>, have, not known, at 0.900, 0.100",
        "  pin: <text:5>, new, to, at 0.333, not known",
        "  line: <text:4> to <text:5>, 0.250, 0.750 to 0.333, not known",
    })
    t.eq(section(text, "arrows"), { "none" })
    t.eq(section(text, "rotation icon"), { "icon: not made", "  reason: not known" })
    t.eq(section(text, "diag"), { "not known" }, "no add-on: the diag word cannot be asked")
    t.eq(section(text, "chat"), { "lines: 0" })
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
    t.ok(anyFinds(section(two, "arrows"), "Fly to " .. slot(FAR_POST)), "the flight is still on the arrow")
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

    -- Lines handed in are used as their templates; false asks for none.
    local handed = section(seen(c, addon, { madeUp = true, diag = { "one", "Zzyx two" } }), "diag")
    t.eq(handed, { "  " .. said("one"), "  " .. said("Zzyx two") })
    t.ok(not anyFinds(handed, "Zzyx"), "a handed-in line is templated too")
    t.eq(section(seen(c, addon, { madeUp = true, diag = false }), "diag"), { "not asked" })
    t.eq(c.printed[#c.printed], "after", "still nothing said")
end

-- The guard (lead section 188 section 3): known names are replaced on top
-- of the template. All four names are made up.
tests["seen: no names: character, realm, guild and account are slotted or replaced in arrow, chat and diag lines"] = function(t)
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

    -- The add-on's own words: the names are free text, slotted.
    local text, lines = seen(c, addon, { names = { account = ACCOUNT }, absent = { "guid" } })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    local low = tostring(text):lower()
    for _, name in ipairs({ CHARACTER, REALM, "QuellMade", GUILD, ACCOUNT }) do
        t.ok(not low:find(name:lower(), 1, true), name .. " is not in the snapshot")
    end
    t.ok(anyFinds(section(text, "arrows"), "  line 1: Fly to "), "the arrow's own words stay")

    -- Words that let the names through: then the names are replaced.
    local words = { ns.id.title, "Fly to Camp Vortexmade Then Help Zzyxmade of Quell Made welcome back",
        "QuellMade account WOBBLEMADE events not registered ZZYXMADE SEEN" }
    text, lines = seen(c, addon, { names = { account = ACCOUNT }, absent = { "guid" }, words = words })
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    low = tostring(text):lower()
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
    t.ok(type((seen(c, nil, named({ character = "Zzyxmade" })))) == "string",
        "a name handed in, the other kinds marked absent, is enough")
    t.ok(type((seen(c, nil, MADE_UP))) == "string", "and so is saying the state is made up")
end

-- The review of section 188's guard: six gaps, a test each. No add-on is
-- loaded: a bare fake client and what it printed are enough. Every name is
-- made up. Where a line must reach the name replacing, the test hands in
-- words that let the names through the template.

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
    local opts = named({ character = "Zzyxmade", realm = "Quell Made" }, { words = { "at Quell Made" } })
    local own = parts.redact
    parts.redact = function(line) return line end
    local ok, text, why = pcall(seen, c, nil, opts)
    parts.redact = own
    t.ok(ok, "nothing raised: " .. tostring(text))
    t.eq(text, nil, "a line redact left alone is refused")
    t.ok(type(why) == "string" and why:find("chat", 1, true) ~= nil, "the reason names the section: " .. tostring(why))
    t.eq(section(seen(c, nil, opts), "chat"), { "lines: 1", "  at <realm>" }, "with redact back, the line is replaced")
end

-- Gap 2. What was replaced, what was marked absent and what was not known
-- is said under the head; a key of opts.names that is no kind of name is
-- refused, not passed over.
tests["seen names: a line under the head says the kinds known, absent and not known; a key that is no kind refuses"] = function(t)
    local c = ns.make.fakeClient()
    local text, lines = seen(c, nil, named({ character = "Zzyxmade", realm = "Quell Made" }))
    t.ok(type(text) == "string", "no guild is no reason to refuse once it is marked absent: " .. tostring(lines))
    lines = type(lines) == "table" and lines or {}
    t.eq(lines[1], parts.HEAD)
    t.eq(lines[2], "names: character, realm known; guild, account, guid absent; none not known")
    t.eq(lines[3], "words: the add-on's")
    t.eq(lines[4], "== arrows ==", "the first section comes after them")
    local by, order = parts.sections(text)
    t.eq(order[1], "head")
    t.eq(by.head, { parts.HEAD, lines[2], lines[3] }, "the compare has them in the head, in no section")

    local made = select(2, seen(c, nil, MADE_UP))
    t.eq(type(made) == "table" and made[2], UNPROVEN_LINE, "this client answers no name read")
    local all = select(2, seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made",
        guild = "Vortexmade", account = "Wobblemade", guid = "Player-1234-ABCDEF" } }))
    t.eq(type(all) == "table" and all[2], "names: character, realm, guild, account, guid known; none absent; none not known")
    local given = select(2, seen(c, nil, { madeUp = true, words = { "x" } }))
    t.eq(type(given) == "table" and given[3], "words: given", "a test's own words are said")

    local bad = {
        { "Zzyxmade" },
        { character = "Zzyxmade", guildd = "Vortexmade" },
        "Zzyxmade",
        { character = 5 },
        { character = { "Zzyxmade", 5 } },
        { character = { first = "Zzyxmade" } },
    }
    for i, given2 in ipairs(bad) do
        local got, why = seen(c, nil, { madeUp = true, names = given2 })
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
    local words = { "at Quell Made quell made and QuellMade guid Player short bare ABCDEF the stands",
        "account WOBBL\195\169 MADE" }
    local text, lines = seen(c, nil, named({ character = "Zzyxmade", realm = "Quell Made",
        account = "Wobbl\195\169 Made" }, { words = words }, { "guid" }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), {
        "lines: 4",
        "  at <realm>, <realm>, <realm> and <realm>",
        "  guid <guid>, short <guid>, bare <guid>",
        "  the Player stands",
        "  account <account>",
    })
    t.eq(type(lines) == "table" and lines[2], "names: character, realm, account, guid known; guild absent; none not known",
        "the GUID the client answers is known")
end

-- Gap 4. Two names that overlap in a line leave no piece of either.
tests["seen names: two names that overlap in a line are one placeholder, no piece left"] = function(t)
    local c = ns.make.fakeClient()
    c.print("Zzyxmade")
    local text, lines = seen(c, nil, named({ character = "Zzyx", guild = "Xmade" }, { words = { "Zzyxmade" } }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), { "lines: 1", "  <character>" })
end

-- Gap 5. The problems are texts of errors: a file path (with the name of
-- the computer's user in it) and the names are taken out of them too.
tests["seen names: the problems have no path and no name in them"] = function(t)
    local c = ns.make.fakeClient()
    local addon = { id = { slash = "/zzseen", accountDB = "ZzSeenMadeUpDB" } }
    c.slashes["/zzseen"] = function()
        error("C:\\Users\\Zzyxowner\\src\\x.lua:12: boom for Zzyxmade", 0)
    end
    local text, _, problems = seen(c, addon, named({ character = "Zzyxmade" }))
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
    local text, why = seen(c, nil, named({ character = "Al" }))
    t.eq(text, nil, "refused")
    t.ok(type(why) == "string" and why:find("under 3 characters", 1, true) ~= nil, "the reason: " .. tostring(why))
    text, why = seen(c, nil, { madeUp = true, names = { guild = "A-b" } })
    t.eq(text, nil, "two letters and a hyphen are two characters")
    t.ok(type(why) == "string" and why:find("under 3 characters", 1, true) ~= nil, "the reason: " .. tostring(why))
    local short = seen(c, nil, named({ character = "Al" }, { shortNames = true, words = { "Al is in a small hall AL" } }))
    t.eq(section(short, "chat"), { "lines: 1", "  <character> is in a small hall, <character>." })
end

-- The second review of the guard: four more gaps, a test each. Every name
-- is made up.

-- Second review 1. A sign that is not ASCII (a no-break space, a curly
-- apostrophe) between the letters of a name whose own bytes are all ASCII.
tests["seen names: an ASCII name with a non-ASCII sign between its letters is replaced and the second check finds it"] = function(t)
    local NBSP, CURLY = "\194\160", "\226\128\153"
    local c = ns.make.fakeClient()
    c.print("at Quell" .. NBSP .. "Made")
    c.print("Q" .. CURLY .. "Zorvex says hello")
    local given = { character = "Q'Zorvex", realm = "Quell Made" }
    -- A non-ASCII byte is part of a word: each joined form is one word.
    local words = { "at Quell" .. NBSP .. "Made Q" .. CURLY .. "Zorvex says hello" }
    local text, lines = seen(c, nil, named(given, { words = words }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), { "lines: 2", "  at <realm>", "  <character> says hello" })

    local names = parts.names(c, nil, given)
    t.ok(type(names) == "table", "the names came back")
    names = type(names) == "table" and names or {}
    t.eq(parts.redact("at Quell" .. NBSP .. "Made", names), "at <realm>")
    t.eq(parts.held("  at Quell" .. NBSP .. "Made", names), true, "a no-break space between the words")
    t.eq(parts.held("  Q" .. CURLY .. "Zorvex", names), true, "a curly apostrophe")
    t.eq(parts.held("  caf\195\169 at noon", names), false, "a non-ASCII letter alone is no name")
end

-- Second review 2. A path in a problem's text that the first cut let
-- through: a stop character in a folder, a path that ends at the user's
-- folder, and a path that starts where no path was looked for. Since lead
-- section 199 (N4) a relative path keeps its file's name.
tests["seen names: a path with a quote in a folder, one ending at a folder and a relative one leave no folder name"] = function(t)
    local function cut(text, want, why)
        local got = parts.paths(text)
        t.eq(got, want, why)
        local low = tostring(got):lower()
        t.ok(not low:find("zzyxowner", 1, true) and not low:find("zorvex", 1, true), "no folder name: " .. tostring(got))
    end
    cut("diag: C:\\Users\\Q'Zorvex\\src\\x.lua:12: bad", "diag: <path>/x.lua:12: bad",
        "a quote in the user's folder: the folder goes, the file's name stays")
    cut("diag: C:\\Users\\Zzyx Q'Zorvex Jr\\src\\x.lua:12: bad", "diag: <path>/x.lua:12: bad",
        "a quote and blanks")
    cut("chat: cannot open /home/zzyxowner (No such file or directory)", "chat: cannot open <path>/",
        "the last part is a folder, not a file")
    cut("chat: cannot open /home/zzyxowner: Permission denied", "chat: cannot open <path>/: Permission denied",
        "a folder, then a colon")
    cut("diag: ..\\Zzyxowner\\src\\x.lua:12: bad", "diag: <path>/x.lua:12: bad", "a relative path, backslashes")
    cut("diag: ./home/zzyxowner/x.lua:3: bad", "diag: <path>/x.lua:3: bad", "a relative path, slashes")
    for _, sign in ipairs({ "`", "@", "<", ">", "{", "-" }) do
        cut("diag: " .. sign .. "/home/zzyxowner/x.lua:3: bad", "diag: <path>/x.lua:3: bad", "a path after " .. sign)
    end
    -- Cut too much on purpose: a problem is read for what went wrong.
    t.eq(parts.paths("chat: either/or is not a number"), "chat: <path> is not a number", "prose with a slash")
    t.eq(parts.paths("diag: C:\\a\\b.lua:5: cannot open D:/c/d.txt"), "diag: <path>/b.lua:5: cannot open <path>/d.txt",
        "a file's name with an extension stays")

    local c = ns.make.fakeClient()
    local addon = { id = { slash = "/zzseen", accountDB = "ZzSeenMadeUpDB" } }
    c.slashes["/zzseen"] = function()
        error("cannot open /home/zzyxowner (No such file or directory)", 0)
    end
    local text, _, problems = seen(c, addon, named({ character = "Zzyxmade" }))
    t.ok(type(text) == "string", "a text came back")
    problems = type(problems) == "table" and problems or {}
    t.eq(problems, { "diag: cannot open <path>/" })
    t.eq(parts.held("diag: <path> bad for <path>/x.lua", parts.names(c, nil, { character = "Zzyxmade" }) or {}), false,
        "the paths' placeholders are no names")
end

-- Second review 3. A name that is only digits (a part of a GUID) is a whole
-- number in the line, never digits of two numbers joined.
tests["seen names: a name of digits only is replaced as a whole number, never across or inside another"] = function(t)
    local c = ns.make.fakeClient()
    c.setGuid("player", "Player-4904-ABCDEF")
    c.print("pin at 0.349, 0.412")
    c.print("line 1: 234 gold")
    c.print("server 4904, id 1234, not 49040 or 14904")
    local given = { character = "Zzyxmade", guid = "Player-1234-FEDCBA" }
    local text, lines = seen(c, nil, named(given, { words = { "pin at line gold server id not or" } }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), {
        "lines: 3",
        "  pin at 0.349, 0.412",
        "  line 1: 234 gold",
        "  server <guid>, id <guid>, not 49040 or 14904",
    })

    local names = parts.names(c, nil, given)
    t.ok(type(names) == "table", "the names came back")
    names = type(names) == "table" and names or {}
    t.eq(parts.held("  pin at 0.349, 0.412", names), false, "digits of two numbers are not the name")
    t.eq(parts.held("  line 1: 234 gold", names), false, "nor across a colon")
    t.eq(parts.held("  id 49040 and 14904", names), false, "nor inside a longer number")
    t.eq(parts.held("  id 4904.", names), true, "the whole number is")
    t.eq(parts.held("  id (1234)", names), true, "the whole number is")
end

-- Second review 4, and lead section 199: format 3 is the block with the
-- names line, the words line and the templates.
tests["seen: the head says format 3 or later, the block with the names and words lines"] = function(t)
    local n = tostring(parts.HEAD):match("^zflow seen (%d+)$")
    t.ok(n ~= nil and tonumber(n) >= 3, "the head: " .. tostring(parts.HEAD))
    local made = select(2, seen(ns.make.fakeClient(), nil, MADE_UP))
    t.eq(type(made) == "table" and made[1], parts.HEAD, "and the block starts with it")
end

tests["seen compare: the same text has no differences; one changed arrow line is the one reported"] = function(t)
    local c, addon = flying()
    local one = seen(c, addon, MADE_UP)
    t.eq(seenDiff(one, one), {})
    local wasLine = "  line 1: Fly to " .. slot(FAR_POST)
    local nowLine = "  line 1: Fly to <text:9>"
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

-- ------------------------------------------- lead section 199: the template
-- MyBuddy's root-cause repair: a line prints only the add-on's own words,
-- numbers and compass words; every run of other text is one slot.

tests["seen words: free text is a slot; the add-on's words, numbers and compass words stay"] = function(t)
    local W = parts.wordSet({ "Fly to Then of yd" })
    t.eq(parts.template("Fly to Qorvfar Zank", W), "Fly to <text:12>", "one slot for the run, its length")
    t.eq(parts.template("Then: Help Zzyx of Quell Made", W), "Then: <text:9> of <text:10>", "two runs, two slots")
    t.eq(parts.template("200 yd NE", W), "200 yd NE", "a number, the add-on's word and a compass word")
    t.eq(parts.template("0.349, 12/40", W), "0.349, 12/40", "numbers and their signs")
    t.eq(parts.template("Caf\195\169 Zzyx", W), "<text:10>", "a non-ASCII letter is part of a word")
    t.eq(parts.template("fly TO", W), "<text:6>", "a word is kept only as the add-on writes it")
    t.eq(parts.template("<text:1234> Zz", W), "(<text:4>:1234> <text:2>", "a typed slot cannot pass for one")
    t.eq(parts.template("", W), "", "nothing stays nothing")
end

tests["seen words: the words come from string literals, never from comments or code"] = function(t)
    local src = table.concat({
        '-- Zzcomment "Zzquoted"',
        'local x = "Fly to %s" .. [[Zzlong words]] --[==[ Zzblock ]==] .. "Then"',
        "local y = 'Zzsingle'",
        'local z = "Zzesc\\"aped"',
    }, "\n")
    local W = parts.wordSet(parts.literals(src))
    for _, word in ipairs({ "Fly", "to", "Zzlong", "words", "Then", "Zzsingle", "Zzesc", "aped" }) do
        t.eq(W[word], true, word .. " is a word of a literal")
    end
    for _, word in ipairs({ "Zzcomment", "Zzquoted", "Zzblock", "local", "x", "s" }) do
        t.eq(W[word], nil, word .. " is not")
    end
end

tests["seen words: the default words are the shipped add-on's own"] = function(t)
    local W, why = parts.words()
    t.ok(type(W) == "table", "the add-on's words were read: " .. tostring(why))
    W = type(W) == "table" and W or {}
    for _, word in ipairs({ "Fly", "to", "Then", "yd", "suggesting", "Judgement", "Flow" }) do
        t.eq(W[word], true, word .. " is the add-on's")
    end
    for _, word in ipairs({ "Qorvfar", "Qorvwolves", "Zzyxmade", "Zzyxowner" }) do
        t.eq(W[word], nil, word .. " is not")
    end
end

tests["seen: the chat is counted, and each line is its template"] = function(t)
    local c = ns.make.fakeClient()
    c.print("Zzyx says: hello Qorv")
    c.print("7 of 9 Qorv")
    local text = seen(c, nil, { madeUp = true, words = { "says of" } })
    t.eq(section(text, "chat"), { "lines: 2", "  <text:4> says: <text:10>", "  7 of 9 <text:4>" })
    t.eq(section(seen(c, nil, { madeUp = true, chat = false }), "chat"), { "not asked" })
end

-- A slot is no name: a name that is in "text" leaves it alone, and a slot
-- typed into a line cannot hide a name from the second check.
tests["seen: a slot is neither searched nor forged"] = function(t)
    local c = ns.make.fakeClient()
    c.print("Zzyx Qorvwolves")
    local text, lines = seen(c, nil, named({ character = "Tex" }, { words = { "says" } }))
    t.ok(type(text) == "string", "a name inside the word text is no reason to refuse: " .. tostring(lines))
    t.eq(section(text, "chat"), { "lines: 1", "  <text:15>" })

    local c2 = ns.make.fakeClient()
    c2.setGuid("player", "Player-1234-ABCDEF")
    c2.print("<text:1234> Zzyx")
    text, lines = seen(c2, nil, named({ character = "Zzyxmade" }, { words = { "text" } }, { "guid" }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), { "lines: 1", "  (text:<guid>> <text:4>" })
end

-- ---------------------------------------------------- lead section 199: N1-N4

tests["seen N1: real state needs every kind of name known or marked absent"] = function(t)
    local c = ns.make.fakeClient()
    c.print("a line")
    local text, why = seen(c, nil, { names = { character = "Zzyxmade" } })
    t.eq(text, nil, "realm, guild and account neither known nor marked absent: refused")
    t.ok(type(why) == "string" and why:find("absent", 1, true) ~= nil, "the reason says how: " .. tostring(why))
    text = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made" }, absent = { "guild" } })
    t.eq(text, nil, "account is still neither")
    text = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made" }, absent = { "guild", "account" } })
    t.eq(text, nil, "guid is still neither")
    local lines
    text, lines = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made" },
        absent = { "guild", "account", "guid" } })
    t.ok(type(text) == "string", "every kind known or absent: " .. tostring(lines))
    t.eq(type(lines) == "table" and lines[2], "names: character, realm known; guild, account, guid absent; none not known")

    local bad = { "guild", { "guildd" }, { guild = true }, { 5 }, { "character" }, { "realm" } }
    for i, absent in ipairs(bad) do
        local got, why2 = seen(c, nil, { names = { character = "Zzyxmade", realm = "Quell Made" }, absent = absent })
        t.eq(got, nil, "absent " .. i .. " is refused")
        t.ok(type(why2) == "string" and #why2 > 0, "absent " .. i .. ": the reason is given")
        t.ok(not tostring(why2):find("Zzyx", 1, true) and not tostring(why2):find("Quell", 1, true),
            "absent " .. i .. ": and it says no name: " .. tostring(why2))
    end
end

tests["seen N2: made-up state says so on line 2 and is refused when the client answers a character name"] = function(t)
    -- A client that answers the name read with no name: made up is shown.
    local blank = ns.make.fakeClient({ env = { UnitName = function() return nil end } })
    local made = select(2, seen(blank, nil, MADE_UP))
    t.eq(type(made) == "table" and made[2], MADE_LINE)
    for _, read in ipairs({ "UnitName", "UnitFullName" }) do
        local c = ns.make.fakeClient({ env = { [read] = function() return "Zzyxmade", "Quellmade" end } })
        local text, why = seen(c, nil, MADE_UP)
        t.eq(text, nil, read .. " answers a name: not made up")
        t.ok(type(why) == "string" and why:find("made up", 1, true) ~= nil, read .. ": the reason: " .. tostring(why))
        t.ok(not tostring(why):find("Zzyx", 1, true), read .. ": and it says no name")
        t.ok(type((seen(c, nil, { absent = { "guild", "account", "guid" } }))) == "string",
            read .. ": said as real state, it is taken")
    end
    -- The character a diag snapshot kept in the account's saved table.
    local c = ns.make.fakeClient()
    c.setSaved("ZzSeenMadeUpDB", { diag = { snaps = { { timing = { character = "Zzyxmade" } } } } })
    local addon = { id = { slash = "/zzseen", accountDB = "ZzSeenMadeUpDB" } }
    t.eq(seen(c, addon, { madeUp = true, diag = false }), nil, "a kept snapshot's character: not made up")
end

tests["seen N3: a short name inside colour codes is not printed"] = function(t)
    local c = ns.make.fakeClient()
    c.print("|cff00ff00Al|r is here")
    local opts = named({ character = "Al" }, { shortNames = true, words = { "is here" } })
    local chat = section(seen(c, nil, opts), "chat")
    t.eq(chat, { "lines: 1", "  |<text:13> is here" })
    t.ok(not anyFinds(chat, "Al"), "the name is not in the line")
    local plain = section(seen(c, nil, named({ character = "Al" }, { shortNames = true })), "chat")
    t.ok(plain ~= nil and not anyFinds(plain, "Al"), "nor with the add-on's own words")
end

tests["seen N4: a relative path in a problem's text keeps only its file's name"] = function(t)
    t.eq(parts.paths("diag: ZFlow/Core/Diag.lua:120: attempt to index a nil value"),
        "diag: <path>/Diag.lua:120: attempt to index a nil value", "slashes")
    t.eq(parts.paths("diag: Tests\\x.lua:3: bad"), "diag: <path>/x.lua:3: bad", "a backslash")
    t.eq(parts.paths("diag: Zzyxowner/src/notes: bad"), "diag: <path> bad", "no file's name: the whole word goes")
    t.eq(parts.paths("diag: Zzyxowner/x.lua:3:Zzyxowner bad"), "diag: <path> bad", "more after the file: the whole word goes")
end

-- ------------------------------------------ the desk check of format 3
-- Six findings, a test each (items 1 to 5; 6 is THE LIMITS' text). Every
-- name, word and folder here is made up.

-- Item 1. "%%" is a literal percent: it goes before the specifiers, and a
-- specifier ends at a conversion letter, so no cut word joins the list.
tests["seen words: a literal percent goes before the specifiers, and no cut word is kept"] = function(t)
    local src = 'local a = "%d%% what" .. "%d%% durability" .. "% of yours" .. "%5.1f%% done"'
    local W = parts.wordSet(parts.literals(src))
    for _, word in ipairs({ "what", "durability", "of", "yours", "done" }) do
        t.eq(W[word], true, word .. " is a word of a literal")
    end
    for _, word in ipairs({ "hat", "urability", "f", "d" }) do
        t.eq(W[word], nil, word .. " is a cut word, not the add-on's")
    end
end

-- Item 2. A backslash before CR LF continues the string over both bytes:
-- the code after it is not read as a literal.
tests["seen words: a backslash before CR LF continues the string over both bytes"] = function(t)
    local src = 'local x = "Zzone\\\r\nZztwo" .. Zzcode .. "Zzthree"\n'
    local lits = parts.literals(src)
    t.eq(#lits, 2, "two literals")
    t.eq(lits[2], "Zzthree")
    local W = parts.wordSet(lits)
    t.eq(W.Zzone, true); t.eq(W.Zztwo, true); t.eq(W.Zzthree, true)
    t.eq(W.Zzcode, nil, "code is not a literal's word")
end

-- Item 3. A known name with an add-on word in it ("Made") is replaced on
-- the raw text, before the template could cut it at a slot's edge; the
-- placeholders pass the template as they are.
tests["seen names: a known name split by a kept word is replaced whole, before the template"] = function(t)
    local c = ns.make.fakeClient()
    c.print("at Quell Made")
    c.print("Quell-Made at")
    local text, lines = seen(c, nil, named({ character = "Zzyxmade", realm = "Quell Made" }, { words = { "at Made" } }))
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    local chat = section(text, "chat")
    t.eq(chat, { "lines: 2", "  at <realm>", "  <realm> at" })
    t.ok(not anyFinds(chat, "Made"), "no piece of the name: " .. table.concat(chat or {}, " / "))
    t.eq(parts.template("Zzyx <character> of <realm>", parts.wordSet({ "of" })), "<text:4> <character> of <realm>",
        "a placeholder is neither slotted nor rewritten")
    local c2 = ns.make.fakeClient()
    c2.print("<realm> says")
    local typed = section(seen(c2, nil, { madeUp = true, words = { "says" } }), "chat")
    t.ok(typed ~= nil and not anyFinds(typed, "<realm>"), "a typed placeholder is not one: "
        .. table.concat(typed or {}, " / "))
end

-- Item 4. The repo's folder is the one the runner was given (-Root), not
-- only where this file lies. No second tree is made on disk: a made-up
-- folder handed in is read (and fails), which the file's own folder would
-- not.
tests["seen words: the repo folder is the runner's root"] = function(t)
    t.ok(type(parts.RUN_ROOT) == "string" and #parts.RUN_ROOT > 0, "the runner handed its root in")
    local own = parts.RUN_ROOT
    parts.RUN_ROOT = "Zzmissing-root-folder"
    local W, why = parts.words()
    parts.RUN_ROOT = own
    t.eq(W, nil, "the words were looked for under the root handed in")
    t.ok(type(why) == "string" and why:find("manifest", 1, true) ~= nil, "the reason: " .. tostring(why))
    t.ok(not tostring(why):find("Zzmissing", 1, true), "and it names no path")
    t.ok(type((parts.words())) == "table", "the runner's root again: the words are read")
end

-- Item 5. A GUID part of 3 is a name (a realm id), replaced as a whole
-- number and never inside another; guid is a kind real state must have
-- known or marked absent.
tests["seen names: a 3-digit realm id of the GUID is replaced whole, never inside another number"] = function(t)
    t.eq(parts.MUST, { "character", "realm", "guild", "account", "guid" })
    local c = ns.make.fakeClient()
    c.setGuid("player", "Player-349-0ABCDEF1")
    c.print("realm 349, at 0.349, 1349 and 3490, (349)")
    c.print("guid Player-349-0ABCDEF1")
    local opts = named({ character = "Zzyxmade" }, { words = { "realm at and guid" } }, { "guid" })
    local text, lines = seen(c, nil, opts)
    t.ok(type(text) == "string", "a text came back: " .. tostring(lines))
    t.eq(section(text, "chat"), { "lines: 2", "  realm <guid>, at 0.349, 1349 and 3490, (<guid>)", "  guid <guid>" })
    t.eq(type(lines) == "table" and lines[2], "names: character, guid known; realm, guild, account absent; none not known")

    local names = parts.names(c, nil, { character = "Zzyxmade" }) or {}
    t.eq(parts.held("  id 349.", names), true, "the whole number")
    t.eq(parts.held("  at 0.349, 349.5 and 13490", names), false, "not inside another number")

    local bare = ns.make.fakeClient()
    bare.print("a line")
    t.eq(seen(bare, nil, { names = { character = "Zzyxmade" }, absent = { "realm", "guild", "account" } }), nil,
        "guid neither known nor marked absent: refused")
end

-- Section 217, MyBuddy's N4 rest 1 and 2: after "Users" or "home" the next
-- part of a path is a name, whatever it holds, up to the next separator,
-- ": " or the end. Every name here is made up.
tests["seen paths N4: the part after Users or home goes whole, an apostrophe or a dot in it too"] = function(t)
    local function gone(text, want, why)
        local got = parts.paths(text)
        t.eq(got, want, why)
        local low = tostring(got):lower()
        t.ok(not low:find("zzyx", 1, true) and not low:find("owner", 1, true) and not low:find("'", 1, true),
            "nothing of the name is left: " .. tostring(got))
    end
    gone("chat: cannot open C:\\Users\\O'Zzyx: Permission denied", "chat: cannot open <path>/: Permission denied",
        "rest 1: an apostrophe in the user's folder")
    gone("chat: cannot open C:\\Users\\zzyx.owner: denied", "chat: cannot open <path>/: denied",
        "rest 2: a dot in the user's folder, which looks like a file's name")
    gone("chat: cannot open /home/zzyx.owner: denied", "chat: cannot open <path>/: denied", "home, a dot")
    gone("chat: cannot open D:/USERS/Zzyx.Owner", "chat: cannot open <path>/", "Users in any case, at the end")
    gone("diag: D:/Users/O'Zzyx Owner/x.lua:3: bad", "diag: <path>/x.lua:3: bad", "a file below it keeps its name")
end

-- Section 217, MyBuddy's N2 gap: with no add-on and no name read answered,
-- that the state is made up cannot be shown; and no refusal text offers the
-- made-up flag as a way round it.
tests["seen N2: made up that cannot be shown says not known; refusals do not offer the flag"] = function(t)
    local lines = select(2, seen(ns.make.fakeClient(), nil, MADE_UP))
    t.eq(type(lines) == "table" and lines[2], UNPROVEN_LINE, "no add-on, no name read answered")
    local blank = ns.make.fakeClient({ env = { UnitName = function() return nil end } })
    lines = select(2, seen(blank, nil, MADE_UP))
    t.eq(type(lines) == "table" and lines[2], MADE_LINE, "the name read answered no name: made up is shown")
    local c = ns.make.fakeClient()
    local _, why = seen(c, nil, { names = { character = "Zzyxmade" } })
    t.ok(type(why) == "string", "refused: kinds not known or absent")
    t.ok(not tostring(why):find("madeUp", 1, true), "the refusal does not offer madeUp: " .. tostring(why))
    _, why = seen(c, nil, { names = { character = "Zzyxmade" }, absent = { "character" } })
    t.ok(type(why) == "string", "refused: character marked absent")
    t.ok(not tostring(why):find("madeUp", 1, true), "nor this one: " .. tostring(why))
end

-- Lead section 223, MyBuddy's SP-1, SP-2, SP-3, SP-5 on 7108f8b. Every
-- name here is made up.
local function noName(t, got, why)
    local low = tostring(got):lower()
    t.ok(not low:find("zzyx", 1, true) and not low:find("owner", 1, true), why .. ": no piece of the name: " .. tostring(got))
end

tests["seen paths SP-1: a home folder after a blank or a line break is a home folder too"] = function(t)
    local got = parts.paths("chat: cannot open home/zzyx.owner: denied")
    noName(t, got, "after a blank")
    t.ok(tostring(got):find("denied", 1, true) ~= nil, "the rest of the line stays")
    noName(t, parts.paths("chat: one\nUsers/zzyx.owner: denied"), "after a line break")
    noName(t, parts.paths("chat: one\tUsers/zzyx.owner: denied"), "after a tab")
end

tests["seen paths SP-2: Documents and Settings is a home folder"] = function(t)
    local got = parts.paths("diag: C:\\Documents and Settings\\zzyx.owner: denied")
    noName(t, got, "Documents and Settings")
    t.eq(got, "diag: <path>/: denied")
end

tests["seen paths SP-3: a tab or a double quote ends the name; the rest of the line stays"] = function(t)
    local got = parts.paths("chat: cannot open /home/zzyx\tthen more")
    noName(t, got, "a tab")
    t.ok(tostring(got):find("then more", 1, true) ~= nil, "what follows the tab stays: " .. tostring(got))
    got = parts.paths('chat: open "/home/zzyx" failed')
    noName(t, got, "a double quote")
    t.ok(tostring(got):find("failed", 1, true) ~= nil, "what follows the quote stays: " .. tostring(got))
end

tests["seen SP-5: an add-on table with no kept snapshot does not show made up"] = function(t)
    local lines = select(2, seen(ns.make.fakeClient(), {}, MADE_UP))
    t.eq(type(lines) == "table" and lines[2], UNPROVEN_LINE, "an empty add-on table: not known")
    lines = select(2, seen(ns.make.fakeClient(), { id = { accountDB = "ZzSeenNoSnapsDB" } }, MADE_UP))
    t.eq(type(lines) == "table" and lines[2], UNPROVEN_LINE, "an add-on with no saved table: not known")
    local c = ns.make.fakeClient()
    c.setSaved("ZzSeenSnapsDB", { diag = { snaps = { { timing = {} } } } })
    lines = select(2, seen(c, { id = { accountDB = "ZzSeenSnapsDB" } }, MADE_UP))
    t.eq(type(lines) == "table" and lines[2], MADE_LINE, "a kept snapshot with no character: made up is shown")
end

return tests
