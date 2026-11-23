local _, ns = ...

-- The gear verdict on the game's item tooltip: hover a piece of gear and
-- read whether it is an upgrade for what you wear, for each role your class
-- pack has weights for. It only reads and adds lines of text; nothing is
-- equipped, moved or picked up.
--
--   lines = GearTooltipModule.Lines(client, packs, link)
--   api   = GearTooltipModule.Declare(k[, packs])
--     api.hooked()   true once the client's item tooltip is being followed
--     api.errors()   how many tooltips could not be worked out
--   ns.use(GearTooltipModule.NAME) -> { Hooked = api.hooked, Errors = api.errors }
--
-- Lines: the lines for one item link, { { text, tone } ... }, or nil when
-- nothing is to be said (not gear, or no gear read on this client).
--   One line per role, in name order, when you can use the item. A line
--   that would read the same for every role (can't use; no verdict) is
--   said once. Each of these is asked of the client and may be missing:
--     client.gear(link)   the item, what you wear, dual wield
--     client.class()      which class pack (packs[class])
--     client.level()      your level; no such read, or no answer: not known
--   Not known is never an upgrade (Gear/Verdict.lua).
--   opts { score = true, role } (G11), when you can use the item: after the
--   verdict lines, all with tone "info" (RollHint and MerchantMarks read
--   only "good" and "none" lines and lines[1], and pass no opts):
--     "Score 10 (dps), 6 (tank)"   the item's score per role the pack has
--                                  weights for, `role` (spec.role) first
--     "vs your head piece: 2.7 (dps), 3.2 (tank)"   the score of what it was
--                                  held up to; roles held up to different
--                                  slots get a line each
--     "You're wearing this."       in place of the vs lines, when
--                                  client.wornLinks() names the same item
--                                  (Items.Same); not read, or raising: not
--                                  known, so not said
--   Then, for a weapon whose speed was read, one speed line (G15,
--   Gear/WeaponSpeed.lua). An error working that line out leaves it off,
--   keeps the others, and is the second value: lines, err.
--
--   lines = GearTooltipModule.Why(client, packs, role)   the `gear why` word:
--     for each bag item (client.bagItems()) that is gear, once per link, its
--     verdict line for `role` (spec.role, else the pack's first role) and
--     its score; nothing for what is not gear; at most WHY_CAP items, then
--     "and N more". Look only.
--
-- The module: two setting rows, account wide:
--   gear.tooltip        "Gear verdict on item tooltips", on by default
--   gear.tooltipScore   "Gear score on item tooltips", off by default (G11)
-- and the word `<slash> gear why` (with its help line) when diag is given.
-- At start it asks the client to be told about item tooltips:
--   client.onItemTooltip(fn) -> cancel;  fn(link, add);  add(text, r, g, b)
-- A client without that hook (none of its two routes works), or one that
-- refuses it, leaves the module started and quiet: hooked() is false. With
-- the setting off nothing is worked out and nothing is added. An error
-- while working a tooltip out adds nothing to that tooltip, is counted, and
-- is kept as one "gear" problem per distinct error; the module goes on.

local M = {}
ns.GearTooltipModule = M

M.NAME = "gearTooltip"
M.SETTING = "gear.tooltip"
M.SCORE_SETTING = "gear.tooltipScore"   -- G11: the score lines on the tooltip
M.ROLE = "spec.role"                    -- Rotation/Role.lua's setting

-- G11 words. Authored here.
M.SCORE_WORD = "Score"
M.WEARING = "You're wearing this."
M.WORD = "gear"
M.WHY_CAP = 20
M.HELP = "why: each piece of gear in your bags with its verdict and score for your role. It changes nothing."
M.NO_GEAR = "No gear in your bags."
M.BAGS_UNREAD = "Your bags could not be read."

-- A line's colour by its tone: { r, g, b }. Authored here.
M.COLOUR = {
    good = { 0.1, 1, 0.1 },
    same = { 1, 1, 1 },
    bad = { 1, 0.3, 0.3 },
    none = { 0.6, 0.6, 0.6 },
    info = { 0.6, 0.6, 0.6 },   -- a note, not a verdict (the weapon speed line)
}

-- One read of the client; nil when it has no such read.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The roles a pack has weights for, sorted.
local function rolesOf(pack)
    local out = {}
    if type(pack) == "table" and type(pack.weights) == "table" then
        for role, w in pairs(pack.weights) do
            if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
        end
    end
    table.sort(out)
    return out
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A score in words: whole, or to one decimal place ("10", "2.7").
local function amount(n)
    local rounded = math.floor(n * 10 + 0.5) / 10
    if rounded == math.floor(rounded) then return string.format("%d", rounded) end
    return string.format("%.1f", rounded)
end

-- The roles with `first` ahead of the others when it is one of them.
local function firstOf(roles, first)
    local out = {}
    for i = 1, #roles do
        if roles[i] == first then out[1] = first end
    end
    if out[1] == nil then return roles end
    for i = 1, #roles do
        if roles[i] ~= first then out[#out + 1] = roles[i] end
    end
    return out
end

-- The class pack and what the verdict needs of you: pack, level, skills.
local function whoOf(client, packs)
    local class = ask(client, "class")
    local pack = nil
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    -- G16: the skill lines you know; a read that raises is not read.
    local skills = nil
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end
    return pack, ask(client, "level"), skills
end

-- Whether the item is one you wear: true, false, or nil when the worn
-- links are not known (no read, no answer, or the read raised).
local function wearing(client, link)
    if type(client) ~= "table" or type(client.wornLinks) ~= "function" then return nil end
    local ok, worn = pcall(client.wornLinks)
    if not ok or type(worn) ~= "table" then return nil end
    for _, wornLink in pairs(worn) do
        if ns.Items.Same(wornLink, link) then return true end
    end
    return false
end

-- G11: the score lines, all "info": the item's score per role, then what it
-- was held up to with that item's score (roles held up to the same slot
-- share a line), or "You're wearing this." in place of those.
local function scoreLines(scored, worn)
    if #scored == 0 then return {} end
    local parts = {}
    for i = 1, #scored do parts[i] = amount(scored[i].result.score) .. " (" .. scored[i].role .. ")" end
    local out = { { text = M.SCORE_WORD .. " " .. table.concat(parts, ", "), tone = "info" } }
    if worn == true then
        out[2] = { text = M.WEARING, tone = "info" }
        return out
    end
    local groups, order = {}, {}
    for i = 1, #scored do
        local result = scored[i].result
        if finite(result.against) then
            local what = ns.GearTooltip.What(result)
            if groups[what] == nil then
                groups[what] = {}
                order[#order + 1] = what
            end
            local group = groups[what]
            group[#group + 1] = amount(result.against) .. " (" .. scored[i].role .. ")"
        end
    end
    for i = 1, #order do
        out[#out + 1] = { text = "vs " .. order[i] .. ": " .. table.concat(groups[order[i]], ", "), tone = "info" }
    end
    return out
end

function M.Lines(client, packs, link, opts)
    local gear = ask(client, "gear", link)
    if type(gear) ~= "table" then return nil end
    local pack, level, skills = whoOf(client, packs)
    local roles = rolesOf(pack)
    local withScore = type(opts) == "table" and opts.score == true
    local scored = {}

    local out, said = {}, {}
    local function keep(lines)
        for i = 1, #lines do
            if not said[lines[i].text] then
                said[lines[i].text] = true
                out[#out + 1] = lines[i]
            end
        end
    end
    -- With no role to score by, one pass still says why there is no verdict.
    for i = 1, math.max(#roles, 1) do
        local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[i], level = level,
                                                            skills = skills })
        if lines == nil then return nil end
        keep(lines)
        -- Whether you can use it does not depend on the role.
        if type(detail.use) ~= "table" or detail.use.can ~= true then break end
        if roles[i] ~= nil and type(detail.result) == "table" and finite(detail.result.score) then
            scored[#scored + 1] = { role = roles[i], result = detail.result }
        end
    end
    -- G11: the score lines, after every verdict line (lines[1] stays the
    -- verdict), only when asked for: the readers that ask nothing (RollHint,
    -- MerchantMarks) get the lines they always got.
    if withScore and #scored > 0 then
        local byRole = {}
        for i = 1, #scored do byRole[scored[i].role] = scored[i] end
        local ordered = {}
        local names = firstOf(roles, opts.role)
        for i = 1, #names do
            if byRole[names[i]] then ordered[#ordered + 1] = byRole[names[i]] end
        end
        keep(scoreLines(ordered, wearing(client, link)))
    end
    -- G15: a weapon's speed, last, with the pack's weaponSpeed preferences:
    -- the chosen role's alone (opts.role) when the pack has one for it, else
    -- every role's. An error here keeps the verdict lines and comes back as
    -- the second value.
    local ok, speed = pcall(function()
        local W = ns.GearWeaponSpeed
        local prefs = type(pack) == "table" and pack.weaponSpeed or nil
        local chosen = type(opts) == "table" and opts.role or nil
        if type(prefs) == "table" and type(chosen) == "string" and type(prefs[chosen]) == "table" then
            prefs = { [chosen] = prefs[chosen] }
        end
        return W.Line(W.From(gear), prefs)
    end)
    if not ok then return out, speed end
    -- Its own tone, "info": readers of these lines (RollHint, MerchantMarks)
    -- take "none" as a no-verdict, which a speed note is not.
    if type(speed) == "table" then keep({ { text = speed.text, tone = "info" } }) end
    return out
end

-- The role chosen (spec.role) when the pack has weights for it, else the
-- first role by name; nil with none.
local function roleFor(roles, chosen)
    for i = 1, #roles do
        if roles[i] == chosen then return chosen end
    end
    return roles[1]
end

function M.Why(client, packs, chosen)
    local ok, stacks = pcall(ask, client, "bagItems")
    if not ok or type(stacks) ~= "table" then return { M.BAGS_UNREAD } end
    local pack, level, skills = whoOf(client, packs)
    local role = roleFor(rolesOf(pack), chosen)
    local found, seen = {}, {}
    for i = 1, #stacks do
        local link = nil
        if type(stacks[i]) == "table" then link = stacks[i].item end
        if type(link) == "string" and link ~= "" and not seen[link] then
            seen[link] = true
            local gear = ask(client, "gear", link)
            local lines, detail = nil, nil
            if type(gear) == "table" then
                lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = role, level = level,
                                                             skills = skills })
            end
            if type(lines) == "table" and type(lines[1]) == "table" then
                local text = link .. ": " .. lines[1].text
                local result = detail.result
                local usable = type(detail.use) == "table" and detail.use.can == true
                if usable and type(result) == "table" and finite(result.score) then
                    text = text .. "; score " .. amount(result.score)
                end
                found[#found + 1] = text
            end
        end
    end
    if #found == 0 then return { M.NO_GEAR } end
    local title = "Gear in your bags:"
    if role ~= nil then title = "Gear in your bags, for " .. role .. ":" end
    local out = { title }
    for i = 1, math.min(#found, M.WHY_CAP) do out[#out + 1] = found[i] end
    if #found > M.WHY_CAP then out[#out + 1] = "and " .. (#found - M.WHY_CAP) .. " more" end
    return out
end

-- The gear word: "why" lists the bags; anything else says how.
function M.Run(k, rest, packs)
    local word = tostring(rest or ""):lower():match("^%s*(%S*)")
    if word ~= "why" then
        local slash = ""
        if type(k.id) == "table" and type(k.id.slash) == "string" then slash = k.id.slash end
        return { "Say " .. tostring(slash) .. " " .. M.WORD .. " why to list the gear in your bags "
                 .. "with its verdict and score." }
    end
    local chosen = nil
    if type(k.settings) == "table" then chosen = k.settings:get(M.ROLE) end
    return M.Why(k.client, packs or ns.Packs, chosen)
end

function M.Declare(k, packs, diag)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen = {}
    function api.hooked() return hooked end
    function api.errors() return errors end

    local function run(rest)
        local ok, lines = pcall(M.Run, k, rest, packs)
        if not ok then
            local text = tostring(lines)
            if type(k.problems) == "table" then k.problems:add("gear", "why", text) end
            lines = { "The gear check failed: " .. text }
        end
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        return false
    end
    api.run = run
    if diag and type(diag.commands) == "table" then
        diag.commands[M.WORD] = run
        if type(diag.help) == "table" then diag.help[M.WORD] = M.HELP end
    end

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = M.SETTING, scope = "account", type = "bool", default = true,
            label = "Gear verdict on item tooltips",
            help = "Hover a piece of gear to read whether it is an upgrade for what you wear. It changes nothing.",
            group = "gear", synonyms = { "upgrade", "tooltip", "compare", "armor", "weapon" },
        }, {
            key = M.SCORE_SETTING, scope = "account", type = "bool", default = false,
            label = "Gear score on item tooltips",
            help = "With the gear verdict on, also show the item's score for each role, the score of "
                .. "what you wear in that slot, or that you are wearing it. It changes nothing.",
            group = "gear", synonyms = { "score", "worn", "stats", "points" },
        } },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(ctx)
            if type(ctx.client.onItemTooltip) ~= "function" then return end
            local got = ctx.client.onItemTooltip(function(link, add)
                if ctx.settings:get(M.SETTING) ~= true or type(add) ~= "function" then return end
                -- The role always (the speed line names its preference);
                -- the score lines only with their setting on.
                local opts = { role = ctx.settings:get(M.ROLE) }
                if ctx.settings:get(M.SCORE_SETTING) == true then opts.score = true end
                -- Every line is worked out before the first is added, so an
                -- error leaves the tooltip as the game made it.
                local ok, lines, partErr = pcall(M.Lines, ctx.client, packs or ns.Packs, link, opts)
                local err = partErr
                if not ok then err = lines end
                if err ~= nil then
                    errors = errors + 1
                    local text = tostring(err)
                    if not seen[text] then
                        seen[text] = true
                        k.problems:add("gear", "tooltip", text)
                    end
                end
                if not ok then return end
                for i = 1, #(lines or {}) do
                    local colour = M.COLOUR[lines[i].tone] or M.COLOUR.none
                    add(lines[i].text, colour[1], colour[2], colour[3])
                end
            end)
            if type(got) == "function" then
                cancel, hooked = got, true
            end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearTooltip = M.Declare(ns, nil, ns.diag)
