# Do long vectors work?

library(luajr)
library(data.table)
library(tibble)

biggie = rep(0L, 2^31)
func = lua_func("function(x) x[3] = 10; end", "&.")
system.time(func(biggie))
biggie

alloc_big = lua_func("function() local x = luajr.numeric(2^34*1.5, 0) return x end")
alloc_big()

hugelist = as.list(rep(1L, 2^27+1)) # beyond max size
givelist = lua_func("function(x) end", "$.")
givelist(hugelist)
rm(hugelist)

bigdata = list(big = biggie)
bigdata = data.frame(big = biggie) # doesn't work
bigdata = data.table(big = biggie) # doesn't work
bigdata = tibble(big = biggie) # doesn't work
