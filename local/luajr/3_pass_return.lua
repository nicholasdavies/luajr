----------------------------------
-- 5. PASS TO / RETURN FROM LUA --
----------------------------------

-- Pass to Lua

-- Construct a list. Called with:
--   elements = table (integer keys, 1 to n) with elements to hold
--   names = table, e.g. { foo = 1, bar = 3 } if 1st and 3rd elements are named
luajr.construct_list = function(elements, names)
    local list = { [0] = elements }
    list[0].names = names
    setmetatable(list, mt_list)
    return list
end

-- Return from Lua

-- Called from the LUA_TTABLE branch of luajr_tosexp (push_to.cpp). Only
-- reached for real Lua tables, so the only relevant case is detecting whether
-- the table is a luajr list. Returns R.VECSXP + #obj for a luajr list, or
-- nil, nil for a plain Lua table.
function luajr.return_info(obj)
    if luajr.is_list(obj) then return R.VECSXP, #obj end
    return nil, nil
end


