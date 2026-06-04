test_that("integer vector basics work", {
    lua("x = luajr.integer()")
    expect_equal(lua("return #x"), 0)

    lua("x = luajr.integer(5, 42)")
    expect_equal(lua("return #x"), 5)
    expect_equal(lua("return x[1]"), 42L)
    expect_equal(lua("return x[5]"), 42L)

    lua("x = luajr.integer({10, 20, 30})")
    expect_equal(lua("return #x"), 3)
    expect_equal(lua("return x[1]"), 10L)
    expect_equal(lua("return x[3]"), 30L)

    lua_reset()
})

test_that("integer vector truncation", {
    lua("x = luajr.integer(1, 0)")
    lua("x[1] = 7.9")
    expect_equal(lua("return x[1]"), 7L)
    lua_reset()
})

test_that("integer vector push_back and insert work", {
    lua("x = luajr.integer()")
    lua("for i = 1, 100 do x:push_back(i) end")
    expect_equal(lua("return #x"), 100)
    expect_equal(lua("return x[1]"), 1L)
    expect_equal(lua("return x[100]"), 100L)

    lua("y = luajr.integer({1, 2, 5})")
    lua("y:insert(3, 2, 0)")
    expect_equal(lua("return #y"), 5)
    expect_equal(lua("return y[3]"), 0L)
    expect_equal(lua("return y[5]"), 5L)

    lua_reset()
})

test_that("integer vector erase works", {
    # In-place erase exercises a tail shift in the same buffer, which is the
    # path that previously triggered an ASAN memcpy-overlap report.
    lua("x = luajr.integer({1,2,3,4,5,6,7,8,9,10})")
    lua("x:erase(1)")
    expect_equal(lua("return x:debug_str()"), "9|10|2,3,4,5,6,7,8,9,10")
    lua("x:erase(2,3)")
    expect_equal(lua("return x:debug_str()"), "7|10|2,5,6,7,8,9,10")
    lua("x:erase(5,7)")
    expect_equal(lua("return x:debug_str()"), "4|10|2,5,6,7")
    lua("x:erase(1,4)")
    expect_equal(lua("return x:debug_str()"), "0|10|")

    # Single-element erase from various positions, including the last.
    lua("y = luajr.integer({1,2,3,4,5})")
    lua("y:erase(5)")           # tail position, no shift
    expect_equal(lua("return y:debug_str()"), "4|5|1,2,3,4")
    lua("y:erase(1)")           # head, maximal shift
    expect_equal(lua("return y:debug_str()"), "3|5|2,3,4")
    lua("y:erase(2)")           # middle
    expect_equal(lua("return y:debug_str()"), "2|5|2,4")

    lua_reset()
})

test_that("integer vector NA values", {
    # Returning a single NA element doesn't round-trip as NA (it's INT_MIN as a double).
    # Test via the vector return path instead.
    expect_equal(lua_func("function(x) return x end", "&integer")(c(0L, NA_integer_, 0L)),
                 c(0L, NA_integer_, 0L))
    lua_reset()
})
