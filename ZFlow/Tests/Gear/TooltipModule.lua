local _, ns = ...

-- Tests for ZFlow/Gear/TooltipModule.lua: the module that puts the gear
-- verdict on the game's item tooltip.
--
-- The fake client has these reads (F3); the tests replace them with hand-
-- made ones so each test controls its own answers, in the same shapes:
--   the item-tooltip hook, your level, and the item's class, subclass,
-- needed level and what the game marks on it:
--   c.onItemTooltip(fn) -> cancel       fn(link, add); add(text, r, g, b)
--   c.level() -> number or nil
--   c.gear(link) also carrying classID, subclassID, minLevel
-- c.hover(link) plays the game filling a tooltip and returns what was added.

local M = ns.GearTooltipModule
local tests = {}

local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"
local HELM, PLATE, POTION = "item:1", "item:2", "item:6"

local function packs()
    return { DRUID = {
        weights = {
            tank = { evidence = "first guess", values = { [STA] = 3 } },
            dps = { evidence = "first guess", values = { [STR] = 2, [STA] = 1 } },
        },
        proficiency = { evidence = "first guess", [4] = { [2] = true }, [2] = { [7] = true } },
    } }
end

-- opts.hook = false: a client with no tooltip hook (today's).
local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { [STA] = 40 } })
    c.setItem(POTION, { stats = {} })
    c.setWorn(1, false)
    local types = { [HELM] = { 4, 2, 1 }, [PLATE] = { 4, 4, 1 } }
    -- What the game marks as not met on each item (gear.unmet). A test
    -- takes an entry out to play the marks not having been read.
    c.unmet = { [HELM] = {}, [PLATE] = { "Plate" } }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        local ty = types[link]
        if ty then g.classID, g.subclassID, g.minLevel = ty[1], ty[2], ty[3] end
        if c.unmet[link] ~= nil then g.unmet = c.unmet[link] end
        return g
    end
    c.myLevel = 10
    c.level = function() return c.myLevel end
    c.hooks, c.cancelled = {}, 0
    if opts.hook ~= false then
        c.onItemTooltip = function(fn)
            c.hooks[#c.hooks + 1] = fn
            return function()
                c.cancelled = c.cancelled + 1
                for i = #c.hooks, 1, -1 do
                    if c.hooks[i] == fn then table.remove(c.hooks, i) end
                end
            end
        end
    else
        c.onItemTooltip = nil   -- a client that offers no tooltip hook
    end
    c.hover = function(link)
        local added = {}
        for i = 1, #c.hooks do
            c.hooks[i](link, function(text, r, g, b) added[#added + 1] = { text = text, r = r, g = g, b = b } end)
        end
        return added
    end
    return c
end

local function start(c, thePacks)
    local k = ns.Kernel({}, c)
    local api = M.Declare(k, thePacks or packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, api
end

local function texts(added)
    local out = {}
    for i = 1, #added do out[i] = added[i].text end
    return out
end

-- Lines: client reads to lines ---------------------------------------------

tests["gear tooltip lines: one line for each role the pack has weights for, in name order"] = function(t)
    local c = client()
    local lines = M.Lines(c, packs(), HELM)
    t.eq(lines, {
        { text = "Upgrade for your head piece (+4, dps)", tone = "good" },
        { text = "Upgrade for your head piece (+12, tank)", tone = "good" },
    })
end

-- G31: the chosen role (spec.role, passed as opts.role) drives the verdict.
tests["gear tooltip lines: a chosen role gets its own verdict alone"] = function(t)
    local c = client()
    t.eq(M.Lines(c, packs(), HELM, { role = "tank" }), {
        { text = "Upgrade for your head piece (+12, tank)", tone = "good" },
    })
    t.eq(M.Lines(c, packs(), HELM, { role = "dps" }), {
        { text = "Upgrade for your head piece (+4, dps)", tone = "good" },
    })
end

tests["gear tooltip lines: no role chosen, or one the pack has no weights for: every role"] = function(t)
    local c = client()
    local every = M.Lines(c, packs(), HELM)
    t.eq(#every, 2)
    t.eq(M.Lines(c, packs(), HELM, {}), every, "no role in opts")
    t.eq(M.Lines(c, packs(), HELM, { role = "" }), every, "none chosen")
    t.eq(M.Lines(c, packs(), HELM, { role = "heal" }), every, "no weights for it")
    t.eq(M.Lines(c, packs(), HELM, { role = 3 }), every, "not a role")
end

tests["gear tooltip lines: a chosen role still gets can't use, once"] = function(t)
    local c = client()
    t.eq(M.Lines(c, packs(), PLATE, { role = "tank" }),
        { { text = "Can't use: " .. ns.GearUsable.REASON.unmet .. ": Plate", tone = "bad" } })
end

tests["gear tooltip lines: a chosen role - the score line still has every role, the chosen first"] = function(t)
    local c = client()
    local lines = M.Lines(c, packs(), HELM, { role = "tank", score = true })
    t.eq(lines[1], { text = "Upgrade for your head piece (+12, tank)", tone = "good" })
    t.eq(lines[2], { text = "Score 12 (tank), 4 (dps)", tone = "info" })
    for i = 1, #lines do
        t.ok(lines[i].text ~= "Upgrade for your head piece (+4, dps)", "the other role's verdict is not shown")
    end
end

tests["gear tooltip lines: can't use is said once, not once for each role"] = function(t)
    local c = client()
    local lines = M.Lines(c, packs(), PLATE)
    t.eq(lines, { { text = "Can't use: " .. ns.GearUsable.REASON.unmet .. ": Plate", tone = "bad" } })
end

tests["gear tooltip lines: what is not gear gets nothing"] = function(t)
    local c = client()
    t.eq(M.Lines(c, packs(), POTION), nil)
    t.eq(M.Lines(c, packs(), "item:999"), nil)
    t.eq(M.Lines(c, packs(), nil), nil)
end

tests["gear tooltip lines: a class with no pack, or a class not known, is no verdict"] = function(t)
    local c = client()
    c.setClass("ROGUE")
    local lines = M.Lines(c, packs(), HELM)
    t.eq(lines, { { text = "No verdict: " .. ns.GearScore.REASON.weights, tone = "none" } })
    c.setClass(nil)
    t.eq(M.Lines(c, packs(), HELM), lines)
end

tests["gear tooltip lines: your level not known is no verdict"] = function(t)
    local c = client()
    c.unmet[HELM] = nil   -- the marks not read: the class table and your level decide
    c.myLevel = nil
    t.eq(M.Lines(c, packs(), HELM), { { text = "No verdict: " .. ns.GearCanUse.REASON.yourLevel, tone = "none" } })
    c.level = nil
    t.eq(M.Lines(c, packs(), HELM), { { text = "No verdict: " .. ns.GearCanUse.REASON.yourLevel, tone = "none" } },
        "a client with no level read")
end

tests["gear tooltip lines: a pack with no weights says so once"] = function(t)
    local c = client()
    local p = packs()
    p.DRUID.weights = nil
    t.eq(M.Lines(c, p, HELM), { { text = "No verdict: " .. ns.GearScore.REASON.weights, tone = "none" } })
end

tests["gear tooltip lines: the same no-verdict for every role is said once"] = function(t)
    local c = client()
    c.setWorn(1, nil)
    t.eq(M.Lines(c, packs(), HELM),
        { { text = "No verdict: " .. ns.GearScore.REASON.worn .. ": head", tone = "none" } })
end

tests["gear tooltip lines: a client with no gear read says nothing"] = function(t)
    local c = client()
    c.gear = nil
    t.eq(M.Lines(c, packs(), HELM), nil)
end

tests["gear tooltip lines P-Q: a class-table yes with the game's marks not read is no verdict, said once"] = function(t)
    local c = client()
    c.unmet[HELM] = nil
    t.eq(M.Lines(c, packs(), HELM),
        { { text = "No verdict: " .. ns.GearUsable.REASON.unconfirmed, tone = "none" } })
end

tests["gear tooltip lines P-Q: with the marks not read, the class table's no still shows, labelled"] = function(t)
    local c = client()
    c.unmet[PLATE] = nil
    t.eq(M.Lines(c, packs(), PLATE),
        { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } })
end

-- The module ------------------------------------------------------------------

tests["gear tooltip: hovering gear adds its lines to the tooltip, coloured by tone"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k:ModuleState(M.NAME), "started")
    local added = c.hover(HELM)
    t.eq(texts(added), { "Upgrade for your head piece (+4, dps)" }, "no role chosen, no tank sign: dps (lead section 561)")
    t.eq({ added[1].r, added[1].g, added[1].b }, M.COLOUR.good)
    added = c.hover(PLATE)
    t.eq(texts(added), { "Can't use: " .. ns.GearUsable.REASON.unmet .. ": Plate" })
    t.eq({ added[1].r, added[1].g, added[1].b }, M.COLOUR.bad)
end

tests["gear tooltip: what is not gear adds nothing"] = function(t)
    local c = client()
    start(c)
    t.eq(c.hover(POTION), {})
    t.eq(c.hover("item:999"), {})
end

tests["gear tooltip: the setting is on by default, and off adds nothing"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k.settings:get(M.SETTING), true, "on by default")
    t.eq(#c.hover(HELM), 2)
    t.eq(k.settings:set(M.SETTING, false), true)
    t.eq(c.hover(HELM), {}, "switched off")
    t.eq(k.settings:set(M.SETTING, true), true)
    t.eq(#c.hover(HELM), 2, "and on again, with no reload")
end

tests["gear tooltip: the row is a bool named gear.tooltip"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(M.SETTING, "gear.tooltip")
    local row = k.settings:row(M.SETTING)
    t.eq(type(row), "table")
    t.eq(row.type, "bool")
    t.eq(row.default, true)
end

tests["gear tooltip: on a client with no tooltip hook it starts, hooks nothing and says so"] = function(t)
    local c = client({ hook = false })
    local k, api = start(c)
    t.eq(k:ModuleState(M.NAME), "started")
    t.eq(api.hooked(), false)
    t.eq(c.hover(HELM), {})
    local with = client()
    local _, apiWith = start(with)
    t.eq(apiWith.hooked(), true)
    t.eq(#with.hooks, 1, "hooked once")
end

tests["gear tooltip: a hook the client refuses is not hooked"] = function(t)
    local c = client()
    c.onItemTooltip = function() return nil end
    local _, api = start(c)
    t.eq(api.hooked(), false)
end

tests["gear tooltip: an error while working a line out adds nothing and is counted"] = function(t)
    local c = client()
    local k, api = start(c)
    c.gear = function() error("the read broke") end
    t.eq(c.hover(HELM), {}, "nothing half-written on the tooltip")
    t.eq(api.errors(), 1)
    t.eq(k:ModuleState(M.NAME), "started", "one bad tooltip does not stop the module")
    t.eq(k.problems:count("gear"), 1, "and it is kept as a problem")
    c.hover(HELM)
    t.eq(api.errors(), 2)
    t.eq(k.problems:count("gear"), 1, "the same error is one problem, not one per hover")
end

tests["gear tooltip: switched off by the kernel, the hook is given back"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k:SwitchOff(M.NAME, "test"), true)
    t.eq(c.cancelled, 1)
    t.eq(c.hover(HELM), {})
end

-- G15 weapon speed ------------------------------------------------------------

local STAFF, DPS = "item:7", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local STAFF_LINE = "Speed 3.60 (slow), 50.0 damage per second"

-- A client whose STAFF is a 3.6 s two-hander; c.speeds[link] is the speed
-- c.gear answers (a test takes it out to play the speed not read).
local function weaponClient()
    local c = client()
    c.setItem(STAFF, { kind = "INVTYPE_2HWEAPON", stats = { [STR] = 4, [DPS] = 50 } })
    c.speeds = { [STAFF] = 3.6, [HELM] = 3.6 }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        if c.speeds[link] ~= nil then g.speed = c.speeds[link] end
        return g
    end
    return c
end

local function speedLines(added)
    local out = {}
    for i = 1, #added do
        if string.find(added[i].text, "^Speed ") then out[#out + 1] = added[i] end
    end
    return out
end

tests["gear tooltip G15: hovering a 3.6 s weapon adds the speed line, after the verdict"] = function(t)
    local c = weaponClient()
    start(c)
    local added = c.hover(STAFF)
    t.eq(texts(speedLines(added)), { STAFF_LINE })
    t.eq(added[#added].text, STAFF_LINE, "the speed line comes last")
    t.eq(#added > 1, true, "the verdict lines stay")
    t.eq({ added[#added].r, added[#added].g, added[#added].b }, M.COLOUR.info)
    t.eq(M.COLOUR.info, M.COLOUR.none, "drawn like none")
    local lines = M.Lines(c, packs(), STAFF)
    t.eq(lines[#lines], { text = STAFF_LINE, tone = "info" },
        "its own tone, so no reader takes it for a no-verdict")
end

tests["gear tooltip G15: a non-weapon, even one with a speed read, adds no speed line"] = function(t)
    local c = weaponClient()
    start(c)
    t.eq(texts(c.hover(HELM)), { "Upgrade for your head piece (+4, dps)" })
end

tests["gear tooltip G15: a weapon whose speed is not read adds no speed line"] = function(t)
    local c = weaponClient()
    c.speeds[STAFF] = nil
    start(c)
    local added = c.hover(STAFF)
    t.eq(speedLines(added), {})
    t.eq(#added > 0, true, "the verdict still shows")
end

tests["gear tooltip G15: with the setting off there is no speed line either"] = function(t)
    local c = weaponClient()
    local k = start(c)
    t.eq(k.settings:set(M.SETTING, false), true)
    t.eq(c.hover(STAFF), {})
end

tests["gear tooltip G15: item data late - no speed on the first hover, the line on the next"] = function(t)
    local c = weaponClient()
    c.speeds[STAFF] = nil
    start(c)
    t.eq(speedLines(c.hover(STAFF)), {})
    c.speeds[STAFF] = 3.6
    t.eq(texts(speedLines(c.hover(STAFF))), { STAFF_LINE })
end

tests["gear tooltip G15: a speed line that raises adds no speed line, keeps the verdict, is counted"] = function(t)
    local W = ns.GearWeaponSpeed
    local c = weaponClient()
    local k, api = start(c)
    local verdict = texts(c.hover(STAFF))
    table.remove(verdict)   -- the speed line
    local line, from = W.Line, W.From
    W.Line = function() error("speed broke") end
    local ok, added = pcall(c.hover, STAFF)
    W.Line = line
    t.eq(ok, true, "no error escapes the hover")
    t.eq(texts(added), verdict, "the other lines stay")
    t.eq(api.errors(), 1)
    t.eq(k.problems:count("gear"), 1)
    W.From = function() error("from broke") end
    ok, added = pcall(c.hover, STAFF)
    W.From = from
    t.eq(ok, true)
    t.eq(texts(added), verdict)
    t.eq(api.errors(), 2)
end

tests["gear tooltip: it only reads; nothing is equipped or picked up"] = function(t)
    local c = client()
    local calls = 0
    for _, name in ipairs({ "EquipItemByName", "PickupContainerItem", "UseContainerItem", "PickupInventoryItem" }) do
        c[name] = function() calls = calls + 1 end
    end
    start(c)
    c.hover(HELM)
    c.hover(PLATE)
    t.eq(calls, 0)
end

return tests
