
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

You can install the development version of luajr from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("nicholasdavies/luajr")
```

## Under development

luajr is under **early development**. As such, the interface and
behaviour of the package is subject to change.

<!--
## Example
&#10;This is a basic example which shows you how to solve a common problem:
&#10;
```r
library(luajr)
## basic example code
```
&#10;What is special about using `README.Rmd` instead of just `README.md`? You can include R chunks like so:
&#10;
```r
summary(cars)
#>      speed           dist       
#>  Min.   : 4.0   Min.   :  2.00  
#>  1st Qu.:12.0   1st Qu.: 26.00  
#>  Median :15.0   Median : 36.00  
#>  Mean   :15.4   Mean   : 42.98  
#>  3rd Qu.:19.0   3rd Qu.: 56.00  
#>  Max.   :25.0   Max.   :120.00
```
&#10;You'll still need to render `README.Rmd` regularly, to keep `README.md` up-to-date. `devtools::build_readme()` is handy for this.
&#10;You can also embed plots, for example:
&#10;<img src="man/figures/README-pressure-1.png" width="100%" />
&#10;In that case, don't forget to commit and push the resulting figure files, so they display on GitHub and CRAN.
-->
