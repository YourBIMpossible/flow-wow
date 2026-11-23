-- Lead section 188: what the sanitizer (zflow-sanitize.lua) knows of a
-- capture. Every field ZFlow saves, with its kind; see the spec kinds at the
-- top of zflow-sanitize.lua. A field not here is refused.
--
-- Where the names are (read from the code, ZFlow/):
--   diag.snaps[].timing.character / .realm        Core/Diag.lua session()
--   diag.snaps[].shapes.realm, .realmNormalized,
--     .fullName (name, realm)                     Core/Diag.lua probes
--   learned.prices.auction / .auctionHistory keys "<realm>-<faction>"
--                                                 Import/FromFlow.lua,
--                                                 Items/AuctionLog.lua
--   learned.fights.deaths[] (Flow deathReports lines: "id|who|class|level|
--     zone|summary || findings", who the player)   Import/FromFlow.lua,
--                                                 Modules/Rotation/Engine.lua
--   learned.fights.mobs keys (target names) on the character
-- Free text (error lines, problem texts, import notes, export lines, typed
-- labels, other add-ons' globals) is replaced whole by a made-up "text N"
-- unless it holds no letter (section 190). No code reads guild, account,
-- mail or chat text: those kinds have no field here, so a capture holding
-- one is refused.
--
-- OPEN marks a subtree the add-on fills with keys it does not fix (copied
-- from Flow, learned game data, recovered skeleton keys): any keys and
-- plain values. Every text value is free text (replaced whole); a key is
-- kept only when it is a lower-case-first ASCII word, as add-on fields are,
-- and is replaced otherwise (character and realm names start with a
-- capital), so a name only ever in such a subtree does not reach the copy.

local OPEN = { key = { any = { "num", "fieldKey" } } }
OPEN.map = { any = { "num", "bool", "free", OPEN } }

local function fields(t, open) return { fields = t, open = open } end

-- A timing mark: Core/Diag.lua dataNow(), saved under the event name
-- (fileLoad, ADDON_LOADED ...) next to order, start and errors.
local MARK = fields({ at = "num", accountData = "bool", charData = "bool", phase = "str" })
local function list(spec) return { list = spec } end
local function map(spec, key) return { map = spec, key = key } end

-- A probe answer (Core/Diag.lua shape()): v1..vN are plain or a table of
-- plain fields; an answer that failed holds the error text: free.
local VALUE = { any = { "num", "bool", "free", map({ any = { "num", "bool", "free" } }, "str") } }
local function shape(values)
    return fields({
        ok = "bool", n = "num", types = list("str"),
        values = values or map(VALUE, "str"),
        error = "free",
    })
end
local NAME_VALUES = fields({ v1 = { any = { "char", "free" } }, v2 = { any = { "realm", "free" } } }, VALUE)
local REALM_VALUES = fields({ v1 = { any = { "realm", "free" } } }, VALUE)

local SNAP = fields({
    why = "str", at = "num", clock = "num",
    reads = OPEN,
    known = map("bool", "str"),
    shapes = fields({
        realm = shape(REALM_VALUES),
        realmNormalized = shape(REALM_VALUES),
        fullName = shape(NAME_VALUES),
    }, shape()),
    kernel = fields({
        phase = "str", paused = "bool", pauseText = "free", storeOpened = "bool",
        blocked = map("free", "str"),
        problems = list(fields({ kind = "str", owner = "str", text = "free", count = "num" })),
        eventsNotRegistered = list("str"),
        eventsExpectedAbsent = list("str"),
        eventFrameNotMade = "bool", tickFrameNotMade = "bool",
        meter = OPEN,
    }),
    timing = fields({
        order = list("str"),
        start = "num",
        character = "char",
        realm = "realm",
        errors = list(fields({ text = "free", count = "num", at = "num", phase = "str", ours = "bool" })),
    }, { any = { "num", MARK } }),
})

local DIAG = fields({
    starts = "num", count = "num",
    names = fields({ build = "str", names = map("str", "str") }),
    api = fields({
        -- Section 194, from the writer (Core/Diag.lua Diag.Api, the same at
        -- 88bd08d and at head): namespaces[name] = client.peek(name) or
        -- false. peek (Core/Client.lua, ClientFake.lua) gives a number,
        -- text or boolean as it is, or a table of tostring(key) = number,
        -- text, boolean, or the Lua type name of any other value.
        namespaces = map({ any = { "num", "bool", "free",
            map({ any = { "num", "bool", "typeName" } }, "str") } }, "str"),
        globals = map(list("free"), "str"),
    }),
    reads = list(fields({ at = "num", build = "str", reads = OPEN })),
    -- The window kit's login probe (UI/KitProbe.lua save()): the row ids of
    -- UI/Kit/Parts.lua plus EJ_LOADED, each with "works" or what the client
    -- said of a template, atlas, texture path or client name. No player,
    -- realm or chat text is in it, so it is kept as it is.
    kitProbe = fields({ at = "num", interface = "str", rows = map("str", "str") }),
    -- What each kit window drew (lead section 319; UI/KitProbe.lua): window id,
    -- then part name, then "first" or "fallback". No player text.
    kitDrawn = map("str", map("str", "str")),
    -- The sell list's first grey item (lead section 340; UI/SellList.lua):
    -- an item name and fixed words. No player text.
    sellGrey = fields({ item = "str", rule = "str", why = "str", counts = "str" }),
    snaps = list(SNAP),
})

-- A price book entry as Items/Prices.lua Prices.Record writes it: the
-- copper, how it is known, where from, when seen (a time) and how many it
-- was for (a stack size). Section 197: White's capture held seenAt and per.
local PRICE = fields({ value = "num", basis = "str", source = "str", seenAt = "num", per = "num" })
local HISTORY = fields({ h = list("num") })

local IMPORT = fields({
    source = "str", sourceVersion = "scalar", importer = "scalar", schema = "scalar",
    counts = OPEN, merge = OPEN,
    vendorChoices = OPEN, sameAsFlowDefault = OPEN,
    vendorSameAsFlowDefault = OPEN, vendorConfirmed = OPEN,
    refused = "free",
    dropped = list(fields({ key = "free", why = "str", reason = "free" })),
    adjusted = list(fields({ key = "free", from = OPEN.map, to = OPEN.map, reason = "free" })),
})

local ACCOUNT_LEARNED = fields({
    prices = fields({
        vendor = map(PRICE, { any = { "num", "str" } }),
        auction = map(map(PRICE, { any = { "num", "str" } }), "realmFaction"),
        auctionHistory = map(map(HISTORY, { any = { "num", "str" } }), "realmFaction"),
    }),
    fights = fields({
        deaths = list("free"),
    }, OPEN),
}, OPEN)

local CHAR_LEARNED = fields({
    fights = fields({ mobs = map(OPEN.map, "char") }, OPEN),
}, OPEN)

return {
    globals = {
        ZFlowDB = fields({
            schema = "num",
            recovered = OPEN,
            settings = OPEN,
            layout = OPEN,
            learned = ACCOUNT_LEARNED,
            imports = list(IMPORT),
            facts = OPEN,
            diag = DIAG,
        }),
        ZFlowCharDB = fields({
            schema = "num",
            recovered = OPEN,
            settings = OPEN,
            layout = OPEN,
            state = OPEN,
            learned = CHAR_LEARNED,
            audit = OPEN,
            export = fields({ at = "num", lines = list("free") }),
        }),
    },
}
