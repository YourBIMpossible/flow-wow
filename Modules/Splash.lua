-- Login intro, played on Flow's arrow (it replaced a separate title card):
-- the ring's pillars stand tall and spin fast around a deep gold FLOW,
-- slowing to a step, while the text under it says "Flow (unfettered)", the
-- version and what Flow has to work with. Then the arrow appears over the
-- now-still pillars and goes back to pointing the way.
-- /flow splash replays it; Options > AddOns > Flow turns it off.

local _, ns = ...
local I = {}
ns.intro = I

local SPIN, TAIL = 3.2, 1.4   -- seconds: pillars spinning with FLOW, then the arrow
local TURNS = 6               -- ring turns during the spin (fast, easing out)
I.SPIN, I.TURNS = SPIN, TURNS

-- The short intro (F-097, /flow splash short): no spinning, FLOW shows still
-- and fades, 1.6 s instead of 4.6 s.
local SHORT_SHOW, SHORT_TAIL = 1.0, 0.6
-- Seconds of the two phases, and whether the first one moves.
function I.Times()
    if ns.db.splash.short then return SHORT_SHOW, SHORT_TAIL, false end
    return SPIN, TAIL, true
end

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ns.name, "Version") or "?"
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- The quest database, in two or three words. The intro plays in the first
-- seconds after a login or /reload, while Questie is still starting up: it
-- said "no quest database" with Questie installed (seen on screen,
-- 0.35.181), which reads as if something were missing.
--   linked: Flow can read it now; installed: the add-on is loaded
function I.QuestWords(linked, installed)
    if linked then return "Questie linked" end
    if installed then return "Questie starting up" end
    return "no quest database"
end
function I.QuestieInstalled()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not loaded then return false end
    local ok, yes = pcall(loaded, "Questie")
    return ok and yes and true or false
end

-- One short status line about what Flow has to work with.
function I.Status()
    local bits = {}
    local spells = ns.rotation and count(ns.rotation:KnownSpells()) or 0
    bits[#bits + 1] = spells .. " spells"
    local src = ns.quests and ns.quests:Source()
    bits[#bits + 1] = I.QuestWords(src and src.label == "Questie", I.QuestieInstalled())
    local plan = ns.nav and ns.nav.plan
    if plan and #plan > 0 then bits[#bits + 1] = #plan .. " steps planned" end
    return table.concat(bits, "  ·  ")
end

-- The ring's turn t seconds into the intro: very fast at first, easing out
-- to a step after TURNS full turns (so it ends where it started).
function I.SpinAngle(t)
    local u = math.min(math.max(t / SPIN, 0), 1)
    return (1 - (1 - u) ^ 3) * TURNS * 2 * math.pi
end

-- FLOW with depth: the word stacked a few times, each copy a pixel lower and
-- to the right and darker (the sides of the letters), the gold face on top
-- and a faint light edge above it.
-- Drawn on its own layer ABOVE the arrow (the arrow and its pillars are a
-- child frame, which the game always draws over its parent), so FLOW sits
-- on top of the spinning pillars, on a soft dark backing so it reads.
-- The backing fades out at its edges: a few ovals, each a little bigger and
-- each only faintly dark, stacked so the middle is about half dark and the
-- rim melts into the pillars (no hard black edge).
I.BACKING = { layers = 6, alpha = 0.11, from = { 38, 14 }, to = { 96, 40 } }
-- FLOW (and its backing) at half strength: the arrow shows through it.
I.TEXT_ALPHA = 0.5
local function deepText(f, arrow)
    local host = CreateFrame("Frame", nil, f)
    host:SetAllPoints(f)
    host:SetFrameLevel(arrow:GetFrameLevel() + 10)
    host:SetAlpha(I.TEXT_ALPHA)   -- (each layer's own fade multiplies this)
    local layers = {}
    local B = I.BACKING
    for i = 1, B.layers do
        local u = (i - 1) / (B.layers - 1)
        local back = host:CreateTexture(nil, "BACKGROUND")
        back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        back:SetSize(B.from[1] + (B.to[1] - B.from[1]) * u, B.from[2] + (B.to[2] - B.from[2]) * u)
        back:SetPoint("CENTER", host, "CENTER", 0, 6)
        back:SetVertexColor(0, 0, 0, B.alpha)
        layers[#layers + 1] = back
    end
    local function face(dx, dy, r, g, b, a, outline, layer)
        local fs = host:CreateFontString(nil, layer or "OVERLAY")
        local ok = pcall(fs.SetFont, fs, "Fonts\\MORPHEUS.TTF", 22, outline or "")
        if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, 19, outline or "") end
        fs:SetPoint("CENTER", host, "CENTER", dx, dy + 6)
        fs:SetTextColor(r, g, b, a)
        fs:SetText("FLOW")
        layers[#layers + 1] = fs
        return fs
    end
    -- The sides of the letters: six copies stepping down and right, darkest at the back.
    for i = 6, 1, -1 do face(i * 0.55, -i * 0.55, 0.32 - i * 0.04, 0.18 - i * 0.025, 0.02, 1, nil, "ARTWORK") end
    face(0, 0.8, 1, 1, 0.85, 0.6)                          -- light top edge
    face(0, 0, 1, 0.84, 0.28, 1, "THICKOUTLINE")           -- bold gold face
    local t = { host = host }   -- (host: tests)
    function t:SetAlpha(v) for _, l in ipairs(layers) do l:SetAlpha(v) end end
    function t:SetShown(v) host:SetShown(v) end
    function t:Show() self:SetShown(true) end
    function t:Hide() self:SetShown(false) end
    return t
end

local driver = CreateFrame("Frame")

function I:Play()
    local f = ns.nav and ns.nav.arrowFrame
    if not (f and f.arrow) or ns.db.nav.enabled == false then ns.nav.intro = nil return end
    local a = f.arrow
    f.introText = f.introText or deepText(f, a)
    ns.nav.intro = true   -- the arrow's own update leaves it alone meanwhile
    f:Show()
    local col = ns.theme.route
    a:SetVertexColor(col[1], col[2], col[3])
    -- The pillars, tall and spinning, FLOW where the sphere would be.
    local pillars = a.SetRingSpin ~= nil   -- (the flat arrow has no pillars: it spins itself)
    a.noBall, a.spinning = true, true
    a:SetArrived(false)
    if pillars then a:SetArrived(true) end
    a:SetRotation(0)
    f.text:SetText("|cffffd200Flow|r |cffbbbbbb(unfettered)|r")
    local ok, s = pcall(I.Status)
    f.sub:SetText("v" .. version() .. (ok and ("  ·  " .. s) or ""))
    f.introText:SetAlpha(0)
    f.introText:Show()
    local spin, tail, moves = I.Times()
    local t0 = GetTime()
    f.introStatusAt = nil
    local function finish()
        driver:SetScript("OnUpdate", nil)
        f.introText:Hide()
        a.noBall, a.spinning = nil, nil
        if pillars then a:SetRingSpin(0) end
        a:SetArrived(false)
        ns.nav.intro = nil   -- back to pointing the way
    end
    driver:SetScript("OnUpdate", function()
        local t = GetTime() - t0
        -- Quest data and the route arrive during the intro: keep the status current.
        if t - (f.introStatusAt or 0) > 0.5 then
            f.introStatusAt = t
            local okS, st = pcall(I.Status)
            f.sub:SetText("v" .. version() .. (okS and ("  ·  " .. st) or ""))
        end
        if t < spin then
            if moves then
                if pillars then a:SetRingSpin(I.SpinAngle(t)) else a:SetRotation(I.SpinAngle(t)) end
                f.introText:SetAlpha(math.min(1, t / 0.6))   -- FLOW fades in fast
            else
                f.introText:SetAlpha(1)   -- (short: FLOW shows at once, nothing turns)
            end
        elseif t < spin + tail then
            if a.spinning then
                -- Pillars still and short again, the arrow appears over them.
                a.spinning = nil
                if pillars then a:SetRingSpin(0) end
                a:SetArrived(false)
            end
            f.introText:SetAlpha(math.max(0, 1 - (t - spin) / 0.4))   -- FLOW fades out
        else
            finish()
        end
    end)
end

ns:OnLoad(function(saved)
    saved.splash = saved.splash or {}
    if saved.splash.enabled == nil then saved.splash.enabled = true end
    -- Hold the arrow from the very start, so it never shows a quest first
    -- and then gets taken over (that flashed).
    if saved.splash.enabled and ns.nav then ns.nav.intro = true end
end)

local shown = false
ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    -- Only on login or /reload, not on every loading screen.
    if not shown or isInitialLogin or isReloadingUi then
        shown = true
        -- (New to Flow: no intro on the very first login; the arrow fades in
        -- when you start walking instead, Reveal.lua.)
        if ns.db.splash.enabled and not (ns.reveal and not ns.reveal:Shown("arrow")) then
            -- At once: the status line fills in as quest data and the route arrive.
            local ok = pcall(I.Play, I)
            if not ok and ns.nav then ns.nav.intro = nil end
            -- Never leave the arrow held if the intro didn't run to the end.
            C_Timer.After(SPIN + TAIL + 2, function() if ns.nav and not driver:GetScript("OnUpdate") then ns.nav.intro = nil end end)
        elseif ns.nav then
            ns.nav.intro = nil   -- (no intro: never hold the arrow)
        end
    end
end)

ns.commands.splash = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.splash.enabled = (arg == "on")
        ns:Print("login intro on the arrow " .. arg)
    elseif arg:match("^short") then
        local v = arg:match("^short%s+(%S+)")
        if v == "on" or v == "off" then ns.db.splash.short = (v == "on") or nil
        else ns.db.splash.short = not ns.db.splash.short or nil end
        ns:Print("short, still intro " .. (ns.db.splash.short and "on" or "off") .. " (/flow splash plays it)")
    else
        I:Play()
    end
end
ns.commands.hello = ns.commands.splash
ns.commands.intro = ns.commands.splash
