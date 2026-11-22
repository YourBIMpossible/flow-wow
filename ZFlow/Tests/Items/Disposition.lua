local _, ns = ...

-- Tests for ZFlow/Items/Disposition.lua. Pure: items and context are made up.

local D, R = ns.Disposition, ns.Resources
local tests = {}

local function leather(count)
    return { key = 2318, name = "Light Leather", count = count, quality = 1, sellPrice = 15, classID = 7 }
end

tests["disposition: nothing known means keep, with unknown as the basis"] = function(t)
    local d = D.Decide(leather(5), {})
    t.eq(d.action, "keep", "no rule has an opinion: kept")
    t.eq(d.reason, "no rule matched", "and it says why")
    t.eq(d.basis, "unknown", "the basis is unknown, not a recommendation")
    t.eq(d.rule, nil, "no rule decided")
    t.eq(d.count, 5, "it applies to all five")
    t.eq(D.Decide(leather(5)).action, "keep", "no context at all: kept")
    local odd = D.Decide("Light Leather", {})
    t.ok(odd.action == "keep" and odd.basis == "unknown", "not an item table: kept")
    t.eq(D.Decide(nil, {}).action, "keep", "nothing: kept")
    t.eq(D.Decide({ key = 2318 }, {}).count, nil, "no count known: the decision has none, and covers all")
end

tests["disposition: every decision says its rule and its basis"] = function(t)
    local c = {
        choices = { keep = { [1] = true }, never = { [2] = true } },
        tools = { [3] = "Mining" },
        questItems = { [4] = { quest = "Wolves at the Gate", inLog = true }, [5] = { quest = "Later", level = 14 } },
        classKeep = { [6] = { why = "for your class quest", untilLevel = 20 } },
        level = 10,
    }
    local function of(item) local d = D.Decide(item, c); return d.action .. "/" .. tostring(d.rule) .. "/" .. d.basis end
    t.eq(of({ key = 1, count = 1 }), "keep/yourChoice/choice", "the player's own keep")
    t.eq(of({ key = 2, count = 1 }), "keep/neverSell/choice", "bought back once")
    t.eq(of({ key = 99, count = 1, sellPrice = 0 }), "keep/unsellable/fact", "the game says it can't be sold")
    t.eq(of({ key = 3, count = 1 }), "keep/professionTool/fact", "a profession's tool")
    t.eq(of({ key = 98, count = 1, classID = 12 }), "keep/quest/fact", "a quest item by its class")
    t.eq(of({ key = 4, count = 1 }), "keep/questNeeds/fact", "needed by a quest in the log")
    t.eq(of({ key = 6, count = 1 }), "keep/classKeep/recommendation", "kept for the class")
    t.eq(of({ key = 97, count = 3, quality = 0, sellPrice = 4 }), "sell/junk/recommendation", "grey with a price: sell")
    t.eq(D.Decide({ key = 3, count = 1 }, c).reason, "tool for Mining", "the reason names the profession")
    t.eq(D.Decide({ key = 4, count = 1 }, c).reason, "for your quest: Wolves at the Gate", "the quest's name")
    t.eq(D.Decide({ key = 5, count = 1 }, c).reason, "for an upcoming quest: Later (level 14)", "an upcoming quest and its level")
    t.eq(D.Decide({ key = 97, count = 3, quality = 0, sellPrice = 4 }, c).count, 3, "a sell covers the count")
end

tests["disposition: an unknown price or quality sells nothing"] = function(t)
    t.eq(D.Decide({ key = 1, count = 2, quality = 0 }, {}).action, "keep", "grey with no price known: kept")
    t.eq(D.Decide({ key = 1, count = 2, sellPrice = 4 }, {}).action, "keep", "a price but no quality known: kept")
    t.eq(D.Decide({ key = 1, count = 2, quality = 0, sellPrice = 0 }, {}).rule, "unsellable", "grey that can't be sold: kept as unsellable")
    t.eq(D.Decide({ key = 1, count = 2, quality = 1, sellPrice = 4 }, {}).action, "keep", "white with a price: not junk")
    t.eq(D.Decide({ key = 1, count = 2, quality = 0, sellPrice = -1 }, {}).action, "keep", "a price that isn't a count: kept")
end

tests["disposition: a keep lists every reason"] = function(t)
    local c = {
        choices = { keep = { [2318] = true } },
        questItems = { [2318] = { quest = "Leather for Lina", inLog = true } },
        classKeep = { [2318] = { why = "for your class quest" } },
    }
    local d = D.Decide(leather(4), c)
    t.eq(d.rule, "yourChoice", "the first rule decides")
    t.eq(#d.reasons, 3, "three reasons apply")
    t.eq(d.reasons[1], "you chose to keep it", "the deciding one first")
    t.eq(d.reason, "you chose to keep it; for your quest: Leather for Lina; for your class quest", "joined for the player")
    -- A class-keep past its level is no longer a reason.
    c.level = 30
    c.classKeep[2318].untilLevel = 20
    t.eq(#D.Decide(leather(4), c).reasons, 2, "past the level it was wanted until: that reason is gone")
    c.level = nil
    t.eq(#D.Decide(leather(4), c).reasons, 3, "a level that isn't known does not end it")
    -- A sell lists no reasons table.
    t.eq(D.Decide({ key = 5, count = 1, quality = 0, sellPrice = 2 }, {}).reasons, nil, "only a keep collects reasons")
end

tests["disposition: what claims hold is kept by count, the rest goes on"] = function(t)
    local grants = R.Resolve(R.Fake({ bags = { [2318] = 12 } }), {
        { owner = "quest:8", kind = "item", key = 2318, amount = 8 },
    })
    local d = D.Decide({ key = 2318, count = 12, quality = 0, sellPrice = 3 }, { grants = grants })
    t.eq(d.action, "keep", "the held part is kept")
    t.eq(d.rule, "held", "by the held rule")
    t.eq(d.count, 8, "8 of the 12")
    t.eq(d.basis, "fact", "a claim holding it is a fact")
    t.eq(d.reason, "8 held for your steps", "with the count in the reason")
    t.ok(d.rest ~= nil and d.rest.action == "sell" and d.rest.count == 4 and d.rest.rule == "junk",
        "the other 4 are decided by the rules after it: grey with a price, sold")
    t.eq(D.CountOf(d, "keep"), 8, "kept in all")
    t.eq(D.CountOf(d, "sell"), 4, "sold in all")
    -- Nothing after it has an opinion: the rest is kept as unknown.
    local white = D.Decide(leather(12), { grants = grants })
    t.ok(white.rest.action == "keep" and white.rest.basis == "unknown" and white.rest.count == 4, "4 kept, basis unknown")
    t.eq(D.CountOf(white, "keep"), 12, "all 12 kept, for two different reasons")
    -- Everything is held: no rest.
    local all = D.Decide(leather(6), { grants = grants })
    t.ok(all.count == 6 and all.rest == nil, "6 owned, 8 held: all kept, nothing left over")
    -- Nothing is held: the rule has no opinion.
    t.eq(D.Decide({ key = 4306, count = 3 }, { grants = grants }).rule, nil, "an item no claim holds")
    -- A rule ahead of it keeps everything: no split.
    local chosen = D.Decide(leather(12), { grants = grants, choices = { keep = { [2318] = true } } })
    t.ok(chosen.count == 12 and chosen.rest == nil, "the player's keep covers all 12")
    t.eq(#chosen.reasons, 2, "and the held reason is listed with it")
    -- No count known: nothing is split, and CountOf says it doesn't know.
    local blind = D.Decide({ key = 2318, quality = 0, sellPrice = 3 }, { grants = grants })
    t.ok(blind.action == "keep" and blind.rest == nil and blind.count == nil, "count unknown: all kept, none sold")
    t.eq(D.CountOf(blind, "keep"), nil, "and no number is given")
end

tests["disposition: a later keep rule that fails while reasons are gathered is reported"] = function(t)
    local seen = {}
    local rules = {
        { key = "first", order = 1, check = function() return { action = "keep", reason = "needed", basis = "fact" } end },
        { key = "broken", order = 2, check = function() error("boom") end },
        { key = "third", order = 3, check = function() return { action = "keep", reason = "liked", basis = "fact" } end },
    }
    local d = D.Decide(leather(3), { rules = rules, onError = function(key, err) seen[#seen + 1] = key .. "|" .. tostring(err) end })
    t.eq(d.action, "keep")
    t.eq(d.rule, "first")
    t.eq(d.reasons, { "needed", "liked" }, "the failing rule adds no reason and stops no later one")
    t.eq(#seen, 1, "the failing check was not reported, or more than once")
    t.ok(seen[1]:find("broken|", 1, true) == 1 and seen[1]:find("boom", 1, true) ~= nil, "with the rule and the error")
    local quiet = D.Decide(leather(3), { rules = rules, onError = function() error("again") end })
    t.eq(quiet.reasons, { "needed", "liked" }, "a failing error handler changes nothing")
    t.eq(D.Decide(leather(3), { rules = rules }).reasons, { "needed", "liked" }, "nor does having none")
end

tests["disposition: a rule that fails keeps the item"] = function(t)
    local seen = {}
    local rules = {
        { key = "broken", order = 1, check = function() error("boom") end },
        { key = "sellAll", order = 2, check = function() return { action = "sell", reason = "sell it", basis = "recommendation" } end },
    }
    local d = D.Decide(leather(3), { rules = rules, onError = function(key, err) seen[#seen + 1] = key .. "|" .. tostring(err) end })
    t.eq(d.action, "keep", "the item is kept, not passed to the rule that would sell it")
    t.eq(d.rule, "broken", "the failing rule is named")
    t.eq(d.basis, "unknown", "the basis is unknown")
    t.eq(d.failed, true, "and the decision says a check failed")
    t.eq(#seen, 1, "the error is reported once")
    t.ok(seen[1]:find("broken|", 1, true) == 1 and seen[1]:find("boom", 1, true) ~= nil, "with the rule and the error")
    -- A verdict that isn't one is treated the same way.
    local odd = D.Decide(leather(3), { rules = {
        { key = "odd", order = 1, check = function() return { action = "burn" } end },
        rules[2],
    } })
    t.ok(odd.action == "keep" and odd.rule == "odd" and odd.failed == true, "an unknown action: kept")
    local text = D.Decide(leather(3), { rules = { { key = "text", order = 1, check = function() return "sell" end }, rules[2] } })
    t.ok(text.action == "keep" and text.failed == true, "a verdict that isn't a table: kept")
    -- An error in onError itself does not get out.
    local quiet = D.Decide(leather(3), { rules = rules, onError = function() error("again") end })
    t.eq(quiet.action, "keep", "a failing error handler changes nothing")
    -- A basis that isn't one of the four reads as unknown.
    local vague = D.Decide(leather(3), { rules = { { key = "v", check = function() return { action = "sell", basis = "hunch" } end } } })
    t.ok(vague.action == "sell" and vague.basis == "unknown", "an unknown basis is not passed off as a fact")
end

tests["disposition: rules run in order, whatever the list's order"] = function(t)
    local function rule(key, order, action)
        return { key = key, order = order, check = function() return { action = action, reason = key, basis = "recommendation" } end }
    end
    local list = { rule("late", 30, "sell"), rule("early", 2, "keep"), rule("middle", 10, "auction") }
    t.eq(D.Decide(leather(1), { rules = list }).rule, "early", "the lowest order decides")
    t.eq(D.Decide(leather(1), { rules = { list[1], list[3] } }).rule, "middle", "then the next")
    local ties = { rule("first", 5, "sell"), rule("second", 5, "keep") }
    t.eq(D.Decide(leather(1), { rules = ties }).rule, "first", "the same order: the list's order")
    local noOrder = { rule("unordered", nil, "sell"), rule("ordered", 99, "keep") }
    t.eq(D.Decide(leather(1), { rules = noOrder }).rule, "ordered", "no order counts as 100")
    t.eq(D.Decide(leather(1), { rules = { "junk", { key = "nocheck" }, rule("real", 1, "equip") } }).rule, "real",
        "entries that aren't rules are skipped")
    t.eq(D.Decide(leather(1), { rules = {} }).reason, "no rule matched", "no rules: kept, no rule matched")
    -- A generic keep is not listed among another keep's reasons.
    local generic = { rule("why", 1, "keep"), { key = "fallback", order = 2, generic = true,
        check = function() return { action = "keep", reason = "not gear" } end } }
    t.eq(#D.Decide(leather(1), { rules = generic }).reasons, 1, "a fallback keep is not a reason worth listing")
    -- The built-in list is in order and every rule has a key.
    local last, ok = -1, true
    for _, r in ipairs(D.RULES) do
        if type(r.key) ~= "string" or type(r.order) ~= "number" or r.order < last then ok = false end
        last = r.order
    end
    t.ok(ok, "the built-in rules have keys and rising orders")
end

tests["disposition: deciding changes neither the item nor the context"] = function(t)
    local function deepCopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = deepCopy(x) end
        return out
    end
    local item = leather(12)
    local c = { choices = { keep = {} }, questItems = { [2318] = { quest = "Q", inLog = true } }, level = 10 }
    local itemWas, cWas = deepCopy(item), deepCopy(c)
    local rulesWas, rowsWas = {}, deepCopy(D.RULES)
    for i, r in ipairs(D.RULES) do rulesWas[i] = r end
    local verdict = D.Decide(item, c)
    t.ok(verdict ~= nil, "a decision came back")
    t.eq(item, itemWas, "the whole item is as it was, nothing added")
    t.eq(c, cWas, "the whole context is as it was, the quest items it read included")
    t.eq(#D.RULES, #rulesWas, "the built-in list is no longer or shorter")
    for i, r in ipairs(rulesWas) do
        t.ok(D.RULES[i] == r, "rule " .. i .. " is the same row in the same place")
    end
    t.eq(D.RULES, rowsWas, "and no rule row was written to")
    t.ok(item.count == 12 and item.key == 2318 and item.rule == nil and item.action == nil, "the item is as it was")
    t.ok(c.level == 10 and c.rules == nil and next(c.choices.keep) == nil, "the context too")
    t.eq(#D.RULES, 9, "and the built-in list has its nine rules")
end

return tests
