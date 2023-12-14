# luajr: Use LuaJIT Scripting with R

<!-- badges: start -->

<!-- badges: end -->

`luajr` provides an interface to Mike Pall's LuaJIT (<https://luajit.org>), a just-in-time compiler for the Lua scripting language (<https://www.lua.org>). It allows users to run Lua code from R.

One of the advantages of using `luajr` is that LuaJIT runs Lua code with very fast compilation times, fast execution times, and no need for an external toolchain, as the LuaJIT compiler is "built in" to the luajr package. This contrasts with e.g. `Rcpp`, which results in compiled code with very fast execution times but slow compilation times and the need to invoke an external C++ compiler toolchain like `gcc` or `clang`.

## Installation

You can install the released version of luajr from [CRAN](https://CRAN.R-project.org) with:

``` r
install.packages("luajr")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(luajr)
## basic example code
```
