test_that("numeric __call extracts single element", {
    lua("x = luajr.numeric({10, 20, 30})")
    expect_identical(lua("return x(1)"), 10)
    expect_identical(lua("return x(3)"), 30)

    lua_reset()
})

test_that("integer __call extracts single element", {
    lua("x = luajr.integer({10, 20, 30})")
    expect_identical(lua("return x(2)"), 20L)

    lua_reset()
})

test_that("logical __call extracts single element", {
    lua("x = luajr.logical({true, false, true})")
    expect_identical(lua("return x(2)"), FALSE)

    lua_reset()
})

test_that("character __call extracts single element", {
    lua("x = luajr.character({'a', 'b', 'c'})")
    expect_identical(lua("return x(2)"), "b")

    lua_reset()
})

test_that("numeric NA round-trips via __call", {
    lua("x = luajr.numeric({1, luajr.NA_real_, 3})")
    expect_identical(lua("return x(2)"), NA_real_)

    lua_reset()
})

test_that("integer NA round-trips via __call", {
    lua("x = luajr.integer({1, luajr.NA_integer_, 3})")
    expect_identical(lua("return x(2)"), NA_integer_)

    lua_reset()
})

test_that("logical NA round-trips via __call", {
    lua("x = luajr.logical({true, luajr.NA_logical_, false})")
    expect_identical(lua("return x(2)"), NA)

    lua_reset()
})

test_that("character NA round-trips via __call", {
    lua("x = luajr.character({'a', luajr.NA_character_, 'c'})")
    expect_identical(lua("return x(2)"), NA_character_)

    lua_reset()
})

test_that("__call out of bounds returns NA", {
    expect_identical(lua("return luajr.numeric({1, 2, 3})(10)"), NA_real_)
    expect_identical(lua("return luajr.integer({1, 2})(5)"), NA_integer_)
    expect_identical(lua("return luajr.logical({true})(2)"), NA)
    expect_identical(lua("return luajr.character({'a'})(3)"), NA_character_)

    lua_reset()
})

test_that("__call with named access works", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    expect_identical(lua("return x('b')"), c(b = 20))
    expect_identical(lua("return x('c')"), c(c = 30))

    lua_reset()
})

test_that("__call with named access returns NA for missing name", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    r = lua("return x('z')")
    expect_identical(unname(r), NA_real_)
    expect_true(is.na(names(r)))

    lua_reset()
})

test_that("__call NA round-trip through lua_func", {
    f = lua_func("function(x) return x(2) end", "N")
    expect_identical(f(c(1, NA_real_, 3)), NA_real_)

    f = lua_func("function(x) return x(2) end", "I")
    expect_identical(f(c(1L, NA_integer_, 3L)), NA_integer_)

    f = lua_func("function(x) return x(2) end", "L")
    expect_identical(f(c(TRUE, NA, FALSE)), NA)

    f = lua_func("function(x) return x(2) end", "C")
    expect_identical(f(c("a", NA_character_, "c")), NA_character_)

    lua_reset()
})

test_that("list __call extracts single element", {
    lua("x = luajr.list()")
    lua("x:push_back(42)")
    lua("x:push_back('hello')")
    lua("x:push_back(luajr.numeric({1, 2, 3}))")
    expect_identical(lua("return x(1)"), list(42))
    expect_identical(lua("return x(2)"), list("hello"))
    expect_identical(lua("return x(3)"), list(c(1, 2, 3)))

    lua_reset()
})

test_that("list __call out of bounds returns NULL", {
    lua("x = luajr.list()")
    lua("x:push_back(1)")
    expect_identical(lua("return x(5)"), list(NULL))

    lua_reset()
})
