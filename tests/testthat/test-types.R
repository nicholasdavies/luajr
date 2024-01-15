test_that("returning R value types works", {
    expect_identical(lua("return luajr.logical(3, true)"), c(TRUE, TRUE, TRUE))
    expect_identical(lua("return luajr.integer({1, 2, 3})"), c(1L, 2L, 3L))
    expect_equal(lua("return luajr.numeric(1, math.pi)"), pi)
    expect_identical(lua("return luajr.character({ 'well', 'I', 'never', '!' })"), c("well", "I", "never", "!"))
    expect_identical(lua("local l = luajr.list(); l[1] = 'moo'; l.bar = 'bark'; l.baz = luajr.numeric({1,2,3}); return l"),
        list("moo", bar = "bark", baz = c(1,2,3)))
})

test_that("returning R reference types works", {
    expect_identical(lua("return luajr.logical_r(1, false)"), FALSE)
    expect_identical(lua("return luajr.integer_r(2, 2)"), c(2L, 2L))
    expect_identical(lua("return luajr.numeric_r(2, 0.5)"), c(0.5, 0.5))
    expect_identical(lua("return luajr.character_r(3, 'hi')"), rep('hi', 3))
})

test_that("extra types work", {
    # luajr.dataframe
    lua("x = luajr.dataframe(2)")
    lua("x.l = luajr.logical({true, false})")
    lua("x.i = luajr.integer({1, 2})")
    lua("x.r = luajr.numeric({1.1, 2.2})")
    lua("x.c = luajr.character({'hi', 'lo'})")
    expect_identical(lua("return x"), data.frame(l = c(TRUE, FALSE), i = c(1L, 2L), r = c(1.1, 2.2), c = c("hi", "lo")))

    # luajr.matrix
    lua("x = luajr.matrix(3, 3)")
    lua("x[1] = 1")
    lua("x[5] = 1")
    lua("x[9] = 1")
    expect_identical(lua("return x"), diag(3))

    # luajr.datamatrix
    lua("x = luajr.datamatrix(3, 3, {'a', 'b', 'c'})")
    lua("x[1] = 1")
    lua("x[5] = 1")
    lua("x[9] = 1")
    eyes = diag(3)
    colnames(eyes) = letters[1:3]
    expect_identical(lua("return x"), eyes)

    lua_reset()
})
