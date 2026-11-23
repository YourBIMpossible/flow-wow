local _, ns = ...
-- N41 key controls (P-KEYS slice B): the settings rows that say what the
-- rotation key (the easy key, Rotation/KeyFrame.lua) does with each
-- modifier, and the pure functions the driver (Rotation/Driver.lua) runs
-- on its key plan each tick. Each control is one char row on the Combat
-- topic, on by default; off means that modifier slot is not set.
--
--   Shift + key   your fastest direct heal, on you (rotation.shiftHeal)
--   Alt + key     the healthstone or potion (N8: plan.altItem)
--                 (rotation.altItem)
--   Ctrl + key    with a friend targeted (N63: client.unitCare), your
--                 fastest direct heal on the target; with none, the pack's
--                 own Ctrl spell (rotation.ctrlFriend)
--   the key       gathering: the gathering tracking step (P-GATHER, step
--                 "track"); fishing, a corpse, a station and an upgrade
--                 (N1, N2, N20, N5: Rotation/KeyActions.lua)
--                 (rotation.keyActions)
--
--   KC.Read(settings) -> { shift, alt, ctrl, actions } (a row not false
--                 is on); nil without settings
--   KC.Shape(plan, controls, s, pack, friend) -> plan, the same table
--                 changed; plan or controls not a table: plan as it was.
--                 Slot units go in plan.units (ns.cast puts them on the
--                 button; a slot with none casts on the target)
--   KC.Friend(client) -> true when the target exists, is friendly and is
--                 not you; a read that fails or gives nothing is false
--   KC.Gate(suggestion, controls) -> the suggestion; with the key's
--                 actions off, a gathering step is marked keyOff = true:
--                 still shown, never put on the key
--   KC.Fishing(s) -> the key's fishing step (N1, P-KEYS slice D):
--                 Rotation/KeyActions.lua KA.Fishing, asked when called;
--                 nil without it.
-- Pure but for the settings rows. Nothing is bound, no macro is made
-- (section 246), and nothing acts on a timer or an event. Fake client
-- only; not tested in game.
local KC = {}
ns.KeyControls = KC

KC.NAME = "keyControls"
KC.SHIFT = "rotation.shiftHeal"
KC.ALT = "rotation.altItem"
KC.CTRL = "rotation.ctrlFriend"
KC.ACTIONS = "rotation.keyActions"
KC.GATHER_STEP = "track"

local R = ns.Rotation

function KC.Read(settings)
    if type(settings) ~= "table" or type(settings.get) ~= "function" then return nil end
    return {
        shift = settings:get(KC.SHIFT) ~= false,
        alt = settings:get(KC.ALT) ~= false,
        ctrl = settings:get(KC.CTRL) ~= false,
        actions = settings:get(KC.ACTIONS) ~= false,
    }
end

local function spellRow(s, name)
    if type(s) ~= "table" or type(s.spells) ~= "table" then return nil end
    local row = s.spells[name]
    if type(row) ~= "table" then return nil end
    return row
end

-- The fastest direct heal you know, from the pack's own heals; nil when
-- none is known.
local function quickHeal(s, pack)
    if type(pack) ~= "table" or type(pack.heals) ~= "table" then return nil end
    local own = pack.heals.self
    if type(own) ~= "table" then return nil end
    local hots = pack.heals.hots
    if type(hots) ~= "table" then hots = {} end
    return R.DirectHeal(own, hots, function(name)
        local row = spellRow(s, name)
        return row ~= nil and row.known == true
    end, function(name)
        local row = spellRow(s, name)
        if row and type(row.castMs) == "number" then return row.castMs end
        return 0
    end)
end

function KC.Shape(plan, controls, s, pack, friend)
    if type(plan) ~= "table" or type(controls) ~= "table" then return plan end
    if type(plan.states) ~= "table" then return plan end
    local quick = quickHeal(s, pack)
    if plan.states[0] == nil and quick then plan.states[0] = {} end
    local units = {}
    if type(plan.units) == "table" then
        for slot, unit in pairs(plan.units) do units[slot] = unit end
    end
    local ctrlHeal = controls.ctrl and friend == true and quick ~= nil
    for state = 0, R.STEALTH_STATE do
        local row = plan.states[state]
        if type(row) == "table" then
            if not controls.shift then
                row.shift = nil
            elseif quick then
                row.shift = quick
            end
            if not controls.alt then row.alt = nil end
            if not controls.ctrl then
                row.ctrl = nil
            elseif ctrlHeal then
                row.ctrl = quick
            end
        end
    end
    if not controls.shift then
        units.shift = nil
    elseif quick then
        units.shift = "player"
    end
    if not controls.alt then plan.altItem = nil end
    if not controls.ctrl then
        units.ctrl = nil
    elseif ctrlHeal then
        units.ctrl = "target"
    end
    if next(units) == nil then
        plan.units = nil
    else
        plan.units = units
    end
    return plan
end

function KC.Friend(client)
    if type(client) ~= "table" or type(client.unitCare) ~= "function" then return false end
    local ok, row = pcall(client.unitCare, "target")
    if not ok or type(row) ~= "table" then return false end
    return row.exists == true and row.friend == true and row.isSelf ~= true
end

function KC.Gate(suggestion, controls)
    if type(suggestion) ~= "table" or type(controls) ~= "table" then return suggestion end
    if controls.actions == false and suggestion.step == KC.GATHER_STEP then suggestion.keyOff = true end
    return suggestion
end

-- The fishing hook: N1 (P-KEYS slice D) builds it in Rotation/KeyActions.lua.
function KC.Fishing(s)
    local KA = ns.KeyActions
    if type(KA) ~= "table" or type(KA.Fishing) ~= "function" then return nil end
    return KA.Fishing(s)
end

-- The addon's own rows; the driver reads them each tick.
function KC.Declare(k)
    k:Module({
        name = KC.NAME,
        needs = { "store" },
        settings = { {
            key = KC.SHIFT, scope = "char", type = "bool", default = true,
            label = "Shift + key heals you",
            help = "With the rotation key on, Shift + the key casts your fastest direct heal on you. Off: Shift + the key does nothing.",
            group = "combat.rotation", synonyms = { "shift", "heal", "self heal", "quick heal", "modifier", "easy key" },
        }, {
            key = KC.ALT, scope = "char", type = "bool", default = true,
            label = "Alt + key uses a healthstone or potion",
            help = "With the rotation key on, Alt + the key uses your healthstone or healing potion. Off: Alt + the key does nothing.",
            group = "combat.rotation", synonyms = { "alt", "healthstone", "potion", "item", "modifier", "easy key" },
        }, {
            key = KC.CTRL, scope = "char", type = "bool", default = true,
            label = "Ctrl + key heals a friend you target",
            help = "With the rotation key on and a friend targeted, Ctrl + the key casts your fastest direct heal on them. Off: Ctrl + the key does nothing.",
            group = "combat.rotation", synonyms = { "ctrl", "control", "friend", "heal", "target", "modifier", "easy key" },
        }, {
            key = KC.ACTIONS, scope = "char", type = "bool", default = true,
            label = "The key does gathering and its out-of-fight actions",
            help = "Lets the gathering tracking step count as something the key does, and the key's fishing, corpse, station and upgrade actions. Off: the step is still shown, but kept off the key, and none of those actions is put on it.",
            group = "combat.rotation", synonyms = { "gather", "gathering", "fishing", "tracking", "mining", "herbalism", "easy key" },
        } },
    })
    return KC
end

KC.Declare(ns)
