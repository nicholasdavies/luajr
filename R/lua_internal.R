# Access to Lua API

lua_gettop = function(L = NULL) .Call(`_luajr_lua_gettop`, L)
