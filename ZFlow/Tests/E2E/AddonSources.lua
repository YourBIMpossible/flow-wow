local _, ns = ...
-- N67 (research items 16 and 26), section 236 whole-add-on scenarios: the
-- optional runtime sources GatherMate2 (nodes on the player's map, an extra
-- source beside Z-Flow's own) and Attune (this character's attunement
-- progress, shown as one Advisor prompt). Through the real entry points:
-- login, ADDON_LOADED of the other add-on, the map change
-- (ZONE_CHANGED_NEW_AREA), the setting, the diag word and a reload. Read
-- only: nothing of theirs is written or kept in Z-Flow's saved data. Fake
-- client, made-up data; not tested in game. No Lua runtime on Zen: traced
-- by hand.
local tests = {}

local MAP, OTHER = 1429, 1411
local GM, AT = "GatherMate2", "Attune"
local NODES = {
    { kind = "Mining", x = 0.25, y = 0.5, node = "Copper Vein" },
    { kind = "Herb Gathering", x = 0.1, y = 0.2, node = "Peacebloom" },
}
local PROGRESS = {
    { id = 1, name = "Molten Core", percent = 100 },
    { id = 2, name = "Onyxia", percent = 40 },
    { id = 3, name = "Blackwing Lair" },
}

local function sources() return ns.Nav.AddonSources end

-- opts.gm / opts.attune: the add-on is there at login. opts.account,
-- opts.char: saved tables (a reload).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(60); c.setDead(false)
    c.setPosition(MAP, 0.5, 0.5)
    if opts.gm then c.setLoaded(GM, true); c.setGatherMateNodes(MAP, NODES) end
    if opts.attune then c.setLoaded(AT, true); c.setAttuneProgress(PROGRESS) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(1, 2)
    return c, addon
end

local function nodes(addon)
    local api = addon.use(sources().GATHER_NAME)
    if type(api) ~= "table" then return "not running" end
    return api.Nodes()
end

local function advice(addon)
    for _, p in ipairs(addon.use("advisor").List()) do
        if p.id == sources().ADVICE_ID then return p.text end
    end
    return nil
end

local function diagLine(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("sources:", 1, true) then return line end
    end
    return ""
end

-- A field of the first node, or nil.
local function first(list, key)
    if type(list) ~= "table" or type(list[1]) ~= "table" then return nil end
    return list[1][key]
end

local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end

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

tests["addon sources 236: both absent: nothing added, no prompt, Diag says each is absent"] = function(t)
    local c, addon = start()
    t.eq(nodes(addon), nil, "no GatherMate2: no nodes from it")
    t.eq(advice(addon), nil, "no Attune: no prompt")
    local line = diagLine(c)
    t.ok(has(line, "GatherMate2 absent"), line)
    t.ok(has(line, "Attune absent"), line)
end

tests["addon sources 236: both loaded at login: nodes on this map, the attunement under way on the Advisor"] = function(t)
    local c, addon = start({ gm = true, attune = true })
    local got = nodes(addon)
    t.eq(type(got) == "table" and #got or got, 2, "the two nodes on this map")
    t.eq(first(got, "source"), GM, "each node says where it came from")
    t.eq(first(got, "node"), "Copper Vein")
    t.eq(advice(addon), "Attunements under way: Onyxia 40%.",
        "done (100%) and not known are left out")
    local line = diagLine(c)
    t.ok(has(line, "GatherMate2 2 nodes on this map"), line)
    t.ok(has(line, "Attune 3 attunements read, 1 under way"), line)
    -- The map changes: the nodes of the new map only.
    c.setGatherMateNodes(OTHER, { { kind = "Mining", x = 0.9, y = 0.9, node = "Tin Vein" } })
    c.setPosition(OTHER, 0.5, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    got = nodes(addon)
    t.eq(type(got) == "table" and #got or got, 1, "the new map's node")
    t.eq(first(got, "node"), "Tin Vein")
end

tests["addon sources 236: loaded late: ADDON_LOADED of each after login brings it in"] = function(t)
    local c, addon = start()
    t.eq(nodes(addon), nil)
    c.setGatherMateNodes(MAP, NODES); c.setLoaded(GM, true)
    c.fire("ADDON_LOADED", GM)
    local got = nodes(addon)
    t.eq(type(got) == "table" and #got or got, 2, "read when GatherMate2 says it loaded")
    t.eq(advice(addon), nil, "Attune still absent")
    c.setAttuneProgress(PROGRESS); c.setLoaded(AT, true)
    c.fire("ADDON_LOADED", AT)
    t.eq(advice(addon), "Attunements under way: Onyxia 40%.")
end

tests["addon sources 236: a read that raises then recovers: no error, Diag says it failed, then back"] = function(t)
    local c, addon = start({ gm = true, attune = true })
    c.setReadFails("gatherMateNodes", true)
    c.setReadFails("attuneProgress", true)
    local ok = pcall(c.fire, "ZONE_CHANGED_NEW_AREA")
    t.ok(ok, "nothing escapes the listener")
    t.eq(nodes(addon), nil, "no nodes while the read raises")
    t.eq(advice(addon), nil, "no prompt while the read raises")
    local line = diagLine(c)
    t.ok(has(line, "GatherMate2 read failed"), line)
    t.ok(has(line, "Attune read failed"), line)
    c.setReadFails("gatherMateNodes", false)
    c.setReadFails("attuneProgress", false)
    c.fire("ZONE_CHANGED_NEW_AREA")
    local got = nodes(addon)
    t.eq(type(got) == "table" and #got or got, 2, "recovered")
    t.eq(advice(addon), "Attunements under way: Onyxia 40%.", "recovered")
end

tests["addon sources 236: reload: nothing of theirs was saved; without them the second instance has none"] = function(t)
    local c = start({ gm = true, attune = true })
    c.slashes[ns.id.slash]("diag")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    for _, text in ipairs({ "Copper Vein", "Peacebloom", "Onyxia", "Molten Core" }) do
        t.ok(not holds(account, text), "account data holds no " .. text)
        t.ok(not holds(char, text), "character data holds no " .. text)
    end
    local _, addon2 = start({ account = account, char = char })
    t.eq(nodes(addon2), nil, "no nodes after a reload without GatherMate2")
    t.eq(advice(addon2), nil, "no prompt after a reload without Attune")
end

tests["addon sources 236: the settings off: nothing asked, no prompt, Diag says switched off; on again: back"] = function(t)
    local c, addon = start({ gm = true, attune = true })
    local S = sources()
    t.eq(addon.settings:get(S.GATHER_SETTING), true, "on by default")
    t.eq(addon.settings:get(S.ATTUNE_SETTING), true, "on by default")
    addon.settings:set(S.GATHER_SETTING, false)
    addon.settings:set(S.ATTUNE_SETTING, false)
    c.advance(1, 2)
    t.eq(nodes(addon), nil, "switched off: no nodes")
    t.eq(advice(addon), nil, "switched off: the prompt is gone")
    local asked = c.gatherMateAsks
    c.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(c.gatherMateAsks, asked, "switched off: GatherMate2 is not asked")
    local line = diagLine(c)
    t.ok(has(line, "GatherMate2 switched off"), line)
    t.ok(has(line, "Attune switched off"), line)
    addon.settings:set(S.GATHER_SETTING, true)
    addon.settings:set(S.ATTUNE_SETTING, true)
    c.advance(1, 2)
    local got = nodes(addon)
    t.eq(type(got) == "table" and #got or got, 2, "on again")
    t.eq(advice(addon), "Attunements under way: Onyxia 40%.", "on again")
end

tests["addon sources: the rows are filed under professions and party"] = function(t)
    local _, addon = start()
    local S = sources()
    local g, a = addon.settings:row(S.GATHER_SETTING), addon.settings:row(S.ATTUNE_SETTING)
    t.eq(g and g.group, "professions")
    t.eq(a and a.group, "party")
end

return tests
