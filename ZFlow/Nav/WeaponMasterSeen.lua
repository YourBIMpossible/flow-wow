local _, ns = ...

-- WeaponMasterSeen (G16 follow-up): when the player opens a trainer window
-- whose list holds a weapon skill (a service named as one of
-- GearWeaponSkill.SKILL's names: "Swords", "Daggers", ...), that npc is
-- saved as a weapon master, so Nav/WeaponMasterStep.lua finds a place and
-- the arrow a needle.
--
-- Saved account "learned.places.npcs"[npc] gets map, x, y (client.position()
-- at the window: beside the npc), roles.weaponMaster = true, factions[f]
-- (only when client.faction() is known), seen = client.clock() when known,
-- and n + 1. Everything else already on the entry is kept (the shape
-- Nav/ProfSeen.lua writes). No trainer answer, no npc name, no weapon skill
-- in the list, or no position: nothing is written. A read that raises
-- writes nothing and the module goes on.
--
-- Language: the skill names are English; on another language no service
-- matches and nothing is marked (never a wrong mark).
--
--   WeaponMasterSeen.Seen(client, store) -> report { ok, reason, npc }
--   WeaponMasterSeen.Declare(k) -> api; api.last()
-- LOOK ONLY: nothing trains, buys or clicks. Not seen in game.

local WS = {}
ns.WeaponMasterSeen = WS

WS.NAME = "weaponMasterSeen"
WS.EVENT = "TRAINER_SHOW"
WS.NPCS = "learned.places.npcs"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function name(v)
    return type(v) == "string" and v ~= ""
end

local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read])
    if not ok then return nil end
    return v
end

-- True when a service of the list is named as a weapon skill.
function WS.Teaches(services)
    if type(services) ~= "table" then return false end
    local skills = {}
    for _, skill in pairs(ns.GearWeaponSkill.SKILL) do skills[skill] = true end
    for i = 1, #services do
        local row = services[i]
        if type(row) == "table" and name(row.name) and skills[row.name] == true then return true end
    end
    return false
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

function WS.Seen(client, store)
    local report = { kind = "weaponMaster" }
    local tr = ask(client, "trainer")
    if type(tr) ~= "table" or not name(tr.npc) then return refuse(report, "no trainer answered") end
    report.npc = tr.npc
    if not WS.Teaches(tr.services) then return refuse(report, "not a weapon master") end
    local pos = ask(client, "position")
    if type(pos) ~= "table" or not finite(pos.map) or not finite(pos.x) or not finite(pos.y) then
        return refuse(report, "the position is not known")
    end
    local faction = ask(client, "faction")
    local now = ask(client, "clock")

    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return refuse(report, "the npcs cannot be saved")
    end
    local okGet, npcs = pcall(store.get, store, "account", WS.NPCS)
    if not okGet or (npcs ~= nil and type(npcs) ~= "table") then
        return refuse(report, "the npcs cannot be saved")
    end
    npcs = npcs or {}
    local e = {}
    local old = npcs[tr.npc]
    if type(old) == "table" then
        for k, v in pairs(old) do e[k] = v end
    end
    local roles, factions = {}, {}
    if type(e.roles) == "table" then for k, v in pairs(e.roles) do roles[k] = v end end
    if type(e.factions) == "table" then for k, v in pairs(e.factions) do factions[k] = v end end
    roles.weaponMaster = true
    if name(faction) then factions[faction] = true end
    e.roles = roles
    if next(factions) ~= nil then e.factions = factions end
    e.map, e.x, e.y = pos.map, pos.x, pos.y
    if finite(now) then e.seen = now end
    e.n = (finite(e.n) and e.n or 0) + 1
    local okSet, set = pcall(store.set, store, "account", WS.NPCS, npcs)
    if not okSet or set ~= true then return refuse(report, "the npcs cannot be saved") end
    npcs[tr.npc] = e
    report.ok = true
    return report
end

function WS.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = WS.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        start = function(ctx)
            if type(ctx.client.watchTrainer) == "function" then pcall(ctx.client.watchTrainer) end
            ctx.bus:on(WS.NAME, WS.EVENT, function()
                last = WS.Seen(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.weaponMasterSeen = WS.Declare(ns)
