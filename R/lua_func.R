#' Create a Lua function callable from R.
#'
#' More documentation to follow.
#'
#' The R types that can be passed to Lua are: \code{NULL}, logical vector,
#' integer vector, numeric vector, string vector, list, and external pointer.
#'
#' The parameter \code{args} is a string with one character for each
#' argument passed to the Lua function, recycled as needed.
#'
#' For \code{NULL} or any argument with length 0, the result in Lua is
#' \strong{nil} regardless of the corresponding \code{args} code.
#'
#' For logical, integer, double, and character vectors, if the corresponding
#' \code{args} code is \code{'s'} (simplify), then if the R vector has length
#' one, it is supplied as a Lua primitive (boolean, number, number, or string,
#' respectively), and if length > 1, as a table. If the code is \code{'a'}, the
#' vector is supplied as an array (table with integer indices) for any length
#' >= 1, discarding names. If \code{'t'}, the vector is supplied as a table for
#' any length >= 1, with or without names depending on the R object.
#'
#' For lists, the Lua object will always be either \strong{nil} (if length 0) or
#' a table (i.e. it is not simplified to a scalar if there is only one entry in
#' the list), but the \code{args} code can be \code{'s'}, \code{'a'}, or
#' \code{'t'}, which is applied to all elements contained in the list (including
#' other lists).
#'
#' Note that Lua does not preserve the order of entries in lists. This means
#' that an R vector with names will often go out of order when passed into
#' Lua. A warning is therefore emitted when a named list or vector gets passed
#' in to Lua.
#'
#' For external pointers, the \code{args} code is ignored and the external
#' pointer is passed to Lua as type \emph{userdata}.
#'
#' Attributes are ignored other than 'names' and 'class', so e.g. matrices will
#' end up as a numeric vector.
#'
#' @param code Lua expression evaluating to a function.
#' @param args How to wrap R arguments for the Lua function.
#' @param L \link[=lua_open]{Lua state} in which to run the code. \code{NULL}
#' (default) to use the default Lua state for \pkg{luajr}.
#' @return An R function.
#' @examples
#' squared = lua_func("function(x) return x^2 end")
#' print(squared(7))
#' @export
lua_func = function(code, args = "s", L = NULL)
{
    fptr = luajr_func_create(code, L);
    func = function(...) {
        # robj_ret can be used by the Lua function to return R objects.
        robj_ret = vector("list", 4);

        # Call the function.
        ret = luajr_func_call(fptr, list(...), args, L);

        # # If robj_ret has been set, return that.
        # if (length(robj_ret) > 0) {
        #     return (robj_ret)
        # }
        # Otherwise, return the returned Lua value converted to an R object.
        # If this is a NULL, return it invisibly.
        if (is.null(ret)) {
            return (invisible())
        } else {
            return (ret)
        }
    }
    return (func)
}

