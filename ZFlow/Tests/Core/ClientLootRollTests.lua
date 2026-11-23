-- F4 Merchant and roll marks: the client's loot-roll hook, onLootRoll. The
-- real client over a hand-built environment (`env` stands in for the
-- game's globals), then the fake. Every call read here is a first guess,
-- not seen in game on 16001.
local _, ns = ...

local LINK = "item:200"

-- Frames that take events; a roll frame for roll 7; our own frames recorded.
local function rollEnv()
    local env = { frames = {}, made = {}, printed = {} }
    function env.CreateFrame(_, _, parent)
        local f = { scripts = {}, events = {}, parent = parent, shown = false }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:SetSize() end
        function f:SetPoint(...) self.point = { ... } end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:CreateFontString()
            local fs = {}
            function fs:SetPoint() end
            function fs:SetText(s) self.text = s end
            function fs:SetTextColor(r, g, b) self.colour = { r, g, b } end
            f.fs = fs
            return fs
        end
        env.frames[#env.frames + 1] = f
        if parent ~= nil then env.made[#env.made + 1] = f end
        return f
    end
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] then f.scripts.OnEvent(f, event, ...) end
        end
    end
    env.GetLootRollItemLink = function(id) if id == 7 or id == 8 then return LINK end end
    env.GroupLootFrame1 = { rollID = 7, writes = 0 }
    setmetatable(env.GroupLootFrame1, { __newindex = function(tbl, key, v) rawset(tbl, "writes", rawget(tbl, "writes") + 1); rawset(tbl, key, v) end })
    env.print = function(s) env.printed[#env.printed + 1] = s end
    return env
end

return {
    ["F4 onLootRoll: a roll tells the roll and its link, and shows the text above that roll's frame"] = function(t)
        local env = rollEnv()
        local c = ns.make.client(env)
        local told = {}
        t.eq(type(c.onLootRoll(function(id, link, show)
            told[#told + 1] = { id, link }
            show("Upgrade", 0.1, 1, 0.1)
        end)), "function")
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(told, { { 7, LINK } })
        t.eq(#env.made, 1, "one frame of ours")
        local mark = env.made[1]
        t.ok(mark.parent == env.GroupLootFrame1, "a child of the roll frame, so it hides with it")
        t.eq(mark.fs.text, "Upgrade")
        t.eq(mark.fs.colour, { 0.1, 1, 0.1 })
        t.eq(mark.shown, true)
        t.eq(env.GroupLootFrame1.writes, 0, "nothing written to the game's frame")
    end,

    ["F4 onLootRoll: a cancelled roll hides its text; a new roll on the frame reuses it"] = function(t)
        local env = rollEnv()
        local c = ns.make.client(env)
        c.onLootRoll(function(_, _, show) show("Unknown") end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        env.fire("CANCEL_LOOT_ROLL", 7)
        t.eq(env.made[1].shown, false)
        rawset(env.GroupLootFrame1, "rollID", 8)
        env.fire("START_LOOT_ROLL", 8, 60000)
        t.eq(#env.made, 1, "reused, not made again")
        t.eq(env.made[1].shown, true)
    end,

    ["F4 onLootRoll: no roll frame found prints the link and the text once"] = function(t)
        local env = rollEnv()
        env.GroupLootFrame1 = nil
        local c = ns.make.client(env)
        c.onLootRoll(function(_, _, show) show("Upgrade"); show("Upgrade") end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(#env.printed, 1)
        t.ok(env.printed[1]:find(LINK, 1, true) and env.printed[1]:find("Upgrade", 1, true), env.printed[1])
        t.eq(#env.made, 0)
    end,

    -- RH-1 (lead section 279): the listener can ask for no chat fallback
    -- (it says the roll in chat itself). Fails before: show takes no
    -- trailing table, so the fallback line is printed (1, not 0).
    ["RH-1 onLootRoll: no roll frame found and show told quiet prints nothing"] = function(t)
        local env = rollEnv()
        env.GroupLootFrame1 = nil
        local c = ns.make.client(env)
        c.onLootRoll(function(_, _, show) show("Upgrade", 0.1, 1, 0.1, { quiet = true }) end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(#env.printed, 0, "no fallback line when told quiet")
        t.eq(#env.made, 0)
    end,

    ["F4 onLootRoll: no link, a secret link or an odd roll id tells nobody"] = function(t)
        local env = rollEnv()
        local c = ns.make.client(env)
        local told = 0
        c.onLootRoll(function() told = told + 1 end)
        env.fire("START_LOOT_ROLL", 9, 60000)
        env.fire("START_LOOT_ROLL", "7", 60000)
        env.issecretvalue = function(v) return v == LINK end
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(told, 0)
    end,

    ["F4 onLootRoll: a listener that raises costs only itself; cancel stops one"] = function(t)
        local env = rollEnv()
        local c = ns.make.client(env)
        local a = 0
        c.onLootRoll(function() error("broken") end)
        local cancel = c.onLootRoll(function() a = a + 1 end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        cancel()
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(a, 1)
        t.eq(c.onLootRoll("not a function"), nil)
    end,

    ["F4 onLootRoll: it never rolls or confirms"] = function(t)
        local env = rollEnv()
        local calls = 0
        for _, name in ipairs({ "RollOnLoot", "ConfirmLootRoll", "ConfirmLootSlot", "LootSlot" }) do
            env[name] = function() calls = calls + 1 end
        end
        local c = ns.make.client(env)
        c.onLootRoll(function(_, _, show) show("Upgrade") end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        env.fire("CANCEL_LOOT_ROLL", 7)
        t.eq(calls, 0)
    end,

    ["F4 fake: offerRoll tells each listener and returns what was shown"] = function(t)
        local c = ns.make.fakeClient()
        local cancel = c.onLootRoll(function(id, link, show) show(link .. " " .. id, 1, 1, 1) end)
        t.eq(c.offerRoll(7, LINK), { { text = LINK .. " 7", r = 1, g = 1, b = 1 } })
        cancel()
        t.eq(c.offerRoll(7, LINK), {})
    end,
    ["API check: a roll frame among GroupLootContainer's children is found"] = function(t)
        local env = rollEnv()
        local frame = { rollID = 7 }
        env.GroupLootFrame1 = nil
        env.GroupLootContainer = { GetChildren = function() return { rollID = 3 }, frame end }
        local c = ns.make.client(env)
        c.onLootRoll(function(_, _, show) show("Upgrade") end)
        env.fire("START_LOOT_ROLL", 7, 60000)
        t.eq(#env.made, 1)
        t.ok(env.made[1].parent == frame)
        t.eq(#env.printed, 0)
    end,

    -- S21 (lead section 275): the value on the roll's item picture.
    ["S21 rollValue: the value sits on the roll's item picture, on a frame of ours; empty hides it"] = function(t)
        local env = rollEnv()
        local icon = { name = "icon" }
        rawset(env.GroupLootFrame1, "IconFrame", icon)
        local c = ns.make.client(env)
        t.eq(c.rollValue(7, "Need +5", 0.1, 1, 0.1), true)
        t.eq(#env.made, 1, "one frame of ours")
        local mark = env.made[1]
        t.ok(mark.parent == icon, "a child of the item picture, so it hides with the roll")
        t.eq(mark.fs.text, "Need +5")
        t.eq(mark.fs.colour, { 0.1, 1, 0.1 })
        t.eq(mark.shown, true)
        t.eq(c.rollValue(7, "Greed", 0.6, 0.6, 0.6), true)
        t.eq(#env.made, 1, "reused, not made again")
        t.eq(mark.fs.text, "Greed")
        t.eq(c.rollValue(7, nil), true)
        t.eq(mark.shown, false, "no text hides it")
        t.eq(env.GroupLootFrame1.writes, 0, "nothing written to the game's frame")
    end,

    ["S21 rollValue: no item picture uses the roll frame; no roll frame or an odd id draws nothing"] = function(t)
        local env = rollEnv()
        local c = ns.make.client(env)
        t.eq(c.rollValue(7, "Greed"), true)
        t.ok(env.made[1].parent == env.GroupLootFrame1)
        t.eq(c.rollValue(9, "Greed"), nil, "no frame shows roll 9")
        t.eq(c.rollValue("7", "Greed"), nil)
        t.eq(#env.made, 1)
    end,

    ["S21 rollValue: it never rolls or confirms"] = function(t)
        local env = rollEnv()
        local calls = 0
        for _, name in ipairs({ "RollOnLoot", "ConfirmLootRoll" }) do
            env[name] = function() calls = calls + 1 end
        end
        local c = ns.make.client(env)
        c.rollValue(7, "Need +5")
        c.rollValue(7, nil)
        t.eq(calls, 0)
    end,

    ["S21 fake: rollValue keeps the value per roll; empty clears it"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.rollValue(7, "Need +5", 0.1, 1, 0.1), true)
        t.eq(c.rollValueOf(7), { text = "Need +5", r = 0.1, g = 1, b = 0.1 })
        c.rollValue(7, nil)
        t.eq(c.rollValueOf(7), nil)
        t.eq(c.rollValue("7", "x"), nil)
    end,

}
