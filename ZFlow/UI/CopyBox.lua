-- Copy box (L6-K, S24): a small text box holding what the addon last said
-- in chat, so the output of `<slash> diag` can be selected and copied.
--
--   <slash> copy        the last thing said (the lines of one command)
--   <slash> copy all    everything kept (the last CopyBox.MAX lines)
--
-- It replaces nothing: every line still goes to chat as before. The box
-- only listens to the addon's own print (client.onPrint) and keeps the
-- lines in memory; nothing is saved and nothing in the game is touched.
--
-- "The last thing said" is the last run: the lines printed at one moment
-- of the client's time, which is what one command prints. So run
-- `<slash> diag`, then `<slash> copy`. The box's own messages are never
-- recorded, so a failed try does not replace what it holds.
--
--   log = CopyBox.Log(max)        log.add(text, at), log.last(), log.all()
--   CopyBox.Start(k, diag) -> { last = fn, all = fn, run = fn }
--
-- CLIENT NEEDs (the lead adds them to Core/Client.lua):
--   client.onPrint(fn) -> cancel    fn(text) for every line client.print says
--   client.copyBox(spec) -> handle  a frame with a selectable, scrolling,
--                                   read-only multi-line text; nil when the
--                                   client cannot draw one
--     spec   { name, width, height, title }
--     handle { setText(text), show(on) }
-- Diag (Core/Diag.lua) is not changed: only its commands table is used.
local _, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

CopyBox.WORD = "copy"
CopyBox.MAX = 200
CopyBox.WIDTH, CopyBox.HEIGHT = 520, 320
CopyBox.NOTHING = "nothing to copy yet. Run a command first, then copy."
CopyBox.NO_FEED = "this client gives no print feed, so there is nothing to copy."
CopyBox.NO_BOX = "this client cannot draw the copy box."

-- The lines kept, oldest first, each with the run it belongs to.
function CopyBox.Log(max)
    max = type(max) == "number" and max >= 1 and math.floor(max) or CopyBox.MAX
    local log = {}
    local lines, run, lastAt = {}, 0, nil

    function log.add(text, at)
        if type(text) ~= "string" or text == "" then return end
        if type(at) ~= "number" or at ~= at then at = nil end
        -- A new run when the time is known and is not the last line's time.
        if #lines == 0 or (at ~= nil and at ~= lastAt) then run = run + 1 end
        lastAt = at
        lines[#lines + 1] = { text = text, run = run }
        while #lines > max do table.remove(lines, 1) end
    end

    function log.last()
        local out = {}
        if #lines == 0 then return out end
        local want = lines[#lines].run
        for i = 1, #lines do
            if lines[i].run == want then out[#out + 1] = lines[i].text end
        end
        return out
    end

    function log.all()
        local out = {}
        for i = 1, #lines do out[i] = lines[i].text end
        return out
    end

    return log
end

function CopyBox.Start(k, diag)
    local client = k.client
    local log = CopyBox.Log(CopyBox.MAX)
    local fed, quiet, box = false, false, nil

    if type(client.onPrint) == "function" then
        fed = true
        client.onPrint(function(text)
            if quiet then return end
            local at
            if type(client.uptime) == "function" then at = client.uptime() end
            log.add(text, at)
        end)
    end

    -- The box's own lines: said in chat, never recorded.
    local function say(text)
        quiet = true
        local ok, err = pcall(client.print, k.id.title .. ": " .. text)
        quiet = false
        if not ok then error(err, 0) end
    end

    local function run(rest)
        if not fed then return say(CopyBox.NO_FEED) end
        local lines = tostring(rest or ""):find("all", 1, true) and log.all() or log.last()
        if #lines == 0 then return say(CopyBox.NOTHING) end
        if not box and type(client.copyBox) == "function" then
            box = client.copyBox({ name = k.id.framePrefix .. "CopyBox", width = CopyBox.WIDTH,
                height = CopyBox.HEIGHT, title = k.id.title .. ": select, then copy" })
        end
        if not box then return say(CopyBox.NO_BOX) end
        box.setText(table.concat(lines, "\n"))
        box.show(true)
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[CopyBox.WORD] = run
    end
    return { last = log.last, all = log.all, run = run }
end

-- The addon's own: listening from the moment this file loads.
ns.copyBox = CopyBox.Start(ns, ns.diag)
