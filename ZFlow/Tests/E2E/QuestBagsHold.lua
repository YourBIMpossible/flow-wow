local _, ns = ...
-- F-044 (lead DISPATCH section 371, P-HOLD): bags full, a quest item that a
-- quest in the log needs, and a keep goal on it. End to end on the whole
-- add-on loaded on a fake client: the sell list does not offer the quest
-- item (its line says why it is kept), it is not junk, the bank prompt and
-- the banker word do not move it out, and the goal holds it. Look only:
-- nothing here sells or moves anything. Made-up items. Not tested in game.
local tests = {}

local FANG, LINEN, BONE = 3410, 2589, 3411
local QUEST_ID = 9410
local INFO = {
    [FANG] = { name = "Gnarled Fang", quality = 1, sellPrice = 25, classID = 12 },
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
}
local BAG = {
    { item = FANG, count = 6 }, { item = LINEN, count = 20 }, { item = BONE, count = 2 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBags({ { free = 0, total = 16, family = 0 } })
    c.setBagItems(BAG)
    c.setItemInfo(INFO)
    c.setQuestLog({ { id = QUEST_ID, title = "Fangs for the Hunter", complete = false, failed = false,
        objectives = { { text = "Gnarled Fang: 6/8", done = false } } } })
    c.setQuestItem(QUEST_ID, FANG)
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.lists = { SellList = addon.sellList, BankList = addon.bankList }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.slashes[ns.id.slash]("goal add " .. FANG .. " 8")
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function noteOf(c, addon, name)
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
    local got = false
    ns.Kit.Each(tree, function(p) if p.kind == "itemLine" and p.name == name then got = p.note end end)
    return got
end

local function promptOf(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == addon.BankList.PROMPT_ID then return p.text end
    end
    return nil
end

local function kept(note)
    return type(note) == "string" and (note:find("held", 1, true) ~= nil or note:find("quest", 1, true) ~= nil)
end

tests["quest bags hold: full bags, a quest item with a keep goal is not offered for sale"] = function(t)
    local c, addon = boot()
    t.eq(c.bags()[1].free, 0, "the bags are full")
    c.setMerchantOpen(true)
    local note = noteOf(c, addon, "Gnarled Fang")
    t.ok(note ~= false, "the quest item has its line, not dropped")
    t.ok(kept(note), "kept, with why: " .. tostring(note))
    t.ok(note ~= "junk", "not junk")
    t.ok(noteOf(c, addon, "Cracked Bone") ~= false, "the grey bone has its line too: the list works")
    t.eq(newProblems(addon), 0)
end

tests["quest bags hold: full bags, the bank prompt and the banker word leave the quest item"] = function(t)
    local c, addon = boot()
    c.setBankOpen(true)
    local text = promptOf(addon)
    t.ok(type(text) == "string" and text:find("Linen Cloth", 1, true) ~= nil, "the prompt banks the linen: " .. tostring(text))
    t.ok(type(text) == "string" and text:find("Gnarled Fang", 1, true) == nil, "not the quest item: " .. tostring(text))
    local from = #c.printed
    c.slashes[ns.id.slash]("banker")
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("^In your bank") or line:find(": In your bank") then break end
        t.ok(not (line:find("Gnarled Fang", 1, true) and line:find("kept for later", 1, true)),
            "the banker word does not bank it: " .. line)
    end
    c.setBankOpen(false)
    t.eq(newProblems(addon), 0)
end

return tests
