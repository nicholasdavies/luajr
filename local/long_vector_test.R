# Do long vectors work?

library(luajr)
library(data.table)
library(tibble)

biggie = rep(0L, 2^31-1)
func = lua_func("function(x) x[3] = 10 end", "v")
system.time(func(biggie))
biggie

bigdata = data.frame(big = biggie) # doesn't work
bigdata = data.table(big = biggie) # doesn't work
bigdata = tibble(big = biggie) # doesn't work
