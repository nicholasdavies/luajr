# Benchmark: malloc vs R allocation in realistic push_back scenario
# This was a test to determine whether it was expensive to change from the old
# vector type (in luajr 0.2.2) which used malloc and free, to the new vector
# type which uses R allocation.
library(luajr)
library(bench)

# R equivalent: grow a vector with c() and sum it
pushback_R = function(N) {
    x = numeric(0)
    for (i in seq_len(N)) {
        x = c(x, i * 1.1)
    }
    sum(x)
}

setup_lua = function() {
    lua("R = require('R')")
    lua("
    local ffi = require('ffi')

    function pushback_malloc(N)
        local p = ffi.cast('double*', ffi.C.malloc(8))
        local n = 0
        local c = 1
        for i = 1, N do
            if n >= c then
                local new_c = c * 2
                local new_p = ffi.cast('double*', ffi.C.malloc(new_c * 8))
                ffi.C.memcpy(new_p, p, n * 8)
                ffi.C.free(p)
                p = new_p
                c = new_c
            end
            p[n] = i * 1.1
            n = n + 1
        end
        local sum = 0.0
        for i = 0, n - 1 do sum = sum + p[i] end
        ffi.C.free(p)
        return sum
    end

    function pushback_r(N)
        local s = R.allocVector(R.REALSXP, 1)
        R.PreserveObject(s)
        local p = R.REAL(s)
        local n = 0
        local c = 1
        for i = 1, N do
            if n >= c then
                local new_c = c * 2
                local new_s = R.allocVector(R.REALSXP, new_c)
                R.PreserveObject(new_s)
                local new_p = R.REAL(new_s)
                ffi.C.memcpy(new_p, p, n * 8)
                R.ReleaseObject(s)
                s = new_s
                p = new_p
                c = new_c
            end
            p[n] = i * 1.1
            n = n + 1
        end
        local sum = 0.0
        for i = 0, n - 1 do sum = sum + p[i] end
        R.ReleaseObject(s)
        return sum
    end
    ")
}

for (N in c(100L, 1000L, 10000L, 100000L)) {
    cat(sprintf("\n--- N = %d (reallocs ~ %d) ---\n", N, ceiling(log2(N))))

    lua_reset(); setup_lua()
    do_malloc = lua_func("pushback_malloc"); do_r = lua_func("pushback_r")
    lua_mode(jit = "on")
    r1 = bench::mark(lua_malloc_jit = do_malloc(N), min_iterations = 5, check = FALSE)

    lua_reset(); setup_lua()
    do_malloc = lua_func("pushback_malloc"); do_r = lua_func("pushback_r")
    lua_mode(jit = "off")
    r2 = bench::mark(lua_malloc_nojit = do_malloc(N), min_iterations = 5, check = FALSE)

    lua_reset(); setup_lua()
    do_malloc = lua_func("pushback_malloc"); do_r = lua_func("pushback_r")
    lua_mode(jit = "on")
    r3 = bench::mark(lua_Ralloc_jit = do_r(N), min_iterations = 5, check = FALSE)

    lua_reset(); setup_lua()
    do_malloc = lua_func("pushback_malloc"); do_r = lua_func("pushback_r")
    lua_mode(jit = "off")
    r4 = bench::mark(lua_Ralloc_nojit = do_r(N), min_iterations = 5, check = FALSE)

    r5 = bench::mark(R_c = pushback_R(N), min_iterations = 5, check = FALSE)

    print(rbind(r1, r2, r3, r4, r5)[, c("expression", "min", "median", "gc/sec", "itr/sec", "mem_alloc")])
}
