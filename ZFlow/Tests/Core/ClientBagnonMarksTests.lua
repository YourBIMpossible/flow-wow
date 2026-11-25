-- Workflow R4 (zflow-r4-bag-marks): the bag marks (c.markBagKinds) and the
-- gear badge letters (c.markBagSlots) reach the item buttons of Bagnon and
-- BagBrother, optional add-ons, over a hand-built environment. Flow
-- origin/HEAD Modules/Items/BagIcons.lua:126-150 walks the Blizzard bag
-- frames only. A first guess, not seen in game: Bagnon's item button class
-- is Bagnon.Item (older: Bagnon.ItemSlot), each button answering GetBag()
-- (else a bag field) and GetID() its slot, its Update method run whenever
-- it is drawn. Made-up frames. Not tested in game.
local _, ns = ...

local tests = {}

local function texture()
    local t = { shown = false }
    function t:SetSize() end
    function t:SetPoint() end
    function t:SetTextColor() end
    function t:SetTexture(p) self.path = p end
    function t:SetText(s) self.text = s end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

-- Bagnon's item class: buttons are instances of it (metatable __index).
local function bagnonClass()
    local Item = {}
    Item.__index = Item
    function Item:Update() self.updated = (self.updated or 0) + 1 end
    function Item:GetBag() return self.bag end
    function Item:GetID() return self.slot end
    function Item:CreateTexture() self.tex = texture() return self.tex end
    function Item:CreateFontString() self.fs = texture() return self.fs end
    function Item.new(bag, slot) return setmetatable({ bag = bag, slot = slot }, Item) end
    return Item
end

local function hookEnv(env)
    function env.hooksecurefunc(a, b, fn)
        local t, name, post = a, b, fn
        if type(a) ~= "table" then t, name, post = env, a, b end
        local old = t[name]
        t[name] = function(...)
            local r = { old(...) }
            post(...)
            return unpack(r)
        end
    end
    return env
end

local function shown(x) return x ~= nil and x.shown and (x.path or x.text) or nil end

tests["bagnon: a Bagnon item button maps to its bag and slot and gets the mark"] = function(t)
    local Item = bagnonClass()
    local env = hookEnv({ NUM_CONTAINER_FRAMES = 0, Bagnon = { Item = Item } })
    local c = ns.make.client(env)
    local a, b = Item.new(0, 1), Item.new(2, 3)
    c.markBagKinds({ [0] = { [1] = "up.tga" } })
    a:Update()
    b:Update()
    t.eq(shown(a.tex), "up.tga", "bag 0 slot 1: marked when Bagnon draws it")
    t.eq(shown(b.tex), nil, "bag 2 slot 3: no mark")
    t.eq(c.markBagKinds({ [2] = { [3] = "sell.tga" } }), 1, "a later draw reaches the seen Bagnon buttons")
    t.eq(shown(a.tex), nil, "old mark hidden")
    t.eq(shown(b.tex), "sell.tga", "new mark shown")
    t.eq(a.updated, 1, "Bagnon's own Update still ran")
end

tests["bagnon: the gear badge letters reach Bagnon buttons too"] = function(t)
    local Item = bagnonClass()
    local env = hookEnv({ NUM_CONTAINER_FRAMES = 0, Bagnon = { ItemSlot = Item } })
    local c = ns.make.client(env)
    c.onBagRedraw(function() end)   -- as Items/BagMarks.lua does at load
    local a = Item.new(1, 4)
    a:Update()
    t.eq(c.markBagSlots({ { bag = 1, slot = 4, text = "T^" } }), 1, "one letter shown")
    t.eq(shown(a.fs), "T^", "the older ItemSlot class, a badge on bag 1 slot 4")
end

tests["bagnon: BagBrother loading after Z-Flow is followed on its ADDON_LOADED"] = function(t)
    local Item = bagnonClass()
    local env = hookEnv({ NUM_CONTAINER_FRAMES = 0 })
    local c = ns.make.client(env)
    c.onBagRedraw(function() end)
    env.BagBrother = { Item = Item }
    c.bagAddonLoaded("BagBrother")
    local a = Item.new(0, 2)
    c.markBagKinds({ [0] = { [2] = "q.tga" } })
    a:Update()
    t.eq(shown(a.tex), "q.tga", "hooked once it loaded")
end

tests["bagnon: none loaded, nothing hooked and the Blizzard path is unchanged"] = function(t)
    local env = hookEnv({ NUM_CONTAINER_FRAMES = 0 })
    local c = ns.make.client(env)
    t.eq(c.markBagKinds({ [0] = { [1] = "a.tga" } }), 0)
    t.eq(c.markBagSlots({ { bag = 0, slot = 1, text = "x" } }), 0)
end

return tests
