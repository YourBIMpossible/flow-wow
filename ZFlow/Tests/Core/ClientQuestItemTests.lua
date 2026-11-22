-- The three client reads of S42 (quest item on the quest arrow, LEDGER
-- 169): the real client over a hand-built environment, then ClientFake's
-- own versions. Read only: nothing uses an item.
--   c.questItem(questID) -> { id, link } or nil
--   c.itemCount(item)    -> a whole number of 0 or more, or nil
--   c.itemUse(item)      -> true / false, or nil when the client will not say
-- Unknown stays unknown: a failed, missing, odd or secret answer is nil.
local _, ns = ...

local tests = {}

local LINK = "|cffffffff|Hitem:12345::::::::1:::::::|h[Totem of Ner]|h|r"

-- Quest 101 is third in the log and its item is LINK.
local function logEnv(extra)
    local env = { asked = {} }
    env.C_QuestLog = { GetLogIndexForQuestID = function(id) return id == 101 and 3 or nil end }
    env.GetQuestLogSpecialItemInfo = function(index)
        env.asked[#env.asked + 1] = index
        if index == 3 then return LINK, 134229, 0, false end
        return nil
    end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

tests["c.questItem: the game's own item of a quest in the log"] = function(t)
    local env = logEnv()
    t.eq(ns.make.client(env).questItem(101), { id = 12345, link = LINK })
    t.eq(env.asked, { 3 }, "asked by the place in the log, not the quest id")
end

tests["c.questItem: the older index read is asked second; 0 is not in the log"] = function(t)
    local env = logEnv({ GetQuestLogIndexByID = function(id) return id == 101 and 3 or 0 end })
    env.C_QuestLog = nil
    t.eq(ns.make.client(env).questItem(101), { id = 12345, link = LINK })
    t.eq(ns.make.client(env).questItem(202), nil, "0: not in the log")
    local none = logEnv({ GetQuestLogIndexByID = function() return 3 end })
    none.C_QuestLog.GetLogIndexForQuestID = function() return nil end
    t.eq(ns.make.client(none).questItem(101), { id = 12345, link = LINK }, "the new read gave nothing")
end

tests["c.questItem: nil when any part is not known"] = function(t)
    t.eq(ns.make.client({}).questItem(101), nil, "no reads at all")
    t.eq(ns.make.client(logEnv()).questItem(202), nil, "not in the log")
    t.eq(ns.make.client(logEnv()).questItem("101"), nil, "not a quest id")
    local noItem = logEnv({ GetQuestLogSpecialItemInfo = function() return nil end })
    t.eq(ns.make.client(noItem).questItem(101), nil, "the quest has no item")
    local odd = logEnv({ GetQuestLogSpecialItemInfo = function() return "|Hspell:5|h" end })
    t.eq(ns.make.client(odd).questItem(101), nil, "a link that is no item")
    local raised = logEnv({ GetQuestLogSpecialItemInfo = function() error("no") end })
    t.eq(ns.make.client(raised).questItem(101), nil, "raised")
    local idRaised = logEnv()
    idRaised.C_QuestLog.GetLogIndexForQuestID = function() error("no") end
    t.eq(ns.make.client(idRaised).questItem(101), nil, "the index read raised and there is no other")
    local secret = logEnv({ issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return v == LINK
    end })
    t.eq(ns.make.client(secret).questItem(101), nil, "a secret link")
end

tests["c.itemCount: how many are in the bags, or not known"] = function(t)
    local asked
    local c = ns.make.client({ C_Item = { GetItemCount = function(item) asked = item return 2 end } })
    t.eq(c.itemCount(12345), 2)
    t.eq(asked, 12345)
    t.eq(ns.make.client({ GetItemCount = function() return 0 end }).itemCount(12345), 0, "the older read; 0 is known")
    t.eq(ns.make.client({}).itemCount(12345), nil, "no read")
    t.eq(ns.make.client({ GetItemCount = function() error("no") end }).itemCount(12345), nil, "raised")
    t.eq(ns.make.client({ GetItemCount = function() return nil end }).itemCount(12345), nil)
    t.eq(ns.make.client({ GetItemCount = function() return -1 end }).itemCount(12345), nil)
    t.eq(ns.make.client({ GetItemCount = function() return 1.5 end }).itemCount(12345), nil)
    t.eq(ns.make.client({ GetItemCount = function() return 0 / 0 end }).itemCount(12345), nil)
    t.eq(ns.make.client({ GetItemCount = function() return 3 end }).itemCount(nil), nil, "no item asked")
    local secret = ns.make.client({ GetItemCount = function() return 7 end,
        issecretvalue = function(v) return v == 7 end })
    t.eq(secret.itemCount(12345), nil, "a secret count")
end

tests["c.itemUse: whether using the item does something"] = function(t)
    local asked
    local c = ns.make.client({ C_Item = { GetItemSpell = function(item) asked = item return "Place Totem", 4711 end } })
    t.eq(c.itemUse(12345), true)
    t.eq(asked, 12345)
    t.eq(ns.make.client({ C_Item = { GetItemSpell = function() return nil end } }).itemUse(12345), false,
        "the read ran and named no spell: no use")
    t.eq(ns.make.client({ GetItemSpell = function() return "Place Totem" end }).itemUse(12345), true, "the older read")
    t.eq(ns.make.client({}).itemUse(12345), nil, "no read: not known, never no use")
    t.eq(ns.make.client({ GetItemSpell = function() error("no") end }).itemUse(12345), nil, "raised")
    t.eq(ns.make.client({ GetItemSpell = function() return 5 end }).itemUse(12345), nil, "not a name")
    t.eq(ns.make.client({ GetItemSpell = function() return "x" end }).itemUse(nil), nil, "no item asked")
    local secret = ns.make.client({ GetItemSpell = function() return "Place Totem" end,
        issecretvalue = function(v)
            if v == nil then error("issecretvalue: nil") end
            return v == "Place Totem"
        end })
    t.eq(secret.itemUse(12345), nil, "a secret name")
end

tests["fake client: the quest item reads are unknown until set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq({ c.questItem(101), c.itemCount(12345), c.itemUse(12345) }, {})
    c.setQuestItem(101, 12345, LINK)
    c.setItemCount(12345, 0)
    c.setItemUse(12345, false)
    t.eq(c.questItem(101), { id = 12345, link = LINK })
    t.eq(c.itemCount(12345), 0)
    t.eq(c.itemUse(12345), false)
    local got = c.questItem(101)
    got.id = 1
    t.eq(c.questItem(101).id, 12345, "a copy each time")
    c.setQuestItem(102, 777)
    t.eq(c.questItem(102), { id = 777, link = "item:777" })
    c.setQuestItem(101, nil)
    c.setItemCount(12345, nil)
    c.setItemUse(12345, nil)
    t.eq({ c.questItem(101), c.itemCount(12345), c.itemUse(12345) }, {})
end

return tests
