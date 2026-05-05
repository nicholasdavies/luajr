test_that("logical vector basics work", {
    lua("x = luajr.logical()")
    expect_equal(lua("return #x"), 0)

    lua("x = luajr.logical(5, luajr.TRUE)")
    expect_equal(lua("return #x"), 5)
    expect_equal(lua("return x[1]"), 1L)
    expect_equal(lua("return x[5]"), 1L)

    lua("x = luajr.logical({luajr.TRUE, luajr.FALSE, luajr.TRUE})")
    expect_equal(lua("return #x"), 3)
    expect_equal(lua("return x[1]"), 1L)
    expect_equal(lua("return x[2]"), 0L)

    lua_reset()
})

test_that("logical vector push_back and insert work", {
    lua("x = luajr.logical()")
    lua("for i = 1, 100 do x:push_back(i % 2 == 0 and luajr.TRUE or luajr.FALSE) end")
    expect_equal(lua("return #x"), 100)
    expect_equal(lua("return x[1]"), 0L)
    expect_equal(lua("return x[2]"), 1L)

    lua("y = luajr.logical({luajr.TRUE, luajr.FALSE, luajr.TRUE})")
    lua("y:insert(2, 2, luajr.FALSE)")
    expect_equal(lua("return #y"), 5)
    expect_equal(lua("return y[2]"), 0L)
    expect_equal(lua("return y[4]"), 0L)

    lua_reset()
})

test_that("logical vector NA values", {
    # Returning a single NA element doesn't round-trip as NA (it's INT_MIN as a double).
    # Test via the vector return path instead.
    expect_equal(lua_func("function(x) return x end", ".")(c(TRUE, NA, FALSE)),
                 c(TRUE, NA, FALSE))
    lua_reset()
})
