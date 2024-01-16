test_that("list index and length works", {
    lua("x = luajr.list()")
    lua("x[1] = 1")
    lua("x[2] = 0")
    lua("x.three = 0")
    lua("x.four = 4")
    lua("x[2] = 2")
    lua("x[3] = 3")
    expect_identical(lua("return #x"), 4)
    lua("x.three = nil")
    expect_identical(lua("return #x"), 3)
    lua("x[1] = nil")
    expect_identical(lua("return #x"), 2)
    expect_identical(lua("return x"), list(2, four = 4))

    expect_identical(lua("return x[1]"), 2)
    expect_identical(lua("return x[2]"), 4)
    expect_identical(lua("return x.four"), 4)
    expect_null(lua("return x[3]"))
    expect_null(lua("return x[4]"))

    lua_reset()
})

test_that("list attributes work", {
    lua("x = luajr.list()")
    lua("x.a = 'eh'")
    lua("x.b = 'be'")

    lua("x('at1', luajr.logical_r({ true }))")
    lua("x('at2', luajr.integer_r({ 1 }))")
    lua("x('at3', luajr.numeric_r({ 0.5 }))")
    lua("x('at4', luajr.character_r(3, 'hi'))")
    lua("x('at5', luajr.list())")

    x = lua("return x")
    expect_mapequal(attributes(x), list(at1 = TRUE, at2 = 1, at3 = 0.5,
        at4 = rep("hi", 3), at5 = list(), names = c("a", "b")))

    lua_reset()
})
