local _, ns = ...

-- Parity row F-21, the logic half (lead section 738): the login intro, as
-- Flow's Modules/Splash.lua. What it says and when it shows; the drawing
-- (Flow played it on the arrow: pillars spinning round the name, then the
-- arrow) is the drawing lane's, which listens for LI.EVENT.
--
-- When (Flow :184-207): at a login or a /reload, or the first world of the
-- session; not at every loading screen. Not with the setting off, and not
-- for a new player whose arrow is not shown yet (UI/Reveal.lua; Flow skips
-- the first login too). The word plays it whenever asked.
-- What (Flow :36-62, in our own words): the add-on's name and version, and
-- one status line: the spells known (when read), the quest data (from
-- Questie, Questie still loading, or none) and the steps ahead on the
-- route (when any). Read only when it plays, and only as things are: the
-- route's View, never a new plan (lead section 757).
-- How long (Flow :14-23): 3.2 s spinning then 1.4 s; the short one 1.0 s
-- still then 0.6 s.
--
--   LI.ShouldShow(r) -> bool  r = { on, initial, reload, shownBefore,
--                             arrowShown }
--   LI.QuestWords(linked, installed), LI.Status(r), LI.Title(id, version)
--   LI.Times(short) -> show, tail, spins
--   LI.Declare(k, diag) -> api; api.Play() emits LI.EVENT with
--     { title, status, show, tail, spins }; api.Shows() counts them.
-- Settings: LI.SETTING (on as made, Flow's default), LI.SHORT (off).
-- "<slash> splash" plays it; "splash on|off", "splash short on|off".
-- Reads: client.version, client.questieModule, client.addonLoaded (all in
-- Core/Client.lua); the spells from the rotation driver's last view and
-- the steps from the route's plan, when they are there. Not tested in game.
local LI = {}
ns.LoginIntro = LI

LI.NAME = "loginIntro"
LI.SETTING = "ui.splash"
LI.SHORT = "ui.splashShort"
LI.WORD = "splash"
LI.EVENT = "LOGIN_INTRO"
LI.HELP = "play the login intro; splash on|off, splash short on|off"
LI.SEP = "; "

function LI.ShouldShow(r)
    if type(r) ~= "table" or r.on ~= true then return false end
    if r.arrowShown == false then return false end
    return r.shownBefore ~= true or r.initial == true or r.reload == true
end

function LI.QuestWords(linked, installed)
    if linked then return "quests from Questie" end
    if installed then return "Questie still loading" end
    return "no quest data"
end

local function count(n) return type(n) == "number" and n == n and n >= 0 end

function LI.Status(r)
    if type(r) ~= "table" then r = {} end
    local bits = {}
    if count(r.spells) then bits[#bits + 1] = r.spells .. " spells known" end
    bits[#bits + 1] = LI.QuestWords(r.linked == true, r.installed == true)
    if count(r.steps) and r.steps > 0 then bits[#bits + 1] = r.steps .. " steps ahead" end
    return table.concat(bits, LI.SEP)
end

function LI.Title(id, version)
    local name = tostring(ns.id.title)
    if type(id) == "table" and id.title ~= nil then name = tostring(id.title) end
    if type(version) == "string" and version ~= "" then return name .. " " .. version end
    return name
end

function LI.Times(short)
    if short then return 1.0, 0.6, false end
    return 3.2, 1.4, true
end

function LI.Declare(k, diag)
    local api = {}
    local ctx
    local shows, shownBefore = 0, false

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function reads()
        local r = {
            linked = ask("questieModule", "QuestieDB") ~= nil,
            installed = ask("addonLoaded", "Questie") == true,
        }
        local D = ns.RotationDriver
        local drv = D and k.use(D.NAME)
        if type(drv) == "table" and type(drv.View) == "function" then
            local ok, v = pcall(drv.View)
            local spells = nil
            if ok and type(v) == "table" and type(v.snapshot) == "table" then spells = v.snapshot.spells end
            if type(spells) == "table" then
                local n = 0
                for _, s in pairs(spells) do
                    if type(s) == "table" and s.known == true then n = n + 1 end
                end
                r.spells = n
            end
        end
        -- The route as it is (TripRoute View, a copy); never Plan, which
        -- builds a route (lead section 757).
        local route = k.use("tripRoute")
        if type(route) == "table" and type(route.View) == "function" then
            local ok, view = pcall(route.View)
            if ok and type(view) == "table" and type(view.stops) == "table" then r.steps = #view.stops end
        end
        return r
    end

    function api.Play()
        if not ctx then return false end
        local show, tail, spins = LI.Times(ctx.settings:get(LI.SHORT) == true)
        local version = ask("version", ns.id.addon)
        shows = shows + 1
        ctx.bus:emit(LI.EVENT, { title = LI.Title(ns.id, version), status = LI.Status(reads()),
            show = show, tail = tail, spins = spins })
        return true
    end
    function api.Shows() return shows end

    k:Module({
        name = LI.NAME,
        needs = { "client", "bus", "settings" },
        provides = { Play = api.Play, Shows = api.Shows },
        settings = { {
            -- A new row, on as made (as Flow's): reviewed from another lane
            -- (lead section 557).
            key = LI.SETTING, scope = "account", type = "bool", default = true,
            label = "Play the intro at login",
            help = "At a login or a reload, a short intro says what " .. ns.id.title
                .. " has to work with: your spells, your quest data, the steps ahead.",
            group = "general.windows", synonyms = { "intro", "splash", "login", "hello" },
        }, {
            key = LI.SHORT, scope = "account", type = "bool", default = false,
            label = "A short, still intro",
            help = "The intro shows still and fades, about a second and a half.",
            group = "general.windows", synonyms = { "intro", "splash", "short" },
        } },
        start = function(c)
            ctx = c
            c.bus:on(LI.NAME, "PLAYER_ENTERING_WORLD", function(isInitial, isReload)
                local R = ns.Reveal
                local arrow = nil
                if type(R) == "table" and type(R.Open) == "function" then arrow = R.Open(k, "arrow") end
                local show = LI.ShouldShow({ on = c.settings:get(LI.SETTING) ~= false, initial = isInitial == true,
                    reload = isReload == true, shownBefore = shownBefore, arrowShown = arrow })
                shownBefore = true
                if show then api.Play() end
            end)
        end,
        stop = function() ctx = nil end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[LI.WORD] = function(rest)
            if not ctx then return end
            local text = tostring(rest or ""):lower()
            local word, more = text:match("^%s*(%S*)%s*(%S*)")
            local function say(line) ctx.client.print(ns.id.title .. ": " .. line) end
            if word == "on" or word == "off" then
                ctx.settings:set(LI.SETTING, word == "on")
                say("login intro " .. word .. ".")
            elseif word == "short" then
                local v = ctx.settings:get(LI.SHORT) ~= true
                if more == "on" or more == "off" then v = more == "on" end
                ctx.settings:set(LI.SHORT, v)
                local state = "off"
                if v then state = "on" end
                say("intro, the short one: " .. state .. ".")
            else
                api.Play()
            end
        end
        if type(diag.help) == "table" then diag.help[LI.WORD] = LI.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.loginIntro = LI.Declare(ns, ns.diag)
