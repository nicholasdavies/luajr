test_that("returning R value types works", {
    expect_identical(lua("return luajr.logical({true, false, false})"), c(TRUE, FALSE, FALSE))
    expect_identical(lua("return luajr.integer(10, 0)"), rep(0L, 10))
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
