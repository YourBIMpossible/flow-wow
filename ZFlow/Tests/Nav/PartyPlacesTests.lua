local _, ns = ...

-- Tests for ZFlow/Nav/PartyPlaces.lua (FLOW-PARITY A2-29, lead section
-- 831.2): places the player learned in game (char learned.places.services)
-- go to party members as add-on data; places received land in their own
-- store (account learned.places.party), never in the player's own. Pure
-- encode and decode, then the module on a fake client. Made-up npcs and
-- names. Not tested in game.

local tests = {}

local function PL() return ns.Nav.PartyPlaces end

local function services()
    return {
        ["Creature-0-1-2-3-54-0"] = { guid = "Creature-0-1-2-3-54-0", name = "Kaita Deepforge",
            map = 1429, x = 0.4167, y = 0.6543, kinds = { vendor = true, repair = true }, n = 1 },
        ["Bero Lake"] = { name = "Bero Lake", map = 1429, x = 0.5, y = 0.25, kinds = { flight = true }, n = 2 },
    }
end

tests["party places: encode and decode give the same places back"] = function(t)
    local rows = PL().Mine(services())
    t.eq(#rows, 2)
    local msgs = PL().Encode(rows, 1)
    t.eq(msgs and #msgs, 1)
    local d, why = PL().Decode(msgs and msgs[1], 1)
    t.ok(d ~= nil, tostring(why))
    t.eq(d and d.seq, 1)
    t.eq(d and #d.places, 2)
    local byName = {}
    for _, p in ipairs(d and d.places or {}) do byName[p.name] = p end
    local k = byName["Kaita Deepforge"]
    t.eq(k and k.id, 54)
    t.eq(k and k.map, 1429)
    t.near(k and k.x or -1, 0.4167, 0.0001)
    t.eq(k and k.roles, { repair = true, vendor = true })
    t.eq(byName["Bero Lake"] and byName["Bero Lake"].id, 0)
end

tests["party places: many places split into messages that each fit"] = function(t)
    local s = {}
    for i = 1, 30 do
        s["Npc" .. i] = { name = "Somebody With A Long Name " .. i, map = 1429, x = 0.1, y = 0.2, kinds = { vendor = true } }
    end
    local msgs = PL().Encode(PL().Mine(s), 1)
    t.ok(#msgs > 1, "more than one message")
    t.ok(#msgs <= PL().MAX_PARTS, "capped parts")
    for i, m in ipairs(msgs) do
        t.ok(#m <= PL().MAX_BYTES, "message " .. i .. " is " .. #m .. " bytes")
        t.ok(PL().Decode(m, 1) ~= nil, "message " .. i .. " decodes")
    end
end

tests["party places: malformed messages do not decode"] = function(t)
    local bad = { "", "hello", "1|L", "1|L|1|1", "2|L|1|1|54,1429,4167,6543,vendor,Kaita",
        "1|X|1|1|54,1429,4167,6543,vendor,Kaita", "1|L|0|1|54,1429,4167,6543,vendor,Kaita",
        "1|L|2|1|54,1429,4167,6543,vendor,Kaita", "1|L|1|1|x,1429,4167,6543,vendor,Kaita",
        "1|L|1|1|54,-1,4167,6543,vendor,Kaita", "1|L|1|1|54,1429,10001,6543,vendor,Kaita",
        "1|L|1|1|54,1429,4167.5,6543,vendor,Kaita", "1|L|1|1|54,1429,4167,6543,quest,Kaita",
        "1|L|1|1|54,1429,4167,6543,,Kaita", "1|L|1|1|54,1429,4167,6543,vendor,",
        "1|L|1|1|54,1429,4167,6543,vendor,Ka%sita", "1|L|1|1|54,1429,4167,6543,vendor,Ka\1ta",
        "1|L|1|1|54,1429,4167,6543,vendor", "1|L|1|1|54,1429,4167,6543,vendor,Kaita,extra",
        "1|L|1|1|" .. string.rep("5", 20) .. ",1429,1,1,vendor,K",
        "1|L|1|1|54,1429,4167,6543,vendor," .. string.rep("K", 60),
        "1|L|1|1|" .. string.rep("54,1429,1,1,vendor,K~", 13) .. "54,1429,1,1,vendor,K",
        string.rep("1", 300) }
    for _, m in ipairs(bad) do
        t.eq(PL().Decode(m, 1), nil, m)
    end
    t.eq(PL().Decode(nil, 1), nil)
end

tests["party places: nothing but the allowed service roles is ever encoded"] = function(t)
    local s = services()
    s["Quest Giver"] = { name = "Quest Giver", map = 1429, x = 0.3, y = 0.3, kinds = { quest = true, questie = true } }
    s["Mixed"] = { name = "Mixed", map = 1429, x = 0.3, y = 0.3, kinds = { vendor = true, quest = true } }
    s["Bad|Name"] = { name = "Bad|Name", map = 1429, x = 0.3, y = 0.3, kinds = { vendor = true } }
    local msgs = PL().Encode(PL().Mine(s), 1)
    local all = table.concat(msgs, "\n")
    t.eq(all:find("Quest Giver", 1, true), nil)
    t.eq(all:find("quest", 1, true), nil)
    t.eq(all:find("Bad", 1, true), nil)
    t.ok(all:find("Mixed", 1, true) ~= nil, "the vendor half is kept")
end

-- opts.party (false: alone), opts.on (true: the setting turned on),
-- opts.char, opts.account: saved tables.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or { learned = { places = { services = services() } } })
    if opts.questie then
        c.setQuestieModule("QuestieDB", { npcData = { [99] = { "Questie Npc", map = 1429, x = 0.5, y = 0.5 } } })
    end
    c.setPlayerName("Ann")
    c.setAddonName("Ann")
    if opts.party ~= false then
        c.setGrouped(true)
        c.setParty(opts.party or { { unit = "party1", name = "Bob" } })
    else
        c.setGrouped(false)
        c.setParty({})
    end
    local k = ns.Kernel({}, c)
    PL().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.on == true then k.settings:set(PL().SETTING, true) end
    return k, c
end

local function sent(c)
    local out = {}
    for _, m in ipairs(c.addonSent) do
        if m.prefix == PL().Prefix() then out[#out + 1] = m end
    end
    return out
end

local function shared(c)
    local root = c.saved(ns.id.accountDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.places or nil
    return type(root) == "table" and root.party or nil
end

local function bobMessage()
    local s = { x = { name = "Gruff Ironhand", guid = "Creature-0-1-2-3-77-0", map = 1426, x = 0.25, y = 0.75,
        kinds = { banker = true } } }
    return PL().Encode(PL().Mine(s), ns.id.commVersion)[1]
end

tests["party places: the setting is off by default; off sends and keeps nothing"] = function(t)
    local k, c = start()
    t.eq(k.settings:get(PL().SETTING), false)
    t.ok(PL().Prefix() ~= ns.id.commPrefix .. "P", "its own prefix")
    c.advance(PL().EVERY + 1)
    t.eq(#sent(c), 0)
    c.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Bob")
    t.eq(shared(c), nil)
end

tests["party places: sent on the party channel when on and in a party"] = function(t)
    local _, c = start({ on = true })
    c.advance(PL().EVERY + 1)
    local s = sent(c)
    t.eq(#s, 1)
    t.eq(s[1] and s[1].channel, "PARTY")
end

tests["party places: nothing is sent outside a party or in a raid"] = function(t)
    local _, c = start({ on = true, party = false })
    c.advance(PL().EVERY + 1)
    t.eq(#c.addonSent, 0)
    local _, r = start({ on = true, party = { { unit = "raid1", name = "Bob" } } })
    r.advance(PL().EVERY + 1)
    t.eq(#r.addonSent, 0)
end

tests["party places: throttled, and only new or changed places are sent again"] = function(t)
    local _, c = start({ on = true })
    c.advance(PL().EVERY + 1)
    t.eq(#sent(c), 1)
    c.advance(PL().EVERY + 1)
    t.eq(#sent(c), 1, "nothing changed")
    local char = c.saved(ns.id.charDB)
    char.learned.places.services["New Inn"] = { name = "New Inn", map = 1429, x = 0.6, y = 0.6, kinds = { innkeeper = true } }
    c.advance(1)
    t.eq(#sent(c), 1, "waits for the throttle")
    c.advance(PL().EVERY + 1)
    local s = sent(c)
    t.eq(#s, 2)
    local d = PL().Decode(s[2] and s[2].text, ns.id.commVersion)
    t.eq(d and #d.places, 1, "only the new place")
    t.eq(d and d.places[1] and d.places[1].name, "New Inn")
end

tests["party places: a new member gets everything again"] = function(t)
    local _, c = start({ on = true })
    c.advance(PL().EVERY + 1)
    t.eq(#sent(c), 1)
    c.setParty({ { unit = "party1", name = "Bob" }, { unit = "party2", name = "Cid" } })
    c.fire("GROUP_ROSTER_UPDATE")
    c.advance(PL().EVERY + 1)
    local s = sent(c)
    t.eq(#s, 2)
    local d = PL().Decode(s[2] and s[2].text, ns.id.commVersion)
    t.eq(d and #d.places, 2)
end

tests["party places: a member's places land in the shared store, marked, never in the player's own"] = function(t)
    local k, c = start({ on = true, account = { learned = { places = { npcs = { Own = { map = 1, x = 0.1, y = 0.1 } } } } } })
    local before = c.saved(ns.id.charDB).learned.places.services["Bero Lake"].x
    c.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Bob-Realm")
    local got = shared(c)
    t.ok(type(got) == "table", "a shared store")
    local e
    for _, v in pairs(got or {}) do e = v end
    t.eq(e and e.name, "Gruff Ironhand")
    t.eq(e and e.from, "Bob")
    t.eq(e and e.source, "party")
    t.eq(e and e.kinds, { banker = true })
    t.eq(c.saved(ns.id.charDB).learned.places.services["Gruff Ironhand"], nil)
    t.eq(c.saved(ns.id.charDB).learned.places.services["Bero Lake"].x, before)
    t.eq(c.saved(ns.id.accountDB).learned.places.npcs["Gruff Ironhand"], nil)
    t.ok(k.use(PL().NAME).Shared() ~= nil, "Shared() reads it")
end

tests["party places: own echo, non-members, wrong channel or prefix and malformed text are ignored"] = function(t)
    local _, c = start({ on = true })
    c.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Ann")
    c.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Zed")
    c.addonDeliver(PL().Prefix(), bobMessage(), "GUILD", "Bob")
    c.addonDeliver(PL().Prefix(), bobMessage(), "WHISPER", "Bob")
    c.addonDeliver(ns.id.commPrefix .. "P", bobMessage(), "PARTY", "Bob")
    c.addonDeliver(PL().Prefix(), "1|L|1|1|nonsense", "PARTY", "Bob")
    t.eq(shared(c), nil)
end

tests["party places: nothing from quest spots or Questie is ever sent"] = function(t)
    local _, c = start({ on = true, account = { learned = { places = {
        questSpots = { [123] = { map = 1429, x = 0.5, y = 0.5, name = "Quest Spot" } },
        npcs = { ["Imported Npc"] = { id = 88, map = 1429, x = 0.2, y = 0.2, roles = { vendor = true } } } } } },
        questie = true })
    c.advance(PL().EVERY + 1)
    local all = {}
    for _, m in ipairs(c.addonSent) do all[#all + 1] = m.text end
    all = table.concat(all, "\n")
    t.ok(all ~= "", "something was sent")
    t.eq(all:find("Questie", 1, true), nil)
    t.eq(all:find("Quest Spot", 1, true), nil)
    t.eq(all:find("Imported", 1, true), nil)
end

-- Lead section 833: places are kept only from a member of the party the
-- client lists; alone or in a raid nothing is kept.
tests["party places: nothing is kept alone or in a raid"] = function(t)
    local _, c = start({ on = true, party = false })
    c.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Bob")
    t.eq(shared(c), nil, "alone")
    local _, r = start({ on = true, party = { { unit = "raid1", name = "Bob" } } })
    r.addonDeliver(PL().Prefix(), bobMessage(), "PARTY", "Bob")
    t.eq(shared(r), nil, "in a raid")
end

return tests
