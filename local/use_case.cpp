// Example use case of luajr
// This would be inside a package that also links to luajr:

#include <Rcpp.h>
#include <vector>
#include <string>

// [[Rcpp::plugins(cpp14)]]

// [[Rcpp::export]]
Rcpp::NumericVector solve_ode_model(
    std::vector<double> init = { 1.0, 1.0 },
    std::string dxdt = "function(x) return { -x[1], x[2] } end",
    double t0 = 0.0, double t1 = 10.0, double t_step = 0.1
)
{
    // etc...
}
