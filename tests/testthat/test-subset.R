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

test_that("__call truncates a fractional index", {
    expect_identical(lua("return luajr.numeric({10, 20, 30})(3.5)"), 30)
    expect_identical(lua("return luajr.numeric({10, 20, 30})(2.7)"), 20)

    lua_reset()
})

test_that("__call with a value sets an element as R's [<- does", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x(2, 99)")
    lua("x(3.5, 77)")
    x = c(10, 20, 30)
    x[2] = 99
    x[3.5] = 77
    expect_identical(lua("return x"), x)

    lua_reset()
})

test_that("__call with a value past the end grows the vector as R's [<- does", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x(5, 9)")
    x = c(10, 20, 30)
    x[5] = 9
    expect_identical(lua("return x"), x)

    lua("y = luajr.character({'a'})")
    lua("y(3, 'c')")
    y = "a"
    y[3] = "c"
    expect_identical(lua("return y"), y)

    lua_reset()
})

test_that("__call with a value and index 0, a fraction below 1 or NaN changes nothing", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x(0, 9)")
    lua("x(0.5, 9)")
    lua("x(-0.5, 9)")
    lua("x(0/0, 9)")
    x = c(10, 20, 30)
    x[0] = 9
    x[0.5] = 9
    x[-0.5] = 9
    x[NA_real_] = 9
    expect_identical(lua("return x"), x)

    lua_reset()
})

test_that("__call with a value and a negative index is an error", {
    lua("x = luajr.numeric({10, 20, 30})")
    expect_error(lua("x(-1, 9)"), "negative indexes are not supported yet")
    expect_error(lua("x(true, 9)"), "cannot subset vector with type boolean")
    expect_identical(lua("return x"), c(10, 20, 30))

    lua_reset()
})

test_that("__call with a value sets an element by name as R's [<- does", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'a'}))")
    lua("x('a', 1)")
    lua("x('z', 2)")
    x = c(a = 10, b = 20, a = 30)
    x["a"] = 1
    x["z"] = 2
    expect_identical(lua("return x"), x)

    lua("y = luajr.numeric({1, 2})")
    lua("y('z', 9)")
    y = c(1, 2)
    y["z"] = 9
    expect_identical(lua("return y"), y)

    lua_reset()
})

test_that("__call with a value sets a list element to NULL", {
    lua("x = luajr.list()")
    lua("for i = 1, 3 do x:push_back(i) end")
    lua("x(2, luajr.NULL)")
    l = list(1, 2, 3)
    l[2] = list(NULL)
    expect_identical(lua("return x"), l)

    lua_reset()
})

test_that("__call with a value on an argument leaves the caller's vector unchanged", {
    f = lua_func("function(x) x(2, 99); x(4, 1); return x end", "N")
    v = c(1, 2, 3)
    expect_identical(f(v), c(1, 99, 3, 1))
    expect_identical(v, c(1, 2, 3))

    lua_reset()
})
