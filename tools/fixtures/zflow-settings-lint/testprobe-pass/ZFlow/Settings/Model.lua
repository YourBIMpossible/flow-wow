local M = {}
-- a comment row: { key = "ghost" } is not a row
M.ROWS = {
    { key = "a.one", type = "bool", default = false },
    { key = "b.two", type = "number", default = 3, bounds = { min = 0 } },
}
return M
