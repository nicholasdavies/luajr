#' Run an interactive LuaJIT shell
#'
#' When in interactive mode, provides a basic read-eval-print loop with LuaJIT.
#'
#' @param L [Lua state][lua_open] in which to run the code. `NULL` (default) to
#' use the default Lua state for \pkg{luajr}.
#' @export
lua_shell = function(L = NULL)
{
    # See if crayon package is available
    crayon_available = requireNamespace("crayon", quietly = TRUE);

    # Error reporting
    do_error = function(e)
    {
        if (crayon_available) {
            cat(crayon::red(e$message), "\n")
        } else {
            cat(e$message, "\n")
        }
    }

    # Loop until blank line received
    line = "."
    while (line != "")
    {
        # Read a line
        line = readline("lua > ")

        # Try to execute the line, print error message if error thrown
        tryCatch(lua(line, L = L), error = do_error)
    }
}
