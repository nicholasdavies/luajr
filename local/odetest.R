library(luajr)
library(ggplot2)
library(data.table)
library(Rcpp)

# Independent Lua version
lua(filename = "./local/odetest.lua")
runner = lua_func("run")

bench = function(..., n = 100000, env = parent.frame())
{
    bench::mark(..., min_iterations = n, max_iterations = n, filter_gc = FALSE, env = env)
}

sol <- runner()
rm(sol)

bench(
    sol <- runner()
) # 24 µs median

ggplot(sol) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))

# deSolve R version
library(deSolve)

beta = 0.05
gamma = 0.025

gradient = function(t, x, pars)
{
    dS = -beta * x[["I"]] * x[["S"]]
    dI =  beta * x[["I"]] * x[["S"]] - gamma * x[["I"]]
    dR = gamma * x[["I"]]
    return (list(c(dS, dI, dR)))
}

# deSolve Rcpp version
cppFunction(
    'List gradient2(double t, Rcpp::NumericVector x, SEXP pars)
    {
        double dS = -0.05 * x[1] * x[0];
        double dI =  0.05 * x[1] * x[0] - 0.025 * x[1];
        double dR = 0.025 * x[1];
        return List::create(NumericVector::create(dS, dI, dR));
    }')

# deSolve Lua version
gradient3 = lua_func("function(t, x, pars)
    local d = luajr.numeric(3)
    d[1] = -0.05 * x[2] * x[1]
    d[2] =  0.05 * x[2] * x[1] - 0.025 * x[2]
    d[3] =                       0.025 * x[2]
    --local l = luajr.list()
    --l[1] = d
    local l = R.PROTECT(R.allocVector(R.VECSXP, 1))
    R.SET_VECTOR_ELT(l, 0, d.s)
    R.UNPROTECT(1)
    return l
end", "xrx")

lua("R = require('R')")
lua("save_d = luajr.numeric(3, 0)")
lua("save_l = R.allocVector(R.VECSXP, 1)")
lua("R.PreserveObject(save_l)")
lua("R.SET_VECTOR_ELT(save_l, 0, save_d.s)")

gradient4 = lua_func("function(t, x, pars)
    save_d[1] = -0.05 * x[2] * x[1]
    save_d[2] =  0.05 * x[2] * x[1] - 0.025 * x[2]
    save_d[3] =                       0.025 * x[2]
    return save_l
end", "xrx")

yini = c(S = 0.999, I = 0.001, R = 0.000)
times = seq(1, 1000, by = 1)

gradient3(0, yini, c())

bench(
    g <- gradient (0, yini, c()),
    g <- gradient2(0, yini, c()),
    g <- gradient3(0, yini, c()),
    g <- gradient4(0, yini, c())
)

# # A tibble: 4 × 13
#   expression                        min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result     memory     time       gc
#   <bch:expr>                   <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>     <list>     <list>     <list>
# 1 g <- gradient(0, yini, c())     656ns 820.03ns   695200.        0B    27.8  100000     4    143.8ms <list [1]> <Rprofmem> <bench_tm> <tibble>
# 2 g <- gradient2(0, yini, c())    328ns    410ns  1948302.        0B    39.0  100000     2     51.3ms <list [1]> <Rprofmem> <bench_tm> <tibble>
# 3 g <- gradient3(0, yini, c())    328ns    492ns   998892.        0B     20.0 100000     2    100.1ms <list [1]> <Rprofmem> <bench_tm> <tibble>
# 4 g <- gradient4(0, yini, c())    246ns    328ns  2242414.        0B     22.4 100000     1     44.6ms <list [1]> <Rprofmem> <bench_tm> <tibble>

bench(
    out <- ode(yini, times, gradient, c(), method = "rk4"),
    out <- ode(yini, times, gradient2, c(), method = "rk4"),
    out <- ode(yini, times, gradient3, c(), method = "rk4"),
    out <- ode(yini, times, gradient4, c(), method = "rk4"),
    sol <- runner(),
    check = FALSE,
    n = 1000
)

# # A tibble: 5 × 13
#   expression                                     min  median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory     time       gc
#   <bch:expr>                                 <bch:t> <bch:t>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>     <list>     <list>
# 1 "out <- ode(yini, times, gradient, c(), m…   4.8ms  5.27ms     172.    885.8KB     54.8  1000   319      5.83s <NULL> <Rprofmem> <bench_tm> <tibble>
# 2 "out <- ode(yini, times, gradient2, c(), …   3.6ms  3.95ms     228.    120.4KB     47.2  1000   207      4.38s <NULL> <Rprofmem> <bench_tm> <tibble>
# 3 "out <- ode(yini, times, gradient3, c(), …   9.3ms  9.94ms      95.8   120.4KB     24.2  1000   253     10.43s <NULL> <Rprofmem> <bench_tm> <tibble>
# 4 "out <- ode(yini, times, gradient4, c(), …  6.34ms  7.05ms     135.    120.4KB     31.2  1000   232      7.43s <NULL> <Rprofmem> <bench_tm> <tibble>
# 5 "sol <- runner()"                          23.74µs 25.62µs   32322.     31.4KB     32.3  1000     1    30.94ms <NULL> <Rprofmem> <bench_tm> <tibble>
# out = as.data.table(out)

# # A tibble: 5 × 13
#   expression                                     min  median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory     time       gc
#   <bch:expr>                                 <bch:t> <bch:t>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>     <list>     <list>
# 1 "out <- ode(yini, times, gradient, c(), m…  4.75ms  5.09ms      182.   885.8KB     49.9  1000   274      5.49s <NULL> <Rprofmem> <bench_tm> <tibble>
# 2 "out <- ode(yini, times, gradient2, c(), …  3.48ms  3.72ms      254.   120.4KB     45.2  1000   178      3.94s <NULL> <Rprofmem> <bench_tm> <tibble>
# 3 "out <- ode(yini, times, gradient3, c(), …  5.12ms  5.41ms      170.   120.4KB     35.1  1000   206      5.87s <NULL> <Rprofmem> <bench_tm> <tibble>
# 4 "out <- ode(yini, times, gradient4, c(), …     3ms  3.28ms      272.   120.4KB     51.2  1000   188      3.67s <NULL> <Rprofmem> <bench_tm> <tibble>
# 5 "sol <- runner()"                          23.41µs 24.56µs    37763.    31.4KB      0    1000     0    26.48ms <NULL> <Rprofmem> <bench_tm> <tibble>

ggplot(out) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))

ggplot(sol) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))





bench(
    out <- ode(yini, times, gradient, c()),
    out <- ode(yini, times, gradient2, c()),
    out <- ode(yini, times, gradient3, c()),
    out <- ode(yini, times, gradient4, c()),
    sol <- runner(),
    check = FALSE,
    n = 1000
)
