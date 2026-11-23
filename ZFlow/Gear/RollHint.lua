local _, ns = ...

-- The hint on a loot roll (S21): when the game offers you a roll on an item,
-- say whether it is an upgrade, by the same verdict the item tooltip gives,
-- and whether that means Need or Greed for the role you chose. Hint only:
-- it never rolls, passes or confirms anything. Legacy Flow's
-- Modules/Gear/RollHint.lua said the same on the roll window, in chat and
-- for `roll <item link>`.
--
--   hint   = GearRollHint.Hint(client, packs, link)
--   advice = GearRollHint.Advice(client, packs, link, role)
--   api    = GearRollHint.Declare(k[, packs[, diag]])
--     api.hooked()   true once the client's loot rolls are being followed
--     api.errors()   how many rolls could not be worked out
--     api.run(rest)  the roll word
--   ns.use(GearRollHint.NAME) -> { Hooked = api.hooked, Errors = api.errors }
--
-- Hint: { text, tone, lines }, or nil for what is not gear.
--   text   "Upgrade"      at least one role's line is an upgrade
--          "Unknown"      no upgrade line, and at least one line is a "No
--                         verdict" (or a note that something was not known)
--          "Not trained yet"  a weapon your class can learn but you have
--                         not trained (the "Can't use yet: " line, G12/G16)
--          "No upgrade"   every line is a known no: the same, worse, or
--                         "Can't use"
--   tone   "good" for an upgrade, else "none"
--   lines  the tooltip lines behind the word, as text: the upgrade lines for
--          "Upgrade", all of them otherwise
--   Unknown is never shown as an upgrade and never as a no.
--
-- Advice: { word, text, value, tone, role, gain }, or nil when there is no
-- advice to give (not gear, or no verdict: never a guess).
--   role   spec.role. One the class pack has weights for: only that role
--          counts. None (or one the pack has no weights for): an upgrade
--          for any role counts, the biggest named.
--   "Need: upgrade for <role>"   an upgrade for that role (word "need",
--                                value "Need +<gain>", tone "good")
--   "Greed"                      usable, no upgrade for the role (word
--                                "greed", value "Greed", tone "none")
--   "Greed (can't use)"          you cannot use it (word "greed")
--   Any role's verdict not known, with no upgrade found: no advice.
--
-- The module: two setting rows, account wide, on by default:
--   gear.rollHint   "Upgrade hint on loot rolls": the hint above the roll
--                   frame and the value on its item
--   gear.rollChat   "Need or Greed advice in chat on loot rolls": one chat
--                   line per roll id, once there is advice
-- At start it asks the client to be told about loot rolls:
--   client.onLootRoll(fn) -> cancel;  fn(rollId, link, show);  show(text, r, g, b)
--   client.rollValue(rollId, text, r, g, b)   the value on the roll's item
-- A client without the roll hook (see Core/Client.lua, F4) leaves the
-- module started and quiet. A roll with no advice yet (the item not loaded,
-- what you wear not read, a read raising) is worked out again every TICK
-- seconds, at most TRIES times. With the setting off nothing is worked out.
-- An error while working a hint out shows nothing for that roll, is
-- counted, and is kept as one "gear" problem per distinct error.
-- The word `<slash> roll <item link>` says the advice for any item. The
-- slash command lower-cases what follows the word, so the item is read by
-- its item string (item:<id>...).

local R = {}
ns.GearRollHint = R

R.NAME = "gearRollHint"
R.SETTING = "gear.rollHint"
R.CHAT_SETTING = "gear.rollChat"
R.ROLE = "spec.role"            -- Rotation/Role.lua's setting
R.TICK = 1
R.TRIES = 10

-- Words. Authored here.
R.WORD = "roll"
R.HELP = "<item link>: Need or Greed for that item, by the gear verdict for your role. It never rolls."
R.NEED = "Need"
R.GREED = "Greed"
R.CANT_USE = "Greed (can't use)"
R.NOT_TRAINED = "Greed (not trained yet)"
R.NO_ADVICE ="no advice: not gear, or not known yet."

function R.Hint(client, packs, link)
    if type(client) ~= "table" or type(link) ~= "string" or link == "" then return nil end
    local lines = ns.GearTooltipModule.Lines(client, packs, link)
    if type(lines) ~= "table" or #lines == 0 then return nil end
    local good, all, unknown, untrained = {}, {}, false, false
    local prefix = ns.GearTooltip.UNTRAINED
    for i = 1, #lines do
        all[i] = lines[i].text
        if lines[i].tone == "good" then
            good[#good + 1] = lines[i].text
        elseif lines[i].tone == "none" then
            unknown = true
        elseif lines[i].text:sub(1, #prefix) == prefix then
            untrained = true
        end
    end
    if #good > 0 then return { text = "Upgrade", tone = "good", lines = good } end
    -- G12: a weapon skill not trained yet is told apart from "your class
    -- can't use this" (that stays "No upgrade").
    if untrained then return { text = "Not trained yet", tone = "none", lines = all } end
    if unknown then return { text = "Unknown", tone = "none", lines = all } end
    return { text = "No upgrade", tone = "none", lines = all }
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- A gain in words: whole, or to one decimal place ("5", "2.8").
local function amount(n)
    local rounded = math.floor(n * 10 + 0.5) / 10
    if rounded == math.floor(rounded) then return string.format("%d", rounded) end
    return string.format("%.1f", rounded)
end

-- The roles to judge by: the chosen one when the pack has weights for it,
-- else every role the pack has weights for, sorted.
local function rolesFor(pack, role)
    local weights = {}
    if type(pack) == "table" and type(pack.weights) == "table" then weights = pack.weights end
    if type(role) == "string" and role ~= "" and type(weights[role]) == "table" then return { role } end
    local out = {}
    for r, w in pairs(weights) do
        if type(r) == "string" and type(w) == "table" then out[#out + 1] = r end
    end
    table.sort(out)
    return out
end

function R.Advice(client, packs, link, role)
    if type(client) ~= "table" or type(link) ~= "string" or link == "" then return nil end
    local gear = ask(client, "gear", link)
    if type(gear) ~= "table" then return nil end
    local class = ask(client, "class")
    local pack = nil
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    local roles = rolesFor(pack, role)
    if #roles == 0 then return nil end
    local level = ask(client, "level")
    local skills = nil
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end

    local best, bestGain, unknown = nil, nil, false
    for i = 1, #roles do
        local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[i], level = level,
                                                            skills = skills })
        if lines == nil then return nil end
        local can = nil
        if type(detail) == "table" and type(detail.use) == "table" then can = detail.use.can end
        if can == false then
            -- G12: a weapon skill not trained yet is said apart from a
            -- kind the class can never use.
            if detail.use.why == "untrained" then
                return { word = "greed", text = R.NOT_TRAINED, value = R.GREED, tone = "none" }
            end
            return { word = "greed", text = R.CANT_USE, value = R.GREED, tone = "none" }
        end
        if can ~= true then return nil end
        local res = {}
        if type(detail.result) == "table" then res = detail.result end
        local v = res.verdict
        if v == "upgrade" and finite(res.delta) and res.delta >= ns.GearTooltip.SAME then
            if bestGain == nil or res.delta > bestGain then best, bestGain = roles[i], res.delta end
        elseif v ~= "upgrade" and v ~= "same" and v ~= "worse" then
            unknown = true
        end
    end
    if best ~= nil then
        return { word = "need", text = R.NEED .. ": upgrade for " .. best, role = best, gain = bestGain,
                 value = R.NEED .. " +" .. amount(bestGain), tone = "good" }
    end
    if unknown then return nil end
    return { word = "greed", text = R.GREED, value = R.GREED, tone = "none" }
end

-- The roll word's lines for `rest`: the advice for the item in it.
function R.Run(k, rest, packs)
    local slash = ""
    if type(k.id) == "table" and type(k.id.slash) == "string" then slash = k.id.slash end
    local link = string.match(tostring(rest or ""), "(item:[%-%d:]+)")
    if link == nil then
        return { "Say " .. slash .. " " .. R.WORD .. " and shift-click an item: Need or Greed for your role."
                 .. " It never rolls." }
    end
    local role = nil
    if type(k.settings) == "table" then role = k.settings:get(R.ROLE) end
    local advice = R.Advice(k.client, packs or ns.Packs, link, role)
    if advice == nil then return { link .. ": " .. R.NO_ADVICE } end
    return { link .. ": " .. advice.text }
end

function R.Declare(k, packs, diag)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen, said, pending = {}, {}, {}
    local ctx, ticker = nil, nil
    function api.hooked() return hooked end
    function api.errors() return errors end

    local function title()
        if type(k.id) == "table" and type(k.id.title) == "string" then return k.id.title end
        return ns.id.title
    end

    local function problem(what, err)
        errors = errors + 1
        local text = tostring(err)
        if not seen[text] then
            seen[text] = true
            k.problems:add("gear", what, text)
        end
    end

    local function run(rest)
        local ok, lines = pcall(R.Run, k, rest, packs)
        if not ok then
            local text = tostring(lines)
            if type(k.problems) == "table" then k.problems:add("gear", R.WORD, text) end
            lines = { "The roll check failed: " .. text }
        end
        for i = 1, #lines do k.client.print(title() .. ": " .. lines[i]) end
        return false
    end
    api.run = run
    if diag and type(diag.commands) == "table" then
        diag.commands[R.WORD] = run
        if type(diag.help) == "table" then diag.help[R.WORD] = R.HELP end
    end

    -- The value on the roll's item: advice.value, or cleared with none.
    local function value(rollID, advice)
        if type(ctx.client.rollValue) ~= "function" then return end
        local text, colour = nil, nil
        if advice ~= nil then
            text = advice.value
            colour = ns.GearTooltipModule.COLOUR[advice.tone] or ns.GearTooltipModule.COLOUR.none
        end
        local ok, err
        if colour ~= nil then
            ok, err = pcall(ctx.client.rollValue, rollID, text, colour[1], colour[2], colour[3])
        else
            ok, err = pcall(ctx.client.rollValue, rollID, text)
        end
        if not ok then problem("roll value", err) end
    end

    local function chat(rollID, link, advice)
        if said[rollID] or ctx.settings:get(R.CHAT_SETTING) ~= true then return end
        said[rollID] = true
        ctx.client.print(title() .. ": " .. link .. ": " .. advice.text)
    end

    local stopTicker

    -- Works one roll out: the hint above it, the value on it, the chat line.
    -- No advice yet: kept in pending for the next tick.
    local function work(rollID, entry)
        local ok, hint, advice = pcall(function()
            local all = packs or ns.Packs
            return R.Hint(ctx.client, all, entry.link),
                R.Advice(ctx.client, all, entry.link, ctx.settings:get(R.ROLE))
        end)
        if not ok then
            problem("roll hint", hint)
            pending[rollID] = entry
            return
        end
        if hint ~= nil and hint.text ~= entry.shown then
            entry.shown = hint.text
            local colour = ns.GearTooltipModule.COLOUR[hint.tone] or ns.GearTooltipModule.COLOUR.none
            entry.show(hint.text, colour[1], colour[2], colour[3])
        end
        value(rollID, advice)
        if advice == nil then
            pending[rollID] = entry
            return
        end
        pending[rollID] = nil
        chat(rollID, entry.link, advice)
    end

    local function tick()
        if ctx.settings:get(R.SETTING) ~= true then
            pending = {}
        end
        for rollID, entry in pairs(pending) do
            entry.tries = entry.tries + 1
            work(rollID, entry)
            if entry.tries >= R.TRIES then pending[rollID] = nil end
        end
        if next(pending) == nil then stopTicker() end
    end

    stopTicker = function()
        if ticker then ticker() end
        ticker = nil
    end

    k:Module({
        name = R.NAME,
        needs = { "client", "store", "bus", "sched" },
        settings = { {
            key = R.SETTING, scope = "account", type = "bool", default = true,
            label = "Upgrade hint on loot rolls",
            help = "When the game offers you a roll on gear, say whether it is an upgrade. It never rolls for you.",
            group = "gear", synonyms = { "roll", "need", "greed", "loot", "upgrade" },
        }, {
            key = R.CHAT_SETTING, scope = "account", type = "bool", default = true,
            label = "Need or Greed advice in chat on loot rolls",
            help = "With the roll hint on, also say in chat, once per roll, Need when the item is an upgrade "
                .. "for your role and Greed when it is not. It never rolls for you.",
            group = "gear", synonyms = { "roll", "need", "greed", "loot", "hint" },
        } },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(c)
            ctx = c
            if type(c.client.onLootRoll) ~= "function" then return end
            local got = c.client.onLootRoll(function(rollID, link, show)
                if c.settings:get(R.SETTING) ~= true or type(show) ~= "function" then return end
                if type(link) ~= "string" or link == "" then return end
                local entry = { link = link, show = show, tries = 0 }
                pending[rollID] = nil
                work(rollID, entry)
                if pending[rollID] ~= nil and ticker == nil then
                    ticker = c.sched:every(R.NAME, R.TICK, tick)
                end
            end)
            if type(got) == "function" then
                cancel, hooked = got, true
            end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
            stopTicker()
            pending = {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearRollHint = R.Declare(ns, nil, ns.diag)
