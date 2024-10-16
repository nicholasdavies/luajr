
# luajr: LuaJIT Scripting

<!-- badges: start -->

[![R-CMD-check](https://github.com/nicholasdavies/luajr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/nicholasdavies/luajr/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

<!-- reminder: update README.md with devtools::build_readme() -->

luajr provides an interface to [LuaJIT](https://luajit.org), a
just-in-time compiler for the [Lua scripting
language](https://www.lua.org). It allows users to run Lua code from R.

One of the advantages of using luajr is that LuaJIT runs Lua code with
very fast compilation times, fast execution times, and no need for an
external toolchain, as the LuaJIT compiler is “built in” to the luajr
package. This contrasts with e.g. [Rcpp](https://www.rcpp.org/), which
results in compiled code with very fast execution times but slow
compilation times and the need to invoke an external C++ compiler
toolchain like `gcc` or `clang`.

## Installation

You can install the released version of luajr from
[CRAN](https://CRAN.R-project.org/package=luajr) with:

``` r
install.packages("luajr")
```

You can install the development version of luajr from
[GitHub](https://github.com/nicholasdavies/luajr) with:

``` r
# install.packages("devtools")
devtools::install_github("nicholasdavies/luajr")
```

## Under development

luajr is under **early development**. As such, the interface and
behaviour of the package is subject to change.
