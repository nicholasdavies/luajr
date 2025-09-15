# Do long vectors work?

library(luajr)
library(data.table)
library(tibble)

biggie = rep(0L, 2^31)
func = lua_func("function(x) x[3] = 10; end", "r")
system.time(func(biggie))
biggie

alloc_bigr = lua_func("function(x) local x = luajr.numeric_r(2^34*1.5, 0) return x end", "r")
alloc_bigr()

alloc_bigv = lua_func("function(x) local x = luajr.numeric(2^38, 0) return x end", "r")
alloc_bigv()

hugelist = as.list(rep(1L, 2^27+1))
givelist = lua_func("function(x) end", "s")
givelist(hugelist)
rm(hugelist)

bigdata = list(big = biggie)
bigdata = data.frame(big = biggie) # doesn't work
bigdata = data.table(big = biggie) # doesn't work
bigdata = tibble(big = biggie) # doesn't work
