# Benchmarking calling lua functions -- trying to get to minimal.
library(luajr)
library(Rcpp)

bench = function(...)
{
    bench::mark(..., min_iterations = 100000, max_iterations = 100000)
}

blank_R = function() {}
blank_L = lua_func("function() end")
blank_C = cppFunction("void cpp_nothing() { }") # interesting: this puts invisible() around the function call as it detects void().

bench(
    blank_R(),
    blank_L(),
    blank_C()
)

# # A tibble: 3 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result memory             time                 gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list> <list>             <list>               <list>
#     1 blank_R()         0     41ns 23849117.        0B        0 100000     0     4.19ms <NULL> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
#     2 blank_L()     205ns    287ns  3551951.        0B        0 100000     0    28.15ms <NULL> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
#     3 blank_C()      82ns    164ns  5645351.        0B        0 100000     0    17.71ms <NULL> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>

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

# blank_L looks like this:
# function(...) {
#         ret = .Call(`_luajr_func_call`, fx, list(...), argcode, L);
#
#         if (is.null(ret)) invisible() else ret
#     }


x = rnorm(100)
identity_R = function(x) x
identity_L = lua_func("function(x) return x end", "x")
identity_C = cppFunction("SEXP cpp_identity(SEXP x) { return x; }")

bench(
    identity_R(x),
    identity_L(x),
    identity_C(x)
)

# # A tibble: 3 × 13
#   expression         min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result      memory             time                 gc
#   <bch:expr>    <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>      <list>             <list>               <list>
# 1 identity_R(x)        0   82.2ns  8289252.        0B      0   100000     0     12.1ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 2 identity_L(x)    697ns    820ns  1139910.        0B     11.4  99999     1     87.7ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 3 identity_C(x)     82ns    164ns  5108476.        0B     51.1  99999     1     19.6ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>

# # A tibble: 3 × 13
#   expression         min   median `itr/sec` mem_alloc `gc/sec`  n_itr  n_gc total_time result      memory             time                 gc
#   <bch:expr>    <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>  <int> <dbl>   <bch:tm> <list>      <list>             <list>               <list>
# 1 identity_R(x)        0     82ns  7504288.        0B      0   100000     0     13.3ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 2 identity_L(x)    451ns    574ns  1628137.        0B     16.3  99999     1     61.4ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
# 3 identity_C(x)     82ns    164ns  5108476.        0B     51.1  99999     1     19.6ms <dbl [100]> <Rprofmem [0 × 3]> <bench_tm [100,000]> <tibble>
