test_that("modules work", {
    mymod = lua_module(file = "Lua/example.lua", package = "luajr")
    greets = function(name) lua_import(mymod, "greets", "s")

    expect_match(greets("Nick"), "Nice one")
    expect_match(greets("Janet"), "Hello, Janet!$")

    mymod["fave_name"] = "Nork"
    expect_identical(mymod["fave_name"], "Nork")
    expect_match(greets("Nork"), "Nice one")
    mymod["fave_name", as = "a"] = "Nork"
    expect_identical(mymod["fave_name"], list("Nork"))
})

test_that("module errors are caught", {
    mymod = lua_module(file = "Lua/example.lua", package = "luajr")
    expect_error(mymod["greet"] <- 0)
    expect_error(mymod["fave_name", 1] <- 0)

    greetl = function(name) lua_import(mymod, "greetl", "s")
    expect_error(greetl("Nick"))
})
