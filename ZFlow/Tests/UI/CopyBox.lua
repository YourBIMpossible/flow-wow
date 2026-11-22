local _, ns = ...

-- Tests for ZFlow/UI/CopyBox.lua (L6-K, S24): a text box holding what the
-- addon last said in chat (the last `<slash> diag` output), so it can be
-- selected and copied. It replaces nothing: chat is printed as before.
--
-- Two CLIENT NEEDs the lead adds to Core/Client.lua and Core/ClientFake.lua:
-- client.onPrint(fn) and client.copyBox(spec). Until the fake has them these
-- tests put both on the fake directly, in the same shape.

local B = ns.CopyBox
local tests = {}

-- ------------------------------------------------------------------ the log

tests["copy log: lines said at one moment are one run"] = function(t)
    local log = B.Log(10)
    log.add("a", 1)
    log.add("b", 1)
    log.add("c", 2)
    t.eq(log.last(), { "c" }, "the last run")
    t.eq(log.all(), { "a", "b", "c" }, "everything kept, oldest first")
end

tests["copy log: with no time, lines join the run before them"] = function(t)
    local log = B.Log(10)
    log.add("a", nil)
    log.add("b", nil)
    t.eq(log.last(), { "a", "b" })
    log.add("c", 5)
    t.eq(log.last(), { "c" }, "a known time after an unknown one starts a run")
end

tests["copy log: it keeps only so many lines, the newest"] = function(t)
    local log = B.Log(3)
    for i = 1, 5 do log.add("line " .. i, i) end
    t.eq(log.all(), { "line 3", "line 4", "line 5" })
    t.eq(B.MAX, 200, "the addon's own limit")
    t.eq(B.Log(3).last(), {}, "nothing said yet: an empty run")
end

tests["copy log: only text is kept"] = function(t)
    local log = B.Log(10)
    log.add(nil, 1)
    log.add(5, 1)
    log.add("", 1)
    t.eq(log.all(), {}, "nothing that is not a line of text")
end

-- ------------------------------------------------------------------ the box

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local boxes = {}
    if opts.onPrint ~= false and type(c.onPrint) ~= "function" then
        local fns, real = {}, c.print
        c.print = function(text)
            real(text)
            for i = 1, #fns do fns[i](tostring(text)) end
        end
        c.onPrint = function(fn) fns[#fns + 1] = fn return function() end end
    end
    if opts.box ~= false and type(c.copyBox) ~= "function" then
        c.copyBox = function(spec)
            local h = { spec = spec, text = "", shown = false }
            function h.setText(text) h.text = tostring(text) end
            function h.show(on) h.shown = on and true or false end
            boxes[#boxes + 1] = h
            return h
        end
    end
    if opts.onPrint == false then c.onPrint = nil end
    if opts.box == false then c.copyBox = nil end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    local api = B.Start(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    return k, c, diag, boxes, api
end

tests["copy box: the word is added to the slash command"] = function(t)
    local _, _, diag = start()
    t.eq(B.WORD, "copy")
    t.ok(type(diag.commands[B.WORD]) == "function")
end

tests["copy box: it shows what was last said, ready to select"] = function(t)
    local _, c, diag, boxes = start()
    c.advance(1)
    c.print("Z: first line")
    c.print("Z: second line")
    diag.commands[B.WORD]("")
    t.eq(#boxes, 1, "one box made")
    t.eq(boxes[1].text, "Z: first line\nZ: second line")
    t.eq(boxes[1].shown, true)
    t.eq(boxes[1].spec.name, ns.id.framePrefix .. "CopyBox")
end

tests["copy box: only the last thing said, unless all is asked for"] = function(t)
    local _, c, diag, boxes = start()
    c.advance(1)
    c.print("old")
    c.advance(1)
    c.print("new 1")
    c.print("new 2")
    diag.commands[B.WORD]("")
    t.eq(boxes[1].text, "new 1\nnew 2")
    diag.commands[B.WORD]("all")
    t.ok(boxes[1].text:find("old\nnew 1\nnew 2", 1, true) ~= nil, "all: everything kept")
    t.eq(#boxes, 1, "the same box is used again")
end

tests["copy box: its own messages never replace what it holds"] = function(t)
    local _, c, diag, boxes = start({ box = false })
    c.advance(1)
    c.print("the diag line")
    c.advance(1)
    diag.commands[B.WORD]("")
    t.eq(#boxes, 0)
    t.eq(c.printed[#c.printed], ns.id.title .. ": " .. B.NO_BOX, "said in chat that no box can be drawn")
    t.eq(ns.copyBox ~= nil, true)
    local _, _, _, _, api = start()
    t.eq(api.last(), {}, "a fresh one holds nothing")
end

tests["copy box: after a failed try, the earlier output is still what it holds"] = function(t)
    local _, c, diag, _, api = start({ box = false })
    c.advance(1)
    c.print("the diag line")
    c.advance(1)
    diag.commands[B.WORD]("")
    t.eq(api.last(), { "the diag line" }, "its own 'cannot draw' line was not recorded")
end

tests["copy box: nothing said yet, or no print feed, is said plainly"] = function(t)
    local _, c, diag, boxes = start()
    diag.commands[B.WORD]("")
    t.eq(#boxes, 0, "no empty box")
    t.eq(c.printed[#c.printed], ns.id.title .. ": " .. B.NOTHING)
    local _, c2, diag2 = start({ onPrint = false })
    c2.print("something")
    diag2.commands[B.WORD]("")
    t.eq(c2.printed[#c2.printed], ns.id.title .. ": " .. B.NO_FEED)
end

tests["copy box: chat is still printed as before"] = function(t)
    local _, c = start()
    local before = #c.printed
    c.print("a line")
    t.eq(#c.printed, before + 1, "the line still goes to chat")
    t.eq(c.printed[#c.printed], "a line", "unchanged")
end

return tests
