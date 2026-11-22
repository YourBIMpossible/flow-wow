-- F3 Gear advice on hover: the client reads it adds. gear(link) gains the
-- item's classID, subclassID, minLevel, unmet and speed; level(); and the
-- item tooltip hook onItemTooltip. The real client over a hand-built
-- environment (`env` stands in for the game's globals), then the fake. Every
-- call read here is a first guess, not seen in game on 16001.
local _, ns = ...

local HELM, SWORD = "item:100", "item:200"
local RED = { r = 1, g = 0.125, b = 0.125 }
local WHITE = { r = 1, g = 1, b = 1 }

local function boom() error("the client refused") end

-- An item the client knows: `say[link]` = { name, class, subclass, minLevel,
-- lines = { { leftText, leftColor, rightText, rightColor } ... } }.
local function itemEnv(say)
    local env = { SPEED = "Speed" }
    env.GetItemInfoInstant = function(link)
        local it = say[link] or {}
        return 1, "Armor", "Leather", it.kind, 0, it.class, it.subclass
    end
    env.GetItemInfo = function(link)
        local it = say[link] or {}
        return it.name, link, 2, 10, it.minLevel
    end
    env.C_TooltipInfo = {
        GetHyperlink = function(link)
            local it = say[link]
            if not it or not it.lines then return nil end
            return { lines = it.lines }
        end,
    }
    return env
end

local function helm()
    return { name = "Helm", kind = "INVTYPE_HEAD", class = 4, subclass = 2, minLevel = 12,
             lines = { { leftText = "Helm", leftColor = WHITE }, { leftText = "Head", rightText = "Leather", rightColor = WHITE } } }
end

-- A tooltip the game fills: route A (OnTooltipSetItem) or B (data post call).
local function tooltipEnv(route)
    local env = {}
    local tip = { lines = {}, link = HELM }
    function tip.GetItem(self) return "Helm", self.link end
    function tip.AddLine(self, text, r, g, b) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b } end
    if route == "A" then
        function tip.HasScript(_, name) return name == "OnTooltipSetItem" end
        function tip.HookScript(self, name, fn) self.hooked = self.hooked or {}; self.hooked[name] = fn end
    elseif route == "B" then
        env.Enum = { TooltipDataType = { Item = 0 } }
        env.TooltipDataProcessor = {
            AddTooltipPostCall = function(kind, fn) env.postCalls = env.postCalls or {}; env.postCalls[kind] = fn end,
        }
    end
    env.GameTooltip = tip
    -- Plays the game filling the tooltip.
    env.fill = function()
        if route == "A" then tip.hooked.OnTooltipSetItem(tip) else env.postCalls[0](tip, {}) end
        return tip.lines
    end
    return env, tip
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

return {
    -- -------------------------------------------------------- the item
    ["F3 gear(): the item's class and subclass in the client's own spelling"] = function(t)
        local g = ns.make.client(itemEnv({ [HELM] = helm() })).gear(HELM)
        t.eq(g.classID, 4)
        t.eq(g.subclassID, 2)
        t.eq(g.minLevel, 12)
    end,

    ["F3 gear(): a class or subclass that is no whole number is left out"] = function(t)
        local it = helm()
        it.class, it.subclass = "4", -1
        local g = ns.make.client(itemEnv({ [HELM] = it })).gear(HELM)
        t.eq(g.classID, nil)
        t.eq(g.subclassID, nil)
    end,

    ["F3 gear(): nothing the game marks is an empty list, not an absent one"] = function(t)
        local g = ns.make.client(itemEnv({ [HELM] = helm() })).gear(HELM)
        t.eq(g.unmet, {})
    end,

    ["F3 gear(): the lines the game draws in red, left and right, in its own words"] = function(t)
        local it = helm()
        it.lines[#it.lines + 1] = { leftText = "Requires Level 40", leftColor = RED }
        it.lines[2].rightColor = RED   -- "Leather" in red
        local g = ns.make.client(itemEnv({ [HELM] = it })).gear(HELM)
        t.eq(g.unmet, { "Leather", "Requires Level 40" })
    end,

    ["F3 gear(): a red line whose text cannot be read is still a mark"] = function(t)
        local it = helm()
        it.lines[#it.lines + 1] = { leftText = "", leftColor = RED }
        local env = itemEnv({ [HELM] = it })
        local g = ns.make.client(env).gear(HELM)
        t.eq(g.unmet, { false })
        local secret = {}
        it.lines[3].leftText = "Requires Level 40"
        env.issecretvalue = function(v) return secret[v] == true end
        secret["Requires Level 40"] = true
        t.eq(ns.make.client(env).gear(HELM).unmet, { false }, "a secret red text")
    end,

    ["F3 gear(): a colour that is not the game's red is not a mark"] = function(t)
        local it = helm()
        it.lines[#it.lines + 1] = { leftText = "Unique", leftColor = { r = 1, g = 0.82, b = 0 } }
        it.lines[#it.lines + 1] = { leftText = "Odd", leftColor = { r = "1", g = 0, b = 0 } }
        it.lines[#it.lines + 1] = { leftText = "None" }
        t.eq(ns.make.client(itemEnv({ [HELM] = it })).gear(HELM).unmet, {})
    end,

    ["F3 gear(): an item not loaded yet gives no level, marks or speed"] = function(t)
        local it = helm()
        it.name = nil
        it.lines[#it.lines + 1] = { leftText = "Requires Level 40", leftColor = RED }
        local g = ns.make.client(itemEnv({ [HELM] = it })).gear(HELM)
        t.eq(g.minLevel, nil)
        t.eq(g.unmet, nil, "not read: never \"the game marks nothing\"")
        t.eq(g.speed, nil)
        t.eq(g.classID, 4, "the instant read needs nothing loaded")
    end,

    ["F3 gear(): no tooltip data read is no marks, never an empty list"] = function(t)
        local env = itemEnv({ [HELM] = helm() })
        env.C_TooltipInfo = nil
        t.eq(ns.make.client(env).gear(HELM).unmet, nil)
        env.C_TooltipInfo = { GetHyperlink = boom }
        t.eq(ns.make.client(env).gear(HELM).unmet, nil, "a call that fails")
        env.C_TooltipInfo = { GetHyperlink = function() return { lines = "x" } end }
        t.eq(ns.make.client(env).gear(HELM).unmet, nil, "lines that are no list")
        env.GetItemInfo = nil
        env.C_TooltipInfo = nil
        t.eq(ns.make.client(env).gear(HELM).minLevel, nil, "no GetItemInfo: not known to be loaded")
    end,

    ["F3 gear(): a weapon's speed, after the client's own word, with a point or a comma"] = function(t)
        local it = { name = "Sword", kind = "INVTYPE_WEAPON", class = 2, subclass = 7, minLevel = 1,
            lines = { { leftText = "Sword", leftColor = WHITE },
                      { leftText = "11 - 21 Damage", leftColor = WHITE, rightText = "Speed 2.60", rightColor = WHITE } } }
        local env = itemEnv({ [SWORD] = it })
        t.eq(ns.make.client(env).gear(SWORD).speed, 2.6)
        it.lines[2].rightText = "Speed 3,40"
        t.eq(ns.make.client(env).gear(SWORD).speed, 3.4)
        it.lines[2].rightText = "Speedy 2.60"
        t.eq(ns.make.client(env).gear(SWORD).speed, nil, "not the word itself")
        it.lines[2].rightText = "Speed 2.60"
        env.SPEED = nil
        t.eq(ns.make.client(env).gear(SWORD).speed, nil, "no word to read it by: not read")
        t.eq(ns.make.client(itemEnv({ [HELM] = helm() })).gear(HELM).speed, nil, "no speed line")
    end,

    ["F3 gear(): worn items carry kind and stats only, as before"] = function(t)
        local env = itemEnv({ [HELM] = helm() })
        env.GetInventoryItemID = function(_, slot) if slot == 1 then return 100 end end
        env.GetInventoryItemLink = function(_, slot) if slot == 1 then return HELM end end
        env.GetItemStats = function() return {} end
        local worn = ns.make.client(env).gear(nil).worn
        t.eq(worn[1], { kind = "INVTYPE_HEAD", stats = {} })
        t.eq(count(worn), 17)
    end,

    -- ------------------------------------------------------------ level
    ["F3 level(): your level as the client says, or nil"] = function(t)
        local env = { UnitLevel = function(unit) if unit == "player" then return 24 end end }
        t.eq(ns.make.client(env).level(), 24)
        for _, odd in ipairs({ 0, -1, 2.5, "24" }) do
            env.UnitLevel = function() return odd end
            t.eq(ns.make.client(env).level(), nil, tostring(odd))
        end
        env.UnitLevel = boom
        t.eq(ns.make.client(env).level(), nil)
        t.eq(ns.make.client({}).level(), nil, "no call")
        env.UnitLevel = function() return 24 end
        env.issecretvalue = function(v) return v == 24 end
        t.eq(ns.make.client(env).level(), nil, "a secret level")
    end,

    -- ---------------------------------------------------- tooltip hook
    ["F3 onItemTooltip: route A tells the link and adds lines to the game's tooltip"] = function(t)
        local env, tip = tooltipEnv("A")
        local c = ns.make.client(env)
        local told = {}
        local cancel = c.onItemTooltip(function(link, add)
            told[#told + 1] = link
            add("Upgrade", 0.1, 1, 0.1)
        end)
        t.eq(type(cancel), "function")
        t.eq(type(tip.hooked.OnTooltipSetItem), "function", "a hook, not a replaced script")
        local lines = env.fill()
        t.eq(told, { HELM })
        t.eq(lines, { { text = "Upgrade", r = 0.1, g = 1, b = 0.1 } })
    end,

    ["F3 onItemTooltip: route B for clients with tooltip data post calls, GameTooltip only"] = function(t)
        local env, tip = tooltipEnv("B")
        local c = ns.make.client(env)
        local told = 0
        t.eq(type(c.onItemTooltip(function() told = told + 1 end)), "function")
        env.fill()
        t.eq(told, 1)
        env.postCalls[0]({ GetItem = tip.GetItem, link = HELM }, {})
        t.eq(told, 1, "another tooltip is not ours to add to")
    end,

    ["F3 onItemTooltip: no route is nil, and nothing is hooked"] = function(t)
        local env = tooltipEnv("none")
        t.eq(ns.make.client(env).onItemTooltip(function() end), nil)
        t.eq(ns.make.client({}).onItemTooltip(function() end), nil)
        local envA = tooltipEnv("A")
        t.eq(ns.make.client(envA).onItemTooltip("not a function"), nil)
    end,

    ["F3 onItemTooltip: hooked once for any number of listeners; cancel stops one"] = function(t)
        local env, tip = tooltipEnv("A")
        local hooks = 0
        local hook = tip.HookScript
        tip.HookScript = function(...) hooks = hooks + 1; return hook(...) end
        local c = ns.make.client(env)
        local a, b = 0, 0
        local cancelA = c.onItemTooltip(function() a = a + 1 end)
        c.onItemTooltip(function() b = b + 1 end)
        t.eq(hooks, 1)
        env.fill()
        cancelA()
        env.fill()
        t.eq({ a, b }, { 1, 2 })
    end,

    ["F3 onItemTooltip: a listener that raises costs only its own line"] = function(t)
        local env = tooltipEnv("A")
        local c = ns.make.client(env)
        c.onItemTooltip(function() error("broken") end)
        c.onItemTooltip(function(_, add) add("Same") end)
        local lines = env.fill()
        t.eq(#lines, 1)
        t.eq(lines[1].text, "Same")
    end,

    ["F3 onItemTooltip: no link, an empty or a secret one tells nobody"] = function(t)
        local env, tip = tooltipEnv("A")
        local c = ns.make.client(env)
        local told = 0
        c.onItemTooltip(function() told = told + 1 end)
        for _, link in ipairs({ false, "" }) do
            tip.link = link or nil
            env.fill()
        end
        tip.link = HELM
        env.issecretvalue = function(v) return v == HELM end
        env.fill()
        t.eq(told, 0)
    end,

    -- ------------------------------------------------------------- fake
    ["F3 fake: setItem carries the new fields; worn items do not"] = function(t)
        local c = ns.make.fakeClient()
        c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = {}, classID = 4, subclassID = 2, minLevel = 5,
            unmet = { "Plate" }, speed = 2.6 })
        c.setWorn(1, HELM)
        local g = c.gear(HELM)
        t.eq({ g.classID, g.subclassID, g.minLevel, g.speed }, { 4, 2, 5, 2.6 })
        t.eq(g.unmet, { "Plate" })
        t.eq(g.worn[1], { kind = "INVTYPE_HEAD", stats = {} })
        g.unmet[1] = "x"
        t.eq(c.gear(HELM).unmet, { "Plate" }, "a copy each time")
        c.setItem(HELM, { kind = "INVTYPE_HEAD" })
        t.eq(c.gear(HELM).unmet, nil, "not set: not read")
    end,

    ["F3 fake: level and the tooltip hook"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.level(), nil)
        c.setLevel(24)
        t.eq(c.level(), 24)
        local cancel = c.onItemTooltip(function(link, add) add("seen " .. link, 1, 1, 1) end)
        t.eq(c.showItemTooltip(HELM), { { text = "seen " .. HELM, r = 1, g = 1, b = 1 } })
        cancel()
        t.eq(c.showItemTooltip(HELM), {})
    end,
}
