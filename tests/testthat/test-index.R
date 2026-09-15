test_that("reading within range gives the element, truncating fractions", {
    lua("x = luajr.numeric({10, 20, 30})")
    expect_identical(lua("return x[1]"), 10)
    expect_identical(lua("return x[3]"), 30)
    expect_identical(lua("return x[2.7]"), 20)
    expect_identical(lua("return x[3.999]"), 30)

    lua_reset()
})

test_that("reading out of range is an error", {
    lua("x = luajr.numeric({10, 20, 30})")
    expect_error(lua("return x[0]"), "subscript out of bounds")
    expect_error(lua("return x[0.5]"), "subscript out of bounds")
    expect_error(lua("return x[-1]"), "subscript out of bounds")
    expect_error(lua("return x[4]"), "subscript out of bounds")
    expect_error(lua("return x[0/0]"), "subscript out of bounds")
    expect_error(lua("return luajr.numeric()[1]"), "subscript out of bounds")

    lua_reset()
})

test_that("writing within range sets the element, truncating fractions", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x[2] = 99")
    lua("x[3.5] = 77")
    expect_identical(lua("return x"), c(10, 99, 77))

    lua_reset()
})

test_that("writing within range to an argument leaves the caller's vector unchanged", {
    f = lua_func("function(x) x[2] = 99; return x end", "N")
    v = c(1, 2, 3)
    expect_identical(f(v), c(1, 99, 3))
    expect_identical(v, c(1, 2, 3))

    lua_reset()
})

test_that("writing past the end grows the vector as R's [[<- does", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x[5] = 9")
    x = c(10, 20, 30)
    x[[5]] = 9
    expect_identical(lua("return x"), x)

    lua("y = luajr.numeric({10, 20, 30})")
    lua("y[4] = 9")
    expect_identical(lua("return y"), c(10, 20, 30, 9))

    lua("z = luajr.numeric({10, 20, 30})")
    lua("z[4.5] = 9")
    expect_identical(lua("return z"), c(10, 20, 30, 9))

    lua("e = luajr.numeric()")
    lua("e[3] = 1")
    expect_identical(lua("return e"), c(NA, NA, 1))

    lua_reset()
})

test_that("writing past the end fills the gap with the type's NA", {
    lua("x = luajr.integer({1})")
    lua("x[3] = 5")
    expect_identical(lua("return x"), c(1L, NA, 5L))

    lua("x = luajr.logical({true})")
    lua("x[3] = false")
    expect_identical(lua("return x"), c(TRUE, NA, FALSE))

    lua("x = luajr.character({'a'})")
    lua("x[3] = 'c'")
    expect_identical(lua("return x"), c("a", NA, "c"))

    lua("x = luajr.list()")
    lua("x:push_back(1)")
    lua("x[3] = 'z'")
    l = list(1)
    l[[3]] = "z"
    expect_identical(lua("return x"), l)

    lua_reset()
})

test_that("writing past the end gives the new elements blank names", {
    lua("x = luajr.numeric({1, 2})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x[4] = 9")
    x = c(a = 1, b = 2)
    x[[4]] = 9
    expect_identical(lua("return x"), x)

    lua_reset()
})

test_that("writing past the end of an argument leaves the caller's vector unchanged", {
    f = lua_func("function(x) x[5] = 9; return x end", "N")
    v = c(1, 2, 3)
    expect_identical(f(v), c(1, 2, 3, NA, 9))
    expect_identical(v, c(1, 2, 3))

    lua_reset()
})

test_that("appending repeatedly grows the capacity geometrically", {
    lua("x = luajr.numeric()")
    lua("for i = 1, 1000 do x[#x + 1] = i end")
    expect_identical(lua("return x"), as.numeric(1:1000))
    expect_true(lua("return x:capacity()") <= 2000)

    lua_reset()
})

test_that("writing below 1, with NaN or with a non-number key is an error", {
    lua("x = luajr.numeric({10, 20, 30})")
    expect_error(lua("x[0] = 1"), "subscript out of bounds")
    expect_error(lua("x[0.5] = 1"), "subscript out of bounds")
    expect_error(lua("x[-1] = 1"), "subscript out of bounds")
    expect_error(lua("x[0/0] = 1"), "subscript out of bounds")
    expect_error(lua("x['a'] = 1"), "cannot index vector with type string")
    expect_error(lua("x[true] = 1"), "cannot index vector with type boolean")
    expect_identical(lua("return x"), c(10, 20, 30))

    lua_reset()
})

test_that("writing past the end of a vector passed by reference is an error", {
    f = lua_func("function(x) x[5] = 9 end", "&N")
    v = c(1, 2, 3)
    expect_error(f(v), "cannot grow a vector passed by reference")
    expect_identical(v, c(1, 2, 3))

    lua_reset()
})
