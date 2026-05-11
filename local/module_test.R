library(luajr)

mymod = lua_module(file = "Lua/example.lua", package = "luajr")
greet = function(name) lua_import(mymod, "greet", "$.")

mymod[]

meh = function() { greet("Hi") }
mah = function() { greet = function(...) cat("Sorry!\n"); meh() }
meh()
mah()

greet("Nick")
greet("Janet")

mymod["fave_name"]
mymod["fave_name"] = "Janet"
mymod["fave_name"]

greet("Nick")
greet("Janet")

mymod["fave_name"] = "Nork"
mymod["fave_name"]

greet("Nick")
greet("Nork")
greet("Janet")

mymod["x"]
mymod["x", "y"]
mymod["x", "y", "z"] # error

mymod["x", "y", "z"] <- 1 # error
mymod["x", "y"] <- 42
mymod["x", "y"]
mymod["x"]
mymod["x"] <- 1
mymod["x"]

mymod["x", as = "table"] <- 1
mymod["bah", as = "table"] <- 1
mymod[]
mymod["bah"]

mymod["koo"]
mymod["koo"] = "Janet"

greet("Nick")
greet("Janet")
greet("Nork")

