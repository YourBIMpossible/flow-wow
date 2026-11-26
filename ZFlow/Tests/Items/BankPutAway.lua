-- E-21: the route step data "put N stacks away at the bank"
-- (Items/BankPutAway.lua). Returned only; nothing here wires it into the
-- route. Made-up items and places, fake client only; not tested in game.
local _, ns = ...

local P = ns.BankPutAway
local tests = {}

local LINEN, LEATHER, POTION = 2589, 2318, 858
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [LEATHER] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

local NEAR = { kind = "banker", key = "a", name = "Made Up Banker", map = 1411, x = 0.5, y = 0.3, cont = 1, yards = 100 }

local function row(key, name, count)
    return { key = key, name = name, count = count, quality = 1, reason = "made up" }
end

local function stack(item, count)
    return { item = item, count = count }
end

-- ------------------------------------------------------------------ pure

tests["bank put away: the names agreed"] = function(t)
    t.eq(P.NAME, "bankPutAway")
    t.eq(P.KIND, "bank")
    t.eq(P.SERVICE, "banker")
    t.eq(P.TAKE_OUT, "bankTakeOut")
    t.eq(P.MIN_STACKS, 4)
    t.eq(P.NEARLY_FULL, 3)
    t.eq(P.WEIGHT, 1)
    t.eq(P.KEEP, 5)
    local seen = {}
    for _, name in ipairs({ "NOT_STARTED", "OFF", "AT_BANK", "BAGS_UNREAD", "RESERVATIONS_UNKNOWN",
                            "NOT_WORTH", "FAILED", "NO_BANK", "WHAT", "TAKE_WHAT" }) do
        local words = P[name]
        t.ok(type(words) == "string" and words ~= "", name .. " is said")
        t.ok(not seen[words], name .. " is its own line")
        seen[words] = true
    end
end

tests["bank put away: stacks are summed, a row with none is not known, never one"] = function(t)
    local n, unknown = P.Stacks({ { stacks = 3 }, { stacks = 2 } })
    t.eq(n, 5)
    t.eq(unknown, 0)
    n, unknown = P.Stacks({ { stacks = 3 }, { count = 12 } })
    t.eq(n, 3)
    t.eq(unknown, 1)
    n, unknown = P.Stacks(nil)
    t.eq(n, 0)
    t.eq(unknown, 0)
end

tests["bank put away: under the minimum no stop, at the minimum a stop"] = function(t)
    t.eq(P.Worth(P.MIN_STACKS - 1, nil, false), false)
    t.eq(P.Worth(P.MIN_STACKS, nil, false), true)
    t.eq(P.Worth(2, 2, false, 4), true, "a minimum handed in")
end

tests["bank put away: things to take out count towards the stop"] = function(t)
    t.eq(P.Worth(P.MIN_STACKS - 1, 1, false), true)
    t.eq(P.Worth(0, P.MIN_STACKS, false), true)
    t.eq(P.Worth(P.MIN_STACKS - 1, nil, false), false, "out not known adds nothing")
end

tests["bank put away: nearly full bags make any stack worth it, never none"] = function(t)
    t.eq(P.Worth(1, nil, true), true)
    t.eq(P.Worth(0, 1, true), true)
    t.eq(P.Worth(0, nil, true), false)
    t.eq(P.Worth(nil, nil, true), false)
    t.eq(P.Worth(1, nil, nil), false, "not known is not nearly full")
end

tests["bank put away: the slots behind the rows, most stacks first"] = function(t)
    local items = P.Count(
        { row(LEATHER, "Light Leather", 25), row(LINEN, "Linen Cloth", 60) },
        { stack(LINEN, 20), stack(LEATHER, 20), stack(LINEN, 20), stack(LEATHER, 5), stack(LINEN, 20), stack(POTION, 5) })
    t.eq(#items, 2)
    t.eq(items[1].key, LINEN)
    t.eq(items[1].stacks, 3)
    t.eq(items[1].count, 60)
    t.eq(items[2].key, LEATHER)
    t.eq(items[2].stacks, 2)
end

tests["bank put away: a part held by your steps has no stack count, never a guess"] = function(t)
    local items = P.Count({ row(LINEN, "Linen Cloth", 12), row(LEATHER, "Light Leather", 20) },
        { stack(LINEN, 20), stack(LEATHER, 20) })
    t.eq(items[1].key, LEATHER, "known stacks first")
    t.eq(items[1].stacks, 1)
    t.eq(items[2].stacks, nil)
    t.eq(items[2].count, 12)
    local none = P.Count({ row(LINEN, "Linen Cloth", 20) }, nil)
    t.eq(none[1].stacks, nil, "bags not read: not known")
end

tests["bank put away: the words carry the numbers, one form each"] = function(t)
    t.ok(P.Text(5, nil):find("5", 1, true) ~= nil)
    t.ok(P.Text(5, 3):find("3", 1, true) ~= nil)
    t.ok(P.Text(0, 3):find("3", 1, true) ~= nil)
    t.ok(P.Text(5, 0) == P.Text(5, nil), "no take out: the put away form")
    t.ok(P.Text(5, 3) ~= P.Text(5, 0))
    t.ok(P.Text(0, 4) ~= P.Text(4, 0))
    t.ok(P.Text(1, 0) ~= P.Text(2, 0))
end

local function input(stacks, more)
    local out = { stacks = stacks, items = { row(LINEN, "Linen Cloth", 20 * stacks) } }
    for k, v in pairs(more or {}) do out[k] = v end
    return out
end

tests["bank put away: the step, at the nearest banker you have used"] = function(t)
    local step, why = P.Of(input(5, { near = NEAR }))
    t.eq(why, nil)
    t.eq(step.kind, P.KIND)
    t.eq(step.stacks, 5)
    t.eq(step.out, nil, "out not known stays nil")
    t.eq(step.text, P.Text(5, nil))
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    t.eq(step.radius, P.RADIUS)
    t.eq(step.yards, 100)
    t.eq(step.name, NEAR.name)
    t.eq(step.optional, true)
    t.eq(step.weight, P.WEIGHT)
    t.eq(step.why, nil)
    t.eq(step.items[1].key, LINEN)
    t.eq(step.words, { step.text, P.WHAT })
end

tests["bank put away: no banker known, no place and a plain reason"] = function(t)
    local step = P.Of(input(5, {}))
    t.eq(step.place, nil)
    t.eq(step.yards, nil)
    t.eq(step.why, P.NO_BANK)
    t.eq(step.words, { step.text, P.WHAT, P.NO_BANK })
    local odd = P.Of(input(5, { near = { kind = "banker", map = 1411, x = 2, y = 0.3 } }))
    t.eq(odd.place, nil, "a place that is no place is not pointed at")
    local other = P.Of(input(5, { near = { kind = "vendor", map = 1411, x = 0.5, y = 0.3 } }))
    t.eq(other.place, nil, "another kind is not a bank")
end

tests["bank put away: under the minimum no step, with the reason"] = function(t)
    local step, why = P.Of(input(P.MIN_STACKS - 1, { near = NEAR }))
    t.eq(step, nil)
    t.eq(why, P.NOT_WORTH)
    step = P.Of(input(P.MIN_STACKS - 1, { near = NEAR, nearlyFull = true }))
    t.eq(step.stacks, P.MIN_STACKS - 1)
    step, why = P.Of(nil)
    t.eq(step, nil)
    t.eq(why, P.NOT_WORTH)
end

tests["bank put away: the take out adds its words and its count"] = function(t)
    local step = P.Of(input(P.MIN_STACKS - 1, { near = NEAR, out = 1 }))
    t.eq(step.out, 1)
    t.eq(step.text, P.Text(P.MIN_STACKS - 1, 1))
    t.eq(step.words, { step.text, P.WHAT, P.TAKE_WHAT })
end

-- ---------------------------------------------------------------- module

local function cloth(stacks)
    local out = { stack(POTION, 5) }
    for _ = 1, stacks do out[#out + 1] = stack(LINEN, 20) end
    return out
end

local BANKER = { a = { map = 1411, x = 0.5, y = 0.3, name = "Made Up Banker", kinds = { banker = true } } }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services } } })
    c.setItemInfo(INFO)
    c.setBagItems(cloth(opts.stacks or 0))
    c.setBags({ { free = opts.free or 10, total = 16, family = 0 } })
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.reservations ~= false then ns.Reservations.Declare(k) end
    if opts.takeOut then
        k:Module({ name = P.TAKE_OUT, needs = {}, provides = { List = opts.takeOut }, start = function() end })
    end
    local api = P.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["bank put away module: at the minimum a step, at a banker you used"] = function(t)
    local k, _, api = start({ stacks = P.MIN_STACKS, services = BANKER })
    local step, why = api.step()
    t.eq(why, nil)
    t.eq(step.kind, P.KIND)
    t.eq(step.stacks, P.MIN_STACKS)
    t.eq(step.items[1].key, LINEN)
    t.eq(step.items[1].stacks, P.MIN_STACKS)
    t.eq(#step.items, 1, "the potion stays with you")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    t.eq(k.use(P.NAME).Step().stacks, P.MIN_STACKS, "others ask for it by name")
end

tests["bank put away module: under the minimum no step"] = function(t)
    local _, _, api = start({ stacks = P.MIN_STACKS - 1, services = BANKER })
    local step, why = api.step()
    t.eq(step, nil)
    t.eq(why, P.NOT_WORTH)
end

tests["bank put away module: nearly full bags make a few stacks worth it"] = function(t)
    local _, _, api = start({ stacks = 2, free = P.NEARLY_FULL, services = BANKER })
    t.eq(api.step().stacks, 2)
end

tests["bank put away module: no banker used, no place and the reason"] = function(t)
    local _, _, api = start({ stacks = P.MIN_STACKS })
    local step = api.step()
    t.eq(step.stacks, P.MIN_STACKS)
    t.eq(step.place, nil)
    t.eq(step.why, P.NO_BANK)
end

tests["bank put away module: no step while the bank window is open"] = function(t)
    local _, c, api = start({ stacks = P.MIN_STACKS, services = BANKER })
    t.ok(api.step() ~= nil)
    c.setBankOpen(true)
    local step, why = api.step()
    t.eq(step, nil)
    t.eq(why, P.AT_BANK)
    c.setBankOpen(false)
    t.ok(api.step() ~= nil)
end

tests["bank put away module: Flow's own off switch, imported, turns the step off"] = function(t)
    local _, _, api = start({ stacks = P.MIN_STACKS, services = BANKER,
        account = { settings = { banker = { off = true } } } })
    local step, why = api.step()
    t.eq(step, nil)
    t.eq(why, P.OFF)
end

tests["bank put away module: reservations not known, no step"] = function(t)
    local _, _, api = start({ stacks = P.MIN_STACKS, services = BANKER, reservations = false })
    local step, why = api.step()
    t.eq(step, nil)
    t.eq(why, P.RESERVATIONS_UNKNOWN)
end

tests["bank put away module: the answer is kept for P.KEEP seconds"] = function(t)
    local _, c, api = start({ stacks = P.MIN_STACKS, services = BANKER })
    t.eq(api.step().stacks, P.MIN_STACKS)
    c.setBagItems(cloth(P.MIN_STACKS + 2))
    t.eq(api.step().stacks, P.MIN_STACKS, "kept")
    c.advance(P.KEEP + 1)
    t.eq(api.step().stacks, P.MIN_STACKS + 2, "asked again")
end

tests["bank put away module: the take out list counts; not known stays nil"] = function(t)
    local _, _, api = start({ stacks = P.MIN_STACKS - 1, services = BANKER,
        takeOut = function() return { rows = { { key = 4865 } }, unread = 0 } end })
    local step = api.step()
    t.eq(step.stacks, P.MIN_STACKS - 1)
    t.eq(step.out, 1)
    local _, _, unknown = start({ stacks = P.MIN_STACKS - 1, services = BANKER,
        takeOut = function() return nil, "not seen" end })
    local none, why = unknown.step()
    t.eq(none, nil, "a bank not seen adds nothing")
    t.eq(why, P.NOT_WORTH)
    local _, _, raises = start({ stacks = P.MIN_STACKS, services = BANKER, takeOut = function() error("boom") end })
    t.eq(raises.step().out, nil, "a list that raises adds nothing and stops nothing")
    local _, _, absent = start({ stacks = P.MIN_STACKS, services = BANKER })
    t.eq(absent.step().out, nil, "no take out module: not known")
end

tests["bank put away module: a read that raises is said, not passed on"] = function(t)
    local _, c, api = start({ stacks = P.MIN_STACKS, services = BANKER })
    c.bags = function() error("boom") end
    local ok, step, why = pcall(api.step)
    t.ok(ok, "the call does not raise")
    t.eq(step, nil)
    t.eq(why, P.FAILED)
end

-- Nothing acts: every client function the step calls is noted, and none of
-- them moves, takes, puts, sells, buys or uses a thing; the bags are as
-- they were.
tests["bank put away module: nothing is moved"] = function(t)
    local _, c, api = start({ stacks = P.MIN_STACKS, services = BANKER })
    local called, n = {}, 0
    for name, fn in pairs(c) do
        if type(fn) == "function" then
            c[name] = function(...)
                called[name] = true
                n = n + 1
                return fn(...)
            end
        end
    end
    t.eq(api.step().stacks, P.MIN_STACKS)
    t.ok(n > 0, "the calls are seen")
    for name in pairs(called) do
        local w = tostring(name):lower()
        t.ok(not (w:find("deposit") or w:find("withdraw") or w:find("pickup") or w:find("sell") or w:find("click")
            or w:find("^use") or w:find("^buy") or w:find("^move") or w:find("^equip") or w:find("^delete")),
            "a read, not an act: " .. w)
    end
    t.eq(#c.bagItems(), P.MIN_STACKS + 1, "the bags are as they were")
end

return tests
