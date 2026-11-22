local _, ns = ...

-- The role reminder (G31): the role the player chose for this character,
-- and one line when the rotation is playing another one, or has no part
-- for the chosen one. It changes nothing but its own setting: the rotation
-- suggests as before, and no talent, form or gear is touched.
--
-- No talents are read. What the rotation plays you as is taken only from
-- the driver's view (view.snapshot.role). The driver plays the role chosen
-- here when the class's pack has a part for it, and none otherwise, so the
-- two are the same or what it plays is "not known"; a role the pack has no
-- part for is the one reminder that shows until a readable talent API is
-- seen in this client.
--
--   Ro.Check(chosen, pack, played) -> check
--     chosen  the setting: "dps", "heal", "tank"; anything else: none chosen
--     pack    the class pack, or nil when the class has none
--     played  the role the rotation plays; anything but the three: not known
--   check = {
--     state   "none"     no role chosen
--             "noPack"   no rotation for this class
--             "noPart"   the pack names no such role
--             "unknown"  what the rotation plays is not known
--             "same"     both are one role
--             "differs"  they are two roles
--     chosen, played      the roles, when they are roles
--     chosenName, playedName   the pack's own names for them, or nil
--   }
--   Ro.Reminder(check) -> text   only for "differs" and "noPart"; else nil
--   Ro.Lines(check) -> lines     the state in plain words
--   Ro.Declare(k[, diag, packs]) -> { status = fn }
--     the module on kernel k, its setting row, and the word Ro.WORD after
--     the slash command: alone it shows the state; with dps, heal, tank or
--     none it sets the role.
local Ro = {}
ns.RotationRole = Ro

local D = ns.RotationDriver

Ro.NAME = "rotationRole"
Ro.SETTING = "spec.role"
Ro.WORD = "role"
Ro.NONE = ""
Ro.CHOICES = { "", "dps", "heal", "tank" }
Ro.WORDS = { dps = "damage", heal = "healing", tank = "tanking" }
Ro.HELP = "show the role you chose; role dps, role heal, role tank or role none sets it"

local function roleOf(value)
    return type(value) == "string" and Ro.WORDS[value] ~= nil and value or nil
end

local function nameIn(pack, role)
    local row = type(pack) == "table" and type(pack.roles) == "table" and pack.roles[role] or nil
    if type(row) ~= "table" then return nil, false end
    return type(row.name) == "string" and row.name ~= "" and row.name or nil, true
end

function Ro.Check(chosen, pack, played)
    local check = { chosen = roleOf(chosen) }
    if not check.chosen then
        check.state = "none"
        return check
    end
    if type(pack) ~= "table" then
        check.state = "noPack"
        return check
    end
    local name, has = nameIn(pack, check.chosen)
    if not has then
        check.state = "noPart"
        return check
    end
    check.chosenName = name
    check.played = roleOf(played)
    if not check.played then
        check.state = "unknown"
        return check
    end
    check.playedName = nameIn(pack, check.played)
    check.state = check.played == check.chosen and "same" or "differs"
    return check
end

local function named(role, name)
    return Ro.WORDS[role] .. (name and (" (" .. name .. ")") or "")
end

function Ro.Reminder(check)
    if type(check) ~= "table" then return nil end
    if check.state == "differs" then
        return "your role is set to " .. named(check.chosen, check.chosenName)
            .. ", but the rotation is playing you as " .. named(check.played, check.playedName)
            .. ". It suggests as before; " .. ns.id.slash .. " " .. Ro.WORD .. " changes your role."
    end
    if check.state == "noPart" then
        local word = Ro.WORDS[check.chosen]
        return "your role is set to " .. word .. ", but your class's rotation has no " .. word
            .. " part. It suggests as before."
    end
    return nil
end

function Ro.Lines(check)
    check = type(check) == "table" and check or { state = "none" }
    local reminder = Ro.Reminder(check)
    if reminder then return { reminder } end
    if check.state == "none" then
        return { "no role chosen. " .. ns.id.slash .. " " .. Ro.WORD .. " dps, heal or tank sets one." }
    end
    local chosen = "your role is set to " .. named(check.chosen, check.chosenName) .. "."
    if check.state == "noPack" then
        return { chosen .. " There is no rotation for your class, so there is nothing to compare." }
    end
    if check.state == "same" then
        return { chosen .. " The rotation is playing you as the same." }
    end
    return { chosen .. " What the rotation plays you as is not known, so there is nothing to compare." }
end

-- The module on kernel k. diag (optional) is what Diag.Start returned;
-- packs: { [class token] = pack }, ns.Packs when left out.
function Ro.Declare(k, diag, packs)
    local api = {}
    local client
    local played, saidFor = nil, nil

    local function packNow()
        local class = client and type(client.class) == "function" and client.class() or nil
        local all = packs or ns.Packs
        return type(class) == "string" and type(all) == "table" and all[class] or nil
    end

    function api.status()
        return Ro.Check(k.settings:get(Ro.SETTING), packNow(), played)
    end

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    -- Said once for one disagreement; again only after it went away or
    -- became another one.
    local function onView(view)
        played = type(view) == "table" and type(view.snapshot) == "table" and view.snapshot.role or nil
        if type(view) ~= "table" then return end
        local check = api.status()
        local text = Ro.Reminder(check)
        local key = text and (check.state .. ":" .. check.chosen .. ":" .. tostring(check.played)) or nil
        if key and key ~= saidFor then say(text) end
        saidFor = key
    end

    local function run(rest)
        local word = tostring(rest or ""):lower():match("^%s*(%S*)")
        if word ~= "" then
            local value = word == "none" and Ro.NONE or roleOf(word)
            if value == nil then
                say("\"" .. word .. "\" is no role. Use dps, heal, tank or none.")
                return
            end
            k.settings:set(Ro.SETTING, value)
        end
        local lines = Ro.Lines(api.status())
        for i = 1, #lines do say(lines[i]) end
    end

    k:Module({
        name = Ro.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = Ro.SETTING, scope = "char", type = "choice", default = Ro.NONE,
            choices = Ro.CHOICES,
            label = "Your role",
            help = "The role you play this character as. You are told when the rotation plays another one."
                .. " It changes nothing by itself.",
            group = "Rotation",
        } },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(Ro.NAME, D.EVENT, onView)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Ro.WORD] = run
        if type(diag.help) == "table" then diag.help[Ro.WORD] = Ro.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads. It says nothing until a
-- role is chosen.
ns.rotationRole = Ro.Declare(ns, ns.diag)
