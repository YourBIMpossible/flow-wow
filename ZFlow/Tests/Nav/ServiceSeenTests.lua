-- Tests for ZFlow/Nav/ServiceSeen.lua (G37): the recorder over the fake
-- client. The npc read and the repair read are not in the fake yet, so
-- they are set on it here. Made-up npcs, test only. Not tested in game.
local _, ns = ...

local S = ns.ServiceSeen
local N = ns.Nav
local tests = {}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

local VENDOR = { guid = "Creature-0-1-2-3-54-0", name = "Kaita Deepforge" }

-- opts: char (saved table), date (false: the client will not say), npc
-- (what serviceNpc() answers; false for no such read), repair.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if opts.date ~= false then c.setClock(opts.date or 5000) end
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.25)
    local held = { npc = opts.npc, repair = opts.repair }
    if opts.npc ~= false then c.serviceNpc = function() return held.npc end end
    c.merchantRepairs = function() return held.repair end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local w = S.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, w, held
end

local function places(c)
    local root = c.saved(ns.id.charDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.places or nil
    return type(root) == "table" and root.services or nil
end

local function char(c)
    local out = copy(c.saved(ns.id.charDB))
    if type(out) == "table" then out.diag = nil end
    return out
end

tests["service seen: the names are the ones agreed"] = function(t)
    t.eq(S.NAME, "serviceSeen")
    t.eq(S.PLACES, "learned.places.services")
    t.eq(S.PLACES, N.SERVICES, "the recorder writes where the reader reads")
    local kinds = {}
    for _, row in ipairs(S.EVENTS) do kinds[row.event] = row.kind end
    t.eq(kinds, { MERCHANT_SHOW = "vendor", BANKFRAME_OPENED = "banker", TAXIMAP_OPENED = "flight",
                  CONFIRM_BINDER = "innkeeper", MAIL_SHOW = "mailbox", AUCTION_HOUSE_SHOW = "auction" })
end

tests["service seen: before any event nothing is saved"] = function(t)
    local k, c, w = start({ npc = VENDOR })
    t.eq(places(c), nil)
    t.eq(w.last(), nil)
    t.eq(k.problems:count(), 0)
end

tests["service seen: a merchant window saves a vendor where the player stands"] = function(t)
    local k, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c), { [VENDOR.guid] = {
        guid = VENDOR.guid, name = "Kaita Deepforge", map = 1411, x = 0.5, y = 0.25,
        kinds = { vendor = true }, seen = 5000, n = 1,
    } })
    t.eq(w.last(), { kind = "service", service = "vendor", ok = true, key = VENDOR.guid,
                     name = "Kaita Deepforge" })
    t.eq(k.problems:count(), 0)
end

tests["service seen: a vendor that sold a trade good is marked trade"] = function(t)
    local _, c = start({ npc = VENDOR })
    c.setItemInfo({ [2318] = { name = "Test Leather", classID = 7 }, [2319] = { name = "Test Hat", classID = 4 } })
    c.setMerchant({ { item = "item:2319", price = 60, stack = 1 } })
    c.setMerchantOpen(true)
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].trade, nil, "a hat is not a trade good")
    c.setMerchant({ { item = "item:2319", price = 60, stack = 1 }, { item = "item:2318", price = 15, stack = 1 } })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].trade, true)
    -- The wares are not read (the window is shut): the mark stays.
    c.setMerchantOpen(false)
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].trade, true)
    -- Read again with no trade good: the mark goes.
    c.setMerchant({ { item = "item:2319", price = 60, stack = 1 } })
    c.setMerchantOpen(true)
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].trade, nil)
end

tests["service seen: saved for the character, not the account"] = function(t)
    local _, c = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    local account = c.saved(ns.id.accountDB)
    -- The store's skeleton always makes account.learned; nothing of the
    -- places may land in it.
    local learned = type(account) == "table" and account.learned or nil
    t.eq(type(learned) == "table" and learned.places or nil, nil)
end

tests["service seen: a merchant that repairs is a repair vendor too"] = function(t)
    local _, c, w = start({ npc = VENDOR, repair = true })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].kinds, { vendor = true, repair = true })
    t.eq(w.last().repair, true)
end

tests["service seen: a plain no takes the repair mark off, no answer leaves it"] = function(t)
    local _, c, _, held = start({ npc = VENDOR, repair = true })
    c.fire("MERCHANT_SHOW")
    held.repair = nil
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].kinds, { vendor = true, repair = true }, "no answer is not a no")
    held.repair = "yes"
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].kinds.repair, true, "anything but true or false is no answer")
    held.repair = false
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].kinds, { vendor = true })
end

tests["service seen: each window names its kind"] = function(t)
    local _, c, _, held = start({})
    local seen = {
        { "BANKFRAME_OPENED", "banker", "Banker Olivia" },
        { "TAXIMAP_OPENED", "flight", "Dungar Longdrink" },
        { "CONFIRM_BINDER", "innkeeper", "Innkeeper Allison" },
    }
    for _, row in ipairs(seen) do
        held.npc = { name = row[3] }
        c.fire(row[1])
        t.eq(places(c)[row[3]].kinds, { [row[2]] = true }, row[1])
    end
end

tests["service seen: one npc seen in two ways keeps both kinds"] = function(t)
    local _, c = start({ npc = { guid = "Creature-0-1-2-3-99-0", name = "Innkeeper Allison" } })
    c.fire("MERCHANT_SHOW")
    c.setPosition(1411, 0.52, 0.25)
    c.fire("CONFIRM_BINDER")
    local e = places(c)["Creature-0-1-2-3-99-0"]
    t.eq(e.kinds, { vendor = true, innkeeper = true })
    t.eq(e.n, 2)
    t.eq(e.x, 0.52, "the place is where the player last stood")
end

tests["service seen: with no guid the name is the key"] = function(t)
    local _, c, w = start({ npc = { name = "Banker Olivia" } })
    c.fire("BANKFRAME_OPENED")
    local e = places(c)["Banker Olivia"]
    t.eq(e.name, "Banker Olivia")
    t.eq(e.guid, nil)
    t.eq(w.last().key, "Banker Olivia")
end

tests["service seen: a name with a dot in it is one key, not a path"] = function(t)
    local _, c = start({ npc = { name = "Mr. Smite" } })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)["Mr. Smite"].kinds, { vendor = true })
end

tests["service seen: a guid with no name is saved without a name"] = function(t)
    local _, c = start({ npc = { guid = "Creature-0-1-2-3-7-0" } })
    c.fire("TAXIMAP_OPENED")
    local e = places(c)["Creature-0-1-2-3-7-0"]
    t.eq(e.name, nil)
    t.eq(e.kinds, { flight = true })
end

tests["service seen: an npc that is not known writes nothing"] = function(t)
    for _, npc in ipairs({ "nil", "empty", "blank", "junk" }) do
        local answers = { empty = {}, blank = { guid = "", name = "" }, junk = "junk" }
        local k, c, w = start({ npc = answers[npc] })
        local before = char(c)
        c.fire("MERCHANT_SHOW")
        t.eq(char(c), before, npc)
        t.eq(w.last().ok, false, npc)
        t.eq(w.last().reason, "the npc is not known", npc)
        t.eq(k.problems:count(), 0, npc)
    end
end

tests["service seen: a client with no npc read writes nothing"] = function(t)
    local _, c, w = start({ npc = false })
    c.fire("BANKFRAME_OPENED")
    t.eq(places(c), nil)
    t.eq(w.last().reason, "the npc is not known")
end

tests["service seen: with no position nothing is written"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.setPosition(nil)
    local before = char(c)
    c.fire("MERCHANT_SHOW")
    c.fire("MAIL_SHOW")
    t.eq(char(c), before)
    t.eq(w.last().reason, "the position is not known")
end

tests["service seen: a mailbox needs no npc and is keyed by its place"] = function(t)
    local _, c, w = start({ npc = false })
    c.fire("MAIL_SHOW")
    t.eq(places(c), { ["mailbox:1411:50:25"] = {
        map = 1411, x = 0.5, y = 0.25, kinds = { mailbox = true }, seen = 5000, n = 1,
    } })
    t.eq(w.last().key, "mailbox:1411:50:25")
end

tests["service seen: the same mailbox again is one entry, another box is another"] = function(t)
    local _, c = start({})
    c.fire("MAIL_SHOW")
    c.setPosition(1411, 0.502, 0.251)
    c.fire("MAIL_SHOW")
    t.eq(places(c)["mailbox:1411:50:25"].n, 2)
    c.setPosition(1411, 0.7, 0.25)
    c.fire("MAIL_SHOW")
    t.eq(places(c)["mailbox:1411:70:25"].n, 1)
end

tests["service seen: a second sighting counts, moves and re-dates the entry"] = function(t)
    local _, c = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    c.setClock(6000)
    c.setPosition(1411, 0.6, 0.3)
    c.fire("MERCHANT_SHOW")
    local e = places(c)[VENDOR.guid]
    t.eq(e.n, 2)
    t.eq(e.seen, 6000)
    t.eq({ e.map, e.x, e.y }, { 1411, 0.6, 0.3 })
end

tests["service seen: with no clock a saved date stays and a new entry has none"] = function(t)
    local _, c, _, held = start({ npc = VENDOR, date = false, char = { learned = { places = { services = {
        [VENDOR.guid] = { name = "Kaita Deepforge", map = 1411, x = 0.1, y = 0.1, kinds = { vendor = true },
                          seen = 4000, n = 2 },
    } } } } })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].seen, 4000)
    t.eq(places(c)[VENDOR.guid].n, 3)
    held.npc = { name = "Banker Olivia" }
    c.fire("BANKFRAME_OPENED")
    t.eq(places(c)["Banker Olivia"].seen, nil)
end

tests["service seen: what else is on an entry is kept"] = function(t)
    local _, c = start({ npc = VENDOR, char = { learned = { places = { services = {
        [VENDOR.guid] = { note = "kept", kinds = { banker = true }, n = "junk" },
    } } } } })
    c.fire("MERCHANT_SHOW")
    local e = places(c)[VENDOR.guid]
    t.eq(e.note, "kept")
    t.eq(e.kinds, { banker = true, vendor = true })
    t.eq(e.n, 1, "a count that is not a number starts again")
end

tests["service seen: a store that refuses the write is left unchanged"] = function(t)
    local k, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    local before = char(c)
    k.store.blocked.char = "refused in a test"
    c.setPosition(1411, 0.9, 0.9)
    c.fire("MERCHANT_SHOW")
    c.fire("MAIL_SHOW")
    t.eq(char(c), before)
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the places cannot be saved")
    k.store.blocked.char = nil
    c.fire("MAIL_SHOW")
    t.eq(w.last().ok, true)
end

tests["service seen: saved places that are not a table are not written over"] = function(t)
    local _, c, w = start({ npc = VENDOR, char = { learned = { places = { services = "junk" } } } })
    c.fire("MERCHANT_SHOW")
    t.eq(places(c), "junk")
    t.eq(w.last().reason, "the places cannot be saved")
end

tests["service seen: past the cap a new place is not written, a known one still is"] = function(t)
    local rows = {}
    for i = 1, S.MAX - 1 do
        rows["npc " .. i] = { map = 1, x = 0.5, y = 0.5, kinds = { vendor = true }, n = 1 }
    end
    local _, c, w, held = start({ npc = VENDOR, char = { learned = { places = { services = rows } } } })
    c.fire("MERCHANT_SHOW")
    t.eq(w.last().ok, true, "the last free place")
    held.npc = { name = "One Too Many" }
    c.fire("MERCHANT_SHOW")
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the list of places is full")
    t.eq(places(c)["One Too Many"], nil)
    held.npc = VENDOR
    c.fire("MERCHANT_SHOW")
    t.eq(w.last().ok, true)
    t.eq(places(c)[VENDOR.guid].n, 2)
end

tests["service seen: what it saves is what the nearest read finds"] = function(t)
    local k, c = start({ npc = VENDOR, repair = true })
    c.setMapSize(1411, 1000, 500)
    c.fire("MERCHANT_SHOW")
    c.setPosition(1411, 0.5, 0.45)
    local got = N.Nearest("repair", c, k.store)
    t.eq(got.name, "Kaita Deepforge")
    t.eq(got.guid, VENDOR.guid)
    t.eq(got.yards, 100)
    t.eq(N.Nearest("banker", c, k.store), nil)
end

tests["service seen: the pure read, by hand"] = function(t)
    local saved = { char = {} }
    local store = {}
    function store:get(scope, path) return saved[scope][path] end
    function store:set(scope, path, value)
        saved[scope][path] = value
        return true
    end
    local client = {
        clock = function() return 42 end,
        serviceNpc = function() return { name = "Dungar Longdrink" } end,
        position = function() return { map = 1453, x = 0.25, y = 0.75 } end,
    }
    local report = S.Seen("flight", client, store)
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(saved.char[S.PLACES]["Dungar Longdrink"],
        { name = "Dungar Longdrink", map = 1453, x = 0.25, y = 0.75, kinds = { flight = true }, seen = 42, n = 1 })
    t.eq(S.Seen("repair", client, store).ok, false, "repair is read off a vendor, never seen alone")
    t.eq(S.Seen("trainer", client, store).reason, "not a kind of service")
    t.eq(S.Seen("flight", nil, store).ok, false)
    t.eq(S.Seen("flight", client, nil).ok, false)
    t.eq(S.Seen("flight", {}, store).ok, false)
end

-- Moved places (G37, lead section 395 item 8). NEAR is a share of the map:
-- a sighting closer than that to the saved spot is the same spot.
tests["service seen: the near distance is a small share of the map"] = function(t)
    t.eq(S.NEAR, 0.01)
end

tests["service seen: the first visit is not a move"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    t.eq(w.last().moved, nil)
    t.eq(places(c)[VENDOR.guid].x, 0.5)
end

tests["service seen: the same npc met far away moves its one entry"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    c.setPosition(1411, 0.8, 0.6)
    c.fire("MERCHANT_SHOW")
    local n = 0
    for _ in pairs(places(c)) do n = n + 1 end
    t.eq(n, 1, "one entry, no copy")
    local e = places(c)[VENDOR.guid]
    t.eq({ e.map, e.x, e.y, e.n }, { 1411, 0.8, 0.6, 2 })
    t.eq(w.last().moved, true)
end

tests["service seen: the same npc met on another map moves too"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    c.setPosition(1429, 0.5, 0.25)
    c.fire("MERCHANT_SHOW")
    t.eq(places(c)[VENDOR.guid].map, 1429)
    t.eq(w.last().moved, true)
end

tests["service seen: a small step beside the npc keeps the saved spot"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    c.setPosition(1411, 0.504, 0.253)
    c.fire("MERCHANT_SHOW")
    local e = places(c)[VENDOR.guid]
    t.eq({ e.x, e.y, e.n }, { 0.5, 0.25, 2 })
    t.eq(w.last().moved, false)
end

tests["service seen: an old entry with no place takes the new one"] = function(t)
    local _, c, w = start({ npc = VENDOR, char = { learned = { places = { services = {
        [VENDOR.guid] = { name = "Kaita Deepforge", kinds = { vendor = true }, n = 1 },
    } } } } })
    c.fire("MERCHANT_SHOW")
    local e = places(c)[VENDOR.guid]
    t.eq({ e.map, e.x, e.y, e.n }, { 1411, 0.5, 0.25, 2 })
    t.eq(w.last().moved, true)
end

tests["service seen: an unknown place on a known npc changes nothing"] = function(t)
    local _, c, w = start({ npc = VENDOR })
    c.fire("MERCHANT_SHOW")
    local before = copy(places(c))
    c.setPosition(nil)
    c.fire("MERCHANT_SHOW")
    t.eq(places(c), before)
    t.eq(w.last().ok, false)
end

tests["service seen: a mailbox met from its other side is the same one entry"] = function(t)
    local _, c, w = start({})
    c.setPosition(1411, 0.504, 0.25)
    c.fire("MAIL_SHOW")
    c.setPosition(1411, 0.507, 0.252)
    c.fire("MAIL_SHOW")
    local keys = {}
    for key in pairs(places(c)) do keys[#keys + 1] = key end
    t.eq(keys, { "mailbox:1411:50:25" }, "one box, though the spots round apart")
    local e = places(c)["mailbox:1411:50:25"]
    t.eq({ e.x, e.y, e.n }, { 0.504, 0.25, 2 })
    t.eq(w.last().moved, false)
    t.eq(w.last().key, "mailbox:1411:50:25")
end

tests["service seen: a mailbox far from a saved one is another box"] = function(t)
    local _, c = start({})
    c.fire("MAIL_SHOW")
    c.setPosition(1411, 0.53, 0.25)
    c.fire("MAIL_SHOW")
    t.eq(places(c)["mailbox:1411:50:25"].n, 1)
    t.eq(places(c)["mailbox:1411:53:25"].n, 1)
end

tests["service seen: a mailbox with no place is not saved"] = function(t)
    local _, c, w = start({})
    c.setPosition(nil)
    c.fire("MAIL_SHOW")
    t.eq(places(c), nil)
    t.eq(w.last().reason, "the position is not known")
end

return tests
