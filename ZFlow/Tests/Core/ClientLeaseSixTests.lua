local _, ns = ...

-- Lead sections 659, 662, 677, 679, 682, 692, 693: the Client.lua lease
-- reads, each on a made-up game through ns.make.client(env). Not tested in
-- game.

local STONE = "|cffffffff|Hitem:2835:0:0:0:0:0:0:0|h[Rough Stone]|h|r"
local SWORD = "|cff9d9d9d|Hitem:1413:0:0:0:0:0:0:0|h[Bent Sword]|h|r"

local function frameEnv()
    local env = { frames = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end
    -- hooksecurefunc([table,] name, hook): the hook runs after the original.
    function env.hooksecurefunc(a, b, cfn)
        local tbl, name, hook = env, a, b
        if type(a) == "table" then tbl, name, hook = a, b, cfn end
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = { orig(...) }
            hook(...)
            return unpack(r)
        end
    end
    return env
end

-- A tracker frame: Show runs its OnShow hooks, as the game's frames do.
local function trackerFrame()
    local f = { shown = true, onShow = {} }
    function f:IsShown() return self.shown end
    function f:Hide() self.shown = false end
    function f:Show()
        self.shown = true
        for _, h in ipairs(self.onShow) do h(self) end
    end
    function f:HookScript(name, fn) if name == "OnShow" then self.onShow[#self.onShow + 1] = fn end end
    return f
end

return {
    ["lease gossipOptions: each option's name and id, nil when the read is missing or fails"] = function(t)
        local env = frameEnv()
        env.C_GossipInfo = { GetOptions = function()
            return { { gossipOptionID = 7, name = "Make this inn your home." }, { name = "Bye" } }
        end }
        local c = ns.make.client(env)
        t.eq(c.gossipOptions(), { { id = 7, name = "Make this inn your home." }, { name = "Bye" } })
        env.C_GossipInfo.GetOptions = function() error("refused") end
        t.eq(c.gossipOptions(), nil, "a failing read")
        env.C_GossipInfo = nil
        t.eq(c.gossipOptions(), nil, "a game without it")
    end,

    ["lease game tracker: a hide before the frame exists, again on each show, never in a fight"] = function(t)
        local env = frameEnv()
        env.InCombatLockdown = function() return false end
        local c = ns.make.client(env)
        local ok, why = c.hideGameTracker(true)
        t.eq({ ok, why }, { true, "done" }, "accepted before the frame is made")
        local f = trackerFrame()
        env.QuestWatchFrame = f
        env.fire("PLAYER_ENTERING_WORLD")
        t.eq(f:IsShown(), false, "a frame made late is hidden")
        f:Show()
        t.eq(f:IsShown(), false, "shown again, hidden again")
        env.InCombatLockdown = function() return true end
        ok, why = c.hideGameTracker(false)
        t.eq({ ok, why }, { false, "lockdown" }, "a hide in a fight")
        env.InCombatLockdown = function() return false end
        t.eq({ c.hideGameTracker(false) }, { true, "done" })
        t.eq(f:IsShown(), true, "brought back")
    end,

    ["lease Questie tracker: hidden on each show, Questie's saved settings untouched"] = function(t)
        local env = frameEnv()
        env.InCombatLockdown = function() return false end
        env.Questie = { db = { profile = { trackerEnabled = true } } }
        local c = ns.make.client(env)
        local f = trackerFrame()
        env.Questie_BaseFrame = f
        t.eq({ c.hideQuestieTracker(true) }, { true, "done" })
        t.eq(f:IsShown(), false)
        f:Show()
        t.eq(f:IsShown(), false, "Questie shows it, it is hidden again")
        t.eq(env.Questie.db.profile.trackerEnabled, true, "never writes Questie's settings")
        env.InCombatLockdown = function() return true end
        t.eq({ c.hideQuestieTracker(false) }, { false, "lockdown" })
    end,

    ["lease inputBox: one popup of our own key, fn gets the typed text"] = function(t)
        local env = frameEnv()
        env.StaticPopupDialogs = {}
        local shown
        env.StaticPopup_Show = function(key) shown = key end
        local c = ns.make.client(env)
        local got
        t.eq(c.inputBox("Type it", function(text) got = text end), true)
        local d = env.StaticPopupDialogs[shown]
        t.ok(type(d) == "table" and d.hasEditBox == true, "an edit-box popup was shown")
        d.OnAccept({ editBox = { GetText = function() return "45.2 63.1" end } })
        t.eq(got, "45.2 63.1")
        env.StaticPopup_Show = function() error("refused") end
        t.eq(c.inputBox("Type it", function() end), nil, "a refusing popup")
        t.eq(c.inputBox("Type it", nil), nil, "no fn")
    end,

    ["lease onBoughtBack: the link from the snapshot, live read as fallback"] = function(t)
        local env = frameEnv()
        local tab = { STONE, SWORD }
        env.GetNumBuybackItems = function() return #tab end
        env.GetBuybackItemLink = function(i) return tab[i] end
        env.BuybackItem = function(i) table.remove(tab, i) end
        local c = ns.make.client(env)
        local got = {}
        t.eq(c.onBoughtBack(function(link) got[#got + 1] = link end), true)
        env.fire("MERCHANT_SHOW")
        env.BuybackItem(2)
        t.eq(got, { SWORD }, "the slot is empty after the buy; the snapshot names it")
        env.fire("MERCHANT_UPDATE")
        tab[2] = SWORD
        env.BuybackItem(2)
        t.eq(got, { SWORD, SWORD }, "not in the snapshot: the live read")
    end,

    ["lease onLootLeft: read while open, reported at LOOT_CLOSED"] = function(t)
        local env = frameEnv()
        local slots = {
            { link = STONE, name = "Rough Stone", count = 2, quality = 1 },
            { link = SWORD, name = "Bent Sword", count = 1, quality = 0 },
        }
        env.GetNumLootItems = function() return #slots end
        env.GetLootSlotInfo = function(i) local s = slots[i] return "icon", s.name, s.count, nil, s.quality end
        env.GetLootSlotLink = function(i) return slots[i].link end
        local c = ns.make.client(env)
        local got
        t.eq(c.onLootLeft(function(items) got = items end), true)
        env.fire("LOOT_OPENED")
        table.remove(slots, 1)
        env.fire("LOOT_SLOT_CLEARED", 1)
        slots = {}
        env.fire("LOOT_CLOSED")
        t.eq(got, { { item = SWORD, count = 1, quality = 0 } })
    end,

    ["lease itemIdByName: the id from GetItemInfo's link, nil when not known"] = function(t)
        local env = frameEnv()
        env.GetItemInfo = function(name)
            if name == "Rough Stone" then return "Rough Stone", STONE end
            return nil
        end
        local c = ns.make.client(env)
        t.eq(c.itemIdByName("Rough Stone"), 2835)
        t.eq(c.itemIdByName("Nothing"), nil)
        env.C_Item = { GetItemInfo = function() error("refused") end }
        t.eq(c.itemIdByName("Rough Stone"), nil, "a failing read")
    end,

    ["lease onCraftStarted: the spell id, count and name from both craft calls"] = function(t)
        local env = frameEnv()
        env.DoTradeSkill = function() end
        env.GetTradeSkillRecipeLink = function() return "|cffffd000|Henchant:3275|h[Linen Bandage]|h|r" end
        env.GetTradeSkillInfo = function() return "Linen Bandage" end
        env.C_TradeSkillUI = {
            CraftRecipe = function() end,
            GetRecipeInfo = function(id) return { name = "Copper Bar", recipeID = id } end,
        }
        local c = ns.make.client(env)
        local got = {}
        t.ok(type(c.onCraftStarted(function(id, n, name) got[#got + 1] = { id, n, name } end)) == "function",
            "a cancel")
        env.DoTradeSkill(4, 10)
        env.C_TradeSkillUI.CraftRecipe(2657, 3)
        env.GetTradeSkillRecipeLink = function() return nil end
        env.DoTradeSkill(5, 2)
        t.eq(got, { { 3275, 10, "Linen Bandage" }, { 2657, 3, "Copper Bar" }, { nil, 2, "Linen Bandage" } })
    end,

    ["lease questRewardXp: the number above 0, else nil"] = function(t)
        local env = frameEnv()
        env.GetQuestLogRewardXP = function(id) if id == 1 then return 450 end return 0 end
        local c = ns.make.client(env)
        t.eq(c.questRewardXp(1), 450)
        t.eq(c.questRewardXp(2), nil)
        env.GetQuestLogRewardXP = function() error("refused") end
        t.eq(c.questRewardXp(1), nil)
    end,
}
