-- A small context menu in Flow's own style (dark panel, accent edge).
--   ns.menu:Open(items)   at the cursor
-- items: { text, func, checked = bool|nil, radio = bool, disabled = bool,
--          title = bool, sep = true }
-- Closes on a click outside it, on Escape, or after choosing an entry.

local _, ns = ...
local Menu = {}
ns.menu = Menu

local ROW_H, PAD, W = 18, 6, 230
local frame, catcher
local rows = {}

local function build()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() Menu:Close() end)
    -- The catcher covers the whole screen to close the menu on a click
    -- outside it: never leave it up without the menu, or no click would get
    -- through to the game.
    catcher:SetScript("OnUpdate", function(self)
        if not (frame and frame:IsShown()) then self:Hide(); ns:Log("menu", "click catcher was up without a menu: hidden") end
    end)
    catcher:Hide()

    frame = CreateFrame("Frame", "FlowMenu", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(catcher:GetFrameLevel() + 10)
    frame:SetWidth(W)
    frame:EnableMouse(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    local o = ns.theme.arrow
    frame.accent = frame:CreateTexture(nil, "BORDER")
    frame.accent:SetPoint("TOPLEFT"); frame.accent:SetPoint("BOTTOMLEFT")
    frame.accent:SetWidth(3)
    frame.accent:SetColorTexture(o[1], o[2], o[3], 1)
    frame:SetScript("OnHide", function() catcher:Hide() end)
    tinsert(UISpecialFrames, "FlowMenu")  -- Escape closes it
    frame:Hide()
end

local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, frame)
    r:SetHeight(ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.1)
    r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.mark:SetPoint("LEFT", 8, 0)
    r.mark:SetWidth(14)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 24, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetPoint("LEFT", 8, 0); r.line:SetPoint("RIGHT", -8, 0)
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.15)
    rows[i] = r
    return r
end

function Menu:Close() if frame then frame:Hide() end end

-- Flow's windows you can switch off (registry "window": { name, order,
-- hidden(), show() }). While one is off, every Flow menu offers to show it
-- again at the bottom (Yang: hide a Flow window, and the other menus bring
-- it back). Flow Settings has a box for each too.
function Menu.HiddenWindowItems()
    local list = {}
    for _, w in ns:Each("window") do
        local ok, hidden = pcall(w.hidden)
        if ok and hidden then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    local out = {}
    if #list == 0 then return out end
    out[1] = { title = true, text = "Hidden Flow windows" }
    for _, w in ipairs(list) do
        out[#out + 1] = { text = "Show " .. w.name, func = function() pcall(w.show) end }
    end
    return out
end

function Menu:Open(items)
    -- Hidden Flow windows: "Show ..." at the end of every menu.
    local hidden = Menu.HiddenWindowItems()
    if #hidden > 0 then
        local all = {}
        for _, it in ipairs(items) do all[#all + 1] = it end
        all[#all + 1] = { sep = true }
        for _, it in ipairs(hidden) do all[#all + 1] = it end
        items = all
    end
    self.items = items   -- the menu on screen (tests read its entries)
    GameTooltip:Hide()
    if not frame then build() end
    local y = -PAD
    local n = 0
    for i, it in ipairs(items) do
        n = i
        local r = row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 3, y)
        r:SetPoint("TOPRIGHT", 0, y)
        local h = it.sep and 7 or ROW_H
        r:SetHeight(h)
        r.line:SetShown(it.sep == true)
        r.text:SetShown(not it.sep)
        r.mark:SetShown(not it.sep)
        r.hl:SetShown(not (it.sep or it.title or it.disabled))
        if not it.sep then
            if it.title then
                r.text:SetText("|cffffd200" .. (it.text or "") .. "|r")
            elseif it.disabled then
                r.text:SetText("|cff777777" .. (it.text or "") .. "|r")
            else
                r.text:SetText(it.text or "")
            end
            local mark = ""
            -- Game fonts lack most symbols, so the tick is a texture.
            if it.checked then mark = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t" end
            r.mark:SetText(mark)
        end
        r:SetScript("OnClick", function()
            if it.sep or it.title or it.disabled then return end
            Menu:Close()
            if it.func then
                local ok, err = pcall(it.func)
                if not ok then ns:Print("menu: " .. tostring(err)) end
            end
        end)
        r:Show()
        y = y - h
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(-y + PAD)
    local scale = UIParent:GetEffectiveScale()
    local x, cy = GetCursorPosition()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cy / scale - 4)
    frame:SetClampedToScreen(true)
    catcher:Show()
    frame:Show()
end

-- Route entries shared by every Flow menu (arrow, tracker rows).
function Menu:RouteItemsRaw()
    local nav = ns.nav
    local mode, profs = nav:Mode(), ns.db.nav.professions ~= false
    local sort = ns.xpValue:Mode()
    local nHidden = 0
    for _ in pairs(ns.db.nav.hidden or {}) do nHidden = nHidden + 1 end
    local function setRoute(m, p)
        return function()
            ns.db.nav.professions = p
            nav:SetMode(m)
            nav:Collect()
        end
    end
    local items = {
        { title = true, text = "Route" },
        { text = "Quests only", radio = true, checked = mode == "quests", func = setRoute("quests", profs) },
        { text = "Optimal", radio = true, checked = mode == "optimal", func = setRoute("optimal", profs) },
        { text = "Completionist: every quest here, any level", radio = true, checked = mode == "complete", func = setRoute("complete", profs) },
        -- Professions: their own switch, whichever route you picked (Quests
        -- only never has them).
        { text = mode == "quests" and "|cff777777Professions (not with Quests only)|r" or "Professions",
          checked = profs and mode ~= "quests", disabled = mode == "quests", func = setRoute(mode, not profs) },
        { sep = true },
        { title = true, text = "Order" },
        { text = ns.theme:ModeText("xp", "Most XP first"), radio = true, checked = sort == "xp", func = function() ns.xpValue:SetMode("xp") end },
        { text = ns.theme:ModeText("distance", "Shortest path"), radio = true, checked = sort == "distance", func = function() ns.xpValue:SetMode("distance") end },
        -- On while you've picked the next stop yourself (a ^ / Go here next);
        -- the two above put you back on an optimised route.
        { text = sort == "custom" and ns.theme:ModeText("custom", "Custom route (your pick)")
                or "|cff777777Custom route (pick a stop: its ^ or Go here next)|r",
          radio = true, checked = sort == "custom", disabled = sort ~= "custom",
          func = function() ns.xpValue:SetMode("custom") end },
        { text = "Finish the area you're in first", checked = ns.db.nav.areaFirst == true,
          func = function() ns.db.nav.areaFirst = (ns.db.nav.areaFirst ~= true); nav.planDirty = true end },
        { sep = true },
        { title = true, text = "Stops on the map" },
    }
    -- Which stops the map and the Flow Tracker show (the Flow Router always
    -- lists them all): everything in this area, or your next N.
    local shown, area = nav:StopsShown(), nav:AreaMode()
    items[#items + 1] = { text = nav.AREA_LABEL, radio = true, checked = area,
        func = function() nav:SetArea(true) end }
    for _, n in ipairs(nav.STOP_CHOICES) do
        items[#items + 1] = { text = nav:StopsShownLabel(n), radio = true, checked = not area and shown == n,
            func = function() nav:SetStopsShown(n) end }
    end
    items[#items + 1] = { text = string.format("All stops (%d on the route now)", nav.plan and #nav.plan or 0),
        radio = true, checked = not area and shown == nil, func = function() nav:SetStopsShown(nil) end }
    local following = ns.follow and ns.follow:Target()
    for _, it in ipairs({
        { sep = true },
        { title = true, text = "Your waypoint" },
        { text = "Set a waypoint (coordinates, or a party member's name)...", func = function() ns.waypoint:Prompt() end },
        { text = "Nearest repair", func = function() if ns.services then ns.services:GoTo("repair") end end },
        { text = "Nearest vendor (sell)", func = function() if ns.services then ns.services:GoTo("vendor") end end },
        { text = "Nearest flight master", func = function() if ns.services then ns.services:GoTo("flight") end end },
        { text = "Nearest innkeeper", func = function() if ns.services then ns.services:GoTo("inn") end end },
        { text = "Nearest mailbox", func = function() if ns.services then ns.services:GoTo("mail") end end },
    }) do items[#items + 1] = it end
    -- In a group: follow a party member (the arrow keeps pointing at them),
    -- or drop your waypoint where they are.
    if ns.follow and ns.party and ns.party:InGroup() then
        for _, it in ipairs(ns.follow:MenuItems()) do items[#items + 1] = it end
    end
    for _, it in ipairs({
        { text = following and ("Clear your waypoint (stop following " .. following .. ")") or "Clear your waypoint",
          disabled = ns.waypoint:Get() == nil and not following,
          func = function()
              if following then ns.follow:Stop() end
              if ns.waypoint:Get() then ns.waypoint:Clear(); ns:Print("waypoint cleared") end
          end },
    }) do items[#items + 1] = it end
    -- Dungeon runs worth doing at your level (Dungeons.lua; needs Questie).
    -- (In a pcall: one error there must not stop the route menu opening.)
    if ns.dungeons then
        local ok, list = pcall(ns.dungeons.MenuItems, ns.dungeons)
        for _, it in ipairs(ok and list or {}) do items[#items + 1] = it end
    end
    for _, it in ipairs({
        { sep = true },
        { text = string.format("Unhide all stops (%d)", nHidden), disabled = nHidden == 0,
          func = function() ns.commands.nav("unhide") end },
        -- Hover-to-bind mode, easy to find (also in /flow settings and /flow bind).
        { text = "Key bindings: hover a button, press a key...", disabled = InCombatLockdown(),
          func = function() if ns.bind then ns.bind:Start() end end },
    }) do items[#items + 1] = it end
    -- In a group: your own route, join the party route (everyone on it: one
    -- route for all their quests, the same for all of you), or just one
    -- member's quests; then following a party member. Never switched for you.
    local P = ns.party
    if P and P:InGroup() then
        items[#items + 1] = { sep = true }
        items[#items + 1] = { title = true, text = "Party" }
        local H = ns.partyHelp
        if H then for _, it in ipairs(H:MenuItems()) do items[#items + 1] = it end end
        -- (A hand-made route someone shared with /flow party share.)
        if P:Active() then
            items[#items + 1] = { text = "Shared stops from " .. (P:Editor() or "the party"), radio = true, checked = P:Following(),
                func = function() P:SetFollowing(true) end }
            items[#items + 1] = { text = "Drop the shared stops", func = function() P:Leave() end }
        end
    end
    return items
end

-- The route list, never failing: an error in one entry (like the waypoint
-- check in 0.35.53) used to stop the whole menu from opening, with nothing
-- on screen. Now it's logged (diagnostics: "[menu]") and said in chat, and
-- the menu still opens with what it can show.
function Menu:RouteItems()
    local ok, items = pcall(self.RouteItemsRaw, self)
    if ok and type(items) == "table" then return items end
    ns:Log("menu", "route items: " .. tostring(items))
    if not Menu.warned then
        Menu.warned = true
        ns:Print("|cffff6060a menu entry failed (logged for the diagnostics).|r")
    end
    return { { title = true, text = "Route" },
             { text = "(something went wrong here: it's logged)", disabled = true } }
end
