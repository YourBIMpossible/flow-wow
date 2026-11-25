local _, ns = ...

-- Tests for ZFlow/Gear/BagUpgrades.lua (parity rows C-30 and C-31): the
-- bag items that are an upgrade you can wear now for your chosen role, as
-- rows, as advisor prompts and as the `gear check` word. Advice only:
-- nothing is equipped. The pure Rows on made-up verdicts; Check and the
-- module on the fake client (setBagItems, setItem, setWorn) and a real
-- kernel with the advisor. Made-up items; not tested in game.
--
-- Red before the code: ns.GearBagUpgrades does not exist.

local tests = {}
local function U() return ns.GearBagUpgrades end

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, TOUGH, STRONG, WEAK, PLATE, HIGH, LEGS = "item:11", "item:12", "item:13", "item:14", "item:15",
    "item:16", "item:17"
local BIG, BIGGER = "item:21", "item:22"

local function packs(evidence)
    return { WARRIOR = {
        weights = {
            dps = { evidence = evidence or "first guess", values = { [STR] = 1, [STA] = 0.35 } },
        },
        proficiency = { evidence = "first guess", [4] = { [0] = true, [1] = true, [2] = true, [3] = true } },
    } }
end

local function piece(kind, stats, unmet, minLevel)
    return { kind = kind, stats = stats, classID = 4, subclassID = 3, minLevel = minLevel or 1, unmet = unmet or {} }
end

local function helm(stats, unmet, minLevel) return piece("INVTYPE_HEAD", stats, unmet, minLevel) end

local function client()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(TOUGH, helm({ [STA] = 10 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(PLATE, helm({ [STR] = 30 }, { "Plate" }))
    c.setItem(HIGH, helm({ [STR] = 40 }, { "Requires Level 40" }, 40))
    c.setItem(LEGS, piece("INVTYPE_LEGS", { [STR] = 9 }))
    c.setItem(BIG, helm({ [STR] = 20 }))
    c.setItem(BIGGER, helm({ [STR] = 30 }))
    c.setWorn(1, WORN)
    return c
end

local function bags(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { item = link, count = 1 } end
    return out
end

-- A made-up verdict detail, as Gear/Verdict.lua's second answer.
local function detail(verdict, delta, more)
    local d = { use = { can = true }, weights = "authored",
                result = { verdict = verdict, delta = delta, slot = "head", reason = "made up" } }
    for key, value in pairs(more or {}) do d[key] = value end
    return d
end

local function judgeOf(map)
    return function(link) return map[link] end
end

local function items(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do out[i] = row.item end
    return out
end

local function texts(advisor)
    local out = {}
    for i, p in ipairs(advisor.List()) do out[i] = p.text end
    return out
end

-- A kernel with the advisor, the role row (Rotation/Role.lua's, declared
-- here so a role can be chosen) and the module. `before`: the gear word
-- that was there first (Gear/TooltipModule.lua's in the add-on).
local function start(c, pk, before)
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    if before then diag.commands.gear = before end
    local advisor = ns.Advisor.Declare(k)
    k:Setting({ key = "spec.role", scope = "char", type = "string", default = "", label = "Your role" })
    local api = U().Declare(k, pk or packs(), diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return k, advisor, api, diag
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function line(text) return ns.id.title .. ": " .. text end

tests["bag upgrades: the module and its words exist"] = function(t)
    t.eq(type(U()), "table", "ns.GearBagUpgrades")
    if type(U()) ~= "table" then return end
    t.eq(type(U().Rows), "function", "GearBagUpgrades.Rows")
    t.eq(type(U().Check), "function", "GearBagUpgrades.Check")
    t.eq(type(U().Text), "function", "GearBagUpgrades.Text")
    t.eq(U().SETTING, "gear.bagAdvice")
    t.eq(U().MAX, 3)
    t.eq(U().NONE, "No upgrades in your bags.")
end

tests["bag upgrades rows: the upgrades, best first, each with its slot, role and gain"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local rows, why = U().Rows(bags("a", "b", "c", "b"), judgeOf({
        a = detail("upgrade", 2),
        b = detail("upgrade", 7.3),
        c = detail("worse", -1),
    }), "dps")
    t.eq(why, nil)
    t.eq(items(rows), { "b", "a" }, "best first; the same link once")
    t.eq({ rows[1].slot, rows[1].role, rows[1].gain, rows[1].what, rows[1].guess },
         { "head", "dps", 7.3, "your head piece", false })
end

tests["bag upgrades rows: equal gains keep the bag order"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local rows = U().Rows(bags("a", "b", "c"), judgeOf({
        a = detail("upgrade", 2), b = detail("upgrade", 2), c = detail("upgrade", 2),
    }), "dps")
    t.eq(items(rows), { "a", "b", "c" })
end

tests["bag upgrades rows: not known is never an upgrade"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local same = ns.GearTooltip.SAME
    local stacks = bags("unread", "cannot", "notKnown", "tiny", "noDelta", "nan", "good")
    stacks[#stacks + 1] = { item = 2589, count = 5 }
    stacks[#stacks + 1] = "not a stack"
    local rows, why = U().Rows(stacks, judgeOf({
        cannot = detail("upgrade", 9, { use = { can = false } }),
        notKnown = detail("upgrade", 9, { use = {} }),
        tiny = detail("upgrade", same / 2),
        noDelta = detail("upgrade", nil),
        nan = detail("upgrade", 0 / 0),
        good = detail("upgrade", same),
    }), "dps")
    t.eq(why, nil)
    t.eq(items(rows), { "good" }, "only the one at the mark's own threshold (GearTooltip.SAME)")
end

tests["bag upgrades rows: first-guess weights are marked on the row; weights with no label too"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local rows = U().Rows(bags("a", "b", "c"), judgeOf({
        a = detail("upgrade", 3, { weights = "first guess" }),
        b = detail("upgrade", 2, { weights = "authored" }),
        c = detail("upgrade", 1, { weights = false }),
    }), "dps")
    t.eq({ rows[1].guess, rows[2].guess, rows[3].guess }, { true, false, true })
end

tests["bag upgrades rows: the whole check cannot run - one reason, no rows"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local R = U().REASON
    local judge = judgeOf({ a = detail("upgrade", 5) })
    local rows, why = U().Rows(nil, judge, "dps")
    t.eq({ rows == nil, why }, { true, R.bags }, "the bags not read")
    rows, why = U().Rows(bags("a"), judge, "")
    t.eq({ rows == nil, why }, { true, R.role }, "no role chosen")
    rows, why = U().Rows(bags("a"), judge, nil)
    t.eq({ rows == nil, why }, { true, R.role }, "no role read")
    t.eq(R.role, "choose a role")
    t.eq(R.worn, "what you wear was not read")
    local wornUnread = { verdict = "none", reason = ns.GearScore.REASON.worn .. ": head" }
    rows, why = U().Rows(bags("a", "b"), judgeOf({
        a = detail("none", nil, { result = wornUnread }), b = detail("none", nil, { result = wornUnread }),
    }), "dps")
    t.eq({ rows == nil, why }, { true, R.worn }, "every piece you could wear met a slot not read")
    local noWeights = { verdict = "none", reason = ns.GearScore.REASON.weights }
    rows, why = U().Rows(bags("a"), judgeOf({ a = detail("none", nil, { result = noWeights }) }), "dps")
    t.eq({ rows == nil, why }, { true, R.weights }, "no weights for the role")
end

tests["bag upgrades rows: one slot not read hides that piece only"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local wornUnread = { verdict = "none", reason = ns.GearScore.REASON.worn .. ": legs" }
    local rows, why = U().Rows(bags("a", "b"), judgeOf({
        a = detail("none", nil, { result = wornUnread }), b = detail("upgrade", 4),
    }), "dps")
    t.eq(why, nil)
    t.eq(items(rows), { "b" })
    rows, why = U().Rows(bags("a", "b"), judgeOf({
        a = detail("none", nil, { result = wornUnread }), b = detail("worse", -4),
    }), "dps")
    t.eq(rows, {}, "a piece that was compared and is no upgrade: the check ran")
    t.eq(why, nil)
    rows, why = U().Rows(bags(), judgeOf({}), "dps")
    t.eq(rows, {}, "empty bags: the check ran")
    t.eq(why, nil)
end

tests["bag upgrades text: the item, the gain, the role and the slot; first-guess weights are said"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local row = { item = "[Helm]", role = "dps", gain = 7.3, what = "your head piece", guess = false }
    t.eq(U().Text(row), "Equip [Helm] from your bags: +7.3 for dps over your head piece")
    row.gain, row.guess = 5, true
    t.eq(U().Text(row), "Equip [Helm] from your bags: +5 for dps over your head piece (first-guess weights)")
    t.eq(U().Text(row):lower():find("clear", 1, true), nil, "a first guess is not called a clear upgrade")
    row.guess, row.empty = false, true
    t.eq(U().Text(row), "Equip [Helm] from your bags: +5 for dps over nothing worn (your head piece)")
end

tests["bag upgrades check: the fake client's bags, by the real verdict"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    -- dps: the worn helm scores 2.7; STRONG 10 (+7.3), TOUGH 3.5 (+0.8),
    -- WEAK 0.35 (worse). PLATE and HIGH carry a mark of the game's: no.
    -- item:99 was never read. LEGS: the legs slot was not read.
    c.setBagItems(bags(WEAK, TOUGH, PLATE, HIGH, "item:99", LEGS, STRONG))
    local rows, why = U().Check(c, packs(), "dps")
    t.eq(why, nil)
    t.eq(items(rows), { STRONG, TOUGH })
    if type(rows) ~= "table" or type(rows[1]) ~= "table" then return end
    t.eq({ rows[1].slot, rows[1].role, rows[1].guess }, { "head", "dps", true })
    t.ok(math.abs(rows[1].gain - 7.3) < 1e-9, "the gain: " .. tostring(rows[1].gain))
    t.eq(U().Check(c, packs("authored"), "dps")[1].guess, false, "weights not marked first guess")
    rows, why = U().Check(c, packs(), "")
    t.eq({ rows == nil, why }, { true, U().REASON.role })
    rows, why = U().Check(c, packs(), "tank")
    t.eq({ rows == nil, why }, { true, U().REASON.weights }, "a role the pack has no weights for")
    c.setBagItems(bags(LEGS))
    rows, why = U().Check(c, packs(), "dps")
    t.eq({ rows == nil, why }, { true, U().REASON.worn })
    c.setBagItems(nil)
    rows, why = U().Check(c, packs(), "dps")
    t.eq({ rows == nil, why }, { true, U().REASON.bags })
    rows, why = U().Check({}, packs(), "dps")
    t.eq({ rows == nil, why }, { true, U().REASON.bags })
    t.eq(c.equipCalls, 0, "look only")
end

tests["bag upgrades module: a prompt per upgrade, at most three, best first; gone with the item"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(TOUGH, STRONG))
    local k, advisor, api = start(c)
    t.eq(k:ModuleState(U().NAME), "started")
    t.eq(texts(advisor), {
        "Equip " .. STRONG .. " from your bags: +7.3 for dps over your head piece (first-guess weights)",
        "Equip " .. TOUGH .. " from your bags: +0.8 for dps over your head piece (first-guess weights)",
    }, "no role chosen: the levelling role, dps, as Flow's LevelingRole")
    k.settings:set("spec.role", "dps")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(texts(advisor), {
        "Equip " .. STRONG .. " from your bags: +7.3 for dps over your head piece (first-guess weights)",
        "Equip " .. TOUGH .. " from your bags: +0.8 for dps over your head piece (first-guess weights)",
    })
    t.eq(api.shown(), { U().ID .. STRONG, U().ID .. TOUGH })
    c.setBagItems(bags(TOUGH, STRONG, BIG, BIGGER))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(api.shown(), { U().ID .. BIGGER, U().ID .. BIG, U().ID .. STRONG }, "the best three")
    t.eq(#advisor.List(), 3)
    t.eq(advisor.List()[1].id, U().ID .. BIGGER, "best first on the panel")
    t.eq(advisor.List()[3].id, U().ID .. STRONG)
    c.setBagItems(bags(TOUGH))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(api.shown(), { U().ID .. TOUGH }, "the ones that left the bags are gone")
    c.setWorn(1, STRONG)
    c.fire("PLAYER_EQUIPMENT_CHANGED")
    t.eq(advisor.List(), {}, "no longer an upgrade over what is worn")
    t.eq(api.shown(), {})
    t.eq(k.problems:count(), 0)
    t.eq(c.equipCalls, 0)
end

tests["bag upgrades module: weights not marked first guess - the line does not say so"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(STRONG))
    local k, advisor = start(c, packs("authored"))
    k.settings:set("spec.role", "dps")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(texts(advisor), { "Equip " .. STRONG .. " from your bags: +7.3 for dps over your head piece" })
end

tests["bag upgrades module: off shows nothing; the bags not read takes the prompts away"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(STRONG))
    local k, advisor, api = start(c)
    t.eq(k.settings:get(U().SETTING), true, "on by default")
    k.settings:set("spec.role", "dps")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#advisor.List(), 1)
    c.setBagItems(nil)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(advisor.List(), {}, "not read: no advice to equip")
    c.setBagItems(bags(STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#advisor.List(), 1)
    t.eq(k.settings:set(U().SETTING, false), true)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(advisor.List(), {})
    t.eq(api.shown(), {})
end

tests["bag upgrades module: a read that raises is one gear problem, and no prompt"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(STRONG))
    local k, advisor, api = start(c)
    k.settings:set("spec.role", "dps")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#advisor.List(), 1)
    c.setReadFails("class", true)
    c.fire("BAG_UPDATE_DELAYED")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(advisor.List(), {})
    t.eq(api.errors(), 2)
    t.eq(k.problems:count("gear"), 1, "the same error is one problem")
    c.setReadFails("class", false)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#advisor.List(), 1, "and it recovers")
end

tests["bag upgrades word: check lists the rows; the reason when it cannot run"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(WEAK))
    local k = start(c)
    t.eq(said(c, "gear check"), { line("Bag upgrades cannot be checked: choose a role (say "
        .. ns.id.slash .. " role).") })
    k.settings:set("spec.role", "dps")
    t.eq(said(c, "gear check"), { line("No upgrades in your bags.") })
    c.setBagItems(bags(WEAK, TOUGH, STRONG))
    t.eq(said(c, "gear check"), {
        line("Upgrades in your bags, for dps:"),
        line("Equip " .. STRONG .. " from your bags: +7.3 for dps over your head piece (first-guess weights)"),
        line("Equip " .. TOUGH .. " from your bags: +0.8 for dps over your head piece (first-guess weights)"),
    })
    c.setBagItems(bags(LEGS))
    t.eq(said(c, "gear check"), { line("Bag upgrades cannot be checked: what you wear was not read.") })
    c.setBagItems(nil)
    t.eq(said(c, "gear check"), { line("Bag upgrades cannot be checked: your bags could not be read.") })
    t.eq(c.equipCalls, 0)
    t.eq(k.problems:count(), 0)
end

tests["bag upgrades word: on and off switch the advice; the usage; other sub-words are kept"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    c.setBagItems(bags(STRONG))
    local ran = {}
    local k, advisor, _, diag = start(c, nil, function(rest) ran[#ran + 1] = rest end)
    k.settings:set("spec.role", "dps")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(#advisor.List(), 1)
    t.eq(said(c, "gear off"), { line("Bag upgrade advice is off.") })
    t.eq(k.settings:get(U().SETTING), false)
    t.eq(advisor.List(), {}, "off takes the prompts away at once")
    t.eq(#said(c, "gear check"), 2, "the word still lists them when asked")
    t.eq(said(c, "gear on"), { line("Bag upgrade advice is on.") })
    t.eq(k.settings:get(U().SETTING), true)
    t.eq(#advisor.List(), 1, "on brings them back at once")
    t.eq(ran, {}, "check, on and off are this file's")
    said(c, "gear why")
    said(c, "gear sets mine")
    t.eq(ran, { "why", "sets mine" }, "other sub-words go to the word that was there, as given")
    local usage = said(c, "gear")
    t.eq(#usage, 1)
    for _, word in ipairs({ " gear check", " gear on", " gear off", " gear why" }) do
        t.ok((usage[1] or ""):find(ns.id.slash .. word, 1, true) ~= nil,
             "the usage names" .. word .. ": " .. tostring(usage[1]))
    end
    t.ok((usage[1] or ""):find("other roles", 1, true) ~= nil, "and the keep off-spec setting")
    t.eq(#ran, 2, "the bare word is the usage")
    t.eq(type(diag.help.gear), "string", "the word has a help line")
    t.eq(c.equipCalls, 0)
    t.eq(k.problems:count(), 0)
end

tests["bag upgrades word: with no gear word there before, another sub-word says how"] = function(t)
    if type(U()) ~= "table" then return t.ok(false, "ns.GearBagUpgrades") end
    local c = client()
    start(c)
    local out = said(c, "gear nonsense")
    t.eq(#out, 1)
    t.ok((out[1] or ""):find(ns.id.slash .. " gear check", 1, true) ~= nil, tostring(out[1]))
end

return tests
