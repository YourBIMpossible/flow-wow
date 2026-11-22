-- The presence list: the merchant reads and the move key are asked about.
local _, ns = ...

local function has(list, name)
    for i = 1, #(list or {}) do
        if list[i] == name then return true end
    end
    return false
end

return {
    ["presence list: the merchant reads, the merchant namespace and the move key are listed"] = function(t)
        local D = ns.Diag
        t.ok(has(D.NAMES, "GetMerchantNumItems"), "GetMerchantNumItems")
        t.ok(has(D.NAMES, "GetMerchantItemLink"), "GetMerchantItemLink")
        t.ok(has(D.NAMES, "IsControlKeyDown"), "IsControlKeyDown")
        t.ok(has(D.NAMESPACES, "C_MerchantFrame"), "the members of C_MerchantFrame")
    end,
}
