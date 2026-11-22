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
--   Intro.Lines(id) -> lines        the text, top to bottom, naming the
--                                   addon and slash word from id (ns.id)
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

-- Declares the module on kernel k and adds the word to diag's commands
-- (when diag has them).
function Intro.Declare(k, diag)
    local api = {}
    local shows = 0
    local panel, ctx
    function api.shows() return shows end

    local function show()
        if not ctx then return end
        shows = shows + 1
        local id = k.id or ns.id
        local lines = Intro.Lines(id)
        if panel then
            panel.setLines(lines)
            panel.show(true)
            return
        end
        for i = 1, #lines do ctx.client.print(id.title .. ": " .. lines[i]) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Intro.WORD] = function() show() end
    end

    k:Module({
        name = Intro.NAME,
        needs = { "client", "store", "settings" },
        provides = { Shows = api.shows },
        start = function(c)
            ctx = c
            -- The frame last, after everything that can switch the module off.
            local id = k.id or ns.id
            panel = c.client.panel({ name = id.framePrefix .. "Intro",
                width = Intro.WIDTH, height = Intro.HEIGHT, closable = true })
            if panel then
                panel.show(false)
                panel.place(Intro.DEFAULT_POINT)
                -- Shown at login only when the player can close it: a client
                -- without the close route (h.onClose) would leave a panel
                -- that comes back at every login. /zflow intro still shows it.
                if type(panel.onClose) == "function" then
                    panel.onClose(function() c.store:set("char", Intro.SEEN_PATH, true) end)
                    -- Off only when the player turned it off; a missing row is on.
                    if c.store:get("char", Intro.SEEN_PATH) ~= true and c.settings:get(Intro.SETTING) ~= false then
                        show()
                    end
                end
            end
        end,
        stop = function()
            if panel then panel.show(false) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.intro = Intro.Declare(ns, ns.diag)
