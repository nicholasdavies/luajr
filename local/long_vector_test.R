# Do long vectors work?

library(luajr)

biggie = rep(0L, 2^31)
func = lua_func("function(x) x[3] = 10 end", "r")
func(biggie)
