test_that("SEXP round-trip works for language objects", {
    f = lua_func("function(x) return x end", "S")
    expr = quote(a + b * c)
    result = f(expr)
    expect_identical(result, expr)
})

test_that("SEXP preserves attributes on environment round-trip", {
    f = lua_func("function(x) return x end", "S")
    e = new.env(parent = emptyenv())
    e$x = 42
    attr(e, "custom") = "hello"
    result = f(e)
    expect_identical(attr(result, "custom"), "hello")
    expect_identical(result$x, 42)
})

test_that("SEXP can be inspected via R module", {
    lua("R = require('R')")
    # Types that naturally become SEXP (no dedicated R type)
    expect_identical(lua_func("function(x) return R.length(x) end", "S")(quote(a + b * c)), 3)
    expect_identical(lua_func("function(x) return R.length(x) end", "S")(as.name("foo")), 1)
    # Types that have dedicated R types
    expect_identical(lua_func("function(x) return R.length(x) end", "S")(1:10), 10)
    expect_identical(lua_func("function(x) return R.length(x) end", "S")(factor(letters)), 26)
})

test_that("SEXP works with function type", {
    f = lua_func("function(x) return x end", "S")
    result = f(mean)
    expect_identical(result(1:10), 5.5)
})
