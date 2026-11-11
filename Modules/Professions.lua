-- Your profession plan. Flow suggests one (from class data: for a paladin
-- Mining + Blacksmithing, for a druid Herbalism + Skinning, plus First Aid
-- and Cooking, Fishing optional), but you choose: from level 3 the advice
-- list offers "Choose your professions", and /flow setup has a row for it
-- (/flow professions too). The plan decides which trainers and skill-up stops
-- appear on the route, and a short reminder card (below) says what to learn
-- or train next, now and then.

local _, ns = ...
local P = {}
ns.professions = P

local PRIMARY = { "Mining", "Herbalism", "Skinning", "Blacksmithing", "Engineering", "Alchemy",
                  "Leatherworking", "Tailoring", "Enchanting" }
local SECONDARY = { "First Aid", "Cooking", "Fishing" }
local IS_PRIMARY = {}
for _, n in ipairs(PRIMARY) do IS_PRIMARY[n] = true end

local function suggested()
    local d = ns:ClassData()
    return d and d.leveling and d.leveling.professions or {}
end

-- The plan in use: yours if you chose one, otherwise Flow's suggestion.
function ns:ProfessionPlan()
    local mine = ns.db.prof and ns.db.prof.plan
    if mine then return mine end
    return suggested()
end

-------------------------------------------------------------------------------
-- Picker
-------------------------------------------------------------------------------

local frame

local function build()
    local f = CreateFrame("Frame", "FlowProfessions", UIParent)
    f:SetSize(360, 330)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowProfessions")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    top:SetColorTexture(1, 0.82, 0.25, 0.9)
    ns:MakeMovable(f, ns.db.prof, true)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Flow Professions")
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 14, -34)
    f.note:SetWidth(330)
    f.note:SetJustifyH("LEFT")

    f.checks = {}
    local function column(list, x, header)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", x, -70)
        h:SetText(header)
        for i, name in ipairs(list) do
            local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            c:SetSize(22, 22)
            c:SetPoint("TOPLEFT", x - 4, -84 - (i - 1) * 22)
            c.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
            c.name = name
            c:SetScript("OnClick", function(self)
                -- At most two primary professions.
                if self:GetChecked() and IS_PRIMARY[name] then
                    local n = 0
                    for _, o in ipairs(f.checks) do if o:GetChecked() and IS_PRIMARY[o.name] then n = n + 1 end end
                    if n > 2 then
                        self:SetChecked(false)
                        f.status:SetText("|cffff9933Two primary professions at most.|r")
                        return
                    end
                end
                f.status:SetText("")
            end)
            f.checks[#f.checks + 1] = c
        end
    end
    column(PRIMARY, 18, "Primary (pick 2)")
    column(SECONDARY, 190, "Secondary (any)")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 44)

    local function btn(text, w, x, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("BOTTOMLEFT", x, 12)
        b:SetText(text)
        b:SetScript("OnClick", fn)
    end
    btn("Flow suggests", 110, 12, function() P:Fill(suggested()) end)
    btn("Save", 90, 256, function()
        local plan, want = {}, {}
        for _, s in ipairs(suggested()) do want[s.name] = s end
        for _, c in ipairs(f.checks) do
            if c:GetChecked() then
                plan[#plan + 1] = { name = c.name, optional = want[c.name] and want[c.name].optional or nil }
            end
        end
        ns.db.prof.plan = plan
        ns.db.prof.chosen = true
        if ns.nav then ns.nav:Collect() end
        if ns.advisor then ns.advisor:Refresh() end
        ns:Print(#plan .. " profession(s) in your plan. The route will take you to their trainers.")
        f:Hide()
    end)
    f:Hide()
    return f
end

function P:Fill(plan)
    local on = {}
    for _, p in ipairs(plan) do on[p.name] = true end
    for _, c in ipairs(frame.checks) do
        local have = ns.api.Skill(c.name)
        c:SetChecked(on[c.name] or false)
        c.label:SetText(c.name .. (have and string.format(" |cff888888(%d)|r", have) or ""))
    end
end

function P:Open()
    frame = frame or build()
    local names = {}
    for _, s in ipairs(suggested()) do names[#names + 1] = s.name .. (s.optional and " (optional)" or "") end
    local d = ns:ClassData()
    local why = d and d.leveling and d.leveling.professionsWhy
    frame.note:SetText("Flow suggests: " .. table.concat(names, ", ") .. "." .. (why and (" " .. why) or "")
        .. " Untick what you don't want; the route only takes you to trainers for what's ticked.")
    self:Fill(ns:ProfessionPlan())
    frame:Show()
end

ns:OnLoad(function(saved) saved.prof = saved.prof or {} end)
ns:PerCharacter("prof")   -- your profession plan

-- Offered quietly from level 3 (advice list), never as a pop-up.
ns:Register("advisor", "choosePro", {
    check = function()
        if ns.db.prof.chosen or UnitLevel("player") < 3 then return nil end
        -- Already learned two main professions in game: that's a choice made.
        local primaries = 0
        for _, pr in ipairs(ns.api.Professions()) do
            if IS_PRIMARY[pr.name] then primaries = primaries + 1 end
        end
        if primaries >= 2 then return nil end
        return { { importance = 45, text = "Choose your professions (Flow has a suggestion)",
                   improves = { "Professions" }, onClick = function() P:Open() end } }
    end,
})

ns:Register("setupItem", "professions", {
    order = 95, label = "Professions plan", why = "Which professions the route takes you to train.",
    now = function() return ns.db.prof.chosen and "chosen" or "Flow's suggestion" end,
    action = "Choose...", run = function() P:Open() end,
})

-------------------------------------------------------------------------------
-- Reminder card: what to do next for your professions, for a few seconds
--
--   [book]  Professions: Flow suggests Herbalism + Skinning
--           - Learn Herbalism: stop 4 on your route (Komin Winterhoof, Thunder Bluff, 1240 yd)
--           - Learn Skinning: stop 6 on your route (Mooranta, Thunder Bluff, 1260 yd)
--           Trainers are stops on your optimal route. To go to one next, click its ^ in the Flow Router.
--   [Add to my route]  [Choose others...]  [Not now]      stop reminding
--
-- The trainers are never a waypoint: they're stops the route plans in with
-- everything else (Goals.lua "errands"), however many there are. "Add to my
-- route" shows only when your route leaves trainers out ("Quests only", or
-- the Professions tick off), and turns professions on.
--
-- Opens for 8 s (it waits while your mouse is on it) when there's something
-- to do: a while after you log in, when you level up, when what's needed
-- changes (you learned one, a skill reached its cap) and when you walk into
-- a town where a trainer you need stands. From level 5, once the Flow pieces
-- have all appeared (Reveal.lua). "Not now" waits for your next level;
-- "stop reminding" turns it off (/flow settings: Profession reminders).
-------------------------------------------------------------------------------

local SHOW = 8
-- The level each next tier needs (by the skill cap you're at now).
local TIER_LEVEL = { [75] = 10, [150] = 20, [225] = 35 }

-- What to do next for the professions in a plan, primaries first, optional
-- ones last. skill(name) -> rank, max (nil: not learned).
--   -> { { name, kind = "learn" | "train", optional, text } }
function P.NextSteps(plan, skill, level)
    local steps = {}
    for i, p in ipairs(plan or {}) do
        local rank, max = skill(p.name)
        local step
        if not rank then
            step = { name = p.name, kind = "learn", text = "Learn " .. p.name }
        elseif max and max > 0 and max < 300 and rank >= max - 25 and (level or 0) >= (TIER_LEVEL[max] or 0) then
            -- The trainer teaches the next tier from 25 below the cap.
            step = { name = p.name, kind = "train", text = string.format("Train the next %s tier (%d/%d)", p.name, rank, max) }
        end
        if step then
            step.optional, step.order = p.optional, (p.optional and 200 or IS_PRIMARY[p.name] and 0 or 100) + i
            steps[#steps + 1] = step
        end
    end
    table.sort(steps, function(a, b) return a.order < b.order end)
    return steps
end

-- What the reminder is about, to notice when it changes ("" = nothing to do).
function P.StepsKey(steps)
    local parts = {}
    for _, s in ipairs(steps) do
        if not s.optional then parts[#parts + 1] = s.kind .. ":" .. s.name end
    end
    return table.concat(parts, ",")
end

-- The nearest trainer for a profession on your continent: { name, map, x, y, yards }.
function P.NearestTrainer(profession)
    local nav = ns.nav
    local p = nav and nav:PlayerPos()
    if not p then return nil end
    local best
    for _, name in ipairs(ns.places:TrainersFor(profession)) do
        for _, pt in ipairs(ns.places:Points(name)) do
            local cont, wx, wy = nav:ToWorld(pt.map, pt.x, pt.y)
            if cont == p.cont and wx then
                local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
                if not best or d < best.yards then best = { name = name, map = pt.map, x = pt.x, y = pt.y, yards = d } end
            end
        end
    end
    return best
end

local function mapName(map)
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or "?"
end

-- Where a profession's trainer stands on your route:
--   "planned", n   stop n of the route
--   "off"          your route leaves trainers out (Quests only, or without professions)
--   "later"        on the route's list, not planned in yet (blocked or optional)
--   "unplaced"     Flow doesn't know where a trainer stands yet
-- nav: ns.nav (Mode, plan, Goals); cfg: ns.db.nav.
function P.RouteStatus(name, nav, cfg)
    if cfg.professions == false or nav:Mode() == "quests" then return "off" end
    local key = "train:" .. name
    for i, s in ipairs(nav.plan or {}) do
        if s.goal and s.goal.key == key then return "planned", i end
    end
    for _, g in ipairs(nav:Goals() or {}) do
        if g.key == key then return "later" end
    end
    return "unplaced"
end

local STATUS_TEXT = {
    off = "not on your route (it leaves trainers out)",
    later = "on your route, after the stops nearer you",
    unplaced = "Flow doesn't know where a trainer stands yet (talk to one once and it remembers)",
}

local remindCard

local function closeCard()
    if remindCard then remindCard:Hide() end
end

local function buildCard()
    local f = CreateFrame("Frame", "FlowProfReminder", UIParent)
    f:SetSize(420, 118)
    f:SetPoint("TOP", 0, -260)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Professions", "Interface\\Icons\\INV_Misc_Book_11")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -30)
    f.title:SetWidth(396); f.title:SetJustifyH("LEFT")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.body:SetWidth(396); f.body:SetJustifyH("LEFT"); f.body:SetJustifyV("TOP")
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -6)
    f.hint:SetWidth(396); f.hint:SetJustifyH("LEFT")
    f.hint:SetText("Trainers are stops on your optimal route. To go to one next, click its ^ in the Flow Router.")
    local function button(text, w)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetText(text)
        return b
    end
    f.add = button("Add to my route", 130)
    f.add:SetPoint("BOTTOMLEFT", 10, 10)
    f.choose = button("Choose others...", 120)
    f.later = button("Not now", 80)
    f.later:SetPoint("LEFT", f.choose, "RIGHT", 6, 0)
    f.stop = CreateFrame("Button", nil, f)
    f.stop:SetSize(90, 14)
    f.stop:SetPoint("BOTTOMRIGHT", -8, 14)
    f.stop.text = f.stop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.stop.text:SetAllPoints(); f.stop.text:SetJustifyH("RIGHT")
    f.stop.text:SetText("stop reminding")
    f.timer = CreateFrame("StatusBar", nil, f)
    f.timer:SetPoint("BOTTOMLEFT"); f.timer:SetPoint("BOTTOMRIGHT"); f.timer:SetHeight(3)
    f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local o = ns.theme.arrow
    f.timer:SetStatusBarColor(o[1], o[2], o[3])
    f.timer:SetMinMaxValues(0, SHOW)

    -- Your route with trainers in it: professions on.
    f.add:SetScript("OnClick", function()
        ns.db.nav.professions = true
        if ns.nav:Mode() == "quests" then ns.nav:SetMode("optimal") else ns.nav:Collect() end
        ns:Print("route: professions on. Your trainers are stops on it now.")
        -- (Show where they landed once the route is planned again.)
        C_Timer.After(1.5, function() if f:IsShown() then P:ShowReminder() end end)
    end)
    f.choose:SetScript("OnClick", function() closeCard(); P:Open() end)
    f.later:SetScript("OnClick", function()
        ns.db.prof.snoozeLevel = UnitLevel("player")
        closeCard()
        ns:Print("professions: Flow reminds you again at your next level.")
    end)
    f.stop:SetScript("OnClick", function()
        ns.db.prof.remind = false
        closeCard()
        ns:Print("profession reminders off (/flow settings to turn them back on).")
    end)
    f:SetScript("OnUpdate", function(self, dt)
        if self:IsMouseOver() then return end
        self.left = self.left - dt
        self.timer:SetValue(math.max(0, self.left))
        if self.left <= 0 then self:Hide() end
    end)
    f:Hide()
    return f
end

function P:ShowReminder(steps)
    steps = steps or P.NextSteps(ns:ProfessionPlan(), ns.api.Skill, UnitLevel("player"))
    if #steps == 0 then return false end
    remindCard = remindCard or buildCard()
    local f = remindCard
    local names = {}
    for _, p in ipairs(ns:ProfessionPlan()) do
        if IS_PRIMARY[p.name] then names[#names + 1] = p.name end
    end
    f.title:SetText((ns.db.prof.chosen and "Your plan: " or "Flow suggests: ")
        .. (#names > 0 and table.concat(names, " + ") or "no main professions"))
    local lines, anyOff = {}, false
    for i, s in ipairs(steps) do
        if i > 4 then break end
        local status, n = P.RouteStatus(s.name, ns.nav, ns.db.nav)
        if status == "off" then anyOff = true end
        local t = status ~= "unplaced" and P.NearestTrainer(s.name) or nil
        local where = t and string.format("%s, %s, %d yd", t.name, mapName(t.map), t.yards) or nil
        local text = status == "planned" and ("|cff66ff66stop " .. n .. " on your route|r") or STATUS_TEXT[status]
        lines[#lines + 1] = "- " .. s.text .. ": " .. text .. (where and (" (" .. where .. ")") or "")
    end
    f.body:SetText(table.concat(lines, "\n"))
    -- Only offered when the route leaves trainers out.
    f.add:SetShown(anyOff)
    f.choose:ClearAllPoints()
    if anyOff then f.choose:SetPoint("LEFT", f.add, "RIGHT", 6, 0) else f.choose:SetPoint("BOTTOMLEFT", 10, 10) end
    f.later:ClearAllPoints()
    f.later:SetPoint("LEFT", f.choose, "RIGHT", 6, 0)
    f:SetHeight(30 + (f.title:GetStringHeight() or 14) + 4 + (f.body:GetStringHeight() or 14)
        + 6 + (f.hint:GetStringHeight() or 12) + 44)
    f.left = SHOW
    f.timer:SetValue(SHOW)
    f:Show()
    return true
end

-- Should it open now? why: "login" | "level" | "change" | "town".
function P.ShouldRemind(why, steps, s)
    if s.remind == false or s.level < 5 or not s.revealed or s.inCombat or #steps == 0 then return false end
    if P.StepsKey(steps) == "" then return false end           -- only optional ones left
    if why == "town" then return true end                       -- a trainer you need is right here
    return not (s.snoozeLevel and s.level <= s.snoozeLevel)
end

local remindedOnce, townsSeen, waiting = false, {}, nil

local function remind(why)
    local level = UnitLevel("player")
    local steps = P.NextSteps(ns:ProfessionPlan(), ns.api.Skill, level)
    local key = P.StepsKey(steps)
    local d = ns.db.prof
    if why == "change" and key == (d.lastKey or "") then return end
    if InCombatLockdown() then waiting = why return end
    local ok = P.ShouldRemind(why, steps, { remind = d.remind, level = level, snoozeLevel = d.snoozeLevel,
        revealed = not ns.reveal or ns.reveal:Shown("advice"), inCombat = false })
    if why == "town" then
        -- Only when a trainer for the first step is on the map you just walked into.
        local t = ok and P.NearestTrainer(steps[1].name)
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        ok = t ~= nil and t.map == here and not townsSeen[here]
        if ok then townsSeen[here] = true end
    end
    d.lastKey = key
    if ok then P:ShowReminder(steps) end
end

ns:On("PLAYER_ENTERING_WORLD", function()
    if remindedOnce then return end
    remindedOnce = true
    C_Timer.After(25, function() pcall(remind, "login") end)
end)
ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(3, function() pcall(remind, "level") end) end)
ns:On("SKILL_LINES_CHANGED", function()
    if P.skillTimer then return end
    P.skillTimer = C_Timer.NewTimer(2, function() P.skillTimer = nil; pcall(remind, "change") end)
end)
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, function() pcall(remind, "town") end) end)
ns:On("PLAYER_REGEN_ENABLED", function()
    local why = waiting
    waiting = nil
    if why then C_Timer.After(2, function() pcall(remind, why) end) end
end)

ns.commands.professions = function(arg)
    arg = (arg or ""):lower()
    if arg:find("^plan") then return ns.skillPlan:Explain() end
    if arg:find("^remind") then
        if not P:ShowReminder() then ns:Print("professions: nothing to learn or train right now.") end
        return
    end
    P:Open()
end
ns.commands.prof = ns.commands.professions
