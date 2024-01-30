test_that("parallel code works", {
    # This is just a basic test to ensure the features of lua_parallel() work
    # while its interface is still being developed.
    expect_identical(
        lua_parallel("test", n = 8, threads = 4, pre = "test = function(i) return i * 2 end"),
        as.list(c(2, 4, 6, 8, 10, 12, 14, 16))
    )

    thr = list(lua_open(), lua_open(), lua_open(), NULL)
    expect_identical(
        lua_parallel("test", n = 8, threads = thr, pre = "test = function(i) return i end"),
        as.list(c(1, 2, 3, 4, 5, 6, 7, 8))
    )
})
