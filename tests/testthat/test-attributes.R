test_that("attributes work", {
    x = TRUE; attr(x, 'a') = 1L;
    expect_identical(lua("x = luajr.logical(1, true);  x:set_attr('a', luajr.integer(1, 1));     return x"), x)

    x = 1L; attr(x, 'a') = 1;
    expect_identical(lua("x = luajr.integer(1, 1);     x:set_attr('a', luajr.numeric(1, 1));     return x"), x)

    x = 1; attr(x, 'a') = 'a';
    expect_identical(lua("x = luajr.numeric(1, 1);     x:set_attr('a', luajr.character(1, 'a')); return x"), x)

    x = 'a'; attr(x, 'a') = TRUE;
    expect_identical(lua("x = luajr.character(1, 'a'); x:set_attr('a', luajr.logical(1, true));  return x"), x)

    expect_identical(lua("return x:get_attr('a')"), TRUE)

    lua_reset()
})
