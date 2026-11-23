-- The window kit's parts list (lead DISPATCH section 297 items 2 and 3,
-- section 303 item 5): every Blizzard template, atlas, texture path and
-- client name the kit would like to use, each with the kit element it is
-- for and what that element draws when the client does not have it. Pure
-- data: nothing here asks the client. The login probe (UI/KitProbe.lua,
-- client.kitProbe in Core/Client.lua) asks the client for each row once per
-- login and saves "works" or what the client said, by row id.
--
-- Where the rows come from: the kit parts table (Zen UI session,
-- 2026-11-23; zflow-kit-parts-table.md), whose ids are kept, and names the
-- kit's spec asks for: the SaneUI project's GUI guide (MIT;
-- github.com/GlennDrescher/SaneUI, file Doc/guides/gui-development.md).
-- Names only; none of its code is here. Lead section 308 cut the list to
-- these rows; the ids of the rows left out are not reused.
--
-- EVERY NAME IS A FIRST GUESS: none has been seen on build 16001. A wrong
-- name costs nothing: the probe reads it as missing and the element draws
-- the fallback in its row. frameType (templates) is the widget kind the
-- template is made as, a first guess too. proof names fields that template
-- is known by (first guesses): a frame handed back counts as the template
-- only when it carries one of them.
--
--   row = { id =, kind = "template" | "atlas" | "texture" | "global", name =,
--           frameType = (templates), proof = { field ... } (templates),
--           element = the kit element, fallback = what draws without it }
--   KitParts.rows          the rows, in table order
--   KitParts.KINDS         the four kinds, in table order
--   KitParts.ById(id)      -> row | nil
--   KitParts.Each(kind, fn)   fn(row) for each row of that kind, in order;
--                             kind nil: every row. -> how many were handed on
--
-- One row per line, id then kind then name first: tools\zflow-read-diag.ps1
-- reads this file as text to print each saved answer with its kind and name.
local _, ns = ...

local KitParts = ns.KitParts or {}
ns.KitParts = KitParts

KitParts.KINDS = { "template", "atlas", "texture", "global" }

KitParts.rows = {
    -- Templates.
    { id = "T2", kind = "template", name = "ButtonFrameTemplate", frameType = "Frame", proof = { "CloseButton", "TitleContainer", "TitleText", "Inset", "NineSlice" }, element = "window frame (second choice)", fallback = "plain panel: dark fill, thin edge, title strip" },
    { id = "T5", kind = "template", name = "SearchBoxTemplate", frameType = "EditBox", proof = { "searchIcon", "clearButton", "Instructions" }, element = "header search box (the journal's search box)", fallback = "plain edit box with a dim Search text" },
    { id = "T7", kind = "template", name = "PanelTabButtonTemplate", frameType = "Button", proof = { "Text", "Left", "LeftActive", "LeftDisabled" }, element = "tab strip", fallback = "flat tab: text, gold when selected, tinted backing" },
    { id = "T10", kind = "template", name = "MinimalScrollBar", frameType = "EventFrame", proof = { "Track", "Back", "Forward", "SetScrollPercentage" }, element = "scroll bar (the journal's bar on newer clients)", fallback = "none: mouse wheel only" },
    { id = "T16", kind = "template", name = "UIPanelButtonTemplate", frameType = "Button", proof = { "Text", "Left", "Middle", "Right" }, element = "button, bind button, choice", fallback = "plain button: tinted fill, thin edge, text" },
    { id = "T24", kind = "template", name = "TabSystemTemplate", frameType = "Frame", proof = { "AddTab", "SetTabSelectedCallback", "tabPool" }, element = "tabs (newer system)", fallback = "T7, else its flat tab" },
    { id = "T25", kind = "template", name = "WowScrollBoxList", frameType = "Frame", proof = { "SetDataProvider", "Init", "ScrollTarget" }, element = "scroll list (newer system, with T10)", fallback = "plain scroll frame, mouse wheel only" },



    -- Client names.
    { id = "G2", kind = "global", name = "C_Texture.GetAtlasInfo", element = "the atlas lookup", fallback = "an atlas is asked by a protected SetAtlas on a hidden texture" },
    { id = "G6", kind = "global", name = "GameTooltip", element = "tooltips on kit parts", fallback = "no tooltip" },
    { id = "G15", kind = "global", name = "NORMAL_FONT_COLOR", element = "gold text: headings, the selected tab", fallback = "the kit's own colour" },
    { id = "G16", kind = "global", name = "HIGHLIGHT_FONT_COLOR", element = "white text: values, hover", fallback = "the kit's own colour" },
    { id = "G17", kind = "global", name = "DISABLED_FONT_COLOR", element = "dim text: a part that is off", fallback = "the kit's own colour" },
    { id = "G18", kind = "global", name = "RED_FONT_COLOR", element = "red text: a problem", fallback = "the kit's own colour" },
    { id = "G19", kind = "global", name = "GREEN_FONT_COLOR", element = "green text: a good state", fallback = "the kit's own colour" },
    { id = "G20", kind = "global", name = "GRAY_FONT_COLOR", element = "grey text: a hint", fallback = "the kit's own colour" },
    { id = "G21", kind = "global", name = "GameFontNormal", element = "body text, gold", fallback = "the default font with the kit's own size and colour" },
    { id = "G22", kind = "global", name = "GameFontHighlight", element = "body text, white", fallback = "as G21" },
    { id = "G23", kind = "global", name = "GameFontDisable", element = "body text, dim", fallback = "as G21" },
    { id = "G24", kind = "global", name = "GameFontNormalSmall", element = "small text, gold", fallback = "as G21" },
    { id = "G25", kind = "global", name = "GameFontHighlightSmall", element = "small text, white", fallback = "as G21" },
    { id = "G26", kind = "global", name = "GameFontDisableSmall", element = "small text, dim", fallback = "as G21" },
    { id = "G27", kind = "global", name = "GameFontNormalLarge", element = "window and section titles", fallback = "as G21" },
    { id = "G28", kind = "global", name = "GameFontRed", element = "body text, red", fallback = "as G21" },
    { id = "G29", kind = "global", name = "GameFontGreen", element = "body text, green", fallback = "as G21" },
}

local byId = {}
for i = 1, #KitParts.rows do
    local row = KitParts.rows[i]
    byId[row.id] = row
end

function KitParts.ById(id)
    if type(id) ~= "string" then return nil end
    return byId[id]
end

function KitParts.Each(kind, fn)
    if type(fn) ~= "function" then return 0 end
    local n = 0
    for i = 1, #KitParts.rows do
        local row = KitParts.rows[i]
        if kind == nil or row.kind == kind then
            n = n + 1
            fn(row)
        end
    end
    return n
end
