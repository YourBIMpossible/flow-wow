local _, ns = ...

-- The macro icon search (N72, lead section 248 item 4): a search box on the
-- game's own icon window of the macro editor. It finds icons by spell or
-- item name where the client maps a name to an icon (the player's
-- spellbook, the items in the bags; no bundled list of icons), and by the
-- file name of an icon where the client gives one. All, Spells and Items
-- filters. Matches are shown in the window's own grid, so a click selects
-- through the normal editor; clearing the box shows every icon again. The
-- index is built on first use of the box after the window opens, a slice a
-- frame, and the search runs a slice a frame with its new matches capped
-- per frame, so typing stays responsive. It never makes or edits a macro.
--
-- The hook pattern (an icon window, its data provider, a box above the
-- grid) is that of the add-on LargerMacroIconSelection, GPL-3; the pattern
-- only, reused under its notice. No code and no data copied.
--
-- Pure parts:
--   MI.Norm(s) -> the words typed, lower case, trimmed ("" for a non-string)
--   MI.FileName(icon) -> the lower-case file name of an icon named by path,
--       no folder and no extension; nil for a file number
--   MI.Matcher(query, filter, rows, files) -> job; job.out the icons found
--   MI.Step(job, cap, slice) -> true once every candidate was looked at
--   MI.Runner(phases) / MI.Run(run, slice) -> true once every phase ran
--   MI.NewIndex() / MI.AddRow(index, name, kind, icon) / MI.AddFile(index, icon)
--   MI.Hint(n, done) -> the words under the box
--
-- The module: one setting row, account wide, on by default:
--   macroIcons.search   "Search box on the macro icon window"
-- The box is added once the macro window has loaded (Blizzard_MacroUI is
-- load on demand) and the client names everything the hook needs
-- (client.macroPopup). A missing name: no box, and diag says which.
-- ns.use(MI.NAME) -> { Status = fn } for diag. Not tested in game.

local MI = {}
ns.MacroIcons = MI

MI.NAME = "macroIcons"
MI.SETTING = "macroIcons.search"
MI.FILTERS = { "all", "spells", "items" }
MI.SLICE = 200
MI.CAP = 50
MI.LABEL = "Search icons"
MI.MACRO_UI = "Blizzard_MacroUI"

local KIND_OF = { spells = "spell", items = "item" }

function MI.Norm(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

function MI.FileName(icon)
    if type(icon) ~= "string" or icon == "" then return nil end
    local last = icon:match("([^/\\]+)$")
    if not last or last == "" then return nil end
    last = last:gsub("%.[^.]*$", "")
    if last == "" then return nil end
    return last:lower()
end

local function words(query)
    local out = {}
    for w in MI.Norm(query):gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function hasAll(text, list)
    if type(text) ~= "string" then return false end
    for i = 1, #list do
        if not text:find(list[i], 1, true) then return false end
    end
    return true
end

function MI.Matcher(query, filter, rows, files)
    local kind = KIND_OF[filter]
    rows = type(rows) == "table" and rows or {}
    files = (kind == nil and type(files) == "table") and files or {}
    return {
        words = words(query), kind = kind, rows = rows, files = files,
        pos = 1, total = #rows + #files, out = {}, seen = {},
    }
end

-- The name of a candidate to match against, and its icon.
local function candidate(job, i)
    if i <= #job.rows then
        local r = job.rows[i]
        if type(r) ~= "table" then return nil end
        if job.kind ~= nil and r.kind ~= job.kind then return nil end
        local name = r.lname
        if name == nil and type(r.name) == "string" then name = r.name:lower() end
        return name, r.icon
    end
    local f = job.files[i - #job.rows]
    if type(f) ~= "table" then return nil end
    return f.file, f.icon
end

function MI.Step(job, cap, slice)
    if type(job) ~= "table" then return true end
    if #job.words == 0 then
        job.pos = job.total + 1
        return true
    end
    local added, scanned = 0, 0
    while job.pos <= job.total and scanned < slice and added < cap do
        local text, icon = candidate(job, job.pos)
        job.pos = job.pos + 1
        scanned = scanned + 1
        if icon ~= nil and not job.seen[icon] and hasAll(text, job.words) then
            job.seen[icon] = true
            job.out[#job.out + 1] = icon
            added = added + 1
        end
    end
    return job.pos > job.total
end

function MI.Runner(phases)
    return { phases = type(phases) == "table" and phases or {}, p = 1, i = 0 }
end

-- Moves past phases that have nothing left; true when none is left.
local function spent(run)
    while true do
        local phase = run.phases[run.p]
        if phase == nil then return true end
        local n = type(phase.n) == "number" and phase.n or 0
        if run.i < n then return false end
        run.p, run.i = run.p + 1, 0
    end
end

function MI.Run(run, slice)
    local done = 0
    while done < slice do
        if spent(run) then return true end
        run.i = run.i + 1
        run.phases[run.p].fn(run.i)
        done = done + 1
    end
    return spent(run)
end

function MI.NewIndex()
    return { rows = {}, files = {}, seen = {}, seenFile = {} }
end

local function iconOk(icon)
    return (type(icon) == "number" and icon > 0) or (type(icon) == "string" and icon ~= "")
end

function MI.AddRow(index, name, kind, icon)
    if type(index) ~= "table" or type(name) ~= "string" or name == "" then return false end
    if kind ~= "spell" and kind ~= "item" then return false end
    if not iconOk(icon) then return false end
    local key = kind .. "\0" .. name .. "\0" .. tostring(icon)
    if index.seen[key] then return false end
    index.seen[key] = true
    index.rows[#index.rows + 1] = { name = name, lname = name:lower(), kind = kind, icon = icon }
    return true
end

function MI.AddFile(index, icon)
    if type(index) ~= "table" then return false end
    local file = MI.FileName(icon)
    if file == nil or index.seenFile[icon] then return false end
    index.seenFile[icon] = true
    index.files[#index.files + 1] = { file = file, icon = icon }
    return true
end

function MI.Hint(n, done)
    if not done then return "Searching..." end
    if n == 0 then return "No icon matches." end
    if n == 1 then return "1 match" end
    return tostring(n) .. " matches"
end

local function validFilter(kind)
    for i = 1, #MI.FILTERS do
        if MI.FILTERS[i] == kind then return kind end
    end
    return "all"
end

function MI.Declare(k)
    local api = {}
    local ctx
    local h, box, missing
    local index, build
    local query, filter = "", "all"
    local job, cancelTick
    local cancels = {}

    local function on()
        return ctx ~= nil and ctx.settings:get(MI.SETTING) == true
    end

    function api.status()
        if ctx == nil then return nil end
        if not on() then return "off." end
        if missing then return "not added: missing " .. table.concat(missing, ", ") .. "." end
        if not h then return "waiting for the macro window to load." end
        if not box then return "not added: the client made no search box." end
        if not index then return "added; index not built yet." end
        return "added; index of " .. #index.rows .. " names and " .. #index.files .. " file names."
    end

    local function stopTick()
        if cancelTick then cancelTick() end
        cancelTick, job = nil, nil
    end

    -- The reads, done in one frame of their own: the spellbook (a read that
    -- raises is one problem; the index then has no spells, and the next
    -- build reads again), the bags, and the icons the window lists.
    local function prepare()
        local idx = MI.NewIndex()
        local client = ctx.client
        local spells
        if type(client.spellbookIcons) == "function" then
            local ok, got = pcall(client.spellbookIcons)
            if not ok then
                k.problems:add("macro icons", "spellbook", tostring(got))
            elseif type(got) == "table" then
                spells = got
            end
        end
        spells = spells or {}
        local bags
        if type(client.bagItems) == "function" then
            local ok, got = pcall(client.bagItems)
            if ok and type(got) == "table" then bags = got end
        end
        bags = bags or {}
        local count = h.count()
        if type(count) ~= "number" then count = 0 end
        local run = MI.Runner({
            { n = #spells, fn = function(i)
                local r = spells[i]
                if type(r) == "table" then MI.AddRow(idx, r.name, "spell", r.icon) end
            end },
            { n = #bags, fn = function(i)
                local r = bags[i]
                if type(r) ~= "table" or r.item == nil then return end
                local okI, info = pcall(client.itemInfo, r.item)
                local okT, icon = pcall(client.itemTexture, r.item)
                if okI and okT and type(info) == "table" then MI.AddRow(idx, info.name, "item", icon) end
            end },
            { n = count, fn = function(i) MI.AddFile(idx, h.icon(i)) end },
        })
        build = { index = idx, run = run }
    end

    -- One frame of work: the reads, or a slice of the index, or a step of
    -- the search, then the next frame if anything is left.
    local function tick()
        cancelTick = nil
        if query == "" or not h or not box then return end
        if not index then
            if build == nil then
                prepare()
            elseif MI.Run(build.run, MI.SLICE) then
                index, build = build.index, nil
            end
            cancelTick = ctx.sched:nextFrame(MI.NAME, tick)
            return
        end
        if job == nil then job = MI.Matcher(query, filter, index.rows, index.files) end
        local done = MI.Step(job, MI.CAP, MI.SLICE)
        h.show(job.out)
        if done then
            box.hint(MI.Hint(#job.out, true))
            job = nil
        else
            cancelTick = ctx.sched:nextFrame(MI.NAME, tick)
        end
    end

    local function restart()
        stopTick()
        if query == "" then
            if box then box.hint("") end
            if h then h.show(nil) end
            return
        end
        box.hint(MI.Hint(0, false))
        cancelTick = ctx.sched:nextFrame(MI.NAME, tick)
    end

    local function onText(text)
        if not on() then return end
        query = MI.Norm(text)
        restart()
    end

    local function onFilter(kind)
        if not on() then return end
        filter = validFilter(kind)
        if query ~= "" then restart() end
    end

    local function addBox()
        if box or not h then return end
        box = h.addBox({ onText = onText, onFilter = onFilter, label = MI.LABEL })
    end

    -- The window closed: the next search reads again (new spells may be
    -- known), and the box is empty when it opens.
    local function onHide()
        stopTick()
        index, build, query = nil, nil, ""
        if box then
            box.setText("")
            box.hint("")
        end
        h.show(nil)
    end

    local function onShow()
        stopTick()
        index, build = nil, nil
    end

    local function attach()
        if h or ctx == nil then return end
        local ok, got, names = pcall(ctx.client.macroPopup)
        if not ok then
            k.problems:add("macro icons", "window", tostring(got))
            return
        end
        if type(got) ~= "table" then
            missing = type(names) == "table" and names or { "MacroPopupFrame" }
            return
        end
        missing, h = nil, got
        h.onShow(onShow)
        h.onHide(onHide)
        if on() then addBox() end
    end

    local function changed()
        if on() then
            if not box then addBox() end
            if box then
                box.show(true)
                box.setText("")
            end
            return
        end
        stopTick()
        query = ""
        if box then
            box.hint("")
            box.show(false)
        end
        if h then h.show(nil) end
    end

    k:Module({
        name = MI.NAME,
        needs = { "client", "store", "settings", "sched", "bus" },
        settings = { {
            key = MI.SETTING, scope = "account", type = "bool", default = true,
            label = "Search box on the macro icon window",
            help = "Adds a search box to the icon window of the macro editor: find an icon by spell or item "
                .. "name, or by its file name. It only filters the icons shown; a click still picks through the editor.",
            group = "general", synonyms = { "icon", "macro", "search" },
        } },
        provides = { Status = api.status },
        events = {
            ADDON_LOADED = function(_, name)
                if name == MI.MACRO_UI then attach() end
            end,
        },
        start = function(c)
            ctx = c
            local row = c.settings:row(MI.SETTING)
            if type(row) == "table" then
                local cancel = c.store:watch(row.scope, row.path or ("settings." .. MI.SETTING), changed)
                if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            local okL, loaded = pcall(c.client.addonLoaded, MI.MACRO_UI)
            if okL and loaded == true then attach() end
        end,
        stop = function()
            stopTick()
            for i = 1, #cancels do cancels[i]() end
            cancels = {}
            if h then pcall(h.show, nil) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.macroIcons = MI.Declare(ns)
