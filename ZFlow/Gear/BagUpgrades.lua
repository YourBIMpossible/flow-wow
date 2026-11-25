local _, ns = ...

-- Bag upgrades as advice (parity rows C-30 and C-31): the items in your
-- bags that are an upgrade you can wear now for the role you chose, as
-- advisor prompts ("Equip <item> from your bags: ...") and as the word
-- `<slash> gear check`. ADVICE AND DISPLAY ONLY: nothing here equips,
-- uses, sells, moves or binds an item; no button, key or secure frame is
-- made. The player reads the line and equips the item themselves.
-- Legacy Flow: Modules/Advisor/Builtins.lua lines 221-233 (the prompt) and
-- Modules/Gear/Score.lua lines 461-497 (the gear word).
--
-- The judgement is the one the bag badge already uses (Gear/BagBadge.lua
-- letters): Gear/Verdict.lua's answer for the item, an upgrade when you
-- can use it (the game's own marks, your level, the weapon skills you
-- know) and the gain is at least GearTooltip.SAME. No second scorer.
--
--   rows, why = GearBagUpgrades.Rows(stacks, judge, role)      pure
--   rows, why = GearBagUpgrades.Check(client, packs, role)     reads the client
--   text      = GearBagUpgrades.Text(row)
--   lines     = GearBagUpgrades.Lines(rows, why, id)           the word's lines
--   api       = GearBagUpgrades.Declare(k[, packs[, diag]])
--     api.shown()    the prompt ids shown now, best first
--     api.errors()   how many checks could not be worked out
--   ns.use(GearBagUpgrades.NAME) -> { Shown = api.shown, Errors = api.errors }
--
--   stacks  client.bagItems()'s rows { item, count }; not a table: the bags
--           were not read
--   judge   function(link) -> Gear/Verdict.lua's detail for that item and
--           role ({ result, use, weights }), or nil when the item was not
--           read or is not gear that is compared
--   role    the role chosen (spec.role); "" or nil: none chosen
--   rows    best first (equal gains in bag order, each link once):
--           { item, slot, what, role, gain, guess, evidence, empty, pair, at }
--             slot, what  the slot it was held up to, and in words
--             gain        the item's score minus what it would replace
--             guess       true unless the pack's weights for the role carry
--                         an evidence label other than "first guess"
--             empty       the slot is known to be empty
--           nil when the whole check cannot run, with why, one of
--           GearBagUpgrades.REASON: the bags not read, no role chosen, no
--           weights for the role, or every piece you could wear met a worn
--           slot that was not read. {} is "checked, and none".
-- Unknown never becomes an upgrade: an item not read, a worn slot not read,
-- a level or skill not known, or weights not known gives no row.
--
-- The prompts: one per row, at most MAX, ids ID .. the item's link, so a
-- prompt goes when its item leaves the bags, is worn, or stops being an
-- upgrade, and one that stays is not a new prompt. Worked out again on
-- PLAYER_ENTERING_WORLD, BAG_UPDATE_DELAYED, PLAYER_EQUIPMENT_CHANGED and
-- PLAYER_LEVEL_UP, through the bus (as the bag badge); never per frame.
-- A check that raises shows no prompt, is counted, and is kept as one
-- "gear" problem per distinct error.
--
-- Setting gear.bagAdvice (bool, account, on by default, as Flow had it):
-- "Advise upgrades in your bags". A change made on the settings page is
-- seen at the next of the events above; `gear on` and `gear off` at once.
--
-- The word (with diag): `gear check` lists the rows, `gear on` and
-- `gear off` switch the setting, the bare word says how. Every other
-- sub-word goes to the gear word that was there before
-- (Gear/TooltipModule.lua's `gear why`), as it was given.
--
-- Not tested in game.

local U = {}
ns.GearBagUpgrades = U

U.NAME = "gearBagUpgrades"
U.SETTING = "gear.bagAdvice"
U.ROLE = "spec.role"              -- Rotation/Role.lua's setting
U.ROLE_WORD = "role"              -- and its word
U.KEEP = "gear.keepOffspec"       -- Gear/OffSpec.lua's setting, named in the usage
U.KEEP_LABEL = "Keep gear for your other roles"   -- its label, when the row is not there to ask
U.ID = "gear.bag."                -- prompt ids: this and the item's link
U.MAX = 3
U.PRIORITY = 1
U.WORD = "gear"
U.LIST_CAP = 20
U.GUESS = "first guess"           -- the class packs' label for weights not checked
U.GUESS_NOTE = "first-guess weights"
U.NONE = "No upgrades in your bags."
U.CANNOT = "Bag upgrades cannot be checked: "
U.ON = "Bag upgrade advice is on."
U.OFF = "Bag upgrade advice is off."
U.HELP = "check: the upgrades in your bags you can wear now, for your role; on, off: the advice about them; "
    .. "why: each piece of gear in your bags with its verdict and score. It equips nothing."

U.REASON = {
    bags = "your bags could not be read",
    role = "choose a role",
    weights = "no stat weights are known for that role",
    worn = "what you wear was not read",
}
local R = U.REASON

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- One read of the client; nil when it has no such read.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The role to check for: the chosen one, else the levelling role (dps), as
-- Flow's ns:LevelingRole (Gear/Verdict.lua GearRole.Active).
local function active(role)
    local G = ns.GearRole
    if type(G) == "table" and type(G.Active) == "function" then return (G.Active(role)) end
    return role
end

local function chosen(role)
    return type(role) == "string" and role ~= ""
end

local function startsWith(text, head)
    return type(text) == "string" and text:sub(1, #head) == head
end

-- A gain with its sign: whole, or to one decimal place ("+7", "+7.3").
local function signed(n)
    local rounded = math.floor(math.abs(n) * 10 + 0.5) / 10
    local text
    if rounded == math.floor(rounded) then
        text = string.format("%d", rounded)
    else
        text = string.format("%.1f", rounded)
    end
    if n < 0 then return "-" .. text end
    return "+" .. text
end

function U.Rows(stacks, judge, role)
    if type(stacks) ~= "table" then return nil, R.bags end
    if not chosen(role) then return nil, R.role end
    if type(judge) ~= "function" then return nil, R.weights end
    local S = ns.GearScore.REASON
    local rows, seen = {}, {}
    local usable, unread, unweighted = 0, 0, 0
    for i = 1, #stacks do
        local link = nil
        if type(stacks[i]) == "table" then link = stacks[i].item end
        if type(link) == "string" and link ~= "" and not seen[link] then
            seen[link] = true
            local detail = judge(link)
            local use, res = nil, nil
            if type(detail) == "table" then use, res = detail.use, detail.result end
            if type(use) == "table" and use.can == true and type(res) == "table" then
                usable = usable + 1
                if res.verdict == "upgrade" and finite(res.delta) and res.delta >= ns.GearTooltip.SAME then
                    local evidence = nil
                    if type(detail.weights) == "string" and detail.weights ~= "" then evidence = detail.weights end
                    rows[#rows + 1] = {
                        item = link, slot = res.slot, what = ns.GearTooltip.What(res), role = role,
                        gain = res.delta, guess = evidence == nil or evidence == U.GUESS, evidence = evidence,
                        empty = res.empty == true, pair = res.pair == true, at = #rows + 1,
                    }
                elseif startsWith(res.reason, S.worn) or startsWith(res.reason, S.wornStat) then
                    unread = unread + 1
                elseif res.reason == S.weights then
                    unweighted = unweighted + 1
                end
            end
        end
    end
    -- Nothing found, and nothing could have been: say which read is missing.
    if #rows == 0 and usable > 0 then
        if unweighted == usable then return nil, R.weights end
        if unread == usable then return nil, R.worn end
    end
    table.sort(rows, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.at < b.at
    end)
    return rows
end

function U.Check(client, packs, role)
    local okBags, stacks = pcall(ask, client, "bagItems")
    if not okBags or type(stacks) ~= "table" then return nil, R.bags end
    if not chosen(role) then return nil, R.role end
    local class = ask(client, "class")
    local pack = nil
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    if type(pack) ~= "table" or type(pack.weights) ~= "table" or type(pack.weights[role]) ~= "table" then
        return nil, R.weights
    end
    local level = ask(client, "level")
    local skills = nil
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end
    -- One item's read raising is that item not read: no row for it.
    local function judge(link)
        local okGear, gear = pcall(ask, client, "gear", link)
        if not okGear or type(gear) ~= "table" then return nil end
        local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = role, level = level,
                                                           skills = skills })
        if lines == nil then return nil end
        return detail
    end
    return U.Rows(stacks, judge, role)
end

-- One row as the player reads it. Words only.
function U.Text(row)
    local what = tostring(row.what)
    local text = "Equip " .. tostring(row.item) .. " from your bags: " .. signed(row.gain)
        .. " for " .. tostring(row.role)
    if row.empty == true then
        text = text .. " over nothing worn (" .. what .. ")"
    else
        text = text .. " over " .. what
    end
    -- Weights that are a first guess: said, and never called a sure thing.
    if row.guess then text = text .. " (" .. U.GUESS_NOTE .. ")" end
    return text
end

local function slashOf(id)
    if type(id) == "table" and type(id.slash) == "string" then return id.slash end
    return ""
end

-- The `gear check` lines: the reason, that there are none, or the rows.
function U.Lines(rows, why, id)
    if type(rows) ~= "table" then
        local text = U.CANNOT .. tostring(why or R.bags)
        if why == R.role then text = text .. " (say " .. slashOf(id) .. " " .. U.ROLE_WORD .. ")" end
        return { text .. "." }
    end
    if #rows == 0 then return { U.NONE } end
    local out = { "Upgrades in your bags, for " .. tostring(rows[1].role) .. ":" }
    for i = 1, math.min(#rows, U.LIST_CAP) do out[#out + 1] = U.Text(rows[i]) end
    if #rows > U.LIST_CAP then out[#out + 1] = "and " .. (#rows - U.LIST_CAP) .. " more" end
    return out
end

-- The bare word: every sub-word, and where keeping off-spec gear is set.
function U.Usage(k)
    local say = slashOf(k.id) .. " " .. U.WORD
    local label = U.KEEP_LABEL
    if type(k.settings) == "table" and type(k.settings.row) == "function" then
        local row = k.settings:row(U.KEEP)
        if type(row) == "table" and type(row.label) == "string" then label = row.label end
    end
    return "Say " .. say .. " check for the upgrades in your bags, " .. say .. " on or " .. say
        .. " off for the advice about them, " .. say .. " why for every piece with its verdict and score. "
        .. "Gear for other roles is its own setting: " .. label .. "."
end

function U.Declare(k, packs, diag)
    local api = {}
    local ctx, shown, errors, seen = nil, {}, 0, {}
    function api.shown()
        local out = {}
        for i = 1, #shown do out[i] = shown[i] end
        return out
    end
    function api.errors() return errors end

    local function problem(what, text)
        errors = errors + 1
        text = tostring(text)
        if not seen[text] then
            seen[text] = true
            if type(k.problems) == "table" then k.problems:add("gear", what, text) end
        end
    end

    local function clear(advisor)
        for i = 1, #shown do
            if type(advisor) == "table" then advisor.Remove(shown[i]) end
        end
        shown = {}
    end

    -- The prompts as they should be now. Called on the events below and by
    -- the on and off words; never per frame.
    local function update()
        if not ctx then return end
        local advisor = ctx.use("advisor")
        if type(advisor) ~= "table" then return end
        if ctx.settings:get(U.SETTING) ~= true then return clear(advisor) end
        local ok, rows = pcall(U.Check, ctx.client, packs or ns.Packs, active(ctx.settings:get(U.ROLE)))
        if not ok then
            problem("bag upgrades", rows)
            return clear(advisor)
        end
        -- The check could not run (rows is nil): not known is no advice.
        if type(rows) ~= "table" then return clear(advisor) end
        local want, texts, keep = {}, {}, {}
        for i = 1, math.min(#rows, U.MAX) do
            local id = U.ID .. rows[i].item
            want[i], texts[i], keep[id] = id, U.Text(rows[i]), true
        end
        for i = 1, #shown do
            if not keep[shown[i]] then advisor.Remove(shown[i]) end
        end
        -- Best first: a little more priority the better the row. An id
        -- already there has its text and place replaced, not added again.
        local now = {}
        for i = 1, #want do
            if advisor.Add(want[i], texts[i], U.PRIORITY + (U.MAX - i) / 100) then now[#now + 1] = want[i] end
        end
        shown = now
    end
    api.refresh = update

    local function say(lines)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
    end

    local before = nil
    local function run(rest)
        local word = tostring(rest or ""):lower():match("^%s*(%S*)")
        if word == "check" then
            local role = nil
            if type(k.settings) == "table" then role = k.settings:get(U.ROLE) end
            local ok, rows, why = pcall(U.Check, k.client, packs or ns.Packs, active(role))
            if not ok then
                problem("check", rows)
                say({ "The bag upgrade check failed: " .. tostring(rows) })
            else
                say(U.Lines(rows, why, k.id))
            end
        elseif word == "on" or word == "off" then
            local on = word == "on"
            local set = type(k.settings) == "table" and k.settings:set(U.SETTING, on) == true
            if not set then
                say({ "The bag upgrade advice setting could not be changed." })
            else
                update()
                if on then say({ U.ON }) else say({ U.OFF }) end
            end
        elseif word ~= "" and type(before) == "function" then
            return before(rest)
        else
            say({ U.Usage(k) })
        end
        return false
    end
    api.run = run
    if diag and type(diag.commands) == "table" then
        before = diag.commands[U.WORD]
        diag.commands[U.WORD] = run
        if type(diag.help) == "table" then diag.help[U.WORD] = U.HELP end
    end

    k:Module({
        name = U.NAME,
        needs = { "client", "settings", "bus", "advisor" },
        settings = { {
            key = U.SETTING, scope = "account", type = "bool", default = true,
            label = "Advise upgrades in your bags",
            help = "An item in your bags that is an upgrade you can wear now, for the role you chose, is "
                .. "named on the advice panel. It equips nothing.",
            group = "gear", synonyms = { "bag", "upgrade", "equip", "advice", "role" },
        } },
        provides = { Shown = api.shown, Errors = api.errors },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
                                     "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
                c.bus:on(U.NAME, event, update)
            end
            update()
        end,
        stop = function()
            local advisor = nil
            if type(k.use) == "function" then advisor = k.use("advisor") end
            clear(advisor)
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearBagUpgrades = U.Declare(ns, nil, ns.diag)
