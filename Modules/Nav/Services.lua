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

-- npcFlags bits (classic data)
local FLAG = { vendor = 0x80, repair = 0x1000, flight = 0x2000, inn = 0x10000, bank = 0x20000, auction = 0x200000 }
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
        if spot.map and ns.places.HasRole(spot, kind) then pcall(consider, name, spot.map, spot.x, spot.y, "you") end
    end
    if kind == "mail" then
        for _, m in ipairs(ns.db.mailboxes or {}) do pcall(consider, "Mailbox", m.map, m.x, m.y, "you") end
    end
    -- What other Flow players shared (only NPCs your faction can use).
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local sh = ns.places.Shared()
    for name, s in pairs(sh.npcs) do
        if s.roles[kind] and not (ns.db.places or {})[name] and ns.places.FriendlyTo(s.f, faction) then
            pcall(consider, name, s.map, s.x, s.y, "shared")
        end
    end
    if kind == "mail" then
        for _, m in ipairs(sh.mailboxes) do pcall(consider, "Mailbox", m.map, m.x, m.y, "shared") end
    end
    -- Questie's data: only your own faction's NPCs.
    for _, npc in ipairs(found[kind] or {}) do
        if ns.places.FriendlyTo(npc.faction, faction) then
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
