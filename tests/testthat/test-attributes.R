test_that("attributes work", {
    x = TRUE; attr(x, 'a') = 1L;
    expect_identical(lua("x = luajr.logical_r(1, true);  x('a', luajr.integer_r(1, 1));     return x"), x)

    x = 1L; attr(x, 'a') = 1;
    expect_identical(lua("x = luajr.integer_r(1, 1);     x('a', luajr.numeric_r(1, 1));     return x"), x)

    x = 1; attr(x, 'a') = 'a';
    expect_identical(lua("x = luajr.numeric_r(1, 1);     x('a', luajr.character_r(1, 'a')); return x"), x)

    x = 'a'; attr(x, 'a') = TRUE;
    expect_identical(lua("x = luajr.character_r(1, 'a'); x('a', luajr.logical_r(1, true));  return x"), x)

    expect_identical(lua("return x('a')"), TRUE)

    lua_reset()
})
