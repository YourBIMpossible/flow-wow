-- Nearest repair / vendor / flight master / innkeeper / banker / auctioneer /
-- mailbox: sets Flow's own waypoint on the closest one. Right-click the
-- arrow ("Nearest repair", "Nearest vendor (sell)"), or /flow way repair |
-- vendor | flight | inn | bank | auction | mail.
--
-- Where they are: the ones you've used before (Places.lua learns each NPC
-- you talk to and what they do, for all your characters), plus Questie's NPC
-- data scanned once in the background for every NPC flagged for it. Only
-- NPCs friendly to your faction (a tauren could be sent to an Alliance vendor).

local _, ns = ...
local S = {}
ns.services = S

-- npcFlags bits. They differ between the game's versions, and until
-- 0.35.216 Flow used the later versions' numbers on WoW: Forever's data,
-- which has the first game's: every "flight master" from the data was a
-- stable master (Xon'cha in Orgrimmar, Seikwa in Bloodhoof Village: "only a
-- stable master, no flight path there"), every "vendor" an innkeeper, every
-- "repairer" an auctioneer. Now read from the quest data's own list
-- (QuestieDB.npcFlags), with the first game's numbers when it has none.
S.CLASSIC_FLAGS = { VENDOR = 4, FLIGHT_MASTER = 8, INNKEEPER = 128, BANKER = 256, AUCTIONEER = 4096, REPAIR = 16384 }
-- Pure: Flow's kinds from a data set's flag names.
function S.FlagsFrom(enum)
    enum = type(enum) == "table" and enum or {}
    local C = S.CLASSIC_FLAGS
    return { vendor = enum.VENDOR or C.VENDOR, repair = enum.REPAIR or C.REPAIR, flight = enum.FLIGHT_MASTER or C.FLIGHT_MASTER,
             inn = enum.INNKEEPER or C.INNKEEPER, bank = enum.BANKER or C.BANKER, auction = enum.AUCTIONEER or C.AUCTIONEER }
end
local FLAG = S.FlagsFrom(nil)
local band = bit and bit.band
local found = { vendor = {}, repair = {}, flight = {}, inn = {}, bank = {}, auction = {} }   -- { { name, spawns, faction } }
local scan                                         -- nil, "running", "done"
S.KINDS = { "repair", "vendor", "flight", "inn", "bank", "auction", "mail" }
local trainers = {}   -- [profession or "class:DRUID"] = { names }, from NPC titles

-- An NPC's title as a trainer key: "Cooking Trainer" -> "Cooking", "Druid
-- Trainer" -> "class:DRUID", anything else nil.
local PROFESSIONS = { Mining = true, Herbalism = true, Skinning = true, Blacksmithing = true, Engineering = true,
    Alchemy = true, Leatherworking = true, Tailoring = true, Enchanting = true, ["First Aid"] = true,
    Cooking = true, Fishing = true }
local CLASSES = { Warrior = true, Paladin = true, Hunter = true, Rogue = true, Priest = true, Shaman = true,
    Mage = true, Warlock = true, Druid = true }
function S.TrainerKey(subName)
    local what = type(subName) == "string" and subName:match("^(.-) Trainer$")
    if not what then return nil end
    if PROFESSIONS[what] then return what end
    if CLASSES[what] then return "class:" .. what:upper() end
end

-- Trainer names Questie gives that title (after the background pass).
function S:TrainerNames(key) return trainers[key] or {} end

-- One background pass over Questie's NPCs (a few hundred per frame, paused
-- in combat), keeping the ones that offer a service.
function S:Scan()
    if scan then return scan end
    local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
    if not (db and db.NPCPointers and band) then scan = "done" return scan end
    scan = "running"
    FLAG = S.FlagsFrom(db.npcFlags)
    ns:Log("places", string.format("NPC roles from the quest data: flight master = %s, vendor = %s, repair = %s (%s)", tostring(FLAG.flight),
        tostring(FLAG.vendor), tostring(FLAG.repair), db.npcFlags and "its own list" or "the first game's numbers"))
    local co = coroutine.create(function()
        local n = 0
        for id in pairs(db.NPCPointers) do
            local npc = ns.quests:QuestieGet("GetNPC", id)
            local flags = npc and tonumber(npc.npcFlags)
            if flags and npc.spawns and npc.name then
                for kind, bitv in pairs(FLAG) do
                    if band(flags, bitv) ~= 0 then
                        found[kind][#found[kind] + 1] = { name = npc.name, spawns = npc.spawns, faction = npc.friendlyToFaction }
                    end
                end
            end
            -- Trainers by their title ("Cooking Trainer", "Druid Trainer"):
            -- WoW: Forever adds its own (Pyall Silentstride, Bloodhoof's cook).
            local key = npc and npc.spawns and npc.name and S.TrainerKey(npc.subName)
            if key then
                trainers[key] = trainers[key] or {}
                table.insert(trainers[key], npc.name)
                ns.quests:RememberNPC(npc.name, id, npc.spawns, npc.friendlyToFaction)
            end
            n = n + 1
            if n % 300 == 0 then coroutine.yield() end
        end
    end)
    local function step()
        if InCombatLockdown() then C_Timer.After(1, step) return end
        local ok = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then C_Timer.After(0, step) else scan = "done" end
    end
    step()
    return scan
end

-- Nearest one of `kind` (S.KINDS) on your continent:
-- { name, map, x, y, yards, learned = "you" (you've used it) | "shared" (another
-- Flow player found it) | nil (Questie) } or nil.
function S:Nearest(kind)
    local nav = ns.nav
    local p = nav and nav:PlayerPos()
    if not p then return nil end
    local best
    local function consider(name, map, x, y, learned)
        local cont, wx, wy = nav:ToWorld(map, x, y)
        if cont == p.cont and wx then
            local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
            if not best or d < best.yards then best = { name = name, map = map, x = x, y = y, yards = d, learned = learned } end
        end
    end
    -- What you've learned yourself.
    for name, spot in pairs(ns.db.places or {}) do
        if spot.map and ns.places.HasRole(spot, kind) and not ns.places.NotRole(name, kind) then pcall(consider, name, spot.map, spot.x, spot.y, "you") end
    end
    if kind == "mail" then
        for _, m in ipairs(ns.db.mailboxes or {}) do pcall(consider, "Mailbox", m.map, m.x, m.y, "you") end
    end
    -- What other Flow players shared (only NPCs your faction can use).
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local sh = ns.places.Shared()
    for name, s in pairs(sh.npcs) do
        if s.roles[kind] and not (ns.db.places or {})[name] and ns.places.FriendlyTo(s.f, faction) and not ns.places.NotRole(name, kind) then
            pcall(consider, name, s.map, s.x, s.y, "shared")
        end
    end
    if kind == "mail" then
        for _, m in ipairs(sh.mailboxes) do pcall(consider, "Mailbox", m.map, m.x, m.y, "shared") end
    end
    -- Questie's data: only your own faction's NPCs.
    for _, npc in ipairs(found[kind] or {}) do
        if ns.places.FriendlyTo(npc.faction, faction) and not (ns.places.NotRole and ns.places.NotRole(npc.name, kind)) then
            for areaId, list in pairs(npc.spawns) do
                local map = ns.quests:UiMapForArea(areaId)
                if map then
                    for _, c in ipairs(list) do
                        if c[1] and c[1] >= 0 then pcall(consider, npc.name, map, c[1] / 100, c[2] / 100) end
                    end
                end
            end
        end
    end
    return best
end

-- Every one of `kind` Flow can find on your continent, nearest first, at
-- most `max`: { name, map, x, y, cont, wx, wy, yards, learned } (Export.lua:
-- the flight masters on your way). The same three sources as S:Nearest.
-- Does the quest data list this NPC with that role? (For "talked to them,
-- and they aren't one": Places.lua.)
function S.DataHas(name, kind)
    for _, npc in ipairs(found[kind] or {}) do
        if npc.name == name then return true end
    end
    return false
end

function S:All(kind, max)
    local nav = ns.nav
    local p = nav and nav:PlayerPos()
    if not p then return {} end
    local out, seen = {}, {}
    local function consider(name, map, x, y, learned)
        local cont, wx, wy = nav:ToWorld(map, x, y)
        if cont ~= p.cont or not wx then return end
        local key = name .. ":" .. math.floor(wx / 20) .. ":" .. math.floor(wy / 20)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { name = name, map = map, x = x, y = y, cont = cont, wx = wx, wy = wy, learned = learned,
                          yards = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2) }
    end
    for name, spot in pairs(ns.db.places or {}) do
        if spot.map and ns.places.HasRole(spot, kind) and not ns.places.NotRole(name, kind) then pcall(consider, name, spot.map, spot.x, spot.y, "you") end
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local sh = ns.places.Shared()
    for name, s in pairs(sh.npcs) do
        if s.roles[kind] and not (ns.db.places or {})[name] and ns.places.FriendlyTo(s.f, faction) and not ns.places.NotRole(name, kind) then
            pcall(consider, name, s.map, s.x, s.y, "shared")
        end
    end
    for _, npc in ipairs(found[kind] or {}) do
        if ns.places.FriendlyTo(npc.faction, faction) and not (ns.places.NotRole and ns.places.NotRole(npc.name, kind)) then
            for areaId, list in pairs(npc.spawns) do
                local map = ns.quests:UiMapForArea(areaId)
                if map then
                    for _, c in ipairs(list) do
                        if c[1] and c[1] >= 0 then pcall(consider, npc.name, map, c[1] / 100, c[2] / 100) end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.yards < b.yards end)
    for i = #out, (max or #out) + 1, -1 do out[i] = nil end
    return out
end

local LABEL = { repair = "repair", vendor = "vendor", flight = "flight master", inn = "innkeeper",
                bank = "banker", auction = "auctioneer", mail = "mailbox" }
S.LABEL = LABEL
function S:GoTo(kind)
    if not LABEL[kind] then return end
    local state = self:Scan()
    local n = self:Nearest(kind)
    if not n then
        ns:Print(state == "running" and ("looking up " .. LABEL[kind] .. "s... try again in a few seconds.")
            or ("Flow doesn't know a " .. LABEL[kind] .. " on this continent yet (it learns each one you use)."))
        return
    end
    ns.waypoint:Set(n.map, n.x, n.y, n.name .. " (" .. LABEL[kind] .. ")")
    -- The hearthstone only when Flow's estimate says it's clearly quicker (Hearth.lua).
    local hearth = ns.hearth and ns.hearth.Advice and ns.hearth:Advice(n.map, n.x, n.y, n.yards)
    ns:Print(string.format("nearest %s: %s, %d yd%s.%s", LABEL[kind], n.name, n.yards,
        (n.learned == "you" and " (you've been there)") or (n.learned == "shared" and " (found by another Flow player)") or "",
        hearth and (" " .. hearth) or ""))
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(20, function() pcall(S.Scan, S) end) end)
