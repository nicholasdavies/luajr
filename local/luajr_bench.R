# Time one luajr benchmark expression, or count the R object protection calls
# it makes from Lua.
# See "R object protection: release cost and a leak" in local/devnotes.txt.
#
# Usage, from the luajr directory: Rscript local/luajr_bench.R <name> time|count
#   name: sum_L, logistic_map_L, lorenz2, sum2_r_v1, sum2_v_v1, sum2_s_v1,
#         sum2_v_v4, read_loop, write_cdata_loop, ctor_loop
# Set R_HASH_PRECIOUS=TRUE in the environment to time with R's hashed precious
# list. The count mode counts only calls to R.PreserveObject and
# R.ReleaseObject made from Lua, not R_PreserveObject calls in push_to.cpp.

library(luajr)
args = commandArgs(trailingOnly = TRUE)
name = args[1]
mode = args[2]
set.seed(12345)

# Vignette example 1
x = rnorm(1e6)
sum_L = lua_func("function(x)
    local s = 0
    for i = 1, #x do
        s = s + x[i]
    end
    return s
end")

# Vignette example 2
logistic_map_L = lua_func(
"function(x0, burn, iter, A)
    local dflen = #A * iter
    local aa = luajr.numeric(dflen, 0)
    local xx = luajr.numeric(dflen, 0)

    local j = 1
    for k, a in pairs(A) do
        local x = x0
        for i = 1, burn do
            x = a * x * (1 - x)
        end
        for i = 1, iter do
            aa[j] = a
            xx[j] = x
            x = a * x * (1 - x)
            j = j + 1
        end
    end

    local result = luajr.dataframe()
    result:set('a', aa)
    result:set('x', xx)

    return result
end", "native, native, native, auto")

# Vignette example 3
lorenz2 = lua_func("
function(n, init, rho, sigma, beta)
    local step2 = function(x, rho, sigma, beta, dt)
        local dx = sigma * (x[2] - x[1])
        local dy = x[1] * (rho - x[3]) - x[2]
        local dz = x[1] * x[2] - beta * x[3]
        x[1] = x[1] + dx * dt
        x[2] = x[2] + dy * dt
        x[3] = x[3] + dz * dt
        return x
    end

    local x = init
    local result = luajr.matrix(n, 3)

    for i = 1,n do
        result[i] = x[1]
        result[i + n] = x[2]
        result[i + 2*n] = x[3]
        x = step2(x, rho, sigma, beta, 0.01)
    end

    return result
end", "native auto native")

# local/benchmarks.R
v1 = rnorm(1e1)
v4 = rnorm(1e4)
lua("sum2 = function(x)
    local s = 0
    for i = 1, #x do
        s = s + x[i] * x[i]
    end
    return s
end")
sum2_r = lua_func("sum2", "&.")
sum2_v = lua_func("sum2", ".")
sum2_s = lua_func("sum2", "$.")

# local/bench_sexp.R
xs = as.list(c(rnorm(5000), as.list(sample(letters, 5000, replace = TRUE))))
ys = vector("list", 10000)
read_loop = lua_func("function(x)
    local s = 0
    for i = 1, #x do
        local v = x[i]
    end
    return s
end", "V")
write_cdata_loop = lua_func("function(x)
    local v = luajr.numeric({1, 2, 3})
    for k = 1, 10 do
        for i = 1, #x do x[i] = v end
    end
end", "&V")
ctor_loop = lua_func("function()
    for i = 1, 10000 do
        local x = luajr.list({1, 2, 3, 4, 5, 6, 7, 8, 9, 10})
    end
end")

exprs = alist(
    sum_L = sum_L(x),
    logistic_map_L = logistic_map_L(0.5, 100, 100, 200:385/100),
    lorenz2 = lorenz2(5000, c(1, 1, 1), 28, 10, 8/3),
    sum2_r_v1 = sum2_r(v1),
    sum2_v_v1 = sum2_v(v1),
    sum2_s_v1 = sum2_s(v1),
    sum2_v_v4 = sum2_v(v4),
    read_loop = read_loop(xs),
    write_cdata_loop = write_cdata_loop(ys),
    ctor_loop = ctor_loop()
)
expr = exprs[[name]]

if (mode == "time") {
    res = bench::mark(exprs = list(expr), min_time = 2, check = FALSE)
    label = if (nzchar(Sys.getenv("R_HASH_PRECIOUS"))) "hashed" else "default"
    cat(sprintf("%-18s %-8s median %12.1f us\n", name, label, as.numeric(res$median) * 1e6))
} else if (mode == "count") {
    lua("
local R = require('R')
COUNTS = { preserve = 0, release = 0 }
local preserve = R.PreserveObject
local release = R.ReleaseObject
R.PreserveObject = function(x)
    COUNTS.preserve = COUNTS.preserve + 1
    return preserve(x)
end
R.ReleaseObject = function(x)
    COUNTS.release = COUNTS.release + 1
    return release(x)
end
")
    n = 20
    for (i in seq_len(n)) {
        eval(expr)
    }
    lua("collectgarbage()")
    lua("collectgarbage()")
    cat(sprintf("%-18s count    Lua preserve/call %8.1f  release/call %8.1f\n", name,
        lua("return COUNTS.preserve") / n, lua("return COUNTS.release") / n))
}
