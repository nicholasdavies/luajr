# Benchmarking calling lua functions -- trying to get to minimal.
library(luajr)
library(Rcpp)

bench = function(..., n = 100000)
{
    bench::mark(..., min_iterations = n, max_iterations = n)
}

blank_R = function() {}
blank_L = lua_func("function() end")
blank_C = cppFunction("void cpp_nothing() { }") # interesting: this puts invisible() around the function call as it detects void().

bench(
    blank_R(),
    blank_L(),
    blank_C(),
    n = 1e6
)

# # A tibble: 3 × 13
#   expression      min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result memory             time                   gc
#   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list> <list>             <list>                 <list>
# 1 blank_R()         0     41ns 33068210.        0B     66.1 999998     2     30.2ms <NULL> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 2 blank_L()     164ns    246ns  3973529.        0B     11.9 999997     3    251.7ms <NULL> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 3 blank_C()      41ns    123ns  6990131.        0B     14.0 999998     2    143.1ms <NULL> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>

# # A tibble: 3 × 13
#   expression      min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result memory             time                   gc
#   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list> <list>             <list>                 <list>
# 1 blank_R()         0        0 40027192.        0B    80.1  999998     2       25ms <NULL> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 2 blank_L()         0     82ns 12484338.        0B     49.9 999996     4     80.1ms <NULL> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 3 blank_C()      41ns    123ns  8327683.    2.49KB     33.3 999996     4    120.1ms <NULL> <Rprofmem [1 × 3]> <bench_tm [1,000,000]> <tibble>

# A few critical points. The minimum timing interval seems to be 41 ns.
# A clock cycle here is about 0.25 ns.

# The CPP generated function looks like this:
# // cpp_nothing
# void cpp_nothing();
# RcppExport SEXP sourceCpp_1_cpp_nothing() {
# BEGIN_RCPP
#     Rcpp::RNGScope rcpp_rngScope_gen;
#     cpp_nothing();
#     return R_NilValue;
# END_RCPP
# }

get_R = function() { return (42) }
get_L = lua_func("function() return 42 end")
get_C = cppFunction("double cpp_nothing() { return 42; }")

bench(
    get_R(),
    get_L(),
    get_C(),
    n = 1e6
)

# # A tibble: 3 × 13
#   expression      min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result    memory             time                   gc
#   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>    <list>             <list>                 <list>
# 1 get_R()           0     41ns 26207861.        0B     78.6 999997     3     38.2ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 2 get_L()           0     82ns 11014693.        0B     33.0 999997     3     90.8ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 3 get_C()        41ns    123ns  6525964.        0B     26.1 999996     4    153.2ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>

x = rnorm(100)
identity_R = function(x) x
identity_L = lua_func("function(x) return x end", "x")
identity_C = cppFunction("SEXP cpp_identity(SEXP x) { return x; }")

bench(
    identity_R(x),
    identity_L(x),
    identity_C(x),
    n = 1e6
)

# # A tibble: 3 × 13
#   expression         min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result      memory             time                 gc
#   <bch:expr>    <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>      <list>             <list>               <list>
# 1 identity_R(x)        0   82.2ns  8289252.        0B      0   100000     0     12.1ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 2 identity_L(x)    697ns    820ns  1139910.        0B     11.4  99999     1     87.7ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 3 identity_C(x)     82ns    164ns  5108476.        0B     51.1  99999     1     19.6ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>

# # A tibble: 3 × 13
#   expression         min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result      memory             time                   gc
#   <bch:expr>    <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>      <list>             <list>                 <list>
# 1 identity_R(x)        0     82ns 14177224.        0B     70.9 999995     5     70.5ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 2 identity_L(x)     41ns    123ns  6101000.        0B     30.5 999995     5    163.9ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
# 3 identity_C(x)     82ns    164ns  5247177.        0B     31.5 999994     6    190.6ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [1,000,000]> <tibble>
