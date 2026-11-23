-- Capture loader (lead sections 187, 188): a diag capture, what the client
-- itself wrote to the saved file, put into the fake client, so the whole
-- add-on (ns.offline.addon(c)) starts from the client's real answers.
-- Offline only: listed as `dev` in manifest.lua, never in the TOC.
--
-- CAPTURE FORMAT, version 1. One Lua table; every field is plain saved data.
--   {
--     format  = 1,
--     account = the account saved table (ns.id.accountDB, "ZFlowDB") as the
--               client wrote it, every key kept. Its `diag` (Core/Diag.lua):
--         snaps  = { snap, ... }   oldest first, newest KEEP (20); each snap:
--             why, at, clock, kernel
--             timing = (Core/Diag.lua Diag.Start; Capture.TIMING lists them)
--                      order = { event, ... }   the events marked, in order
--                      fileLoad, and one per event in order (ADDON_LOADED,
--                        VARIABLES_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD):
--                        { at, accountData, charData, phase } (Capture.TIMING_MARK)
--                      errors = { { text, count, at, phase, ours } }  Lua error
--                        lines, ours and other add-ons'
--                      start (a count), character, realm   (names, see NAMES)
--             reads  = { money, combatLockdown, inCombat, bags = { row },
--                        bagStacks, bankOpen, bankStacks,
--                        position = { map, x, y }, zone = { cont, zone },
--                        mapSize = { w, h } (of position.map), recipes,
--                        predecessorLoaded, predecessorData, selfLoaded }
--             known  = { [read name] = true | false }
--             shapes = { [key] = { ok, n, types = { type, ... },
--                                  values = { v1 = plain | { [key] = plain | type name } } } }
--                      type "secret": the client hid the value; no value kept
--         names  = { build = "1.16.1 (7777)", names = { ["C_Map.GetBestMapForUnit"] = "function", ... } }
--         reads  = { { at, build, reads = Diag.Reads(client) }, ... }  oldest first; types only
--         api    = { namespaces = { [ns] = { [member] = type name, or the
--                    member's own number, text or true/false (peek keeps
--                    plain values) } | false }, globals }
--         starts, count
--     char    = the character saved table (ns.id.charDB, "ZFlowCharDB"), or nil
--   }
-- A saved-variables file gives one with Capture.FromSaved(vars), vars being
-- the globals it assigns: { ZFlowDB = ..., ZFlowCharDB = ... } (the account
-- file and the character file are two files). The offline runner reads
-- them with the sanitizer's parser (ns.offline.readSaved): a saved file is
-- parsed as data, never run.
--
-- NAMES. A capture from the game holds character and realm names: diag
-- timing.character and timing.realm; shapes realm, realmNormalized and
-- fullName; auction price keys "<realm>-<faction>". Text that can hold any
-- word, a name too: timing.errors[].text (other add-ons' errors), kernel
-- problem texts, labels the player types (a waypoint's, char state.nav),
-- import notes and export lines. No code reads or saves guild, account,
-- chat or mail text (Capture.NO_TEXT); the sanitizer schema
-- (tools/offline/zflow-sanitize-schema.lua) has no field of those kinds and
-- refuses a capture holding one. A capture must pass the sanitizer before
-- it leaves White, and even then is treated as holding names (section 192).
-- Real captures never enter the repo, a branch, RESULTS or Drive (lead
-- section 188, 3): tests here use made-up captures in this format.
local _, ns = ...

local Capture = {}
ns.Capture = Capture

Capture.FORMAT = 1

-- The timing fields (L2) and the fields of each mark; the text kinds no
-- code saves (L1), as the sanitizer schema's kinds are named.
Capture.TIMING = { "order", "fileLoad", "errors", "start", "character", "realm" }
Capture.TIMING_MARK = { "at", "accountData", "charData", "phase" }
Capture.NO_TEXT = { "account", "chat", "guild", "mail" }

-- WHAT THE LOADER DOES with a capture (Capture.Client):
--   saved    the account and character tables, deep copies, as the saved
--            tables the client has at load (no char table: none set)
--   reads    from the newest snapshot: money, bags, position, zone, the
--            map size of the player's map and its continent (the zone's),
--            whether the predecessor was loaded; and from its shapes the
--            class token, level, faction, facing and form. A secret, a
--            failed read or a value of the wrong kind is left unknown (nil).
--   names    diag.names and diag.api.namespaces become the names the client
--            has (typeOf, peek, globalNames): a function, a table, or a
--            plain value of the recorded type (userdata is left out). A
--            name recorded "nil" or false is not there.
--   answers  a function name with a recorded shape (Capture.CALLS) answers
--            as recorded, whatever its arguments: its values, nil for a
--            "nil", a failure for ok = false. A "secret" answer is a value
--            the client's issecretvalue calls secret, when the capture has
--            issecretvalue; else nil. Other functions answer nothing.
--   left     fights, windows (bank, vendor, trainer), the quest log, auras,
--            spells and the screen are not in a capture: a test sets them.
--
--   Capture.Check(cap)           -> true | nil, why
--   Capture.FromSaved(vars)      -> capture | nil, why
--   Capture.Newest(cap)          -> the newest snapshot, or nil
--   Capture.Env(cap)             -> the env table for ns.make.fakeClient
--   Capture.Apply(c, cap)        -> report { set = { read }, unknown = { read } }
--   Capture.Client(cap [, opts]) -> fake client, report | nil, why
--                                   opts.now: the fake client's start time

-- The shapes Diag.Collect records, with the call that made them. Only calls
-- that name nothing about the player: no realm or character name.
Capture.CALLS = {
    build = "GetBuildInfo", locale = "GetLocale", class = "UnitClass", level = "UnitLevel",
    faction = "UnitFactionGroup", facing = "GetPlayerFacing", form = "GetShapeshiftForm",
    forms = "GetNumShapeshiftForms", health = "UnitHealth", healthMax = "UnitHealthMax",
    power = "UnitPower", powerType = "UnitPowerType", spellTabs = "GetNumSpellTabs",
    talentTabs = "GetNumTalentTabs", skillLines = "GetNumSkillLines", quests = "GetNumQuestLogEntries",
    bestMap = "C_Map.GetBestMapForUnit", bindingSet = "GetCurrentBindingSet",
    merchantItems = "GetMerchantNumItems", canRepair = "CanMerchantRepair",
    trainerServices = "GetNumTrainerServices", tradeSkills = "GetNumTradeSkills", crafts = "GetNumCrafts",
    taxiNodes = "NumTaxiNodes", questEntries = "C_QuestLog.GetNumQuestLogEntries",
    bookLines = "C_SpellBook.GetNumSpellBookSkillLines", professions = "GetProfessions",
    tradeReady = "C_TradeSkillUI.IsTradeSkillReady", activeTalentConfig = "C_ClassTalents.GetActiveConfigID",
}

-- The reads, in the order the report lists them.
Capture.READS = { "money", "bags", "position", "zone", "mapSize", "mapCont", "predecessor",
    "class", "level", "faction", "facing", "form" }

local SECRET = "secret"

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[copy(key)] = copy(value) end
    return out
end

local function number(v) return type(v) == "number" and v == v end
local function share(v) return number(v) and v >= 0 and v <= 1 end

function Capture.Check(cap)
    if type(cap) ~= "table" then return nil, "not a table" end
    if cap.format ~= Capture.FORMAT then return nil, "format " .. tostring(cap.format) .. " is not known" end
    if type(cap.account) ~= "table" then return nil, "no account table" end
    if cap.char ~= nil and type(cap.char) ~= "table" then return nil, "char is not a table" end
    return true
end

function Capture.FromSaved(vars)
    local account = type(vars) == "table" and vars[ns.id.accountDB] or nil
    if type(account) ~= "table" then return nil, "no account table" end
    local char = vars[ns.id.charDB]
    return { format = Capture.FORMAT, account = account, char = type(char) == "table" and char or nil }
end

local function diagOf(cap)
    local d = type(cap) == "table" and type(cap.account) == "table" and cap.account.diag or nil
    return type(d) == "table" and d or nil
end

function Capture.Newest(cap)
    local d = diagOf(cap)
    local snaps = d and d.snaps
    if type(snaps) ~= "table" or #snaps == 0 then return nil end
    local snap = snaps[#snaps]
    return type(snap) == "table" and snap or nil
end

-- The recorded values of a shape, as a list of n, or nil for a row that is
-- not a shape. A "secret" value is the token handed in (nil for none).
local function answers(row, secretToken)
    if type(row) ~= "table" or type(row.types) ~= "table" or not number(row.n) then return nil end
    local values = type(row.values) == "table" and row.values or {}
    local out = {}
    for i = 1, row.n do
        local kind = row.types[i]
        if kind == SECRET then
            out[i] = secretToken
        elseif kind ~= "nil" then
            out[i] = copy(values["v" .. i])
        end
    end
    return out
end

-- One recorded value of a shape that read well, when it is of the kind
-- wanted; nil for a secret, a failed read or another kind.
local function value(shapes, key, i, kind)
    local row = shapes[key]
    if type(row) ~= "table" or row.ok ~= true or type(row.types) ~= "table" then return nil end
    if row.types[i] ~= kind then return nil end
    local v = type(row.values) == "table" and row.values["v" .. i] or nil
    if type(v) ~= kind then return nil end
    return v
end

-- Puts v at the dotted path in env, making the tables on the way. A path
-- that runs into something that is not a table, or a name already there,
-- is left as it is.
local function put(env, path, v)
    local at, last = env, nil
    for seg in tostring(path):gmatch("[^%.]+") do
        if last then
            if at[last] == nil then at[last] = {} end
            if type(at[last]) ~= "table" then return end
            at = at[last]
        end
        last = seg
    end
    if last and at[last] == nil then at[last] = v end
end

-- A stand-in of the recorded type: a function answering nothing, a table,
-- or a plain value. nil for "nil", false, userdata and what is not a type.
local function standIn(kind)
    if kind == "function" then return function() end end
    if kind == "table" then return {} end
    if kind == "number" then return 0 end
    if kind == "string" then return "" end
    if kind == "boolean" then return false end
    return nil
end

local function depth(path)
    local _, n = path:gsub("%.", "")
    return n
end

-- The arguments each recorded call was made with. A capture does not store
-- them: they are fixed in Core/Diag.lua, which asks every unit call about
-- the player and every other call with no argument (a test holds the two
-- lists together). So a recorded answer is an answer for these arguments
-- only. A call with other arguments (another unit, an item, a spell) was
-- never recorded and gets no answer: the player's is not given in its place.
-- A call not listed here was recorded with no argument.
Capture.ARGS = {
    class = { "player" }, level = { "player" }, faction = { "player" },
    health = { "player" }, healthMax = { "player" },
    power = { "player" }, powerType = { "player" },
    bestMap = { "player" },
}

-- Capture.Env(cap) -> env, replay. replay[path] = { answered = n,
-- unanswered = n }: how often a recorded call was asked with the recorded
-- arguments, and how often with others (those got no answer).
function Capture.Env(cap)
    local env, replay = {}, {}
    local d = diagOf(cap)
    if not d then return env, replay end
    local names = type(d.names) == "table" and type(d.names.names) == "table" and d.names.names or {}

    -- A secret answer: a token only this client's issecretvalue knows.
    local secretToken = nil
    if names.issecretvalue == "function" then
        local token = setmetatable({}, { __tostring = function() return SECRET end })
        secretToken = token
        env.issecretvalue = function(v) return v == token end
    end

    -- The recorded answers first: a call that was recorded answers so.
    local snap = Capture.Newest(cap)
    local shapes = snap and type(snap.shapes) == "table" and snap.shapes or {}
    for key, path in pairs(Capture.CALLS) do
        local row = shapes[key]
        local list = answers(row, secretToken)
        if list and names[path] == "function" then
            local want = Capture.ARGS[key] or {}
            local count = { answered = 0, unanswered = 0 }
            replay[path] = count
            -- The recorded arguments exactly: no more, no fewer, no other.
            local function recorded(...)
                local n = select("#", ...)
                while n > 0 and select(n, ...) == nil do n = n - 1 end
                if n ~= #want then return false end
                for i = 1, n do
                    if select(i, ...) ~= want[i] then return false end
                end
                return true
            end
            local ok, n = row.ok == true, row.n
            local text = type(list[1]) == "string" and list[1] or "failed"
            put(env, path, function(...)
                if not recorded(...) then
                    count.unanswered = count.unanswered + 1
                    return
                end
                count.answered = count.answered + 1
                if not ok then error(text, 0) end
                return unpack(list, 1, n)
            end)
        end
    end

    -- Then every other name, the shallow ones first, so a namespace is a
    -- table before its members are put in it.
    local paths = {}
    for path, kind in pairs(names) do
        if type(path) == "string" and type(kind) == "string" then paths[#paths + 1] = path end
    end
    table.sort(paths, function(a, b)
        local da, db = depth(a), depth(b)
        if da ~= db then return da < db end
        return a < b
    end)
    for _, path in ipairs(paths) do
        local v = standIn(names[path])
        if v ~= nil then put(env, path, v) end
    end
    local spaces = type(d.api) == "table" and type(d.api.namespaces) == "table" and d.api.namespaces or {}
    for space, members in pairs(spaces) do
        if type(space) == "string" and type(members) == "table" then
            put(env, space, {})
            for member, kind in pairs(members) do
                if type(member) == "string" then
                    -- peek keeps a plain number or boolean member as itself.
                    local v = standIn(kind)
                    if v == nil and (type(kind) == "number" or type(kind) == "boolean") then v = kind end
                    if v ~= nil then put(env, space .. "." .. member, v) end
                end
            end
        end
    end
    return env, replay
end

function Capture.Apply(c, cap)
    local got = {}
    if type(cap.account) == "table" then c.setSaved(ns.id.accountDB, copy(cap.account)) end
    if type(cap.char) == "table" then c.setSaved(ns.id.charDB, copy(cap.char)) end

    local snap = Capture.Newest(cap)
    local reads = snap and type(snap.reads) == "table" and snap.reads or {}
    local shapes = snap and type(snap.shapes) == "table" and snap.shapes or {}

    if number(reads.money) and reads.money >= 0 then
        c.setMoney(reads.money)
        got.money = true
    end
    local bags = reads.bags
    if type(bags) == "table" and #bags > 0 then
        local whole = true
        for i = 1, #bags do
            if type(bags[i]) ~= "table" then whole = false end
        end
        if whole then
            c.setBags(bags)
            got.bags = true
        end
    end
    local p, map = reads.position, nil
    if type(p) == "table" and number(p.map) and share(p.x) and share(p.y) then
        c.setPosition(p.map, p.x, p.y)
        map, got.position = p.map, true
    end
    local z, cont = reads.zone, nil
    if type(z) == "table" and (number(z.cont) or number(z.zone)) then
        cont = number(z.cont) and z.cont or nil
        c.setZone(cont, number(z.zone) and z.zone or nil)
        got.zone = true
    end
    local size = reads.mapSize
    if map and type(size) == "table" and number(size.w) and number(size.h) and size.w > 0 and size.h > 0 then
        c.setMapSize(map, size.w, size.h)
        got.mapSize = true
    end
    if map and cont then
        c.setMapCont(map, cont)
        got.mapCont = true
    end
    if type(reads.predecessorLoaded) == "boolean" then
        c.setLoaded(ns.id.predecessor, reads.predecessorLoaded)
        got.predecessor = true
    end

    local token = value(shapes, "class", 2, "string")
    if token and token ~= "" then
        c.setClass(token)
        got.class = true
    end
    local level = value(shapes, "level", 1, "number")
    if level and level > 0 then
        c.setLevel(level)
        got.level = true
    end
    local faction = value(shapes, "faction", 1, "string")
    if faction and faction ~= "" then
        c.setFaction(faction)
        got.faction = true
    end
    local facing = value(shapes, "facing", 1, "number")
    if facing and facing == facing then
        c.setFacing(facing)
        got.facing = true
    end
    local form = value(shapes, "form", 1, "number")
    if form and form >= 0 then
        c.setForm(form)
        got.form = true
    end

    local report = { set = {}, unknown = {} }
    for _, name in ipairs(Capture.READS) do
        local list = got[name] and report.set or report.unknown
        list[#list + 1] = name
    end
    return report
end

-- The reads a feature run must have had from the capture for its result to
-- mean anything: who the character is (the rotation) and where it stands
-- (the arrow, flights). A run with one of them missing shows nothing about
-- the feature, so it is reported as missing, never as a pass.
Capture.NEEDED = { "class", "level", "faction", "position", "zone" }

-- Whether a capture gave what a feature run needs. Answers true, or false
-- and the list of what is missing, in the add-on's own words (no value from
-- the capture): "a snapshot", then each needed read that was not set.
function Capture.Evidence(cap, report)
    local missing = {}
    if Capture.Newest(cap) == nil then missing[#missing + 1] = "a snapshot" end
    local set = {}
    if type(report) == "table" and type(report.set) == "table" then
        for _, name in ipairs(report.set) do set[name] = true end
    end
    for _, name in ipairs(Capture.NEEDED) do
        if not set[name] then missing[#missing + 1] = name end
    end
    return #missing == 0, missing
end

function Capture.Client(cap, opts)
    local ok, why = Capture.Check(cap)
    if not ok then return nil, why end
    opts = opts or {}
    local c = ns.make.fakeClient({ env = Capture.Env(cap), now = opts.now })
    return c, Capture.Apply(c, cap)
end

-- Section 191: the features run on a capture, each by the words a player
-- would type, in this order. What each shows is what chat says for them
-- and the arrows and panels shown after them.
Capture.FEATURES = {
    { name = "rotation", words = { "diag" } },
    { name = "arrow", words = { "arrow why" } },
    { name = "flights", words = { "try flight", "arrow why", "try off" } },
    { name = "banker", words = { "banker" } },
    { name = "settings", words = { "settings" } },
}

-- The words a feature says when a read is not known, by the read the
-- loader sets (Capture.READS). Only words that mean that read alone: a line
-- that could mean another cause too (a class with no spell list) is not here.
Capture.UNKNOWN = {
    position = { "not known where you are" },
    facing = { "facing unknown" },
    form = { "form not read" },
}

-- How many lines say unknown for a read the capture answers (report.set,
-- from Capture.Apply). A count only: a line could hold a name.
function Capture.Unknowns(lines, report)
    local n = 0
    local set = type(report) == "table" and type(report.set) == "table" and report.set or {}
    for _, line in ipairs(lines or {}) do
        local text = tostring(line)
        local hit = false
        for _, read in ipairs(set) do
            for _, words in ipairs(Capture.UNKNOWN[read] or {}) do
                if text:find(words, 1, true) then hit = true end
            end
        end
        if hit then n = n + 1 end
    end
    return n
end
