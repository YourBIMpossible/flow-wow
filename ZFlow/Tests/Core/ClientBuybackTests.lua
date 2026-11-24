local _, ns = ...

-- G3: client.returnableItems(), the read of the merchant's Buyback tab, on a
-- made-up game. Not tested in game.

local STONE = "|cffffffff|Hitem:2835:0:0:0:0:0:0:0|h[Rough Stone]|h|r"

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
            if f.events[event] then f.scripts.OnEvent(f, event, ...) end
        end
    end
    return env
end

local function tab(rows, open)
    local env = frameEnv()
    env.GetNumBuybackItems = function() return #rows end
    env.GetBuybackItemLink = function(index) return rows[index].link end
    env.GetBuybackItemInfo = function(index)
        local row = rows[index]
        return row.name, 1, row.price, row.count
    end
    local c = ns.make.client(env)
    c.watchMerchant()
    if open ~= false then env.fire("MERCHANT_SHOW") end
    return c, env
end

return {
    ["buyback read: each item on the tab, in its order"] = function(t)
        local c = tab({
            { link = STONE, name = "Rough Stone", price = 40, count = 5 },
            { link = nil, name = "Bent Sword", price = 1250, count = 1 },
        })
        t.eq(c.returnableItems(), {
            { index = 1, item = STONE, name = "Rough Stone", price = 40, count = 5 },
            { index = 2, name = "Bent Sword", price = 1250, count = 1 },
        })
    end,

    ["buyback read: an empty tab is an empty list, a closed window is not known"] = function(t)
        t.eq(tab({}).returnableItems(), {})
        t.eq(tab({ { link = STONE, name = "Rough Stone", price = 40, count = 5 } }, false).returnableItems(), nil)
    end,

    ["buyback read: a field the game leaves out is left out, never guessed"] = function(t)
        local c = tab({ { link = STONE } })
        t.eq(c.returnableItems(), { { index = 1, item = STONE } })
    end,

    ["buyback read: a secret value or a refusing game is not known, never a shorter list"] = function(t)
        local c, env = tab({
            { link = STONE, name = "Rough Stone", price = 40, count = 5 },
            { link = STONE, name = "Rough Stone", price = 77, count = 5 },
        })
        env.issecretvalue = function(v) return v == 77 end
        t.eq(c.returnableItems(), nil, "a secret price")
        env.issecretvalue = nil
        env.GetBuybackItemInfo = function() error("the client refused") end
        t.eq(c.returnableItems(), nil, "a refusing read")
        env.GetBuybackItemInfo = nil
        env.GetNumBuybackItems = nil
        t.eq(c.returnableItems(), nil, "a game without the tab")
    end,
}
