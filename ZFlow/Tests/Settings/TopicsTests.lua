-- The one list of settings topics and the search over rows
-- (Settings/Topics.lua; lead sections 238 and 239, rows N56 and N57). Pure:
-- no client, no kernel. Made-up rows only.
-- Fails before: Settings/Topics.lua is absent (ns.Settings.Topics is nil).
local _, ns = ...

local T = ns.Settings and ns.Settings.Topics

local function has(t)
    local ok = type(T) == "table" and type(T.Find) == "function" and type(T.Fold) == "function"
        and type(T.Match) == "function" and type(T.Pick) == "function"
    t.ok(ok, "ns.Settings.Topics answers Find, Fold, Match and Pick")
    return ok
end

return {
    ["topics: one list, each topic with an id, a player's name and its sections, none twice"] = function(t)
        if not has(t) then return end
        local ids, names = {}, {}
        t.ok(#T.LIST >= 6 and #T.LIST <= T.MENU_MAX, "a few topics, no more than a menu level holds: " .. #T.LIST)
        for i, topic in ipairs(T.LIST) do
            t.ok(type(topic.id) == "string" and topic.id:find("^%l+$") ~= nil, "topic " .. i .. " has a plain id")
            t.ok(type(topic.name) == "string" and topic.name ~= "", "topic " .. i .. " has a name")
            t.ok(not ids[topic.id] and not names[topic.name], tostring(topic.id) .. " is listed once")
            ids[topic.id], names[topic.name] = true, true
            local sections = {}
            for _, section in ipairs(topic.sections) do
                t.ok(type(section.id) == "string" and type(section.name) == "string" and not sections[section.id],
                    topic.id .. "." .. tostring(section.id))
                sections[section.id] = true
            end
        end
    end,

    ["topics: no topic is a bucket called Other, Misc or Test"] = function(t)
        if not has(t) then return end
        for _, topic in ipairs(T.LIST) do
            local name = topic.name:lower()
            for _, bad in ipairs({ "other", "misc", "test" }) do
                t.eq(name:find(bad, 1, true), nil, topic.name)
                t.ok(topic.id ~= bad, topic.id)
            end
        end
        t.eq(T.Find(T.UNFILED.id), nil, "the not-filed marker is not a topic a row may name")
    end,

    ["topics: a group is a listed topic, or a topic and one of its own sections; anything else is unknown"] = function(t)
        if not has(t) then return end
        local topic, section = T.Find("travel")
        t.eq(topic and topic.id, "travel")
        t.eq(section, nil)
        topic, section = T.Find("travel.flights")
        t.eq(topic and topic.id, "travel")
        t.eq(section and section.id, "flights")
        for _, bad in ipairs({ "Other", "Vendor", "Arrows", "Test", "", "travel.", "travel.nosuch", "gear.flights",
            "Travel" }) do
            t.eq(T.Find(bad), nil, "not a topic: " .. bad)
        end
        t.eq(T.Find(nil), nil)
        t.eq(T.Find(7), nil)
    end,

    ["topics: a row with no group, or an unknown one, is not filed (and is not lost)"] = function(t)
        if not has(t) then return end
        t.eq(T.Of({ key = "a.b" }).id, T.UNFILED.id)
        t.eq(T.Of({ key = "a.b", group = "Other" }).id, T.UNFILED.id)
        t.eq(T.Of({ key = "a.b", group = "bags" }).id, "bags")
        t.eq(T.Of(nil).id, T.UNFILED.id)
    end,

    ["fold: capitals, accents and punctuation do not matter"] = function(t)
        if not has(t) then return end
        t.eq(T.Fold("Bags, Vendors and Bank"), "bags vendors and bank")
        t.eq(T.Fold("  SELL  "), "sell")
        t.eq(T.Fold("Caf\195\169"), "cafe")
        t.eq(T.Fold("CAF\195\137"), "cafe")
        t.eq(T.Fold("cafe\204\129"), "cafe", "a mark written after its letter")
        t.eq(T.Fold("\195\156ber-na\195\175ve"), "uber naive")
        t.eq(T.Fold(nil), "")
        t.eq(T.Words("Well   Fed, food"), { "well", "fed", "food" })
        t.eq(T.Words("  "), {})
    end,

    ["match: label, description, topic name, section name and synonyms are all searched; every word must be found"] = function(t)
        if not has(t) then return end
        local row = { key = "x.sellList", label = "Show the sell list", help = "Beside the merchant window.",
            group = "travel.flights", synonyms = { "junk", "vendor trash" } }
        t.ok(T.Match(row, T.Words("sell")), "the label")
        t.ok(T.Match(row, T.Words("MERCHANT")), "the description, whatever the capitals")
        t.ok(T.Match(row, T.Words("junk")), "a synonym")
        t.ok(T.Match(row, T.Words("trash vendor")), "the words of a synonym, in any order")
        t.ok(T.Match(row, T.Words("questing")), "the topic's name")
        t.ok(T.Match(row, T.Words("crossings")), "the section's name")
        t.ok(T.Match(row, T.Words("sell junk")), "two words, found in two places")
        t.eq(T.Match(row, T.Words("sell dragons")), nil, "one word not found: no match")
        t.eq(T.Match(row, {}), nil, "no words: no match")
        t.ok(T.Match(row, T.Words("sell")) > T.Match(row, T.Words("junk")), "a label match counts more")
        t.ok(T.Match(row, T.Words("junk")) > T.Match(row, T.Words("merchant")), "a synonym more than the description")
    end,

    ["pick: a typed topic name finds its topic"] = function(t)
        if not has(t) then return end
        t.eq(T.Pick("bags").id, "bags")
        t.eq(T.Pick("Gear and Loot").id, "gear")
        t.eq(T.Pick("GEAR").id, "gear")
        t.eq(T.Pick("bank").id, "bags")
        t.eq(T.Pick("dungeons").id, "party")
        t.eq(T.Pick("nosuchtopic"), nil)
        t.eq(T.Pick(""), nil)
    end,

    -- Lead section 247 item 5 (MyBuddy, LOW). Fails before: T.Pick took the
    -- first topic whose name held the letters ("ve" gave Travel).
    ["pick: the best match wins, not the first topic that holds the letters"] = function(t)
        if not has(t) then return end
        t.eq(T.Pick("ve").id, "bags", "a word that starts with it beats letters inside another word")
        t.eq(T.Pick("qu").id, "travel")
        t.eq(T.Pick("loot gear").id, "gear")
        t.eq(T.Pick("and").id, T.LIST[1].id, "a tie goes to the list's order")
    end,

    -- Fails before: T.Pick read no rows, so a synonym named no topic.
    ["pick: with the rows given, a synonym names its topic; a topic's own name counts more"] = function(t)
        if not has(t) then return end
        local rows = {
            { key = "a.sell", label = "Sell list", group = "bags", synonyms = { "junk", "sell" } },
            { key = "a.note", label = "Note", group = "gear.loot", synonyms = { "grey", "vendor trash" } },
            { key = "a.tip", label = "Tip", group = "party", synonyms = { "buffs" } },
        }
        t.eq(T.Pick("junk"), nil, "no rows given: only the names")
        local junk, sell, trash = T.Pick("junk", rows), T.Pick("sell", rows), T.Pick("trash", rows)
        t.eq(junk and junk.id, "bags")
        t.eq(sell and sell.id, "bags")
        t.eq(trash and trash.id, "gear", "a word of a synonym")
        t.eq(T.Pick("buffs", rows).id, "buffs", "the topic named so, not the one with the synonym")
        t.eq(T.Pick("dragons", rows), nil)
    end,
}
