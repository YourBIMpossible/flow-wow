-- Lead section 374 (Lazy item 2): the gathering filters' edge cases.
-- Rotation/Gather.lua G.Read and G.Step (which tracking is offered) and
-- Nav/Nodes.lua nearest (which kept nodes are said). Made-up nodes; plain
-- table clients and the fake client. Look only; no game client.
local _, ns = ...

local G = ns.Gather
local MINERALS, HERBS = "Find Minerals", "Find Herbs"
local MAP = 1411
local tests = {}

-- A snapshot where everything but the gather fields allows an offer.
local function snap(over)
    local s = { inCombat = false, gatherOn = true, trackingAny = false, mounted = false,
        onTaxi = false, buffs = {},
        professions = { Mining = true, Herbalism = true },
        trackKnown = { [MINERALS] = true, [HERBS] = true },
        tracking = { [MINERALS] = false, [HERBS] = false } }
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

local function spellOf(s)
    if type(s) ~= "table" then return nil end
    return s.spell
end

-- Step

tests["gather filter: no gathering profession offers nothing"] = function(t)
    local s, why = G.Step(snap({ professions = {} }))
    t.eq(s, nil)
    t.eq(why, "no gathering tracking to turn on")
    t.eq(G.Step(snap({ professions = { Tailoring = true, Skinning = true } })), nil, "other professions: nothing")
end

tests["gather filter: herb only, mining only, both"] = function(t)
    t.eq(spellOf(G.Step(snap({ professions = { Herbalism = true } }))), HERBS)
    t.eq(spellOf(G.Step(snap({ professions = { Mining = true } }))), MINERALS)
    t.eq(spellOf(G.Step(snap())), MINERALS, "both: G.LIST order, Mining first")
end

tests["gather filter: both professions, the order is the same on every call"] = function(t)
    local first = spellOf(G.Step(snap()))
    for _ = 1, 20 do t.eq(spellOf(G.Step(snap())), first) end
end

tests["gather filter: profession known but its tracking spell not known"] = function(t)
    local s = G.Step(snap({ professions = { Mining = true }, trackKnown = { [MINERALS] = false, [HERBS] = true } }))
    t.eq(s, nil, "Find Herbs known without Herbalism is not offered either")
    t.eq(spellOf(G.Step(snap({ trackKnown = { [MINERALS] = false, [HERBS] = true } }))), HERBS,
        "both professions, only Find Herbs known: Find Herbs")
    t.eq(G.Step(snap({ professions = { Mining = true }, trackKnown = { [HERBS] = true } })), nil,
        "Find Minerals missing from the known list: not offered")
end

tests["gather filter: a tracking state that is unknown or nil"] = function(t)
    local s, why = G.Step(snap({ tracking = "nil" }))
    t.eq(s, nil)
    t.eq(why, "not known which gathering tracking you have")
    t.eq(G.Step(snap({ trackKnown = "nil" })), nil, "known spells not read: nothing")
    t.eq(G.Step(snap({ professions = "nil" })), nil, "professions not read: nothing")
    t.eq(G.Step(snap({ professions = { Mining = true }, tracking = { [HERBS] = false } })), nil,
        "Find Minerals state not read (nil, not false): not offered")
    local _, any = G.Step(snap({ trackingAny = "nil" }))
    t.eq(any, "not known whether a tracking is on")
end

tests["gather filter: an unknown profession or tracking name is ignored"] = function(t)
    t.eq(spellOf(G.Step(snap({ professions = { Mining = true, Fishing = true },
        trackKnown = { [MINERALS] = true, ["Find Fish"] = true },
        tracking = { [MINERALS] = false, ["Find Fish"] = false } }))), MINERALS)
    t.eq(G.Step(snap({ professions = { Mining = "yes" } })), nil, "a profession flag that is not true: nothing")
end

tests["gather filter: in a fight, or the fight unknown, nothing and the snapshot untouched"] = function(t)
    local s = snap({ inCombat = true })
    local before = {}
    for k, v in pairs(s) do before[k] = v end
    local out, why = G.Step(s)
    t.eq(out, nil)
    t.eq(why, "not out of a fight")
    for k, v in pairs(before) do t.eq(s[k], v, "field " .. k) end
    t.eq(G.Step(snap({ inCombat = "nil" })), nil, "fight not known: nothing")
end

tests["gather filter: a step that is not a table"] = function(t)
    t.eq(G.Step(nil), nil)
    t.eq(G.Step("x"), nil)
end

-- Self (recovery R2): the self button's offer.

tests["gather self: the offer for the self button is the step's spell on yourself"] = function(t)
    t.eq(G.Self(snap({ dead = false })), { spell = MINERALS, unit = "player" })
    t.eq(G.Self(snap({ dead = false, professions = { Herbalism = true } })), { spell = HERBS, unit = "player" })
    t.eq(G.Self(snap({ dead = false, resting = true })), { spell = MINERALS, unit = "player" }, "in a town too")
end

tests["gather self: not what the Flow button already holds, not when dead or dead unread"] = function(t)
    t.eq(G.Self(snap({ dead = false }), { spell = MINERALS }), nil, "the Flow button holds it")
    t.eq(G.Self(snap({ dead = false }), { spell = "Smite" }), { spell = MINERALS, unit = "player" })
    t.eq(G.Self(snap({ dead = true })), nil, "dead")
    t.eq(G.Self(snap()), nil, "dead not read")
    t.eq(G.Self(nil), nil)
end

tests["gather self: every guard of the step holds"] = function(t)
    for name, over in pairs({
        ["switched off"] = { gatherOn = false }, ["in a fight"] = { inCombat = true },
        ["mounted"] = { mounted = true }, ["mounted unread"] = { mounted = "nil" },
        ["flight path"] = { onTaxi = true }, ["flight path unread"] = { onTaxi = "nil" },
        ["eating"] = { buffs = { Food = 10 } }, ["buffs unread"] = { buffs = "nil" },
        ["a tracking on"] = { trackingAny = true }, ["tracking unread"] = { trackingAny = "nil" },
        ["professions unread"] = { professions = "nil" }, ["no profession"] = { professions = {} },
    }) do
        over.dead = false
        t.eq(G.Self(snap(over)), nil, name)
    end
end

-- Read

tests["gather filter: tracking read nil vs empty vs missing reader"] = function(t)
    t.eq(G.Read({}, "tracking"), nil, "no tracking reader: nil")
    t.eq(G.Read({ tracking = function() return nil end }, "tracking"), nil, "every answer nil: nil, not empty")
    t.eq(G.Read({ tracking = function() error("no") end }, "tracking"), nil, "a reader that fails: nil")
    t.eq(G.Read({ tracking = function(spell) if spell == HERBS then return true end end }, "tracking"),
        { [HERBS] = true }, "only what was answered is kept")
    t.eq(G.Read(nil, "tracking"), nil)
end

tests["gather filter: professions read nil vs empty"] = function(t)
    t.eq(G.Read({ professions = function() return nil end }, "professions"), nil)
    t.eq(G.Read({ professions = function() return {} end }, "professions"), {})
    t.eq(G.Read({ professions = function() return "Mining" end }, "professions"), nil, "not a table: nil")
    t.eq(G.Step(snap({ professions = {} })), nil, "an empty list offers nothing")
end

tests["gather filter: trackKnown, spell id unknown is not known, a row without known is unread"] = function(t)
    local client = {
        tracking = function() return false end,
        spellId = function(spell) if spell == HERBS then return 2383 end end,
        spell = function() return { name = HERBS } end,
    }
    t.eq(G.Read(client, "trackKnown"), { [MINERALS] = false }, "no id: false; a row without known: left out")
    client.spell = function() return { known = true } end
    t.eq(G.Read(client, "trackKnown"), { [MINERALS] = false, [HERBS] = true })
    t.eq(G.Read({ tracking = function() return false end }, "trackKnown"), nil, "no spell readers: nil")
    t.eq(G.Read(client, "unknownField"), nil)
end

-- Nodes nearest

local function nodes(profs, list)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { nodes = { [MAP] = list } } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 1000)
    c.setProfessions(profs)
    local k = ns.Kernel({}, c)
    local api = ns.Nav.Nodes.Declare(k, ns.Diag.Start(k))
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return api, c
end

local function names(list)
    local out = {}
    for i, r in ipairs(list or {}) do out[i] = r.node.name end
    return out
end

local KEPT = {
    { x = 0.51, y = 0.5, name = "Peacebloom", prof = "Herbalism", n = 1, at = 1 },
    { x = 0.52, y = 0.5, name = "Copper Vein", prof = "Mining", n = 1, at = 1 },
    { x = 0.53, y = 0.5, name = "Old chest", n = 1, at = 1 },
    { x = 0.54, y = 0.5, name = "Odd", prof = "Skinning", n = 1, at = 1 },
}

local function kept()
    local out = {}
    for i, e in ipairs(KEPT) do
        local c = {}
        for k, v in pairs(e) do c[k] = v end
        out[i] = c
    end
    return out
end

tests["nodes filter: herb only, mining only, both, none"] = function(t)
    t.eq(names(nodes({ "Herbalism" }, kept()).nearest()), { "Peacebloom", "Old chest" })
    t.eq(names(nodes({ "Mining" }, kept()).nearest()), { "Copper Vein", "Old chest" })
    t.eq(names(nodes({ "Herbalism", "Mining" }, kept()).nearest()), { "Peacebloom", "Copper Vein", "Old chest" })
    t.eq(names(nodes({ "Tailoring" }, kept()).nearest()), {}, "no gathering profession: no node, the unknown kind too")
end

tests["nodes filter: a dropped profession hides its nodes, they stay saved"] = function(t)
    local api, c = nodes({ "Mining" }, kept())
    t.eq(names(api.nearest()), { "Copper Vein", "Old chest" })
    t.eq(#c.saved(ns.id.accountDB).learned.nodes[MAP], 4, "the Herbalism node is kept")
end

tests["nodes filter: professions not read shows no node"] = function(t)
    local api = nodes(nil, kept())
    t.eq(names(api.nearest()), {})
end

tests["nodes filter: an unknown node kind is never shown"] = function(t)
    for _, profs in ipairs({ { "Herbalism" }, { "Mining" }, { "Herbalism", "Mining", "Skinning" } }) do
        for _, r in ipairs(nodes(profs, kept()).nearest()) do
            t.ok(r.node.prof ~= "Skinning", "Skinning is not a gathering profession here")
        end
    end
end

tests["nodes filter: nodes at the same distance keep their saved order"] = function(t)
    local list = {}
    for i = 1, 12 do
        list[i] = { x = (i % 2 == 0) and 0.51 or 0.49, y = 0.5, name = "N" .. i, prof = "Herbalism", n = 1, at = 1 }
    end
    local want = {}
    for i = 1, 5 do want[i] = "N" .. i end
    t.eq(names(nodes({ "Herbalism" }, list).nearest()), want)
end

return tests
