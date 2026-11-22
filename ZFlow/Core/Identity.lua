-- Identity: every name this addon shows or claims. The only Lua file that may
-- hold these strings (tools/zflow-structure.ps1 fails the build otherwise).
-- The TOC is generated from this table plus manifest.lua.
local _, ns = ...

ns.id = {
    addon = "ZFlow",              -- folder and TOC name
    title = "Z-Flow",             -- shown to the player
    notes = "Levelling companion.",
    framePrefix = "ZFlow",        -- every named frame is framePrefix .. name
    slash = "/zflow",
    commPrefix = "ZFlow",         -- addon message prefix
    commVersion = 1,              -- protocol version field sent with every message
    bindingHeader = "ZFLOW",
    accountDB = "ZFlowDB",        -- SavedVariables
    charDB = "ZFlowCharDB",       -- SavedVariablesPerCharacter
    predecessor = "Flow",         -- the addon this one replaces; never loaded alongside
    predecessorDB = "FlowDB",     -- its account table: a second sign that it is loaded
}
