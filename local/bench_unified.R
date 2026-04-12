# Benchmark: new unified (v4) vs old vector types
library(luajr)
library(bench)

setup_lua = function() {
    lua("
    local luajr = require('luajr')

    -- NUMERIC benchmarks
    function bench_write_old(N)
        local v = luajr.numeric(N, 0)
        for i = 1, N do v[i] = i * 1.1 end
        return v[N]
    end
    function bench_write_new(N)
        local v = luajr.numeric4(N, 0)
        for i = 1, N do v[i] = i * 1.1 end
        return v[N]
    end

    function bench_read_old(N)
        local v = luajr.numeric(N, 1.1)
        local sum = 0
        for i = 1, N do sum = sum + v[i] end
        return sum
    end
    function bench_read_new(N)
        local v = luajr.numeric4(N, 1.1)
        local sum = 0
        for i = 1, N do sum = sum + v[i] end
        return sum
    end

    function bench_pushback_old(N)
        local v = luajr.numeric()
        for i = 1, N do v:push_back(i * 1.1) end
        return v[N]
    end
    function bench_pushback_new(N)
        local v = luajr.numeric4()
        for i = 1, N do v:push_back(i * 1.1) end
        return v[N]
    end

    function bench_pairs_old(N)
        local v = luajr.numeric(N, 1.1)
        local sum = 0
        for k, val in pairs(v) do sum = sum + val end
        return sum
    end
    function bench_pairs_new(N)
        local v = luajr.numeric4(N, 1.1)
        local sum = 0
        for k, val in pairs(v) do sum = sum + val end
        return sum
    end

    -- CHARACTER benchmarks
    function bench_char_write_old(N)
        local v = luajr.character(N, 'x')
        for i = 1, N do v[i] = 'y' end
        return v[N]
    end
    function bench_char_write_new(N)
        local v = luajr.character4(N, 'x')
        for i = 1, N do v[i] = 'y' end
        return v[N]
    end

    function bench_char_read_old(N)
        local v = luajr.character(N, 'hello')
        local last
        for i = 1, N do last = v[i] end
        return last
    end
    function bench_char_read_new(N)
        local v = luajr.character4(N, 'hello')
        local last
        for i = 1, N do last = v[i] end
        return last
    end

    function bench_char_pushback_old(N)
        local v = luajr.character()
        for i = 1, N do v:push_back('item') end
        return v[N]
    end
    function bench_char_pushback_new(N)
        local v = luajr.character4()
        for i = 1, N do v:push_back('item') end
        return v[N]
    end

    function bench_char_pairs_old(N)
        local v = luajr.character(N, 'hello')
        local last
        for k, val in pairs(v) do last = val end
        return last
    end
    function bench_char_pairs_new(N)
        local v = luajr.character4(N, 'hello')
        local last
        for k, val in pairs(v) do last = val end
        return last
    end
    ")
}

run_bench = function(N, label, ...) {
    names = list(...)
    funcs = lapply(names, lua_func)
    cat(sprintf("\n=== %s ===\n", label))
    exprs = lapply(seq_along(funcs), function(i) bquote(.(funcs[[i]])(N)))
    names(exprs) = names
    print(do.call(bench::mark, c(exprs, list(min_iterations = 5, check = FALSE))))
}

jits = c("on", "off")

for (jit in jits) {
    cat(sprintf("\n\n########## JIT %s ##########\n", jit))
    lua_reset()
    setup_lua()
    lua_mode(jit = jit)

    run_bench(10000L, "Numeric write",     "bench_write_old",    "bench_write_new")
    run_bench(10000L, "Numeric read",      "bench_read_old",     "bench_read_new")
    run_bench(10000L, "Numeric push_back", "bench_pushback_old", "bench_pushback_new")
    run_bench(10000L, "Numeric pairs",     "bench_pairs_old",    "bench_pairs_new")

    run_bench(10000L, "Char write",     "bench_char_write_old",    "bench_char_write_new")
    run_bench(10000L, "Char read",      "bench_char_read_old",     "bench_char_read_new")
    run_bench(10000L, "Char push_back", "bench_char_pushback_old", "bench_char_pushback_new")
    run_bench(10000L, "Char pairs",     "bench_char_pairs_old",    "bench_char_pairs_new")
}
