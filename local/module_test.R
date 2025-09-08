library(luajr)

mymod = lua_module(file = "Lua/example.lua", package = "luajr")
greet = function(name) lua_import(mymod, "greet", "s")

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
mymod["x", "y", "z"]

mymod["x", "y", "z"] <- 1
mymod["x", "y"] <- 42
mymod["x", "y"]
mymod["x"]
mymod["x"] <- 1
mymod["x"]

mymod["x", as = "a"] <- 1
mymod["bah", as = "a"] <- 1
mymod["bah"]

mymod["koo"]
mymod["koo"] = "Janet"

greet("Nick")
greet("Janet")
greet("Nork")


# Here's the syntax I'd like to have for modules

# if code present, treat as Lua code
# if file present, treat as filename
# if package present, look for file in installed package
mymod = lua_module(code = "", file = "", package = "")
# this doesn't actually load anything until the first function is called
# that needs to be documented
# but that is so things can be loaded when the package is loaded, not "saved"
# to the package, which wouldn't work
# need to think about how a module would be opened in a specific state.
# R code may want to share a module with Lua code.

# suppose mymod contains two functions, times_two(x) and lua_sum_vector(v, init)

times_two = function(x) lua_import(mymod, "s")
sum_vector = function(v, init = 0) lua_import(mymod, "r1", "lua_sum_vector")

sum_vector(1:5, 0)

# or should that be lua_call
# I think we could have lua_call, for which the call chain would be e.g.
# sum_vector -> lua_call -> .Call(...), or lua_import which would overwrite
# the function so it would be sum_vector -> .Call(...) for less overhead

test_import = function(module, argcode, name = NULL)
{
    thing = sys.call(1)
    print(thing)
    thing = sys.call(0)
    print(thing)
    thing = sys.call(-1) ##
    print(thing)
    thing = sys.call(-2)
    print(thing)
}

test_func = function(x) { test_import() }

test_func(2)


# could also have
lua_bind(R_name, Lua_name, L_or_module)
