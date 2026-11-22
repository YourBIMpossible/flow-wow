local _, ns = ...
ns:Module({
    name = "m",
    settings = { { key = "m.own", scope = "char", type = "bool", default = true } },
    ticks = { { every = 1, run = function(ctx) return ctx.settings:get("m.own") end } },
})
local function arrow(k) k:Setting({ key = "arrow.layout", scope = "account", type = "table" }); return k.settings:get("arrow.layout") end
return arrow
