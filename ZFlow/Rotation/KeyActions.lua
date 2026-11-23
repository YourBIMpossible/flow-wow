local _, ns = ...
-- N1, N2, N20 and N5 (P-KEYS slice D): what the rotation key (the easy key,
-- Rotation/KeyFrame.lua) does out of a fight when the rotation has nothing
-- stronger to suggest. Every one of these goes on the key as a secure spell
-- or item attribute (Rotation/Cast.lua) and acts only on the player's own
-- press. Nothing here casts, equips, loots or uses anything; nothing is
-- bound and no macro is made (section 246).
--
--   N1  fishing (rotation.fishing, off by default): the fishing pole from
--       the bags, then Fishing on you; with an enemy targeted, your weapons
--       back first (main hand, then the off hand). A fish on the line is
--       only shown: reeling in is the bobber click.
--   N2  a corpse you targeted (rotation.corpseKey): loot on it is only
--       shown (looting is the corpse click); looted, the key skins it or
--       gathers it (Skinning, Herb Gathering, Mining) on the target.
--       Resurrecting a dead friend is the care key's (Rotation/CareKeys.lua,
--       care.revive), not repeated here.
--   N20 a crafting station (rotation.stationKey): by a forge with ore, the
--       key opens Smelting; by an anvil or forge, Blacksmithing; by a fire,
--       Cooking. Stations are learned when a profession window opens by one
--       (client.tradeSkillRows, then client.tradeSkillTools(index) for
--       each row: a tool you have) and kept in the add-on's own
--       saved data (account learned.keyStations). Making the count stays
--       the craft bar's own click.
--   N5  a better item in the bags (rotation.upgradeKey): the key equips it.
--       Scored with the class pack's own weights (Gear/Verdict.lua), never a
--       second set of role tables.
--
--   KA.Pick(s, current) -> a suggestion or nil. Only with s.inCombat and
--       s.lockdown both a plain false. Weapons back with an enemy targeted
--       goes over any suggestion; the rest only over a weak one (nothing, a
--       look-only one, or a food, tracking or group step).
--   KA.Fishing(s), KA.WeaponsBack(s), KA.Corpse(s), KA.Station(s),
--   KA.Upgrade(s) -> each one action's suggestion, or nil.
--   KA.Learn(list, pos, kind) -> true when a station is added, else false.
--   KA.StationKind(toolName) -> "anvil", "forge", "fire" or nil.
--   KA.Read(client, input, pack, role, lockdown) -> s, each read under
--       pcall; a read that fails or gives nothing is not known.
--   KA.Declare(k) -> api; api.input(settings) -> what the driver hands
--       KA.Read each tick (the rows, the stations, the weapons).
-- First guesses, not tested in game: the tool names, the reach, the ore
-- ids, the gather spell names.
local KA = {}
ns.KeyActions = KA

KA.NAME = "keyActions"
KA.FISHING = "rotation.fishing"
KA.CORPSE = "rotation.corpseKey"
KA.STATION = "rotation.stationKey"
KA.UPGRADE = "rotation.upgradeKey"
KA.STATIONS_PATH = "learned.keyStations"
KA.WEAPONS_PATH = "state.keyWeapons"
KA.STATIONS_MAX = 200
-- How near a station counts, as a share of the map (first guess).
KA.REACH = 0.004
-- Ores that smelt (first guess: classic copper to thorium).
KA.ORES = { 2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 11370 }
-- The profession a corpse needs, and the spell that gathers it (the spell
-- names are a first guess, SD-4).
-- Engineering has no gathering spell: nothing is put on the key.
KA.GATHER_SPELL = { Skinning = "Skinning", Herbalism = "Herb Gathering", Mining = "Mining" }
KA.WEAK = { food = true, track = true, group = true }
KA.SPELLS = { "Fishing", "Skinning", "Herb Gathering", "Mining", "Smelting", "Blacksmithing", "Cooking" }
KA.POLE_CLASS, KA.POLE_SUBCLASS = 2, 20
KA.WEAPON_CLASS = 2

local function on(s, name) return type(s.on) == "table" and s.on[name] == true end
local function has(t, key) return type(t) == "table" and t[key] == true end

-- Weapons back: the main hand first, then the off hand; only an item in
-- the bags is offered.
function KA.WeaponsBack(s)
    if type(s) ~= "table" or type(s.weapons) ~= "table" then return nil end
    local w, worn = s.weapons, type(s.worn) == "table" and s.worn or {}
    if type(w.main) == "number" and worn.main ~= w.main then
        if has(s.bag, w.main) then
            return { itemId = w.main, step = "weaponsBack", reason = "Your main hand weapon back on" }
        end
        return nil
    end
    if type(w.off) == "number" and worn.off ~= w.off and has(s.bag, w.off) then
        return { itemId = w.off, step = "weaponsBack", reason = "Your off hand back on" }
    end
    return nil
end

function KA.Fishing(s)
    if type(s) ~= "table" or not on(s, "fishing") then return nil end
    if s.channel == "Fishing" then
        return { look = true, step = "fishing", reason = "A fish on the line: click the bobber" }
    end
    if s.pole == true then
        if not has(s.known, "Fishing") then return nil end
        return { spell = "Fishing", unit = "player", step = "fishing", reason = "Fish" }
    end
    if s.enemy == true then return nil end
    if type(s.poleBag) == "number" and has(s.bag, s.poleBag) then
        return { itemId = s.poleBag, step = "fishing", reason = "Put your fishing pole on" }
    end
    return nil
end

function KA.Corpse(s)
    if type(s) ~= "table" or not on(s, "corpse") then return nil end
    local c = s.corpse
    if type(c) ~= "table" or c.exists ~= true or c.dead ~= true or c.player ~= false then return nil end
    if c.lootable == true then
        return { look = true, step = "loot", reason = "Loot it: right-click the corpse" }
    end
    if c.lootable ~= false or type(c.needs) ~= "string" then return nil end
    local spell = KA.GATHER_SPELL[c.needs]
    if spell == nil or not has(s.professions, c.needs) or not has(s.known, spell) then return nil end
    return { spell = spell, unit = "target", step = "corpse", reason = spell .. " the corpse" }
end

local function near(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.map ~= b.map then return false end
    if type(a.x) ~= "number" or type(a.y) ~= "number" or type(b.x) ~= "number" or type(b.y) ~= "number" then
        return false
    end
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= KA.REACH * KA.REACH
end

function KA.Station(s)
    if type(s) ~= "table" or not on(s, "station") or type(s.stations) ~= "table" then return nil end
    local kinds = {}
    for _, st in ipairs(s.stations) do
        if near(st, s.position) then kinds[st.kind] = true end
    end
    local spell
    if kinds.forge and has(s.known, "Smelting") and (s.hasOre == true or not has(s.known, "Blacksmithing")) then
        spell = "Smelting"
    elseif (kinds.anvil or kinds.forge) and has(s.known, "Blacksmithing") then
        spell = "Blacksmithing"
    elseif kinds.fire and has(s.known, "Cooking") then
        spell = "Cooking"
    end
    if spell == nil or s.window == spell then return nil end
    return { spell = spell, unit = "player", step = "station", reason = "Open " .. spell }
end

function KA.Upgrade(s)
    if type(s) ~= "table" or not on(s, "upgrade") or type(s.upgrade) ~= "table" then return nil end
    local id = s.upgrade.itemId
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil end
    local text = "Equip a better item"
    if type(s.upgrade.text) == "string" then text = s.upgrade.text end
    return { itemId = id, step = "upgrade", reason = text }
end

local function weak(current)
    if current == nil then return true end
    if type(current) ~= "table" then return false end
    return current.look == true or (type(current.step) == "string" and KA.WEAK[current.step] == true)
end

function KA.Pick(s, current)
    if type(s) ~= "table" or s.inCombat ~= false or s.lockdown ~= false then return nil end
    local w = type(s.weapons) == "table" and s.weapons or {}
    if s.pole == true and s.enemy == true and (on(s, "fishing") or w.pending == true) then
        return KA.WeaponsBack(s)
    end
    if not weak(current) then return nil end
    local got = KA.Corpse(s)
    if got then return got end
    if on(s, "fishing") then
        got = KA.Fishing(s)
    elseif w.pending == true then
        got = KA.WeaponsBack(s)
    end
    if got then return got end
    got = KA.Station(s)
    if got then return got end
    return KA.Upgrade(s)
end

function KA.Learn(list, pos, kind)
    if type(list) ~= "table" or type(kind) ~= "string" or type(pos) ~= "table" then return false end
    if type(pos.map) ~= "number" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return false end
    for _, st in ipairs(list) do
        if st.kind == kind and near(st, pos) then return false end
    end
    list[#list + 1] = { map = pos.map, x = pos.x, y = pos.y, kind = kind }
    while #list > KA.STATIONS_MAX do table.remove(list, 1) end
    return true
end

function KA.StationKind(name)
    if type(name) ~= "string" then return nil end
    local low = string.lower(name)
    if low:find("anvil", 1, true) then return "anvil" end
    if low:find("forge", 1, true) then return "forge" end
    if low:find("fire", 1, true) then return "fire" end
    return nil
end

-- The reads ----------------------------------------------------------------

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function idOf(item)
    if type(item) == "number" then return item end
    if ns.Items and type(ns.Items.Id) == "function" then
        local ok, id = pcall(ns.Items.Id, item)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

local function infoOf(client, id)
    local info = ask(client, "itemInfo", id)
    if type(info) ~= "table" then return nil end
    return info
end

-- The first better item in the bags for your role (else any role the pack
-- has weights for), or nil.
local function upgradeOf(client, links, skip, pack, role)
    local class = ask(client, "class")
    local level = ask(client, "level")
    local byRole = type(pack) == "table" and type(pack.weights) == "table" and type(pack.weights[role]) == "table"
    for _, link in ipairs(links) do
        local id = idOf(link)
        if id and not skip[id] then
            local lines
            if byRole then
                local gear = ask(client, "gear", link)
                local ok, got = pcall(ns.GearVerdict.Lines, gear, { pack = pack, role = role, level = level })
                if ok then lines = got end
            elseif type(class) == "string" and type(pack) == "table" then
                local ok, got = pcall(ns.GearTooltipModule.Lines, client, { [class] = pack }, link)
                if ok then lines = got end
            end
            for _, line in ipairs(type(lines) == "table" and lines or {}) do
                if type(line) == "table" and line.tone == "good" then
                    return { itemId = id, text = line.text }
                end
            end
        end
    end
    return nil
end

local function signature(links, worn, role)
    local parts = {}
    for _, link in ipairs(links) do parts[#parts + 1] = tostring(link) end
    table.sort(parts)
    local wornParts = {}
    for slot, link in pairs(type(worn) == "table" and worn or {}) do
        wornParts[#wornParts + 1] = tostring(slot) .. "=" .. tostring(link)
    end
    table.sort(wornParts)
    return table.concat(parts, ";") .. "|" .. table.concat(wornParts, ";") .. "|" .. tostring(role)
end

-- Keeps the weapons you wore before the pole went on (state only: what the
-- key puts back; nothing is equipped here).
local function remember(client, s, w)
    if type(w) ~= "table" then return end
    local worn = s.worn
    if s.wornRead ~= true then return end
    if s.pole ~= true and w.pending == true and worn.main == w.main
        and (w.off == nil or worn.off == w.off) then
        w.pending = nil
    end
    if s.pole ~= true and w.pending ~= true and type(worn.main) == "number" then
        w.main = worn.main
        w.off = nil
        if type(worn.off) == "number" then
            -- A weapon in the off hand would be equipped to the main hand by
            -- the item press: only a shield or held item is remembered.
            local info = infoOf(client, worn.off)
            if type(info) == "table" and type(info.classID) == "number" and info.classID ~= KA.WEAPON_CLASS then
                w.off = worn.off
            end
        end
    end
    if s.pole == true and on(s, "fishing") and type(w.main) == "number" then w.pending = true end
end

function KA.Read(client, input, pack, role, lockdown)
    if type(input) ~= "table" then input = {} end
    local s = { lockdown = lockdown, on = {}, known = {}, bag = {}, worn = {}, weapons = {},
                professions = {}, stations = {} }
    if type(input.on) == "table" then
        for _, name in ipairs({ "fishing", "corpse", "station", "upgrade" }) do s.on[name] = input.on[name] == true end
    end
    if type(input.stations) == "table" then s.stations = input.stations end
    local combat = ask(client, "inCombat")
    if type(combat) == "boolean" then s.inCombat = combat end
    if s.inCombat ~= false or lockdown ~= false then return s end

    local target = ask(client, "target")
    s.enemy = type(target) == "table" and target.exists == true and target.hostile == true and target.dead ~= true
    s.pole = ask(client, "fishingPole") == true

    local links, skip = {}, {}
    local rows = ask(client, "bagItems")
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local id = type(row) == "table" and idOf(row.item)
        if id and (type(row.count) ~= "number" or row.count > 0) and not s.bag[id] then
            s.bag[id] = true
            if type(row.item) == "string" then links[#links + 1] = row.item else links[#links + 1] = "item:" .. id end
            local info = infoOf(client, id)
            if s.poleBag == nil and type(info) == "table" and info.classID == KA.POLE_CLASS
                and info.subclassID == KA.POLE_SUBCLASS then
                s.poleBag = id
                skip[id] = true
            end
        end
    end
    local channel = ask(client, "channel")
    if type(channel) == "table" and type(channel.name) == "string" then s.channel = channel.name end

    for _, name in ipairs(KA.SPELLS) do
        local id = ask(client, "spellId", name)
        local row = type(id) == "number" and ask(client, "spell", id)
        s.known[name] = type(row) == "table" and row.known == true
    end

    local worn = ask(client, "wornLinks")
    if type(worn) == "table" then
        s.wornRead = true
        s.worn.main = idOf(worn[16]) or false
        s.worn.off = idOf(worn[17]) or false
    end
    remember(client, s, input.weapons)
    if type(input.weapons) == "table" then
        s.weapons = { main = input.weapons.main, off = input.weapons.off, pending = input.weapons.pending }
        if type(s.weapons.main) == "number" then skip[s.weapons.main] = true end
        if type(s.weapons.off) == "number" then skip[s.weapons.off] = true end
    end

    if s.on.corpse then s.corpse = ask(client, "targetCorpse") end
    local professions = ask(client, "professions")
    if type(professions) == "table" then s.professions = professions end
    if s.on.station then
        s.position = ask(client, "position")
        s.hasOre = false
        for _, ore in ipairs(KA.ORES) do
            local n = ask(client, "itemCount", ore)
            if type(n) == "number" and n > 0 then
                s.hasOre = true
                break
            end
        end
        local window = ask(client, "tradeSkillRows")
        if type(window) == "table" and type(window.name) == "string" then s.window = window.name end
    end
    if s.on.upgrade and s.pole ~= true then
        local cache = type(input.cache) == "table" and input.cache or {}
        local sig = signature(links, worn, role)
        if cache.sig ~= sig then
            cache.sig, cache.value = sig, upgradeOf(client, links, skip, pack, role)
        end
        s.upgrade = cache.value
    end
    return s
end

-- The module -------------------------------------------------------------

function KA.Declare(k)
    local api = {}
    local state = { stations = {}, weapons = {}, cache = {} }

    function api.input(settings)
        if type(settings) ~= "table" or type(settings.get) ~= "function" then return nil end
        return {
            on = {
                fishing = settings:get(KA.FISHING) == true,
                corpse = settings:get(KA.CORPSE) ~= false,
                station = settings:get(KA.STATION) ~= false,
                upgrade = settings:get(KA.UPGRADE) ~= false,
            },
            stations = state.stations, weapons = state.weapons, cache = state.cache,
        }
    end

    -- A profession window opened: each tool it says you are by is learned
    -- where you stand. State only; nothing acts.
    local function learn(ctx)
        if ctx.settings:get(KA.STATION) == false then return end
        local window = ask(ctx.client, "tradeSkillRows")
        if type(window) ~= "table" or type(window.rows) ~= "table" then return end
        local pos = ask(ctx.client, "position")
        for _, row in ipairs(window.rows) do
            local tools = type(row) == "table" and ask(ctx.client, "tradeSkillTools", row.index) or nil
            if type(tools) == "table" then
                for _, tool in ipairs(tools) do
                    if type(tool) == "table" and tool.has == true then
                        KA.Learn(state.stations, pos, KA.StationKind(tool.name))
                    end
                end
            end
        end
    end

    k:Module({
        name = KA.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = KA.FISHING, scope = "char", type = "bool", default = false,
            label = "The key fishes",
            help = "Out of a fight, the rotation key puts your fishing pole on and casts Fishing. With an enemy targeted it puts your weapons back first. Reeling in stays the bobber click.",
            group = "combat.rotation", synonyms = { "fishing", "fish", "pole", "lure", "weapons", "easy key" },
        }, {
            key = KA.CORPSE, scope = "char", type = "bool", default = true,
            label = "The key skins or gathers a looted corpse",
            help = "Out of a fight, with a looted corpse targeted, the rotation key casts Skinning, Herb Gathering or Mining on it. Loot still on it is only shown: looting stays the corpse click.",
            group = "combat.rotation", synonyms = { "skinning", "skin", "loot", "corpse", "herbalism", "mining", "gather", "easy key" },
        }, {
            key = KA.STATION, scope = "char", type = "bool", default = true,
            label = "The key opens your profession by a station",
            help = "By a forge with ore the rotation key opens Smelting; by an anvil or forge, Blacksmithing; by a fire, Cooking. Stations are learned when you open a profession window by one, and kept in Flow's own saved data.",
            group = "combat.rotation", synonyms = { "forge", "anvil", "smelting", "blacksmithing", "cooking", "campfire", "station", "craft", "easy key" },
        }, {
            key = KA.UPGRADE, scope = "char", type = "bool", default = true,
            label = "The key equips a better item from your bags",
            help = "Out of a fight, the rotation key equips an item from your bags that is an upgrade by your class's own weights. Never in a fight.",
            group = "combat.rotation", synonyms = { "upgrade", "equip", "gear", "better item", "bags", "easy key" },
        } },
        provides = { Input = api.input },
        start = function(ctx)
            local store = ctx.store or k.store
            local okS, list = pcall(store.table, store, "account", KA.STATIONS_PATH)
            if okS and type(list) == "table" then state.stations = list else state.stations = {} end
            local okW, weapons = pcall(store.table, store, "char", KA.WEAPONS_PATH)
            if okW and type(weapons) == "table" then state.weapons = weapons else state.weapons = {} end
            state.cache = {}
            ctx.bus:on(KA.NAME, "TRADE_SKILL_SHOW", function() learn(ctx) end)
            ctx.bus:on(KA.NAME, "TRADE_SKILL_UPDATE", function() learn(ctx) end)
            -- The bags changed or item data arrived: the upgrade is read again.
            ctx.bus:on(KA.NAME, "BAG_UPDATE_DELAYED", function() state.cache = {} end)
            ctx.bus:on(KA.NAME, "GET_ITEM_INFO_RECEIVED", function() state.cache = {} end)
        end,
        stop = function() state = { stations = {}, weapons = {}, cache = {} } end,
    })
    return api
end

ns.keyActions = KA.Declare(ns)
