test_that("logical:is_na detects NA elements", {
    lua("x = luajr.logical({luajr.TRUE, luajr.NA_logical_, luajr.FALSE})")
    expect_false(lua("return x:is_na(1)"))
    expect_true (lua("return x:is_na(2)"))
    expect_false(lua("return x:is_na(3)"))

    lua_reset()
})

test_that("integer:is_na detects NA elements", {
    lua("x = luajr.integer({1, luajr.NA_integer_, 3})")
    expect_false(lua("return x:is_na(1)"))
    expect_true (lua("return x:is_na(2)"))
    expect_false(lua("return x:is_na(3)"))

    lua_reset()
})

test_that("numeric:is_na detects NA_real_", {
    lua("x = luajr.numeric({1.5, luajr.NA_real_, 3.5})")
    expect_false(lua("return x:is_na(1)"))
    expect_true (lua("return x:is_na(2)"))
    expect_false(lua("return x:is_na(3)"))

    lua_reset()
})

test_that("numeric:is_na also returns true for arbitrary NaN (matches R's is.na)", {
    lua("x = luajr.numeric({1.0, 0/0, 2.0})")
    expect_false(lua("return x:is_na(1)"))
    expect_true (lua("return x:is_na(2)"))
    expect_false(lua("return x:is_na(3)"))

    lua_reset()
})

test_that("character:is_na detects NA_character_", {
    lua("x = luajr.character({'a', luajr.NA_character_, 'c'})")
    expect_false(lua("return x:is_na(1)"))
    expect_true (lua("return x:is_na(2)"))
    expect_false(lua("return x:is_na(3)"))

    lua_reset()
})

test_that("list:is_na errors", {
    lua("x = luajr.list({1, 2, 3})")
    expect_error(lua("return x:is_na(1)"), "is_na is not defined for luajr.list")

    lua_reset()
})

test_that("is_na on a vector arriving from R with NAs", {
    f = lua_func("function(x) return x:is_na(2) end", ".")
    expect_true(f(c(1, NA, 3)))
    expect_true(f(c(1L, NA_integer_, 3L)))
    expect_true(f(c(TRUE, NA, FALSE)))
    expect_true(f(c("a", NA_character_, "c")))

    lua_reset()
})
