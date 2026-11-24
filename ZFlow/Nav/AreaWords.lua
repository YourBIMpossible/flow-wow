local _, ns = ...
-- Z-Flow: "You're in the area" (parity row A1-09, lead section 485). Inside
-- a step's arrival radius but not close to its middle, the here line says
-- you are in the area, not that you are at the spot.
-- Words only: the pulsing ring waits for Muse.
-- Not here yet: a caller. The arrow's here line is a later hook.
-- Compared with Flow Modules/Nav/Nav.lua (the arrived sub line):
-- "You're here" under ARRIVED * 2 (24 yd), else "You're in the area". The
-- same number; Z-Flow's own here words (UI/Arrow.lua HERE_TEXT) are kept
-- for the near case.
-- Not tested in game.
--
-- Pure:
--   AW.Words(d) -> AW.AREA when d is AW.HERE_YARDS or more, else nil
--                  (nil: the caller's own here words)
ns.Nav = ns.Nav or {}
local N = ns.Nav
local AW = {}
N.AreaWords = AW

AW.HERE_YARDS = 24     -- Flow ARRIVED * 2
-- Player-visible words, from Flow.
AW.AREA = "You're in the area"

function AW.Words(d)
    if type(d) ~= "number" or d ~= d or d == math.huge then return nil end
    if d >= AW.HERE_YARDS then return AW.AREA end
    return nil
end
