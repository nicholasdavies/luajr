test_that("empty environment construction works", {
    lua("e = luajr.environment()")
    expect_identical(lua("return #e:ls()"), 0)

    lua_reset()
})

test_that("environment from SEXP works", {
    lua("R = require('R')")
    lua("e = luajr.environment(R.GlobalEnv)")
    expect_true(lua("return luajr.is_environment(e)"))

    lua_reset()
})

test_that("environment from namespace string works", {
    lua("e = luajr.environment('base')")
    expect_true(lua("return luajr.is_environment(e)"))
    # base namespace should have many entries
    expect_true(lua("return #e:ls() > 100"))

    lua_reset()
})

test_that("environment get/set/exists/remove work", {
    lua("e = luajr.environment()")

    # initially empty
    expect_false(lua("return e:exists('x')"))
    expect_null(lua("return e:get('x')"))

    # set and get a numeric
    lua("e:set('x', luajr.numeric({1, 2, 3}))")
    expect_true(lua("return e:exists('x')"))
    expect_identical(lua("return e:get('x')"), c(1, 2, 3))

    # set and get a string scalar
    lua("e:set('msg', 'hello')")
    expect_identical(lua("return e:get('msg')"), "hello")

    # set and get a boolean scalar
    lua("e:set('flag', true)")
    expect_identical(lua("return e:get('flag')"), TRUE)

    # set and get a number scalar
    lua("e:set('pi', 3.14)")
    expect_identical(lua("return e:get('pi')"), 3.14)

    # overwrite existing
    lua("e:set('x', luajr.integer({10, 20}))")
    expect_identical(lua("return e:get('x')"), c(10L, 20L))

    # remove
    lua("e:remove('x')")
    expect_false(lua("return e:exists('x')"))
    expect_null(lua("return e:get('x')"))

    # other variables unaffected
    expect_true(lua("return e:exists('msg')"))

    lua_reset()
})

test_that("environment set with NULL value is retrievable", {
    lua("e = luajr.environment()")
    lua("e:set('x', nil)")
    expect_true(lua("return e:exists('x')"))
    # from_sexp returns R.NilValue for NILSXP, which round-trips as R NULL
    expect_null(lua("return e:get('x')"))

    lua_reset()
})

test_that("environment ls works", {
    lua("e = luajr.environment()")
    lua("e:set('alpha', 1)")
    lua("e:set('beta', 2)")
    lua("e:set('gamma', 3)")
    lua("e:set('.delta', 4)")
    r = lua("return e:ls()")
    expect_identical(length(r), 3L)
    expect_true(all(c("alpha", "beta", "gamma") %in% r))

    lua_reset()
})

test_that("environment get_parent and set_parent work", {
    lua("parent = luajr.environment()")
    lua("child = luajr.environment()")
    lua("child:set_parent(parent)")
    lua("parent:set('x', 42)")

    # get_parent returns an environment
    expect_true(lua("return luajr.is_environment(child:get_parent())"))

    lua_reset()
})

test_that("environment get retrieves functions", {
    lua("e = luajr.environment('base')")
    lua("f = e:get('sum')")
    expect_true(lua("return luajr.is_rfunction(f)"))

    lua_reset()
})

test_that("environment get retrieves lists", {
    lua("e = luajr.environment()")
    lua("local l = luajr.list(); l:push_back(42); e:set('mylist', l)")
    expect_identical(lua("return e:get('mylist')"), list(42))

    lua_reset()
})

test_that("environment __newindex errors", {
    expect_error(lua("local e = luajr.environment(); e.x = 1"))

    lua_reset()
})

test_that("invalid environment construction errors", {
    expect_error(lua("luajr.environment(123)"))

    lua_reset()
})

test_that("R environment passed via '&.' argcode arrives as environment", {
    f = lua_func("function(e) return luajr.is_environment(e) end", "&.")
    expect_true(f(new.env(parent = emptyenv())))

    lua_reset()
})

test_that("R environment passed via 'E' argcode is usable", {
    e = new.env(parent = emptyenv())
    e$x = 42
    f = lua_func("function(e) return e:get('x') end", "E")
    expect_identical(f(e), 42)

    lua_reset()
})

test_that("R environment round-trips via '&E' argcode", {
    e = new.env(parent = emptyenv())
    e$x = "hello"
    f = lua_func("function(e) return e end", "&E")
    r = f(e)
    expect_identical(r$x, "hello")

    lua_reset()
})

test_that("environment set from Lua is visible in R", {
    e = new.env(parent = emptyenv())
    f = lua_func("function(e) e:set('y', 99) end", ".")
    f(e)
    expect_identical(e$y, 99)

    lua_reset()
})
