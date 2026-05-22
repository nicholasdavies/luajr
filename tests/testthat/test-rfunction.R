test_that("rfunction from SEXP is callable", {
    lua("R = require('R')")
    # Pass mean as bare SEXP, wrap in rfunction, call it from Lua, return result
    f = lua_func("function(x) local m = luajr.rfunction(x); return m(luajr.numeric({1, 2, 3, 4, 5})) end", "S")
    expect_identical(f(mean), 3)

    lua_reset()
})

test_that("rfunction from string looks up in global env", {
    lua("f = luajr.rfunction('mean')")
    expect_true(lua("return luajr.is_rfunction(f)"))
    expect_identical(lua("return f(luajr.numeric({1, 2, 3}))"), 2)

    lua_reset()
})

test_that("rfunction from string with namespace env", {
    lua("f = luajr.rfunction('sum', 'base')")
    expect_true(lua("return luajr.is_rfunction(f)"))
    expect_identical(lua("return f(luajr.numeric({1, 2, 3}))"), 6)

    lua_reset()
})

test_that("rfunction with multiple arguments", {
    lua("f = luajr.rfunction('paste0')")
    expect_identical(lua("return f('hello', ' ', 'world')"), "hello world")

    lua_reset()
})

test_that("rfunction with no arguments", {
    lua("f = luajr.rfunction('Sys.time')")
    r = lua("return f()")
    expect_true(inherits(r, "POSIXct"))

    lua_reset()
})

test_that("rfunction returns vector types correctly", {
    lua("f = luajr.rfunction('seq_len')")
    expect_identical(lua("return f(5)"), 1:5)

    lua_reset()
})

test_that("rfunction returns list correctly", {
    lua("f = luajr.rfunction('list')")
    expect_identical(lua("return f(1, 'two', true)"), list(1, "two", TRUE))

    lua_reset()
})

test_that("rfunction callable from Lua repeatedly", {
    lua("f = luajr.rfunction('sqrt')")
    lua("results = luajr.numeric(3)")
    lua("for i = 1, 3 do results[i] = f(luajr.numeric({i * i}))[1] end")
    expect_identical(lua("return results"), c(1, 2, 3))

    lua_reset()
})

test_that("rfunction with vector argument", {
    lua("f = luajr.rfunction('sum')")
    expect_identical(lua("return f(luajr.numeric({10, 20, 30}))"), 60)

    lua_reset()
})

test_that("rfunction invalid construction errors", {
    expect_error(lua("luajr.rfunction(123)"))

    lua_reset()
})

test_that("rfunction from SEXP rejects non-function", {
    expect_error(lua("luajr.rfunction(luajr.numeric({1, 2, 3}).s)"))

    lua_reset()
})

test_that("rfunction retrieved from environment is callable", {
    lua("e = luajr.environment('stats')")
    lua("f = e:get('median')")
    expect_identical(lua("return f(luajr.numeric({1, 2, 3, 4, 5}))"), 3)

    lua_reset()
})

test_that("R function passed via '&.' argcode arrives as rfunction", {
    f = lua_func("function(fn) return luajr.is_rfunction(fn) end", "&.")
    expect_true(f(mean))

    lua_reset()
})

test_that("R function passed via '.' argcode is callable", {
    f = lua_func("function(fn) return fn(luajr.numeric({1, 2, 3})) end", ".")
    expect_identical(f(sum), 6)

    lua_reset()
})

test_that("R function round-trips via '!F' argcode", {
    f = lua_func("function(fn) return fn end", "!F")
    r = f(mean)
    expect_identical(r(1:10), 5.5)

    lua_reset()
})

test_that("rfunction :call with only positional args matches __call", {
    lua("f = luajr.rfunction('sum')")
    expect_identical(
        lua("return f:call({luajr.numeric({1, 2, 3})})"),
        lua("return f(luajr.numeric({1, 2, 3}))")
    )

    lua_reset()
})

test_that("rfunction :call with named args reaches R", {
    lua("f = luajr.rfunction('paste')")
    expect_identical(lua("return f:call({'a', 'b', sep='-'})"), "a-b")
    expect_identical(lua("return f:call({'a', 'b', 'c', sep='|'})"), "a|b|c")

    lua_reset()
})

test_that("rfunction :call with named args interleaved (positional order preserved)", {
    # In Lua, {'a', sep='-', 'b'} still gives 'a' integer key 1, 'b' integer key 2.
    lua("f = luajr.rfunction('paste')")
    expect_identical(lua("return f:call({'a', sep='-', 'b'})"), "a-b")

    lua_reset()
})

test_that("rfunction :call with na.rm named arg changes behaviour", {
    lua("f = luajr.rfunction('sum')")
    # NA in the input: na.rm=false (default) gives NA, na.rm=true skips it.
    # Lua identifiers can't contain '.', so the named key uses bracket syntax.
    expect_true(is.na(lua("return f:call({luajr.numeric({1, 2, luajr.NA_real_})})")))
    expect_identical(lua("return f:call({luajr.numeric({1, 2, luajr.NA_real_}), ['na.rm']=true})"), 3)

    lua_reset()
})

test_that("rfunction :call with luajr.environment as eval env", {
    lua("f = luajr.rfunction('sum')")
    lua("e = luajr.environment()")
    expect_identical(lua("return f:call({luajr.numeric({1, 2, 3})}, e)"), 6)

    lua_reset()
})

test_that("rfunction :call with bare R.GlobalEnv as eval env", {
    lua("R = require('R')")
    lua("f = luajr.rfunction('sum')")
    expect_identical(lua("return f:call({luajr.numeric({1, 2, 3})}, R.GlobalEnv)"), 6)

    lua_reset()
})

test_that("rfunction :call with empty args table", {
    lua("f = luajr.rfunction('Sys.time')")
    r = lua("return f:call({})")
    expect_true(inherits(r, "POSIXct"))

    lua_reset()
})

test_that("rfunction :call errors on out-of-range integer key", {
    lua("f = luajr.rfunction('paste0')")
    expect_error(lua("return f:call({[3] = 'x'})"))

    lua_reset()
})

test_that("rfunction :call errors on non-string non-integer key", {
    lua("f = luajr.rfunction('paste0')")
    expect_error(lua("return f:call({[true] = 'y'})"))

    lua_reset()
})

test_that("rfunction :call errors when env arg is not an environment", {
    lua("f = luajr.rfunction('sum')")
    expect_error(lua("return f:call({luajr.numeric({1, 2, 3})}, luajr.numeric({1}))"))

    lua_reset()
})

test_that("rfunction __call (positional varargs) supports many positional args", {
    # Sanity: the __call path now wraps {...} into a table.
    lua("f = luajr.rfunction('paste0')")
    expect_identical(lua("return f('a', 'b', 'c', 'd', 'e')"), "abcde")

    lua_reset()
})
