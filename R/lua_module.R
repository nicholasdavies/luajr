#' Load functions from Lua modules
#'
#' [lua_module()] can be used in an R project or package to declare a Lua
#' module in an external file. You can then use [lua_import()] to access the
#' functions within the module, or provide access to those functions to your
#' package users. The object returned by [lua_module()] can also be used to
#' set and get other (non-function) values stored in the Lua module table
#' (see "Setting and getting" below).
#'
#' @section Module files:
#'
#' Module files should have the file extension `.lua` and be placed somewhere
#' in your project directory. If you are writing a package, the best practice
#' is probably to place these in the subdirectory `inst/Lua` of your package.
#'
#' The module file itself should follow standard practice for
#' [Lua modules](http://lua-users.org/wiki/ModulesTutorial). In other words,
#' the module file should return a Lua table containing the module's functions.
#' A relatively minimal example would be:
#'
#' ```Lua
#' local mymodule = {}
#' mymodule.fave_name = "Nick"
#'
#' function mymodule.greet(name)
#'     print("Hello, " .. name .. "!")
#'     if name == mymodule.fave_name then
#'         print("Incidentally, that's a great name. Nice one.")
#'     end
#' end
#'
#' return mymodule
#' ```
#'
#' @section Loading the module:
#'
#' Before you import functions from your module, you need to create a module
#' object using [lua_module()]. Supply the file name as the `filename` argument
#' to [lua_module()]. If you are developing a package, also supply your package
#' name as the `package` argument. If `package` is `NULL`, [lua_module()] will
#' look for the file relative to the current working directory. If `package` is
#' non-`NULL`, [lua_module()] will look for the file relative to the
#' installed package directory (using [system.file()]). So, if you are
#' developing a package and you have put your module file in
#' `inst/Lua/mymodule.lua` as recommended above, supply `"Lua/mymodule.lua"`
#' as the filename.
#'
#' The module returned by [lua_module()] is not actually loaded until the
#' first time that you import a function from the module. If you want the
#' module to be loaded into a specific [Lua state][lua_open()] in your R
#' project, then assign that state to the module's state right after declaring
#' it:
#'
#' ```R
#' mymod <- lua_module("path/to/file.lua", package = "mypackage")
#' mymod$L <- my_state
#' ```
#'
#' If you are creating a package and you want to load your module into a
#' specific Lua state, you will need to create that state and assign it to
#' `module$L` after the package is loaded, probably by using [.onLoad()].
#'
#' @section Importing functions:
#'
#' To import a function from a module, declare it like this:
#'
#' ```R
#' myfunc <- function(x, y) lua_import(mymod, "funcname", "s")
#' ```
#'
#' where `mymod` is the previously-declared module object, `"funcname"` is the
#' function name within the Lua module, and `"s"` is whatever
#' [argcode][lua_func()] you want to use. Note that `lua_import()` must be used
#' as the only statement in your function body and you should **not** enclose
#' it in braces (`{}`). The arguments of `myfunc` will be passed to the
#' imported function in the same order as they are declared in the function
#' signature. You can give default values to the function arguments.
#'
#' With the example above, the first time you call `myfunc()`, it will make
#' sure the module is properly loaded and then call the Lua function. It will
#' also overwrite the existing body of `myfunc()` with a direct call to the
#' Lua function so that subsequent calls to `myfunc()` execute as quickly
#' as possible.
#'
#' In some cases, you may want to do some processing or checking of function
#' arguments in R before calling the Lua function. You can do that with a
#' "two-step" process like this:
#'
#' ```R
#' greet0 <- function(name) lua_import(mymod, "greet", "s")
#' greet <- function(name) {
#'     if (!is.character(name)) {
#'         stop("greet expects a character string.")
#'     }
#'     greet0(name)
#' }
#' ```
#'
#' In a package, you can document and export a function that uses [lua_import()]
#' just like any other function.
#'
#' @section Setting and getting:
#'
#' Lua modules can contain more than just functions; they can also hold other
#' values, as shown in the example module above (under "Module files"). In this
#' example, the module also contains a string called `fave_name` which alters
#' the behaviour of the `greet` function.
#'
#' You can get a value from a module by using e.g. `module["fave_name"]` and
#' set it using e.g. `module["fave_name"] <- "Janet"`. You must use single
#' brackets `[]` and not double brackets `[[]]` or the dollar sign `$` for
#' this, and you cannot change a function at the top level of the module. If
#' your module contains a table `x` which contains a value `y`, you can get or
#' set `y` by using multiple indices, e.g. `module["x", "y"]` or
#' `module["x", "y"] <- 1`. Using empty brackets, e.g. `module[]`, will return
#' all the contents of the module, but you cannot set the entire contents of
#' the module with e.g. `module[] = foo`.
#'
#' By default, when setting a module value using `module[i] <- value`, the
#' value is passed to Lua "by simplify" (e.g. with [argcode][lua_func()]
#' `"s"`). You can change this behaviour with the `as` argument. For example,
#' `module[i, as = "a"] <- 2` will set element `i` of the module to a Lua
#' table `{2}` instead of the plain value `2`.
#'
#' @usage lua_module(filename = NULL, package = NULL)
#' @param filename Name of file from which to load the module. If this is a
#'     character vector, the elements are concatenated together with
#'     [file.path()].
#' @param package If non-`NULL`, the file will be sought within this package.
#' @param module Module previously loaded with [lua_module()].
#' @param name Name of the function to import (character string).
#' @param argcode How to wrap R arguments for the Lua function; see
#'     documentation for [lua_func()].
#' @return [lua_module()] returns an environment with class `"luajr_module"`.
#' @examples
#' module <- lua_module(c("Lua", "example.lua"), package = "luajr")
#' greet <- function(name) lua_import(module, "greet", "s")
#' greet("Janet")
#' greet("Nick")
#' @export
lua_module = function(filename = NULL, package = NULL)
{
    module = as.environment(list(
        filename = filename,
        package = package
    ))

    class(module) = "luajr_module"

    return (module)
}

#' @rdname lua_module
#' @usage f <- function(x, y) lua_import(module, name, argcode)
#' @export
lua_import = function(module, name, argcode)
{
    stopifnot(inherits(module, "luajr_module"))

    # Get the top-level call; for example, if we had
    # somefunc = function(x, y) lua_import(mymod, "s", "func")
    # called with somefunc(1, 2) then get somefunc(1, 2).
    call = sys.call(-1)
    if (is.null(call)) {
        stop("Cannot call lua_import at top level. See ?lua_import.")
    }

    # Get name of R function to overwrite
    R_name = call[[1]]
    if (!is.name(R_name)) {
        stop("Must use lua_import with a plain symbol. See ?lua_import.")
    }
    R_name = as.character(R_name)

    # Get current value of R function to overwrite
    ##R_func = get(R_name, envir = sys.frame(-2))
    R_func = get(R_name, envir = environment(sys.function(-1)))
    if (!identical(body(R_func)[[1]], as.name("lua_import"))) {
        stop("Must use call to lua_import as the body of a function. See ?lua_import.")
    }

    # Ensure module is initialized
    load_module(module)

    # Get module entry
    fx = .Call(`_luajr_module_get`, module[["mod"]], list(name), "function");

    # Create new body for R function which directly calls the Lua function
    R_body = quote({
        ret = .Call(LUAJR_FUNC_CALL, FX, ARGS, ARGCODE, L);
        if (is.null(ret)) invisible() else ret
    })
    # Reassign LUAJR_FUNC_CALL through L above
    R_body[[2]][[3]][2:6] = list(
        luajr:::`_luajr_func_call`$address,
        fx,
        as.call(lapply(c("list", names(formals(R_func))), as.name)),
        argcode,
        module[["L"]]
    )
    body(R_func) = R_body

    # Overwrite R function
    ##assign(R_name, R_func, envir = sys.frame(-2))
    assign(R_name, R_func, envir = environment(sys.function(-1)))

    # Finally, we also need to call the Lua function;
    # next time this will be handled by the overwritten R function.
    # We have to do this in a slightly roundabout way to ensure we get
    # the function arguments from the correct calling frame.
    evaluated_args = as.list(match.call(definition = sys.function(-1), call = sys.call(-1)))[-1]
    ret = .Call(`_luajr_func_call`, fx, evaluated_args, argcode, module[["L"]])
    if (is.null(ret)) invisible() else ret
}

#' @keywords internal
#' @export
print.luajr_module = function(x, ...)
{
    stopifnot(inherits(x, "luajr_module"))

    if (!exists("mod", x)) {
        cat("Unloaded Lua module (",
            do.call(file.path, as.list(x[["filename"]])),
            sep = "")
        if (!is.null(x[["package"]])) {
            cat(" from package", x[["package"]])
        }
        cat(")\n")
    } else {
        cat("Lua module (L = ", format(x[["L"]]), ")\n", sep = "")
    }
}

#' @keywords internal
#' @export
`[.luajr_module` = function(x, ...)
{
    stopifnot(inherits(x, "luajr_module"))

    # Ensure module is initialized
    load_module(x)

    # This seems to be needed for the [ method.
    if (missing(..1)) {
        .Call(luajr:::`_luajr_module_get`, x[["mod"]], list(), NULL)
    } else {
        .Call(luajr:::`_luajr_module_get`, x[["mod"]], list(...), NULL)
    }
}

#' @keywords internal
#' @export
`[<-.luajr_module` = function(x, ..., as = "s", value)
{
    stopifnot(inherits(x, "luajr_module"))

    # Ensure module is initialized
    load_module(x)

    # This seems to be needed for the [ method.
    if (missing(..1)) {
        .Call(luajr:::`_luajr_module_set`, x[["mod"]], list(), as, value)
    } else {
        .Call(luajr:::`_luajr_module_set`, x[["mod"]], list(...), as, value)
    }

    return (x)
}

# Ensures the module is loaded. Creates the Lua state if needed, then
# loads the module from the stored filename if needed. Finally, locks
# the module environment to prevent potentially dangerous future changes.
load_module = function(module)
{
    # Initialize module state
    if (!exists("L", module)) {
        module[["L"]] = lua_open()
    }

    # Load module
    if (!exists("mod", module)) {
        if (is.null(module[["package"]])) {
            file = do.call(file.path, as.list(module[["filename"]]))
        } else {
            file = system.file(
                do.call(file.path, as.list(module[["filename"]])),
                package = module[["package"]]
            )
        }
        module[["mod"]] = .Call(`_luajr_module_load`, file, module[["L"]])
    }

    # Lock the module to prevent later changes
    if (!environmentIsLocked(module)) {
        lockEnvironment(module, bindings = TRUE)
    }
}
