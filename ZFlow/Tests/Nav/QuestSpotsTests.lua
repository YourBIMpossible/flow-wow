local _, ns = ...

-- Tests for ZFlow/Nav/QuestSpots.lua (S43): where the player stood when an
-- objective's count went up or a quest was handed in, learned from the
-- player's own play, account wide. Made-up quests and places only.

local tests = {}

local function QS() return ns.Nav.QuestSpots end

local function row(id, title, texts, complete)
    local r = { id = id, title = title, complete = complete == true, failed = false, objectives = {} }
    for i, text in ipairs(texts or {}) do r.objectives[i] = { text = text, done = false } end
    return r
end

tests["quest spots: the module is there"] = function(t)
    t.ok(type(QS()) == "table", "ns.Nav.QuestSpots")
    t.eq(QS().PATH, "learned.places.questSpots", "the path the Flow import fills")
    t.eq(QS().TURN_IN, 0, "the turn-in is objective 0")
end

tests["quest spots: an objective whose text changes is a change; a new quest is not"] = function(t)
    local before = { row(1, "Rats", { "Rats slain: 0/5", "Cheese: 0/1" }) }
    local after = { row(1, "Rats", { "Rats slain: 1/5", "Cheese: 0/1" }), row(2, "New", { "x: 0/1" }) }
    local got = QS().Changes(before, after)
    t.eq(got, { { quest = 1, objective = 1 } })
end

tests["quest spots: a complete quest that leaves the log is a turn-in, unless the client says not done"] = function(t)
    local before = { row(1, "Rats", { "Rats slain: 5/5" }, true), row(2, "Wolves", { "Wolves: 1/4" }) }
    t.eq(QS().Changes(before, {}), { { quest = 1, objective = 0 } }, "abandoned unfinished quests are not")
    t.eq(QS().Changes(before, {}, function() return false end), {}, "the client says it was not handed in")
    t.eq(QS().Changes(nil, before), {}, "no log before: nothing")
end

tests["quest spots: record keeps points per objective, counts a repeat, and caps them"] = function(t)
    local book = {}
    t.eq(QS().Record(book, { quest = 7, objective = 1 }, { map = 1436, x = 0.3, y = 0.7 }, 100), true)
    t.eq(book[7][1][1], { map = 1436, x = 0.3, y = 0.7, n = 1, at = 100 })
    QS().Record(book, { quest = 7, objective = 1 }, { map = 1436, x = 0.305, y = 0.7 }, 200)
    t.eq(#book[7][1], 1, "a point next to one kept is the same spot")
    t.eq(book[7][1][1].n, 2)
    for i = 1, QS().POINTS_MAX + 3 do
        QS().Record(book, { quest = 7, objective = 1 }, { map = 1436, x = i / 20, y = 0.1 }, 300 + i)
    end
    t.eq(#book[7][1], QS().POINTS_MAX, "capped")
    t.eq(QS().Record(book, { quest = 7, objective = 1 }, { map = 1436 }, 1), false, "no x, y: nothing")
    t.eq(QS().Record(book, { quest = 7, objective = 1 }, nil, 1), false)
end

tests["quest spots: no more quests than the cap; the least recently seen goes"] = function(t)
    local book = {}
    for id = 1, QS().QUESTS_MAX + 1 do
        QS().Record(book, { quest = id, objective = 1 }, { map = 1, x = 0.5, y = 0.5 }, id)
    end
    local n = 0
    for _ in pairs(book) do n = n + 1 end
    t.eq(n, QS().QUESTS_MAX)
    t.eq(book[1], nil, "the oldest went")
    t.ok(book[QS().QUESTS_MAX + 1] ~= nil, "the newest stays")
end

tests["quest spots: places in the quest source's shape, on this map or away"] = function(t)
    local book = { [7] = { [1] = { { map = 1436, x = 0.3, y = 0.7, n = 1 } },
                           [0] = { { map = 1411, x = 0.2, y = 0.2, n = 1 } } } }
    local places = QS().Places(book, { row(7, "Rats", { "Rats slain: 1/5" }) }, 1436)
    t.eq(places[7].objectives[1].points, { { map = 1436, x = 0.3, y = 0.7 } })
    t.eq(places[7].turnIn.points, {})
    t.eq(places[7].turnIn.elsewhere, true)
    t.eq(places[7].turnIn.away, { map = 1411, x = 0.2, y = 0.2 })
    t.eq(QS().Places(nil, {}, 1436), nil, "nothing learned: nil")
end

tests["quest spots: merge keeps Questie's place and fills only what it lacks"] = function(t)
    local questie = { [7] = { objectives = { [1] = { points = { { map = 1, x = 0.1, y = 0.1 } } },
                                             [2] = { points = {}, elsewhere = true, away = { map = 2, x = 0.5, y = 0.5 } } },
                              turnIn = { points = {} } } }
    local learned = { [7] = { objectives = { [1] = { points = { { map = 1, x = 0.9, y = 0.9 } } },
                                             [2] = { points = { { map = 1, x = 0.4, y = 0.4 } } } },
                              turnIn = { points = { { map = 1, x = 0.6, y = 0.6 } } } },
                      [8] = { objectives = { [1] = { points = { { map = 1, x = 0.2, y = 0.2 } } } } } }
    local m = QS().Merge(questie, learned)
    t.eq(m[7].objectives[1].points[1].x, 0.1, "Questie's own place stays")
    t.eq(m[7].objectives[2].points[1].x, 0.4, "a learned spot on this map beats a place on another")
    t.eq(m[7].turnIn.points[1].x, 0.6, "a turn-in Questie has no place for")
    t.eq(m[8].objectives[1].points[1].x, 0.2, "a quest Questie does not know")
    t.eq(QS().Merge(nil, learned), learned, "no Questie: the learned places")
    t.eq(QS().Merge(questie, nil), questie, "nothing learned: Questie's")
end

tests["quest spots: the quest watch uses learned spots when Questie is not there"] = function(t)
    local c = ns.make.fakeClient()
    c.setPosition(1436, 0.5, 0.5)
    c.setMapSize(1436, 1000, 1000)
    c.setQuestLog({ { id = 7, title = "Rats", objectives = { { text = "Rats slain: 1/5" } } } })
    local book = { [7] = { [1] = { { map = 1436, x = 0.3, y = 0.7, n = 1 } } } }
    local watch = ns.Nav.QuestWatch(c, { learned = function() return book end })
    local step = watch.step()
    t.ok(step ~= nil and step.place ~= nil, "a placed step from the learned spot")
    t.eq(step and step.place and { step.place.map, step.place.x, step.place.y }, { 1436, 0.3, 0.7 })
end

tests["quest spots: look only, no acting function"] = function(t)
    for n, v in pairs(QS()) do
        if type(v) == "function" then
            local low = n:lower()
            t.ok(not (low:find("accept") or low:find("turnin") or low:find("target") or low:find("cast")), n)
        end
    end
end

-- C-08 (lead section 603): /zflow spots lists what was learned, in chat.
tests["quest spots: Lines says when nothing is learned yet"] = function(t)
    local got = QS().Lines(nil, {}, function() return nil end)
    t.eq(#got, 1)
    t.eq(got[1], QS().NONE)
end

tests["quest spots: Lines gives one line per quest, by quest id, objectives then hand-in"] = function(t)
    local book = {
        [12] = { [0] = { { map = 1429, x = 0.5, y = 0.25, n = 1 } } },
        [7] = { [2] = { { map = 1429, x = 0.412, y = 0.65, n = 3 }, { map = 1411, x = 0.1, y = 0.2, n = 1 } } },
    }
    local names = { [1429] = "Elwynn Forest" }
    local got = QS().Lines(book, { [7] = "Rats" }, function(m) return names[m] end)
    t.eq(got[1], "2 quests, 3 learned spots:")
    t.eq(got[2], "Rats (7): objective 2 at Elwynn Forest 41.2, 65.0 (3 times), map 1411 10.0, 20.0")
    t.eq(got[3], "quest 12: hand-in at Elwynn Forest 50.0, 25.0")
end

tests["quest spots: Lines stops at LINES_MAX quests and says how many more"] = function(t)
    local book = {}
    for q = 1, QS().LINES_MAX + 3 do book[q] = { [1] = { { map = 1, x = 0.1, y = 0.1, n = 1 } } } end
    local got = QS().Lines(book, {}, function() return "Z" end)
    t.eq(#got, QS().LINES_MAX + 2)
    t.eq(got[#got], "and 3 more quests.")
end

return tests
