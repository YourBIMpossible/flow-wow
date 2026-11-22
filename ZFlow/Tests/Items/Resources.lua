local _, ns = ...

-- Tests for ZFlow/Items/Resources.lua. Pure: every snapshot is made up here.
-- The cases of Modules/Reserve.lua's tests (Modules/Tests/Professions.lua,
-- "reserve: ...") are carried over, each under the same heading, in the new
-- claim shape; the item cases are new.

local R = ns.Resources
local tests = {}

-- A snapshot with money and `general` free slots in the bags that take anything.
local function snap(money, general)
    return R.Fake({ money = money, slots = general and { [0] = { free = general, total = general } } or nil })
end
-- grants -> { [owner] = grant }
local function byOwner(grants)
    local by = {}
    for _, g in ipairs(grants) do by[g.claim.owner] = g end
    return by
end
-- grants -> "kind:owner=got/short ..." in the order they were resolved
local function line(grants)
    local parts = {}
    for _, g in ipairs(grants) do
        parts[#parts + 1] = string.format("%s:%s=%s/%s%s", tostring(g.claim.kind), tostring(g.claim.owner),
            tostring(g.got), tostring(g.short), g.unknown and ("?" .. g.unknown) or "")
    end
    return table.concat(parts, " ")
end
local SLOTS = R.SlotKey(0)

tests["resources: the selected step's money and slot claims come first"] = function(t)
    local function claims(pick)
        return {
            { owner = "train:class", activity = "quest", kind = "money", amount = 800, priority = R.MILESTONE },
            { owner = "train:Mining", activity = "professions", kind = "money", amount = 500, priority = 2,
              selected = pick == "train:Mining" },
            { owner = "buy:1", activity = "quest", kind = "slots", amount = 2, priority = 1 },
            { owner = "buy:2", activity = "professions", kind = "slots", amount = 2, priority = 2,
              selected = pick == "buy:2" },
        }
    end
    local plain = byOwner(R.Resolve(snap(1000, 3), claims()))
    t.eq(plain["train:class"].got, 800, "nothing picked: the milestone is paid first")
    t.eq(plain["train:Mining"].got, 0, "and the profession tier waits")
    t.eq(plain["train:Mining"].short, 500, "500 short")
    t.eq(plain["train:Mining"].before, 800, "with 800 held ahead of it")
    t.eq(plain["buy:1"].got, 2, "slots: the quest's claim first")
    t.eq(plain["buy:2"].got, 1, "the other gets what's left")
    t.eq(plain["buy:2"].short, 1, "and is one short")
    local picked = byOwner(R.Resolve(snap(1000, 3), claims("train:Mining")))
    t.eq(picked["train:Mining"].got, 500, "picked: the profession tier is paid first, before a milestone")
    t.eq(picked["train:class"].got, 0, "and class training waits")
    t.eq(picked["buy:1"].got, 2, "a pick moves only its own claim: the slot claims stay as they were")
    local slotPick = byOwner(R.Resolve(snap(1000, 3), claims("buy:2")))
    t.eq(slotPick["buy:2"].got, 2, "a picked step's slot claim comes first")
    t.eq(slotPick["buy:1"].got, 1, "the quest's then gets the rest")
    t.eq(slotPick["train:class"].got, 800, "and the money claims stay as they were")
end

tests["resources: required before optional, then priority, then the owner"] = function(t)
    local g = R.Resolve(snap(nil, 4), {
        { owner = "a:optional", activity = "quest", kind = "slots", amount = 1, priority = 1, required = false },
        { owner = "b:required", activity = "professions", kind = "slots", amount = 1, priority = 2 },
        { owner = "c:forQuest", activity = "professions", kind = "slots", amount = 1, priority = 1 },
        { owner = "d:required", activity = "quest", kind = "slots", amount = 1, priority = 1, required = true },
        { owner = "a:required", activity = "professions", kind = "slots", amount = 1, priority = 2 },
    })
    t.eq(line(g), "slots:c:forQuest=1/0 slots:d:required=1/0 slots:a:required=1/0 slots:b:required=1/0 slots:a:optional=0/1",
        "required first; priority; then the owner; the optional one last, and short")
    -- Money: required, then priority, then the cheaper, then the owner.
    local m = R.Resolve(snap(10000), {
        { owner = "z", activity = "professions", kind = "money", amount = 10, priority = 2 },
        { owner = "y", activity = "professions", kind = "money", amount = 10, priority = 2 },
        { owner = "x", activity = "professions", kind = "money", amount = 5, priority = 2 },
        { owner = "w", activity = "quest", kind = "money", amount = 900, priority = 1 },
        { owner = "v", activity = "quest", kind = "money", amount = 1, priority = 1, required = false },
        { owner = "u", activity = "professions", kind = "money", amount = 2000, priority = R.MILESTONE },
    })
    t.eq(line(m), "money:u=2000/0 money:w=900/0 money:x=5/0 money:y=10/0 money:z=10/0 money:v=1/0",
        "milestone, the quest's (priority) before the cheaper profession ones, cheaper first, owner, optional last")
    t.eq(m:Held(R.MONEY), 2926, "all of it fits")
    t.eq(m:Free(R.MONEY), 7074, "and the rest is free")
    -- No priorities given: every claim ranks the same.
    local flat = R.Resolve(snap(100), {
        { owner = "b", activity = "professions", kind = "money", amount = 60 },
        { owner = "a", activity = "quest", kind = "money", amount = 70 },
    })
    t.eq(line(flat), "money:b=60/0 money:a=0/70", "without priorities the cheaper goes first")
end

tests["resources: two passes, an optional claim never starves a required one"] = function(t)
    local shot = R.Fake({ bags = { leather = 5 } })
    local upgrade = { owner = "upgrade:A", activity = "profession:A", kind = "item", key = "leather", amount = 5,
                      priority = 1, required = false }
    local craft = { owner = "craft:B", activity = "profession:B", kind = "item", key = "leather", amount = 5, priority = 2 }
    local one = byOwner(R.Resolve(shot, { upgrade, craft }))
    t.eq(one["craft:B"].got, 5, "the required craft gets the leather though the optional one ranks higher")
    t.eq(one["upgrade:A"].got, 0, "the optional upgrade gets nothing")
    t.eq(one["upgrade:A"].short, 5, "and is five short")
    local two = byOwner(R.Resolve(shot, { craft, upgrade }))
    t.eq(two["craft:B"].got, 5, "the same with the list the other way round")
    -- A pick does not lift an optional claim over a required one.
    local pickedUpgrade = { owner = "upgrade:A", activity = "profession:A", kind = "item", key = "leather", amount = 5,
                            required = false, selected = true }
    local three = byOwner(R.Resolve(shot, { pickedUpgrade, craft }))
    t.eq(three["craft:B"].got, 5, "picked but optional: still after every required claim")
    -- Money and slots go by the same two passes.
    local m = R.Resolve(snap(100, 1), {
        { owner = "opt", kind = "money", amount = 10, required = false, selected = true },
        { owner = "req", kind = "money", amount = 100 },
        { owner = "optslot", kind = "slots", amount = 1, required = false, priority = 0 },
        { owner = "reqslot", kind = "slots", amount = 1, priority = 9 },
    })
    t.eq(line(m), "money:req=100/0 slots:reqslot=1/0 money:opt=0/10 slots:optslot=0/1",
        "required money and slots first, then the optional ones")
end

tests["resources: money keeps the order route costs were paid in"] = function(t)
    -- Milestones first, then the cheaper, then the key: the cases of Flow's
    -- "route: steps that cost money are paid for together", through ClaimsOf.
    local function run(steps, money)
        local g = R.Resolve(R.Fake({ money = money }), R.ClaimsOf(steps))
        local over = {}
        for _, x in ipairs(g) do
            if x.short and x.short > 0 then over[x.claim.owner] = x.before end
        end
        return g, over
    end
    local train = { key = "train:class", cost = 800, milestone = true }
    local riding = { key = "mount:riding", cost = 600 }
    local cheap = { key = "train:Cooking", cost = 100 }
    local g, over = run({ riding, cheap, train }, 1000)
    t.eq(g:Held(R.MONEY), 900, "three steps, 10s: training and cooking are paid")
    t.eq(over["mount:riding"], 900, "riding is over, with 900 held ahead of it")
    t.eq(over["train:class"], nil, "training is not over")
    g, over = run({ riding, cheap, train }, 5000)
    t.eq(g:Held(R.MONEY), 1500, "enough for all")
    t.eq(next(over), nil, "none is over")
    g = run({ { key = "x", cost = 900, held = "needs Mining" }, cheap }, 200)
    t.eq(g:Held(R.MONEY), 100, "a held step asks for nothing")
    t.eq(#g, 1, "one grant")
    g, over = run({ { key = "a", cost = 700 }, { key = "b", cost = 700 } }, 1000)
    t.eq(g:Held(R.MONEY), 700, "two the same price: one is paid")
    t.eq(over.b, 700, "the later key is over")
    g, over = run({ { key = "big", cost = 900 }, { key = "small", cost = 50 }, { key = "mid", cost = 400 } }, 500)
    t.eq(g:Held(R.MONEY), 450, "a later one fits after one that didn't")
    t.eq(over.big, 450, "the dear one is over, behind the two cheaper")
    g = run({ { key = "free", cost = 0 }, { key = "odd", cost = -5 }, cheap }, 100)
    t.eq(g:Held(R.MONEY), 100, "no cost and a negative cost ask for nothing")
    t.eq(#g, 1, "one grant")
    g = run({}, 100)
    t.eq(#g, 0, "no steps: no grants")
    t.eq(g:Held(R.MONEY), 0, "nothing held")
end

tests["resources: a unit is granted once"] = function(t)
    -- Made-up claims from a fixed sequence (no math.random: the same every run).
    local seed = 12345
    local function rnd(n)
        seed = (seed * 1103 + 12347) % 65536
        return math.floor(seed / 7) % n
    end
    local acts, kinds, items, bad = { "quest", "professions", "other" }, { "money", "slots", "item" }, { "ore", "leather" }, 0
    for _ = 1, 60 do
        local claims = {}
        for i = 1, 1 + rnd(14) do
            local kind = kinds[1 + rnd(3)]
            local c = { owner = "s" .. rnd(8), activity = acts[1 + rnd(3)], kind = kind }
            if kind == "money" then c.amount = rnd(900) elseif kind == "slots" then c.amount = rnd(5) else c.amount = rnd(9) end
            if kind == "item" then
                c.key = items[1 + rnd(2)]
                if rnd(2) == 0 then c.bank = true end
            end
            if rnd(4) == 0 then c.required = false end
            if rnd(7) == 0 then c.amount = nil end
            if rnd(9) == 0 and c.amount then c.amount = -c.amount - 1 end
            if rnd(6) == 0 then c.priority = rnd(3) end
            if rnd(8) == 0 then c.selected = true end
            claims[i] = c
        end
        local money, general = rnd(2000), rnd(8)
        local bags = { ore = rnd(10), leather = rnd(10) }
        local bank = { ore = rnd(6), leather = rnd(6) }
        local g = R.Resolve(R.Fake({ money = money, slots = { [0] = { free = general, total = 16 } }, bags = bags, bank = bank }),
            claims)
        local sum = { money = 0, slots = 0, ore = 0, leather = 0 }
        for _, x in ipairs(g) do
            local what = x.claim.kind == "item" and x.claim.key or x.claim.kind
            sum[what] = sum[what] + (x.got or 0)
            if x.unknown then
                if x.short ~= nil then bad = bad + 1 end
            elseif x.invalid then
                if x.got ~= 0 or x.short ~= 0 then bad = bad + 1 end
            elseif x.got < 0 or x.short < 0 or x.got + x.short ~= x.claim.amount then
                bad = bad + 1
            end
        end
        if #g ~= #claims then bad = bad + 1 end
        if sum.money > money or sum.slots > general then bad = bad + 1 end
        if sum.ore > bags.ore + bank.ore or sum.leather > bags.leather + bank.leather then bad = bad + 1 end
        if sum.money ~= g:Held(R.MONEY) or sum.slots ~= g:Held(SLOTS) then bad = bad + 1 end
        if sum.ore ~= g:Held("ore") or sum.leather ~= g:Held("leather") then bad = bad + 1 end
        if g:Free(R.MONEY) ~= money - sum.money or g:Free(SLOTS) ~= general - sum.slots then bad = bad + 1 end
        if g:Free("ore") ~= bags.ore + bank.ore - sum.ore then bad = bad + 1 end
    end
    t.eq(bad, 0, "60 made-up sets: never more granted than there is, every claim answered once, got + short = asked")
end

tests["resources: the same claims in another order give the same grants"] = function(t)
    local function claims()
        return {
            { owner = "train:class", activity = "quest", kind = "money", amount = 800, priority = R.MILESTONE },
            { owner = "train:Mining", activity = "professions", kind = "money", amount = 300, priority = 2 },
            { owner = "train:Herbalism", activity = "professions", kind = "money", amount = 300, priority = 2 },
            { owner = "recipe:1", activity = "professions", kind = "money", amount = 300, priority = 2, required = false },
            { owner = "train:Cooking", activity = "professions", kind = "money", priority = 2 },
            { owner = "buy:9", activity = "quest", kind = "slots", amount = 2, priority = 1 },
            { owner = "buy:2320", activity = "professions", kind = "slots", amount = 2, priority = 2 },
            { owner = "buy:2321", activity = "professions", kind = "slots", amount = 2, priority = 2, required = false },
        }
    end
    local want = line(R.Resolve(snap(1500, 3), claims()))
    t.eq(want, "money:train:class=800/0 money:train:Herbalism=300/0 money:train:Mining=300/0 money:train:Cooking=nil/nil?price"
        .. " slots:buy:9=2/0 slots:buy:2320=1/1 money:recipe:1=0/300 slots:buy:2321=0/2", "the grants, in order")
    local list = claims()
    local reversed = {}
    for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
    t.eq(line(R.Resolve(snap(1500, 3), reversed)), want, "the list reversed: the same")
    local differ = 0
    for shift = 1, #list - 1 do
        local turned = {}
        for i = 1, #list do turned[i] = list[(i + shift - 1) % #list + 1] end
        if line(R.Resolve(snap(1500, 3), turned)) ~= want then differ = differ + 1 end
    end
    t.eq(differ, 0, "every rotation of the list: the same")
    t.eq(line(R.Resolve(snap(1500, 3), claims())), want, "and the same again on a second run")
end

tests["resources: equal claims keep the order they came in"] = function(t)
    local a = { owner = "same", activity = "quest", kind = "money", amount = 60, tag = "first" }
    local b = { owner = "same", activity = "quest", kind = "money", amount = 60, tag = "second" }
    local c = { owner = "same", activity = "quest", kind = "money", amount = 60, tag = "third" }
    local g = R.Resolve(snap(100), { a, b, c })
    t.eq(g[1].claim.tag .. "," .. g[2].claim.tag .. "," .. g[3].claim.tag, "first,second,third", "a tie keeps the list's order")
    t.eq(g[1].got, 60, "the first is paid")
    t.eq(g[2].got + g[3].got, 0, "the others are not: 60 is granted once")
    -- The same owner in two activities: the activity's name decides, not the list.
    local q = { owner = "k", activity = "quest", kind = "slots", amount = 1 }
    local p = { owner = "k", activity = "professions", kind = "slots", amount = 1 }
    t.eq(R.Resolve(snap(nil, 1), { q, p })[1].claim.activity, "professions", "same owner, no priorities: by the activity's name")
    t.eq(R.Resolve(snap(nil, 1), { p, q })[1].claim.activity, "professions", "whichever came first")
end

tests["resources: an unknown price is neither granted nor refused"] = function(t)
    local g = R.Resolve(snap(1000), {
        { owner = "train:Mining", activity = "professions", kind = "money", estimate = 400, priority = R.MILESTONE },
        { owner = "train:Cooking", activity = "professions", kind = "money", amount = 900 },
        { owner = "train:Fishing", activity = "professions", kind = "money" },
    })
    local by = byOwner(g)
    local mining = by["train:Mining"]
    t.eq(mining.unknown, "price", "no price: the grant says the price is unknown")
    t.eq(mining.got, nil, "it is not granted")
    t.eq(mining.short, nil, "and not short either: Z-Flow doesn't know")
    t.eq(mining.estimate, 400, "the estimate rides along for the text")
    t.eq(by["train:Cooking"].got, 900, "the estimate holds no money: a known price behind it is still paid in full")
    t.eq(g:Held(R.MONEY), 900, "only the known price is held")
    t.eq(g:Free(R.MONEY), 100, "what's left is counted without the estimate")
    t.eq(by["train:Fishing"].unknown, "price", "a claim with no amount at all: unknown too")
    t.eq(g.unknown, 2, "two unknown grants are counted")
    -- Money that couldn't be read: every money claim is unknown, none is refused.
    local blind = R.Resolve(snap(nil, 2), {
        { owner = "train:class", activity = "quest", kind = "money", amount = 1 },
        { owner = "buy:1", activity = "quest", kind = "slots", amount = 1 },
    })
    local bb = byOwner(blind)
    t.eq(bb["train:class"].unknown, "money", "money not read: unknown, not 'you can't pay'")
    t.eq(bb["train:class"].short, nil, "not short")
    t.eq(blind:Free(R.MONEY), nil, "and no number for what's free")
    t.eq(bb["buy:1"].got, 1, "the slots were read: that claim is answered")
    local noBags = R.Resolve(snap(50), { { owner = "buy:1", activity = "quest", kind = "slots", amount = 1 } })
    t.eq(noBags[1].unknown, "slots", "bags not read: the slot claim is unknown")
    t.eq(noBags[1].got, nil, "nothing known: nothing held")
    t.eq(noBags:Free(SLOTS), nil, "no number for free slots")
    t.eq(R.Resolve(nil, { { owner = "x", activity = "quest", kind = "money", amount = 1 } })[1].unknown, "money",
        "no snapshot at all: unknown")
end

tests["resources: zero, negative and broken amounts hold nothing"] = function(t)
    local g = R.Resolve(snap(100, 2), {
        { owner = "zero", kind = "money", amount = 0 },
        { owner = "neg", kind = "money", amount = -500 },
        { owner = "text", kind = "money", amount = "12" },
        { owner = "nan", kind = "money", amount = 0 / 0 },
        { owner = "inf", kind = "money", amount = math.huge },
        { owner = "real", kind = "money", amount = 100 },
        { owner = "negslot", kind = "slots", amount = -3 },
        { owner = "zeroslot", kind = "slots", amount = 0 },
        { owner = "slot", kind = "slots", amount = 2 },
    })
    local by = byOwner(g)
    t.ok(by.zero.got == 0 and by.zero.short == 0 and not by.zero.invalid, "nothing asked: nothing held, nothing short")
    for _, k in ipairs({ "neg", "text", "nan", "inf", "negslot" }) do
        t.ok(by[k].invalid == true and by[k].got == 0 and by[k].short == 0, k .. ": not a count, holds nothing")
    end
    t.eq(g.invalid, 5, "five claims refused")
    t.eq(by.real.got, 100, "a negative claim adds no money: exactly 100 is there for the real one")
    t.eq(g:Held(R.MONEY), 100, "100 held")
    t.eq(g:Free(R.MONEY), 0, "nothing left, and not less than nothing")
    t.eq(by.slot.got, 2, "a negative slot claim adds no room")
    t.eq(g:Free(SLOTS), 0, "no slot left")
    -- Nothing to hand out.
    local empty = R.Resolve(snap(0, 0), {
        { owner = "m", kind = "money", amount = 1 },
        { owner = "s", kind = "slots", amount = 1 },
        { owner = "free", kind = "money", amount = 0 },
    })
    local eb = byOwner(empty)
    t.ok(eb.m.got == 0 and eb.m.short == 1, "no money: one copper is one short")
    t.ok(eb.s.got == 0 and eb.s.short == 1, "no room: one slot is one short")
    t.ok(eb.free.got == 0 and eb.free.short == 0, "a step that costs nothing fits with no money")
    -- A snapshot that isn't a count is unknown, never a debt.
    t.eq(R.Resolve(R.Fake({ money = -50 }), { { owner = "m", kind = "money", amount = 1 } })[1].unknown, "money",
        "negative money: unknown")
    t.eq(R.Resolve({ money = -50 }, { { owner = "m", kind = "money", amount = 1 } })[1].unknown, "money",
        "the same for a snapshot not made by Fake")
    t.eq(#R.Resolve(snap(10, 1), nil), 0, "no claims: no grants")
    t.eq(#R.Resolve(snap(10, 1), {}), 0, "an empty list: no grants")
end

tests["resources: a claim is checked before it is counted"] = function(t)
    local function why(c)
        local ok, problem = R.CheckClaim(c)
        return ok and "ok" or problem
    end
    t.eq(why({ owner = "a", kind = "money", amount = 5 }), "ok", "a money claim")
    t.eq(why({ owner = "a", kind = "money" }), "ok", "no amount is allowed: it means not known")
    t.eq(why({ owner = "a", kind = "slots", amount = 1 }), "ok", "a slot claim with no family: the general bags")
    t.eq(why({ owner = "a", kind = "item", key = 2318, amount = 1, bank = true }), "ok", "an item claim")
    t.eq(why("money"), "a claim is a table", "not a table")
    t.eq(why({ kind = "money", amount = 5 }), "no owner", "no owner")
    t.eq(why({ owner = {}, kind = "money" }), "the owner is not a name", "an owner that isn't a name")
    t.eq(why({ owner = "a", kind = "gold" }), "kind is not money, slots or item", "an unknown kind")
    t.eq(why({ owner = "a", amount = 5 }), "kind is not money, slots or item", "no kind")
    t.eq(why({ owner = "a", kind = "item", amount = 1 }), "an item claim needs a key", "an item with no key")
    t.eq(why({ owner = "a", kind = "item", key = {}, amount = 1 }), "the item key is not a name or a number", "a table as a key")
    t.eq(why({ owner = "a", kind = "slots", key = "herbs", amount = 1 }), "the bag family is not a number", "a family by name")
    t.eq(why({ owner = "a", kind = "money", amount = -1 }), "the amount is not a count", "a negative amount")
    t.eq(why({ owner = "a", kind = "money", amount = 1, priority = "high" }), "the priority is not a number", "a priority in words")
    t.eq(why({ owner = "a", kind = "money", estimate = -4 }), "the estimate is not a count", "a negative estimate")
    -- A refused claim is still answered, once, and holds nothing.
    local g = R.Resolve(snap(100, 2), {
        "not a claim",
        { kind = "money", amount = 50 },
        { owner = "ok", kind = "money", amount = 50 },
        { owner = "odd", kind = "gold", amount = 50 },
    })
    t.eq(#g, 4, "four claims, four grants")
    t.eq(g.invalid, 3, "three refused")
    t.eq(g:Held(R.MONEY), 50, "only the good one holds money")
    t.eq(g[1].claim.owner, "ok", "the good claim is resolved first; the refused ones are listed after")
    t.eq(g[2].problem, "a claim is a table", "each with what's wrong with it")
    t.eq(#g:For("ok"), 1, "For skips a grant whose claim isn't a table")
end

tests["resources: free slots by family, with an explicit unknown"] = function(t)
    local s = R.Slots({
        { free = 4, total = 16, family = 0 },
        { free = 6, total = 16, family = 0 },
        { free = 10, total = 20, family = 32 },     -- a bag for one kind of thing
        { free = 0, total = 16, family = 0 },
        { free = 3, total = 8, family = 1 },        -- another
    })
    t.eq(s[0].free, 10, "family 0: the bags that take anything")
    t.eq(s[0].total, 48, "and their size")
    t.eq(s[32].free, 10, "a special bag is counted under its own family")
    t.eq(s[1].free, 3, "each family apart")
    t.eq(s.unknown, nil, "every bag said what it holds")
    t.eq(R.SlotsAll(s), 23, "all: every bag, whatever it holds")
    local unsure = R.Slots({ { free = 4, family = 0 }, { free = 8 } })
    t.eq(unsure[0].free, 4, "a bag with no family given is not counted as general")
    t.eq(unsure.unknown.free, 8, "its room is listed as unknown")
    t.eq(R.SlotsAll(unsure), 12, "it is still room in all")
    t.eq(R.Slots(nil), nil, "no bag API: unknown, not 0 and not 99")
    t.eq(R.SlotsAll(nil), nil, "and no total")
    local none = R.Slots({})
    t.eq(next(none), nil, "no bag answered: no family has room")
    t.eq(R.SlotsAll(none), 0, "nothing free")
    local odd = R.Slots({ { free = -2, family = 0 }, { free = "3", family = 0 }, { free = 5, family = 0 } })
    t.eq(odd[0].free, 5, "a count that isn't one is left out")
    -- The snapshot carries the slots, and money as it was given.
    local shot = R.Fake({ money = 1234, slots = R.Slots({ { free = 2, family = 0 }, { free = 9, family = 8 } }) })
    t.eq(shot.money, 1234, "money")
    t.ok(shot.slots[0].free == 2 and shot.slots[8].free == 9, "both families")
    local blank = R.Fake({})
    t.ok(blank.money == nil and blank.slots == nil and blank.bags == nil and blank.bank == nil, "nothing given: all unknown")
    t.eq(blank.bankKnown, false, "the bank has not been seen")
    t.eq(R.Fake({ money = -1 }).money, nil, "money that isn't a count: unknown")
    t.eq(R.Fake({ slots = { [0] = "unknown" } }).slots[0], R.UNKNOWN, "a family can be marked unknown")
    t.eq(R.SlotsAll(R.Fake({ slots = { [0] = "unknown" } }).slots), nil, "then there is no total")
end

tests["resources: a slot claim counts its own kind of bag, then the general bags"] = function(t)
    -- 2 free in the backpack, 12 in a herb bag (family 32).
    local shot = R.Fake({ money = 0, slots = { [0] = { free = 2, total = 16 }, [32] = { free = 12, total = 12 } } })
    local g = R.Resolve(shot, {
        { owner = "buy:a", activity = "quest", kind = "slots", amount = 2 },
        { owner = "buy:b", activity = "quest", kind = "slots", amount = 3 },
    })
    local by = byOwner(g)
    t.eq(by["buy:a"].got, 2, "the first claim takes the two general slots")
    t.eq(by["buy:b"].got, 0, "the herb bag's room is not promised to the second")
    t.eq(by["buy:b"].short, 3, "it is three short")
    t.eq(g:Free(SLOTS), 0, "no general slot left")
    t.eq(g:Free(R.SlotKey(32)), 12, "the herb bag is untouched")
    -- A claim bigger than what's there is granted as far as it goes.
    local part = R.Resolve(shot, { { owner = "buy:c", kind = "slots", amount = 5 } })
    t.ok(part[1].got == 2 and part[1].short == 3, "5 asked, 2 there: 2 held, 3 short")
    -- A herb goes in the herb bag first, then in a general bag.
    local herb = R.Resolve(shot, { { owner = "gather:herb", kind = "slots", key = 32, amount = 13 } })
    t.eq(herb[1].got, 13, "13 herbs: 12 in the herb bag and one in the backpack")
    t.ok(herb[1].from[32] == 12 and herb[1].from[0] == 1, "and the grant says from where")
    t.eq(herb:Held(R.SlotKey(32)), 12, "held in the herb bag")
    t.eq(herb:Held(SLOTS), 1, "held in the backpack")
    -- A family with no bag of its kind: only the general room, and that is known.
    local noBag = R.Resolve(R.Fake({ slots = { [0] = { free = 1, total = 16 } } }),
        { { owner = "gather:ore", kind = "slots", key = 64, amount = 2 } })
    t.ok(noBag[1].got == 1 and noBag[1].short == 1 and noBag[1].unknown == nil, "no mining bag: one fits, one short")
    -- Room in a bag whose family wasn't given: Z-Flow can't say whether it fits.
    local unsure = R.Fake({ slots = { [0] = { free = 1, total = 16 }, unknown = { free = 8, total = 8 } } })
    local fits = R.Resolve(unsure, { { owner = "buy:d", kind = "slots", amount = 1 } })
    t.ok(fits[1].got == 1 and fits[1].short == 0 and fits[1].unknown == nil, "what fits in the known room is granted")
    local over = R.Resolve(unsure, { { owner = "buy:e", kind = "slots", amount = 3 } })
    t.eq(over[1].unknown, "slots", "beyond the known room: unknown, not 'no room'")
    t.eq(over[1].got, 1, "it holds the known slot")
    t.eq(over[1].short, nil, "and is not called short")
    t.eq(over:Free(SLOTS), 0, "the unknown bag's room is promised to no one")
    -- A family marked unknown.
    local marked = R.Resolve(R.Fake({ slots = { [0] = "unknown" } }), { { owner = "buy:f", kind = "slots", amount = 1 } })
    t.eq(marked[1].unknown, "slots", "the general bags unread: unknown")
    t.eq(marked[1].got, nil, "nothing known: nothing held")
end

tests["resources: a snapshot is a copy, and resolving spends nothing"] = function(t)
    local src = { money = 500, slots = { [0] = { free = 3, total = 16 } }, bags = { ore = 5 } }
    local shot = R.Fake(src)
    -- The player's money and bags change after the snapshot was taken.
    src.money, src.slots[0].free, src.bags.ore = 9000, 0, 0
    local claims = {
        { owner = "train:Mining", activity = "professions", kind = "money", amount = 400 },
        { owner = "buy:2320", activity = "professions", kind = "slots", amount = 2 },
        { owner = "smelt", activity = "professions", kind = "item", key = "ore", amount = 4 },
    }
    local g = R.Resolve(shot, claims)
    t.eq(shot.money, 500, "the snapshot keeps the money it was given")
    t.eq(g:Free(R.MONEY), 100, "resolving counts against the snapshot, not the changed table")
    t.eq(g:Free(SLOTS), 1, "the slots too")
    t.eq(g:Free("ore"), 1, "and the items")
    t.eq(g:Held(R.MONEY), 400, "held money")
    t.eq(g:Held(SLOTS), 2, "held slots")
    local again = R.Resolve(shot, claims)
    t.eq(line(again), line(g), "resolving again gives the same: nothing was spent")
    t.eq(R.Resolve(R.Fake({ money = 9000 }), claims):Free(R.MONEY), 8600, "a new snapshot reads again")
    t.eq(shot.takenAt, 0, "a made-up snapshot has no time unless one is given")
    t.eq(R.Fake({ takenAt = 77 }).takenAt, 77, "a given time is kept")
end

tests["resources: claims are read from a step's cost and its own claims"] = function(t)
    local exact = { kind = "money", amount = 250, required = false }
    local claims = R.ClaimsOf({
        { key = "train:class", cost = 800, milestone = true, activity = "quest" },
        { key = "train:Mining", costUnknown = true, costEstimate = 4500, owner = "professions" },
        { key = "held", cost = 900, held = "needs Mining", activity = "quest" },
        { key = "free", cost = 0, activity = "quest" },
        { key = "walk", activity = "quest" },
        { key = "recipe:7", cost = 999, activity = "professions", claims = { exact, { kind = "slots", amount = 1 } } },
        { key = "craft:x", activity = "professions", claims = { { kind = "item", key = 2318, amount = 10 } } },
    })
    local by = {}
    for _, c in ipairs(claims) do by[c.kind .. ":" .. tostring(c.owner)] = c end
    t.eq(#claims, 5, "five claims: a held step, one with no cost and one that costs nothing ask for nothing")
    t.ok(by["money:train:class"].amount == 800 and by["money:train:class"].priority == R.MILESTONE,
        "cost carried over; a milestone becomes the first priority")
    t.eq(by["money:train:class"].activity, "quest", "the step's activity is the claim's")
    local mining = by["money:train:Mining"]
    t.eq(mining.amount, nil, "price unknown: a claim with no amount")
    t.eq(mining.estimate, 4500, "the estimate is carried, not counted")
    t.eq(mining.activity, "professions", "no lane yet: the owner activity")
    t.eq(by["money:recipe:7"].amount, 250, "a step's own money claim replaces the reading of its cost")
    t.eq(by["money:recipe:7"].required, false, "with what it says about itself")
    t.eq(by["money:recipe:7"].owner, "recipe:7", "and gets the step's key as its owner")
    t.eq(exact.owner, nil, "the step's own table is not written to")
    t.eq(by["slots:recipe:7"].amount, 1, "its slot claim too")
    local g = R.Resolve(R.Fake({ money = 5000, slots = { [0] = { free = 4, total = 16 } }, bags = { [2318] = 6 } }), claims)
    t.eq(#g, 5, "five grants")
    local gb = byOwner(g)
    t.eq(gb["train:Mining"].unknown, "price", "the unknown tier price stays unknown with 50s in the bags")
    t.eq(g:Held(R.MONEY), 1050, "800 + 250: the 4500 estimate is not held")
    t.eq(gb["craft:x"].got, 6, "the item claim is resolved now: 6 of 10 are in the bags")
    t.eq(gb["craft:x"].short, 4, "4 short")
end

tests["resources: resolving changes neither the snapshot nor the claims"] = function(t)
    local shot = R.Fake({ money = 300, slots = { [0] = { free = 2, total = 6 } }, bags = { ore = 3 }, bank = { ore = 9 } })
    local claims = {
        { owner = "b", activity = "quest", kind = "money", amount = 200 },
        { owner = "a", activity = "quest", kind = "money", amount = 200 },
        { owner = "s", activity = "quest", kind = "slots", amount = 5 },
        { owner = "i", activity = "quest", kind = "item", key = "ore", amount = 7, bank = true },
    }
    local g = R.Resolve(shot, claims)
    t.ok(shot.money == 300 and shot.slots[0].free == 2 and shot.slots[0].total == 6, "the snapshot is as it was")
    t.ok(shot.bags.ore == 3 and shot.bank.ore == 9, "bags and bank too")
    t.ok(claims[1].owner == "b" and claims[2].owner == "a" and claims[3].owner == "s", "the list keeps its order")
    t.ok(claims[1].amount == 200 and claims[1].got == nil, "a claim is not written to")
    t.eq(g[1].claim, claims[2], "a grant points at its claim")
end

tests["resources: items come from the bags, then the bank when the claim may use it"] = function(t)
    local shot = R.Fake({ bags = { leather = 12 }, bank = { leather = 20 } })
    local quest = { owner = "quest:8", activity = "quest", kind = "item", key = "leather", amount = 8, priority = 1 }
    local craft = { owner = "craft:kit", activity = "profession:Leatherworking", kind = "item", key = "leather", amount = 10,
                    priority = 2 }
    local g = R.Resolve(shot, { craft, quest })
    local by = byOwner(g)
    t.eq(by["quest:8"].got, 8, "a quest that wants 8 of 12 holds 8")
    t.eq(by["craft:kit"].got, 4, "a craft that wants 10 gets the 4 that are left")
    t.eq(by["craft:kit"].short, 6, "and is 6 short: 12 is not enough for both")
    t.eq(by["craft:kit"].before, 8, "with 8 held ahead of it")
    t.eq(g:Held("leather"), 12, "12 held in all")
    t.eq(g:Free("leather"), 20, "what's free is what the bank has")
    -- The same craft, allowed to use the bank.
    local banking = { owner = "craft:kit", activity = "profession:Leatherworking", kind = "item", key = "leather", amount = 10,
                      priority = 2, bank = true }
    local b = byOwner(R.Resolve(shot, { banking, quest }))
    t.eq(b["craft:kit"].got, 10, "with the bank it has all 10")
    t.ok(b["craft:kit"].from.bags == 4 and b["craft:kit"].from.bank == 6, "4 from the bags, 6 from the bank")
    t.eq(b["quest:8"].from.bank, 0, "a claim that didn't ask for the bank takes nothing from it")
    -- The bank has never been seen: what's in it is unknown, not nothing.
    local unseen = R.Fake({ bags = { leather = 12 } })
    local u = byOwner(R.Resolve(unseen, { banking, quest }))
    t.eq(u["craft:kit"].unknown, "bank", "bank unseen: Z-Flow can't say whether there is enough")
    t.eq(u["craft:kit"].got, 4, "it holds what the bags give")
    t.eq(u["craft:kit"].short, nil, "and is not called short")
    local plain = byOwner(R.Resolve(unseen, { craft, quest }))
    t.eq(plain["craft:kit"].short, 6, "a claim that never asked for the bank is simply short")
    t.eq(R.Resolve(unseen, { quest }):Free("leather"), 4, "free without a seen bank: the bags only")
    -- A bank that is given but marked unseen is not used.
    local stale = R.Fake({ bags = { leather = 1 }, bank = { leather = 50 }, bankKnown = false })
    t.eq(byOwner(R.Resolve(stale, { banking }))["craft:kit"].unknown, "bank", "bankKnown false: the bank's count is not trusted")
    -- Bags that weren't read.
    local blind = R.Resolve(R.Fake({ money = 10 }), { quest })
    t.eq(blind[1].unknown, "bags", "bags not read: unknown")
    t.eq(blind[1].got, nil, "nothing held")
    t.eq(blind:Free("leather"), nil, "and no number for what's free")
    -- An item nobody has.
    local none = R.Resolve(shot, { { owner = "x", kind = "item", key = "silk", amount = 2 } })
    t.ok(none[1].got == 0 and none[1].short == 2, "none in the bags: 0 held, 2 short, and that is known")
    -- No amount.
    t.eq(R.Resolve(shot, { { owner = "x", kind = "item", key = "leather" } })[1].unknown, "amount", "an item claim with no amount")
end

tests["resources: a pick orders claims inside its pass only"] = function(t)
    local shot = R.Fake({ bags = { bar = 4 } })
    local a = { owner = "craft:a", activity = "profession:A", kind = "item", key = "bar", amount = 4, priority = 1 }
    local b = { owner = "craft:b", activity = "profession:B", kind = "item", key = "bar", amount = 4, priority = 2 }
    t.eq(byOwner(R.Resolve(shot, { a, b }))["craft:a"].got, 4, "nothing picked: the higher priority gets the bars")
    local picked = { owner = "craft:b", activity = "profession:B", kind = "item", key = "bar", amount = 4, priority = 2,
                     selected = true }
    local g = byOwner(R.Resolve(shot, { a, picked }))
    t.eq(g["craft:b"].got, 4, "picked: it goes first among the required claims")
    t.eq(g["craft:a"].got, 0, "and the other waits")
end

tests["resources: For, Held and Free"] = function(t)
    local g = R.Resolve(R.Fake({ money = 100, bags = { ore = 3 }, slots = { [0] = { free = 2, total = 16 } } }), {
        { owner = "smith", kind = "money", amount = 40 },
        { owner = "smith", kind = "item", key = "ore", amount = 2 },
        { owner = "cook", kind = "money", amount = 30 },
        { owner = "cook", kind = "money", required = false },
    })
    local mine = g:For("smith")
    t.eq(#mine, 2, "two grants for the smith")
    t.ok(mine[1].claim.kind == "money" and mine[2].claim.kind == "item", "in the order they were resolved")
    t.eq(#g:For("cook"), 2, "an unknown grant is still the owner's")
    t.eq(#g:For("nobody"), 0, "none for an owner who asked for nothing")
    t.eq(g:Held(R.MONEY), 70, "money held by everyone together")
    t.eq(g:Held("ore"), 2, "ore held")
    t.eq(g:Held("silk"), 0, "nothing holds what nobody asked for")
    t.eq(g:Held(SLOTS), 0, "no slot was asked for")
    t.eq(g:Free(R.MONEY), 30, "money still free")
    t.eq(g:Free("ore"), 1, "ore still free")
    t.eq(g:Free(SLOTS), 2, "slots still free")
    t.eq(g:Free("silk"), 0, "an item not in the bags: none free, and that is known")
    t.eq(g:Free(R.SlotKey(32)), 0, "a bag family with no bag: no room, and that is known")
    t.eq(R.SlotKey(), "slots:0", "the general bags' key")
end

return tests
