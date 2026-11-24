-- Lead section 425 item 1 (zflow-bag-marks-combined): bag marks on the
-- real client over a hand-built environment. Flow origin/HEAD
-- Modules/Items/BagIcons.lua:126-150 walks ContainerFrameCombinedBags and
-- ContainerFrame<i>, each through EnumerateValidItems, else .Items, else
-- the named <frame>Item<j> buttons; the bag from the button's GetBagID,
-- else the frame's GetID. Every client name here is a first guess; made-up
-- frames. Not tested in game.
local _, ns = ...

local tests = {}

local function texture()
    local t = { shown = false }
    function t:SetSize() end
    function t:SetPoint() end
    function t:SetTexture(p) self.path = p end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

-- A slot button; bagId given: it answers GetBagID (the combined view).
local function button(slot, bagId)
    local b = { tex = nil }
    function b:GetID() return slot end
    if bagId ~= nil then function b:GetBagID() return bagId end end
    function b:CreateTexture() self.tex = texture() return self.tex end
    return b
end

local function shownPath(b)
    if b.tex == nil or not b.tex.shown then return nil end
    return b.tex.path
end

tests["bag marks: the combined bags view gets marks, each slot's bag from its button"] = function(t)
    local a, b, c3 = button(1, 0), button(2, 0), button(1, 2)
    local combined = { list = { a, b, c3 } }
    function combined:GetID() return 0 end
    function combined:EnumerateValidItems()
        local i = 0
        return function()
            i = i + 1
            if self.list[i] then return i, self.list[i] end
        end
    end
    local env = { NUM_CONTAINER_FRAMES = 0, ContainerFrameCombinedBags = combined }
    local c = ns.make.client(env)
    local n = c.markBagSlots({ [0] = { [2] = "up.tga" }, [2] = { [1] = "sell.tga" } })
    t.eq(n, 2, "two marks drawn")
    t.eq(shownPath(a), nil, "bag 0 slot 1: no mark")
    t.eq(shownPath(b), "up.tga", "bag 0 slot 2 marked")
    t.eq(shownPath(c3), "sell.tga", "bag 2 slot 1 marked, the bag read from the button")
    t.eq(c.markBagSlots({}), 0, "no marks asked: none drawn")
    t.eq(shownPath(b), nil, "an old mark is hidden")
end

tests["bag marks: a frame with an Items list and no enumerator is walked; named buttons still work"] = function(t)
    local x = button(3)
    local listed = { Items = { x } }
    function listed:GetID() return 1 end
    local y = button(4)
    local named = {}
    function named:GetID() return 3 end
    function named:GetName() return "ContainerFrame2" end
    local env = { NUM_CONTAINER_FRAMES = 2, ContainerFrame1 = listed, ContainerFrame2 = named,
                  ContainerFrame2Item1 = y }
    local c = ns.make.client(env)
    local n = c.markBagSlots({ [1] = { [3] = "a.tga" }, [3] = { [4] = "b.tga" } })
    t.eq(n, 2)
    t.eq(shownPath(x), "a.tga", "Items list: the frame's bag")
    t.eq(shownPath(y), "b.tga", "named button")
end

tests["bag marks: a frame that raises or has no buttons is passed over"] = function(t)
    local bad = setmetatable({}, { __index = function() error("no") end })
    local env = { NUM_CONTAINER_FRAMES = 1, ContainerFrameCombinedBags = bad, ContainerFrame1 = bad }
    local c = ns.make.client(env)
    t.eq(c.markBagSlots({ [0] = { [1] = "a.tga" } }), 0)
end

tests["bag marks: the combined view's redraw is followed when it can be"] = function(t)
    local hooked = {}
    local combined = {}
    function combined:UpdateItems() end
    local env = { ContainerFrameCombinedBags = combined }
    function env.hooksecurefunc(a, b, fn)
        if type(a) == "table" then hooked[#hooked + 1] = b; a["_hook_" .. b] = fn
        else hooked[#hooked + 1] = a end
    end
    local c = ns.make.client(env)
    local ran = 0
    t.eq(c.onBagRedraw(function() ran = ran + 1 end), true, "followed")
    t.eq(#hooked, 1, "one hook")
    t.eq(hooked[1], "UpdateItems", "the combined view's UpdateItems is followed")
    combined._hook_UpdateItems()
    t.eq(ran, 1, "its redraw reaches the listener")
end

return tests
