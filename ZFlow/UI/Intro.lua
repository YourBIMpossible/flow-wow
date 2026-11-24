-- First-run intro (U-D, G55): on a character's first login with Z-Flow, a
-- panel says in plain words what Z-Flow shows and names /zflow help.
--
-- Shown once. Its close button or Escape hides it, and from then on it is
-- not shown at login again: the character is marked at Intro.SEEN_PATH
-- (Z-Flow's own saved state). A reload before closing shows it again at
-- the next login. `/zflow intro` shows it again at any time.
--
-- LOOK ONLY, and it changes no setting. The one write is the seen mark.
--
-- Drawn by the shared kit (UI/Kit.lua; lead sections 297 item 5 and 322
-- line 6): one window, the welcome as its header, the rest as kit lines
-- (Intro.View). A kit line stays on one line, so each sentence is cut at
-- word ends (Intro.Wrap). When the kit or the client refuses the window,
-- the plain panel shows Intro.Lines as before (UI/KitHost.lua).
--
--   Intro.Lines(id) -> lines        the text, top to bottom, naming the
--                                   addon and slash word from id (ns.id)
--   Intro.View(id) -> view          the same words as a kit window spec
--   Intro.Wrap(text, n) -> lines    text cut at word ends, each line at
--                                   most n letters (a longer word stands
--                                   alone, uncut)
--   Intro.Declare(k, diag) -> api   declares the module on kernel k and adds
--                                   the word "intro" to diag.commands
--     api.shows()   how many times it was shown since the start
--   ns.use(Intro.NAME) -> { Shows = api.shows }
--
-- Setting: "ui.intro" (bool, char, on by default). The row is the lead's to
-- add to the settings model; until it is there, it is on. Off: not shown at
-- login. /zflow intro still shows it, since the player asked for it.
--
-- Reads (through the injected client):
--   client.panel(spec) with spec.closable = true   CLIENT NEED: a close
--       button on the panel, and the Escape route (the panel's global name
--       put in UISpecialFrames, as the arrow menu does), with
--       h.onClose(fn): fn() when the player closes it by the button or
--       Escape; not called for h.show(false).
--   client.kitWindow, through UI/KitHost.lua: the kit window has its own
--       close button and Escape route
--   client.print(text)   when the client cannot make the panel
local _, ns = ...

local Intro = ns.Intro or {}
ns.Intro = Intro

Intro.NAME = "intro"
Intro.WORD = "intro"
Intro.SETTING = "ui.intro"
Intro.SEEN_PATH = "state.intro.seen"
Intro.WIDTH, Intro.HEIGHT = 420, 150
Intro.DEFAULT_POINT = { "CENTER", "CENTER", 0, 120 }
-- The kit window. Its size and the letters a line holds are a first
-- guess: not seen in game.
Intro.KIT_ID = "Intro"
Intro.KIT_WIDTH, Intro.KIT_HEIGHT = 480, 300
Intro.WRAP = 68

-- The text, top to bottom. The addon's name and slash word come from the
-- identity (Core/Identity.lua is the only file that may hold them).
function Intro.Lines(id)
    id = type(id) == "table" and id or ns.id
    local name, slash = tostring(id.title), tostring(id.slash)
    return {
        "Welcome to " .. name .. ".",
        "The arrow points to your next quest step, and a second arrow points to your next profession step. Right-click an arrow for its menu.",
        "At a merchant, a list shows what " .. name .. " would sell, what it keeps, and why. " .. name .. " sells nothing by itself.",
        "Hover a piece of gear: a line in its tooltip gives " .. name .. "'s verdict on it for you.",
        "Type " .. slash .. " help to see every command, and " .. slash .. " " .. Intro.WORD .. " to read this again.",
    }
end

-- Text cut at word ends into lines of at most n letters. A word longer
-- than n stands alone, uncut. No words, or no text: no line.
function Intro.Wrap(text, n)
    local out = {}
    if type(text) ~= "string" then return out end
    local fits = type(n) == "number" and n == n and n >= 1
    local line
    for word in text:gmatch("%S+") do
        if line == nil then
            line = word
        elseif not fits or #line + 1 + #word <= n then
            line = line .. " " .. word
        else
            out[#out + 1] = line
            line = word
        end
    end
    if line ~= nil then out[#out + 1] = line end
    return out
end

-- The same words as a kit window spec (UI/Kit.lua): the welcome as the
-- header, then every other sentence as kit lines. Nothing in it can be
-- pressed but the window's own close; Escape closes it too.
function Intro.View(id)
    id = type(id) == "table" and id or ns.id
    local lines = Intro.Lines(id)
    local kids = { { kind = "header", title = lines[1] } }
    for i = 2, #lines do
        local cut = Intro.Wrap(lines[i], Intro.WRAP)
        for j = 1, #cut do
            kids[#kids + 1] = { kind = "line", key = "line" .. i .. "." .. j, text = cut[j] }
        end
    end
    local d = Intro.DEFAULT_POINT
    return { id = Intro.KIT_ID, title = tostring(id.title), children = kids,
        width = Intro.KIT_WIDTH, height = Intro.KIT_HEIGHT, point = { d[1], d[2], d[3], d[4] },
        closable = true, resizable = false }
end

-- Declares the module on kernel k and adds the word to diag's commands
-- (when diag has them).
function Intro.Declare(k, diag)
    local api = {}
    local shows = 0
    -- host: the kit window with the plain panel behind it (UI/KitHost.lua).
    local host, ctx
    function api.shows() return shows end

    local function show()
        if not ctx then return end
        shows = shows + 1
        local id = k.id or ns.id
        local lines = Intro.Lines(id)
        if host then
            host.draw(Intro.View(id), lines)
            host.show(true)
            return
        end
        for i = 1, #lines do ctx.client.print(id.title .. ": " .. lines[i]) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Intro.WORD] = function() show() end
        if type(diag.help) == "table" then diag.help[Intro.WORD] = "show the introduction again" end
    end

    k:Module({
        name = Intro.NAME,
        needs = { "client", "store", "settings" },
        provides = { Shows = api.shows },
        start = function(c)
            ctx = c
            -- The frame last, after everything that can switch the module off.
            local id = k.id or ns.id
            local panel = c.client.panel({ name = id.framePrefix .. "Intro",
                width = Intro.WIDTH, height = Intro.HEIGHT, closable = true })
            -- A client that makes no plain panel draws nothing: no host,
            -- and the word prints the lines.
            if panel then
                panel.show(false)
                panel.place(Intro.DEFAULT_POINT)
                -- The plain panel as the host draws it: its lines, and
                -- whether it is shown (the client's panel does not say).
                local open = false
                local function seen()
                    c.store:set("char", Intro.SEEN_PATH, true)
                end
                host = ns.KitHost.New(k, c.client, {
                    name = id.framePrefix .. "IntroKit",
                    panel = {
                        draw = function(lines) panel.setLines(lines) end,
                        show = function(on)
                            open = on == true
                            panel.show(open)
                        end,
                        shown = function() return open end,
                    },
                    onClose = seen,
                })
                local closable = type(panel.onClose) == "function"
                if closable then
                    panel.onClose(function()
                        open = false
                        seen()
                    end)
                end
                do
                    -- Off only when the player turned it off; a missing row is on.
                    -- G55 (legacy Splash.lua:211): a new player's first
                    -- login has no intro while the arrow has not come in;
                    -- it shows at a later login. The word still shows it.
                    local R = ns.Reveal
                    local waits = type(R) == "table" and type(R.Open) == "function" and R.Open(k, "arrow") == false
                    if c.store:get("char", Intro.SEEN_PATH) ~= true and c.settings:get(Intro.SETTING) ~= false
                        and not waits then
                        -- Drawn first: that says whether the kit window
                        -- (which has its own close) or the plain panel
                        -- stands. Shown at login only when the player can
                        -- close it: a plain panel without the close route
                        -- (h.onClose) would come back at every login.
                        -- /zflow intro still shows it.
                        host.draw(Intro.View(id), Intro.Lines(id))
                        if not host.plain() or closable then show() end
                    end
                end
            end
        end,
        stop = function()
            if host then host.show(false) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.intro = Intro.Declare(ns, ns.diag)
