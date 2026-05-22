#' Make a Lua function callable from R
#'
#' Takes any Lua expression (as a character string) that evaluates to a
#' Lua function and provides an R function that can be called to invoke the Lua
#' function. Instead of a character string, you can also provide an external
#' pointer to a Lua function (see examples).
#'
#' Any R type can be passed to a Lua function. The R types that have special
#' support in \pkg{luajr} are: `NULL`, logical vector, integer vector, numeric
#' vector, character vector, list, function, environment, and external pointer.
#'
#' The parameter `argcode` is a string that specifies type handling for each
#' argument of the Lua function. The last type is repeated when there are more
#' arguments than specified types.
#'
#' To receive a `luajr.logical` type in Lua, use the argcode `logical` or `L`.
#' Similarly, `luajr.integer` is specified with `integer` or `I`;
#' `luajr.numeric` is specified with `numeric` or `N`; and `luajr.character` is
#' specified with `character` or `C`. `luajr.list` is specified with `list`,
#' `vector`, or `V`.
#'
#' To receive a `luajr.rfunction` type, use `rfunction` or `F`. To receive a
#' `luajr.environment` type, use `environment` or `E`. To receive an `R.sexp`
#' type, use `sexp` or `S`.
#'
#' To pass any R type as "closest available" type from the above, use the
#' argcode `auto` or `"."`.
#'
#' Argcodes should be separated by commas. If you are using a "single-character"
#' argcode like `.` or `S`, there does not need to be a comma following it.
#'
#' You can also receive R values as Lua native types. Specifically, the argcode
#' `function` corresponds to a Lua function; `boolean` is a Lua boolean;
#' `number` is a Lua number; `string` is a Lua string and `table` is a Lua
#' table. `pointer` or `P` passes an external pointer (EXTPTRSXP) as a Lua
#' light userdata. The argcode `native` selects the closest available native
#' type.
#'
#' Additionally, the prefix `$` specifies that the type should be passed as a
#' Lua native type. So `$auto` is equivalent to `native` and `$C` is equivalent
#' to `string`.
#'
#' Note that native scalar argcodes (e.g. `$L`, `$I`, `$N`, `$C`, `boolean`,
#' `number`, `string`) do not preserve R's `NA` values, because Lua has no
#' `NA` concept: an R `NA` of any type is passed as Lua `nil`, which a
#' non-strict argcode silently treats as missing. Plain `NaN` values (e.g.
#' from `0/0`) do survive as Lua `NaN` because they are distinct from R's
#' `NA_real_`. To preserve typed `NA`s on a round-trip, pass values through a
#' `luajr` vector type (e.g. `luajr.numeric`, `luajr.logical`) instead of the
#' native scalar form, and read individual elements in Lua via `v(i)` (which
#' returns a length-1 vector of the same type rather than a bare scalar).
#'
#' The prefix `!` specifies strict type handling (i.e., error if the type cannot
#' be converted). `!` also yields an error on passing `NULL` if the argcode
#' specifies a Lua native type (otherwise, `NULL` gets passed as Lua `nil`).
#'
#' The prefix `&` can be used with logical, integer, numeric, character, or
#' generic (list) vectors and specifies that the value should be passed
#' **by reference**. Vectors passed by reference can have their elements
#' mutated in Lua code, but they cannot be resized.
#'
#' When the function is called and Lua values are returned from the function,
#' the Lua return values are converted to R values as follows.
#'
#' If nothing is returned, the function returns `invisible()` (i.e. `NULL`).
#'
#' If multiple arguments are returned, a list with all arguments is returned.
#'
#' Vector types (e.g. `luajr.logical`) are returned to R as the corresponding R
#' vector. A `luajr.list` is returned as an R list. Vector and list types
#' respect R attributes set within Lua code.
#'
#' A **table** is returned as a list. In the list, any table entries with a
#' number key come first (with indices 1 to n, i.e. the original number key's
#' value is discarded), followed by any table entries with a string key
#' (named accordingly). This may well scramble the order of keys, so beware.
#' Note in particular that Lua does not guarantee that it will traverse a table
#' in ascending order of keys. Entries with non-number, non-string keys are
#' discarded. It is probably best to avoid returning a **table** with anything
#' other than string keys, or to use `luajr.list`.
#'
#' A Lua string with embedded nulls is returned as an R raw type.
#'
#' A function is returned as an external pointer, which itself can be converted
#' into a function that can be called from R, by passing it through `lua_func()`
#' as the `func` argument.
#'
#' @inheritParams lua
#' @param func A character string with a Lua expression evaluating to a
#'   function, or an external pointer to a Lua function.
#' @param argcode How to wrap R arguments for the Lua function.
#' @return An R function which can be called to invoke the Lua function.
#' @examples
#' # use with a character string
#' squared <- lua_func("function(x) return x^2 end", "$.")
#' print(squared(7))
#'
#' # use with an external pointer to a Lua function
#' times2ptr <- lua("return function(x) return 2 * x end")
#' print(times2ptr)
#' times2 <- lua_func(times2ptr, "$.")
#' print(times2(14))
#' @export
lua_func = function(func, argcode = ".", L = NULL)
{
    # Get function and information
    fx = .Call(`_luajr_fcreate`, func, L)
    info = .Call(`_luajr_finfo`, fx)
    nparams = info[[1]]  # number of parameters, not including vararg ...
    isvararg = info[[2]]
    arg_names = as.character(info[[3]])
    if (isvararg) {
        arg_names = c(arg_names, "...")
    }

    # Validate parameters
    if (!is.character(argcode)) {
        stop("argcode must be a string.")
    }
    argcode = interpret_argcode(argcode)
    if ((isvararg || nparams > 0) && length(argcode) == 0) {
        stop("argcode must be a non-empty string for Lua functions with arguments.")
    }

    # Pad argcode to nparams by holding the last element
    if (!isvararg && nparams > 0 && length(argcode) < nparams) {
        argcode = c(argcode, rep(argcode[length(argcode)], nparams - length(argcode)))
    }

    # Build function
    f = function() .Call(`_luajr_fcall0`, fx, argcode, L)

    # Set formals
    arg_syms = lapply(arg_names, as.symbol)
    fmls = lapply(arg_names, function(x) quote(expr = ))
    names(fmls) = arg_names
    formals(f) = fmls

    # Set body
    b = as.list(body(f))
    if (isvararg || nparams > 8) {
        call_name = "_luajr_fcall"
        b = append(b, list(as.call(c(quote(list), arg_syms))), after = 3)
    } else {
        call_name = paste0("_luajr_fcall", nparams)
        b = append(b, arg_syms, after = 3)
    }

    # Embed resolved values in the function body
    # Full embedding allows R function compilation, possibly by avoiding environment lookup
    n = length(b)
    b[[2]] = getNativeSymbolInfo(call_name, "luajr")$address
    b[[3]] = fx
    b[[n - 1]] = argcode
    b[n] = list(L) # in case L = NULL
    body(f) = as.call(b)

    return (compiler::cmpfun(f))
}

argcodes_mod = c(
    "$" = 32,  # native/scalar
    "&" = 64,  # reference
    "!" = 128  # strict
)

argcodes_long = c(
    auto = 0,
    native = 0 + argcodes_mod[["$"]],
    sexp = 1,
    symbol = 2,
    pairlist = 3,
    rfunction = 4,
    "function" = 4 + argcodes_mod[["$"]],
    environment = 5,
    language = 6,
    logical = 7,
    boolean = 7 + argcodes_mod[["$"]],
    integer = 8,
    numeric = 9,
    number = 9 + argcodes_mod[["$"]],
    complex = 10,
    character = 11,
    string = 11 + argcodes_mod[["$"]],
    vector = 12,
    list = 12,
    table = 12 + argcodes_mod[["$"]],
    expression = 13,
    raw = 14,
    pointer = 15
    # others
)

# argcodes that have a native Lua interpretation
argcodes_native = argcodes_long[c("rfunction", "logical", "integer", "numeric", "character", "vector")]

argcodes_short = c(
    "." = 0,
    "S" = argcodes_long[["sexp"]],
    "F" = argcodes_long[["rfunction"]],
    "E" = argcodes_long[["environment"]],
    "L" = argcodes_long[["logical"]],
    "I" = argcodes_long[["integer"]],
    "N" = argcodes_long[["numeric"]],
    "C" = argcodes_long[["character"]],
    "V" = argcodes_long[["list"]],
    "P" = argcodes_long[["pointer"]]
    # others
)

interpret_argcode = function(ac)
{
    ac = paste(ac, collapse = ",")

    pos = 1
    code = 0
    output = integer(0)

    while (pos <= nchar(ac)) {
        ch = substr(ac, pos, pos)
        if (ch %in% c(' ', ',', ';')) {
            pos = pos + 1
            next
        } else if (ch %in% names(argcodes_mod)) {
            code = bitwOr(code, argcodes_mod[ch])
            pos = pos + 1
            next
        } else if (ch == toupper(ch)) {
            if (!ch %in% names(argcodes_short)) {
                stop("Cannot find short code `", ch, "`.")
            }
            code = bitwOr(code, argcodes_short[ch])
            validate_argcode(code)
            pos = pos + 1
            output = c(output, as.integer(code))
            code = 0
            next
        } else {
            pos_end = regexpr("[,; ]", substr(ac, pos, nchar(ac)))[1]
            if (pos_end == -1) {
                pos_end = nchar(ac)
            } else {
                pos_end = pos_end + pos - 2
            }
            sub_ac = substr(ac, pos, pos_end)

            if (sub_ac %in% names(argcodes_long)) {
                code = bitwOr(code, argcodes_long[sub_ac])
                validate_argcode(code)
                pos = pos_end + 1
                output = c(output, as.integer(code))
                code = 0
                next
            } else {
                stop("Cannot find long code `", sub_ac, "`.")
            }
        }
    }

    return (as.raw(output))
}

validate_argcode = function(code)
{
    if (bitwAnd(code, 32) != 0 && bitwAnd(code, 64) != 0)
        stop("Cannot combine $ (native) and & (reference) modifiers.")
    if (bitwAnd(code, 32) != 0) {
        type = bitwAnd(code, 31)
        if (type != 0 && !type %in% argcodes_native)
            stop("$ (native) modifier not supported for this type.")
    }
}

