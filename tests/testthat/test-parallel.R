test_that("workers can be created and closed", {
    lua("pool = luajr.workers(2)")
    expect_identical(lua("return #pool"), 2)
    lua("pool:close()")

    lua_reset()
})

test_that("workers:srun passes arguments to workers", {
    lua("output = luajr.numeric(4, 0)")
    lua("pool = luajr.workers(4)")
    lua("pool:srun(function(output, thread_id) output[thread_id] = thread_id * 10 end, output)")
    expect_identical(lua("return output"), c(10, 20, 30, 40))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:srun with nil reuses preloaded function", {
    lua("output = luajr.numeric(2, 0)")
    lua("pool = luajr.workers(2)")
    lua("pool:preload(function(output, thread_id) output[thread_id] = output[thread_id] + 1 end, output)")
    lua("pool:srun()")
    lua("pool:srun()")
    expect_identical(lua("return output"), c(2, 2))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:srun transfers tables", {
    lua("pool = luajr.workers(2)")
    lua("output = luajr.numeric(2, 0)")
    lua("pool:srun(function(config, output, thread_id) output[thread_id] = config.scale * thread_id end, {scale = 5}, output)")
    expect_identical(lua("return output"), c(5, 10))
    lua("pool:close()")

    lua_reset()
})

test_that("workers ncores returns positive integer", {
    expect_true(lua("return luajr.ncores()") >= 1)

    lua_reset()
})

test_that("workers:prun runs function in each worker in parallel", {
    lua("output = luajr.numeric(4, 0)")
    lua("pool = luajr.workers(4)")
    lua("pool:prun(function(output, thread_id) output[thread_id] = thread_id * 10 end, output)")
    r = lua("return output")
    expect_identical(sort(r), c(10, 20, 30, 40))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:prun with nil reuses preloaded function", {
    lua("output = luajr.numeric(2, 0)")
    lua("pool = luajr.workers(2)")
    lua("pool:preload(function(output, thread_id) output[thread_id] = output[thread_id] + 1 end, output)")
    lua("pool:prun()")
    lua("pool:prun()")
    expect_identical(lua("return output"), c(2, 2))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:pfor distributes work across workers", {
    lua("output = luajr.numeric(100, 0)")
    lua("pool = luajr.workers(4)")
    lua("pool:pfor(1, 100, function(i, output) output[i] = i * 2 end, output)")
    r = lua("return output")
    expect_identical(r, (1:100) * 2)
    lua("pool:close()")

    lua_reset()
})

test_that("workers:pfor with nil reuses preloaded function", {
    lua("output = luajr.numeric(10, 0)")
    lua("pool = luajr.workers(2)")
    lua("pool:preload(function(i, output) output[i] = i end, output)")
    lua("pool:pfor(1, 5)")
    lua("pool:pfor(6, 10)")
    expect_identical(lua("return output"), as.numeric(1:10))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:pfor passes thread_id as last arg", {
    lua("output = luajr.numeric(20, 0)")
    lua("thread_ids = luajr.numeric(20, 0)")
    lua("pool = luajr.workers(4)")
    lua("pool:pfor(1, 20, function(i, output, thread_ids, thread_id) output[i] = i; thread_ids[i] = thread_id end, output, thread_ids)")
    expect_identical(lua("return output"), as.numeric(1:20))
    tids = lua("return thread_ids")
    expect_true(all(tids >= 1 & tids <= 4))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:srun can load modules then pfor uses them", {
    lua("output = luajr.numeric(10, 0)")
    lua("pool = luajr.workers(2)")
    lua("pool:srun(function(thread_id) ffi = require('ffi') end)")
    lua("pool:pfor(1, 10, function(i, output) local x = ffi.new('double[1]', i * 3); output[i] = x[0] end, output)")
    expect_identical(lua("return output"), (1:10) * 3)
    lua("pool:close()")

    lua_reset()
})

test_that("workers:pfor with single worker works", {
    lua("output = luajr.numeric(10, 0)")
    lua("pool = luajr.workers(1)")
    lua("pool:pfor(1, 10, function(i, output) output[i] = i * i end, output)")
    expect_identical(lua("return output"), as.numeric((1:10)^2))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:srun recovers from error", {
    lua("pool = luajr.workers(2)")
    lua("output = luajr.numeric(2, 0)")
    expect_error(lua("pool:srun(function(thread_id) error('test error') end)"))
    # Pool should be usable after error (stacks cleared, need to preload again)
    lua("pool:srun(function(output, thread_id) output[thread_id] = thread_id end, output)")
    expect_identical(lua("return output"), c(1, 2))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:prun recovers from error", {
    lua("pool = luajr.workers(2)")
    lua("output = luajr.numeric(2, 0)")
    expect_error(lua("pool:prun(function(thread_id) error('test error') end)"))
    # Pool should be usable after error
    lua("pool:prun(function(output, thread_id) output[thread_id] = thread_id * 10 end, output)")
    r = lua("return output")
    expect_identical(sort(r), c(10, 20))
    lua("pool:close()")

    lua_reset()
})

test_that("workers:pfor recovers from error", {
    lua("pool = luajr.workers(2)")
    lua("output = luajr.numeric(10, 0)")
    expect_error(lua("pool:pfor(1, 10, function(i) error('test error') end)"))
    # Pool should be usable after error
    lua("pool:pfor(1, 10, function(i, output) output[i] = i end, output)")
    expect_identical(lua("return output"), as.numeric(1:10))
    lua("pool:close()")

    lua_reset()
})

